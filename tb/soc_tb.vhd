
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use STD.textio.all;
use ieee.std_logic_textio.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity soc_tb is
    generic (
        runner_cfg         : string := runner_cfg_default
    );
end soc_tb;

architecture rtl of soc_tb is

constant C_SYS_FREQ : natural := 100_000_000;
constant C_BAUDRATE : natural := 781248;
constant USE_ASYNC_RESET    : boolean   := FALSE;
constant USE_SYNC_RESET     : boolean   := TRUE;
constant ASYNC_RESET_ACTIVE : std_logic := '1';
constant SYNC_RESET_ACTIVE  : std_logic := '1';

constant clk_const      : time := 5 ns;
constant reset_n_const  : time := 83.334 ns;

-- DUT signals
signal clk          : std_logic;
-- Startup completion indicator for the test runner and receive monitors.
signal reset_n      : std_logic := '0';
signal async_reset  : std_logic := ASYNC_RESET_ACTIVE;
signal sync_reset   : std_logic := SYNC_RESET_ACTIVE;
signal uart_rx      : std_logic;
signal uart_tx      : std_logic;

-- CPU control and debug
signal cpu_reset_i        : std_logic := '0';
signal stall_i            : std_logic := '0';
signal fault_i            : std_logic := '0';
signal fault_o            : std_logic;
signal registers_debug_o : std_logic_vector(1023 downto 0);
signal pc_debug_o        : std_logic_vector(31 downto 0);
signal previous_pc_debug_o : std_logic_vector(31 downto 0);


-- AXI-Stream UART interface
signal s_axis_tdata  : std_logic_vector(7 downto 0) := (others => '0');
signal s_axis_tvalid : std_logic := '0';
signal s_axis_tready : std_logic;
signal m_axis_tdata  : std_logic_vector(7 downto 0);
signal m_axis_tvalid : std_logic;
signal m_axis_tready : std_logic := '1';

-- Capture the latest received 9-byte bootloader ACK independently of TX.
-- The test runner clears the count before each expected response.
signal rx_frame_shift : std_logic_vector(71 downto 0) := (others => '0');
signal rx_byte_count  : natural := 0;
signal rx_clear       : std_logic := '0';

-- External AXI4-Lite interface
signal ext_axi_awaddr  : std_logic_vector(31 downto 0) := (others => '0');
signal ext_axi_awprot  : std_logic_vector(2 downto 0)  := (others => '0');
signal ext_axi_awvalid : std_logic := '0';
signal ext_axi_awready : std_logic;

signal ext_axi_wdata   : std_logic_vector(31 downto 0) := (others => '0');
signal ext_axi_wstrb   : std_logic_vector(3 downto 0)  := (others => '0');
signal ext_axi_wvalid  : std_logic := '0';
signal ext_axi_wready  : std_logic;

signal ext_axi_bresp   : std_logic_vector(1 downto 0);
signal ext_axi_bvalid  : std_logic;
signal ext_axi_bready  : std_logic := '0';

signal ext_axi_araddr  : std_logic_vector(31 downto 0) := (others => '0');
signal ext_axi_arprot  : std_logic_vector(2 downto 0)  := (others => '0');
signal ext_axi_arvalid : std_logic := '0';
signal ext_axi_arready : std_logic;

signal ext_axi_rdata   : std_logic_vector(31 downto 0);
signal ext_axi_rresp   : std_logic_vector(1 downto 0);
signal ext_axi_rvalid  : std_logic;
signal ext_axi_rready  : std_logic := '0';

-- uart rx array
type uart_rx_array_t is array (0 to 15) of std_logic_vector(7 downto 0);
signal uart_rx_last16 : uart_rx_array_t := (others => (others => '0'));

-- AXI-Stream write: hold TVALID and TDATA until a rising-edge handshake.
procedure uart_write(
    signal clock_i : in std_logic;
    signal data_o  : out std_logic_vector(7 downto 0);
    signal valid_o : out std_logic;
    signal ready_i : in std_logic;
    constant value : in std_logic_vector(7 downto 0)
) is
begin
    wait until falling_edge(clock_i);
    data_o  <= value;
    valid_o <= '1';
    loop
        wait until rising_edge(clock_i);
        exit when ready_i = '1';
    end loop;
    wait until falling_edge(clock_i);
    valid_o <= '0';
end procedure;

procedure uart_send_frame(
    signal clock_i : in std_logic;
    signal data_o  : out std_logic_vector(7 downto 0);
    signal valid_o : out std_logic;
    signal ready_i : in std_logic;
    constant frame : in std_logic_vector(71 downto 0)
) is
begin
    for i in 0 to 8 loop
        uart_write(clock_i, data_o, valid_o, ready_i,
                   frame((i+1)*8-1 downto i*8));
    end loop;
end procedure;

procedure axi_write(
    signal clock_i   : in  std_logic;

    signal awaddr_o  : out std_logic_vector(31 downto 0);
    signal awvalid_o : out std_logic;
    signal awready_i : in  std_logic;

    signal wdata_o   : out std_logic_vector(31 downto 0);
    signal wstrb_o   : out std_logic_vector(3 downto 0);
    signal wvalid_o  : out std_logic;
    signal wready_i  : in  std_logic;

    signal bresp_i   : in  std_logic_vector(1 downto 0);
    signal bvalid_i  : in  std_logic;
    signal bready_o  : out std_logic;

    constant addr    : in  std_logic_vector(31 downto 0);
    constant data    : in  std_logic_vector(31 downto 0)
) is
    variable aw_done : boolean;
    variable w_done  : boolean;
begin

    wait until falling_edge(clock_i);

    awaddr_o  <= addr;
    awvalid_o <= '1';

    wdata_o   <= data;
    wstrb_o   <= "1111";
    wvalid_o  <= '1';

    bready_o  <= '1';

    aw_done := false;
    w_done  := false;

    -- AW and W are independent AXI-Lite channels.
    while not (aw_done and w_done) loop

        wait until rising_edge(clock_i);

        if not aw_done and awready_i = '1' then
            aw_done := true;
            awvalid_o <= '0';
        end if;

        if not w_done and wready_i = '1' then
            w_done := true;
            wvalid_o <= '0';
        end if;

    end loop;

    -- Wait for write response.
    loop
        wait until rising_edge(clock_i);
        exit when bvalid_i = '1';
    end loop;

    check_equal(bresp_i, std_logic_vector'("00"),
                "AXI-Lite WRITE BRESP");

    wait until falling_edge(clock_i);

    bready_o <= '0';

end procedure;

procedure axi_read(
    signal clock_i   : in  std_logic;

    signal araddr_o  : out std_logic_vector(31 downto 0);
    signal arvalid_o : out std_logic;
    signal arready_i : in  std_logic;

    signal rdata_i   : in  std_logic_vector(31 downto 0);
    signal rresp_i   : in  std_logic_vector(1 downto 0);
    signal rvalid_i  : in  std_logic;
    signal rready_o  : out std_logic;

    constant addr    : in  std_logic_vector(31 downto 0);
    variable data    : out std_logic_vector(31 downto 0)
) is
begin

    wait until falling_edge(clock_i);

    araddr_o  <= addr;
    arvalid_o <= '1';

    rready_o <= '1';

    -- Wait for address acceptance.
    loop
        wait until rising_edge(clock_i);
        exit when arready_i = '1';
    end loop;

    arvalid_o <= '0';

    -- Wait for read response.
    loop
        wait until rising_edge(clock_i);
        exit when rvalid_i = '1';
    end loop;

    data := rdata_i;

    check_equal(rresp_i, std_logic_vector'("00"),
                "AXI-Lite READ RRESP");

    wait until falling_edge(clock_i);

    rready_o <= '0';

end procedure;

---------------------------------------------------------------------------
-- AXI4-Lite WRITE FROM TEXT FILE
--
-- File format:
-- 00 10 01 17
-- 00 01 01 13
-- 00 00 02 97
--
-- Each line contains 4 hexadecimal bytes (MSB first).
-- One AXI-Lite 32-bit write per line.
-- Address increments by 4 after each write.
---------------------------------------------------------------------------

procedure axi_write_file(
    signal clock_i   : in  std_logic;

    signal awaddr_o  : out std_logic_vector(31 downto 0);
    signal awvalid_o : out std_logic;
    signal awready_i : in  std_logic;

    signal wdata_o   : out std_logic_vector(31 downto 0);
    signal wstrb_o   : out std_logic_vector(3 downto 0);
    signal wvalid_o  : out std_logic;
    signal wready_i  : in  std_logic;

    signal bresp_i   : in  std_logic_vector(1 downto 0);
    signal bvalid_i  : in  std_logic;
    signal bready_o  : out std_logic;

    constant start_addr : in std_logic_vector(31 downto 0);
    constant filename   : in string
) is

    file fid : text;

    variable v_line : line;

    variable v_b3 : std_logic_vector(7 downto 0);
    variable v_b2 : std_logic_vector(7 downto 0);
    variable v_b1 : std_logic_vector(7 downto 0);
    variable v_b0 : std_logic_vector(7 downto 0);

    variable v_data : std_logic_vector(31 downto 0);
    variable v_addr : unsigned(31 downto 0);

    variable v_count : natural := 0;

begin

    -- Open file
    
    file_open(fid, filename, read_mode);

    v_addr := unsigned(start_addr);

    report "AXI FILE WRITE START: " & filename
        severity note;

    -- Read and write each line

    while not endfile(fid) loop

        readline(fid, v_line);

        -- Read 4 hexadecimal bytes
        hread(v_line, v_b3);
        hread(v_line, v_b2);
        hread(v_line, v_b1);
        hread(v_line, v_b0);

        -- Assemble 32-bit word (MSB first)
        v_data := v_b3 & v_b2 & v_b1 & v_b0;

        -- AXI-Lite write

        axi_write(
            clock_i,

            awaddr_o,
            awvalid_o,
            awready_i,

            wdata_o,
            wstrb_o,
            wvalid_o,
            wready_i,

            bresp_i,
            bvalid_i,
            bready_o,

            std_logic_vector(v_addr),
            v_data
        );

        -- Next 32-bit address
        v_addr := v_addr + 4;

        v_count := v_count + 1;

    end loop;

    -- Close file

    file_close(fid);

    report "AXI FILE WRITE COMPLETE: " &
           integer'image(v_count) & " words written"
        severity note;

end procedure;

function generate_frame(addr : std_logic_vector(31 downto 0); 
                       data : std_logic_vector(31 downto 0)) 
                       return std_logic_vector is
    variable frame : std_logic_vector(71 downto 0);
begin
    frame(71 downto 40) := data(7 downto 0) & data(15 downto 8) & data(23 downto 16) & data(31 downto 24);
    frame(39 downto 8)  := addr(7 downto 0) & addr(15 downto 8) & addr(23 downto 16) & addr(31 downto 24);
    frame(7 downto 0)   :=  x"AA";
    return frame;
end function;

function generate_jump_frame(addr : std_logic_vector(31 downto 0); 
                       data : std_logic_vector(31 downto 0)) 
                       return std_logic_vector is
    variable frame : std_logic_vector(71 downto 0);
begin
    frame(71 downto 40) := data(7 downto 0) & data(15 downto 8) & data(23 downto 16) & data(31 downto 24);
    frame(39 downto 8)  := addr(7 downto 0) & addr(15 downto 8) & addr(23 downto 16) & addr(31 downto 24);
    frame(7 downto 0)   :=  x"55";
    return frame;
end function;


function flip_bytes(data : std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(data'range);
    variable byte_idx : integer;
begin
    byte_idx := 0;
    for i in 0 to (data'length / 8) - 1 loop
        result((i+1)*8-1 downto i*8) := data(data'length - i*8 - 1 downto data'length - (i+1)*8);
    end loop;
    return result;
end function;

signal bootloader_rx_frame      : std_logic_vector(71 downto 0);
signal data_read_from_file      : std_logic_vector(31 downto 0);

begin

-----------------------------------------
-- clk generation
-----------------------------------------
clk_gen_pr: process
begin
    clk <= '1';
    wait for clk_const;

    clk <= '0';
    wait for clk_const;
end process;

-----------------------------------------
-- reset_n generation
-----------------------------------------
reset_n_gen_pr: process
begin
    reset_n <= '0';
    async_reset <= ASYNC_RESET_ACTIVE;
    sync_reset <= SYNC_RESET_ACTIVE;
    wait for reset_n_const;
    wait until falling_edge(clk);
    async_reset <= not ASYNC_RESET_ACTIVE;
    sync_reset <= not SYNC_RESET_ACTIVE;

    -- Allow the CPU reset release synchronizer to settle before starting tests.
    -- Complete startup even when both configurable resets are disabled.
    for i in 1 to 3 loop
        wait until rising_edge(clk);
    end loop;
    wait until falling_edge(clk);
    reset_n <= '1';
    wait;
end process;


-- Instantiate the SoC; keep the external AXI master idle.
soc_inst : entity work.soc
    generic map (
        USE_ASYNC_RESET    => USE_ASYNC_RESET,
        USE_SYNC_RESET     => USE_SYNC_RESET,
        ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
        SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
        G_SYS_FREQ => C_SYS_FREQ,
        G_BAUDRATE => C_BAUDRATE
    )
    port map (
        -- Clock, reset and UART
        clk         => clk,
        async_reset => async_reset,
        sync_reset  => sync_reset,
        cpu_reset_i => cpu_reset_i,
        uart_rx     => uart_rx,
        uart_tx     => uart_tx,

        -- CPU control and debug
        stall_i             => stall_i,
        fault_i             => fault_i,
        fault_o             => fault_o,
        registers_debug_o   => registers_debug_o,
        pc_debug_o          => pc_debug_o,
        previous_pc_debug_o => previous_pc_debug_o,

        -- Axi lite AXI RAM direct access
        ext_axi_awaddr  => ext_axi_awaddr,
        ext_axi_awprot  => ext_axi_awprot,
        ext_axi_awvalid => ext_axi_awvalid,
        ext_axi_awready => ext_axi_awready,

        ext_axi_wdata   => ext_axi_wdata,
        ext_axi_wstrb   => ext_axi_wstrb,
        ext_axi_wvalid  => ext_axi_wvalid,
        ext_axi_wready  => ext_axi_wready,

        ext_axi_bresp   => ext_axi_bresp,
        ext_axi_bvalid  => ext_axi_bvalid,
        ext_axi_bready  => ext_axi_bready,

        ext_axi_araddr  => ext_axi_araddr,
        ext_axi_arprot  => ext_axi_arprot,
        ext_axi_arvalid => ext_axi_arvalid,
        ext_axi_arready => ext_axi_arready,

        ext_axi_rdata   => ext_axi_rdata,
        ext_axi_rresp   => ext_axi_rresp,
        ext_axi_rvalid  => ext_axi_rvalid,
        ext_axi_rready  => ext_axi_rready
    );

test_runner : process
variable v_bootloader_frame : std_logic_vector(32+32+8-1 downto 0);
file fid_file_in                        : text;
variable v_INLINE                       : line;
variable v_b3, v_b2, v_b1, v_b0         : std_logic_vector(7 downto 0);
variable v_word                         : std_logic_vector(31 downto 0);
variable v_cnt                          : std_logic_vector(31 downto 0):=x"00001000";
variable v_uart_str                     : string(1 to 16);
variable v_uart_hex                     : std_logic_vector(127 downto 0);
begin
test_runner_setup(runner, runner_cfg);

    if run("test_001_one_ms") then

        -- Wait for reset to be released
        wait until rising_edge(reset_n);
        wait for 1 ms;

        info("Wait 2 ms");
        wait for 2 ms;

        -- Display UART RX last 16 bytes in HEX
        for i in 15 downto 0 loop
            info("UART RX [" & integer'image(i) & "] = 0x" &
                to_hstring(uart_rx_last16(i)));
        end loop;

        -- Checker
        for i in 0 to 15 loop
            v_uart_hex(i*8+7 downto i*8) := uart_rx_last16(i);
        end loop;
        check_equal(
            v_uart_hex,
            std_logic_vector'(x"746C6F61646572207265616479200D0A"),
            "UART RX regression test"
        );

        info("Simulation finished"); 

    end if;

    if run("test_002_adder_program") then

        info("Keep the riscv cpu in reset");
        cpu_reset_i <= '1';

        -- Wait for reset to be released
        wait until rising_edge(reset_n);
        wait for 100 us;

        info("Start AXI-Lite program upload");
        axi_write_file(
            clk,

            ext_axi_awaddr,
            ext_axi_awvalid,
            ext_axi_awready,

            ext_axi_wdata,
            ext_axi_wstrb,
            ext_axi_wvalid,
            ext_axi_wready,

            ext_axi_bresp,
            ext_axi_bvalid,
            ext_axi_bready,

            x"00000000",       -- Start address
            "../../../riscv_soc_shell/c/adder/ram_data.txt"   -- Program file
        );
        info("AXI-Lite program upload completed");

        info("Release riscv cpu in reset");
        cpu_reset_i <= '0';

        info("Wait for the boot message to pass");
        wait for 2.5 ms;

        info("Send 10");
        -- Send ASCII 1

        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, std_logic_vector(to_unsigned(49, 8)));

        -- Send ASCII 0

        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, std_logic_vector(to_unsigned(48, 8)));

        -- Send ASCII \r

        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0D");
        
        -- Send ASCII \n

        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0A");

        info("Wait 1 ms");
        wait for 1 ms;

        info("Send 11");
        -- Send ASCII 1

        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, std_logic_vector(to_unsigned(49, 8)));

        -- Send ASCII 1

        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, std_logic_vector(to_unsigned(49, 8)));

        -- Send ASCII \r

        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0D");
        
        -- Send ASCII \n

        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"0A");

        wait for 1 ms;

        -- Display UART RX last 16 bytes in HEX
        for i in 15 downto 0 loop
            info("UART RX [" & integer'image(i) & "] = 0x" &
                to_hstring(uart_rx_last16(i)));
        end loop;

        -- Checker
        for i in 0 to 15 loop
            v_uart_hex(i*8+7 downto i*8) := uart_rx_last16(i);
        end loop;
        check_equal(
            v_uart_hex,
            std_logic_vector'(x"0D0A0D0A456E74657220613A20200D0A"),
            "UART RX regression test"
        );

        info("Simulation finished");

    end if;

    if run("test_003_bootloader_only") then

        -- Wait for reset to be released
        wait until rising_edge(reset_n);
        wait for 100 us;

        info("Wait 2 ms");
        wait for 2 ms;

        info("-----------------------------------------------");
        info("Send a frame");
        info("-----------------------------------------------");
        v_bootloader_frame := generate_frame(x"00000C00", x"12345678");
        wait for 0 ns;

        rx_clear <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        rx_clear <= '0';
        uart_send_frame(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, v_bootloader_frame);
        info("Frame sent");

        info("ACK receive");

        wait until rx_byte_count = 9;
        bootloader_rx_frame <= rx_frame_shift;
        wait for 0 ns;
        check_equal(bootloader_rx_frame, std_logic_vector'(x"78563412000C0000AA"), "First frame ACK");

        info("Wait 1 ms");
        wait for 1 ms;

        info("-----------------------------------------------");
        info("Send a frame");
        info("-----------------------------------------------");
        v_bootloader_frame := generate_frame(x"00000C04", x"9abcdef1");
        wait for 0 ns;

        rx_clear <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        rx_clear <= '0';
        uart_send_frame(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, v_bootloader_frame);
        info("Frame sent");

        info("ACK receive");

        wait until rx_byte_count = 9;
        bootloader_rx_frame <= rx_frame_shift;
        wait for 0 ns;
        check_equal(bootloader_rx_frame, std_logic_vector'(x"F1DEBC9A040C0000AA"), "Second frame ACK");

        info("Wait 1 ms");
        wait for 1 ms;

        info("Simulation finished");

    end if;

    if run("test_004_bootloader_upload_and_jump") then

        -- Wait for reset to be released
        wait until rising_edge(reset_n);
        wait for 100 us;

        info("Open files");
        file_open(fid_file_in, "../../../riscv_soc_shell/c/bootloader_AND_gpio_write_loop/ram_data.txt",  read_mode);

        info("Wait 1.5 ms");
        wait for 1.5 ms;

        info("------------------------------------------------------");
        info("This test lasts 151 ms at 100 Mhz and 781248 bps uart");
        info("------------------------------------------------------");

        info("-----------------------------------------------");
        info("Start to send app");
        info("-----------------------------------------------");

        info("Feed input values from a file");
        while not endfile(fid_file_in) loop
            readline(fid_file_in, v_INLINE);

            hread(v_INLINE, v_b3);
            hread(v_INLINE, v_b2);
            hread(v_INLINE, v_b1);
            hread(v_INLINE, v_b0);
            wait for 0 ns;
            v_word := v_b3 & v_b2 & v_b1 & v_b0;
            wait for 0 ns;
            data_read_from_file <= v_word;
            wait until rising_edge(clk);
            wait until rising_edge(clk);


            info("Send a frame");
            v_bootloader_frame := generate_frame(v_cnt, data_read_from_file);
            v_cnt := std_logic_vector(unsigned(v_cnt)+4);
            wait for 0 ns;

        rx_clear <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        rx_clear <= '0';
        uart_send_frame(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, v_bootloader_frame);
            info("Frame sent");

            info("ACK receive");

        wait until rx_byte_count = 9;
        bootloader_rx_frame <= rx_frame_shift;
        wait for 0 ns;

            info("Wait 0.125 ms");
            wait for 0.125 ms;

        end loop; --end while

        info("Finished to load the app thourgh bootloader");  
        info("Generate the jump frame");
        v_bootloader_frame := generate_jump_frame(v_cnt, data_read_from_file);
        wait for 0 ns;

        rx_clear <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        rx_clear <= '0';
        uart_send_frame(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, v_bootloader_frame);
        info("Jump frame sent");

        info("Wait for bootloader prompt and send 'y' to jump");
        wait for 1 ms;
        uart_write(clk, s_axis_tdata, s_axis_tvalid, s_axis_tready, x"79");
        info("'y' sent to bootloader");

        info("Wait 5 ms");
        wait for 5 ms;

        -- Display UART RX last 16 bytes in HEX
        for i in 15 downto 0 loop
            info("UART RX [" & integer'image(i) & "] = 0x" &
                to_hstring(uart_rx_last16(i)));
        end loop;

        info("The following checker will work only if timing sequencement keeps aligned");

        -- Checker
        for i in 0 to 15 loop
            v_uart_hex(i*8+7 downto i*8) := uart_rx_last16(i);
        end loop;

        check_equal(
            v_uart_hex,
            std_logic_vector'(x"75653A20250A56616C75653A20250A56"),
            "UART RX regression test"
        );

        info("Simulation finished");

    end if;

test_runner_cleanup(runner);
end process;

uart_inst : entity work.uart
    generic map (
        USE_ASYNC_RESET    => USE_ASYNC_RESET,
        USE_SYNC_RESET     => USE_SYNC_RESET,
        ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
        SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
        uart_clock_divider => (C_SYS_FREQ + 4*C_BAUDRATE) / (8*C_BAUDRATE)
    )
    port map (
        clock         => clk,
        async_reset   => async_reset,
        sync_reset    => sync_reset,
        s_axis_tdata  => s_axis_tdata,
        s_axis_tvalid => s_axis_tvalid,
        s_axis_tready => s_axis_tready,
        m_axis_tdata  => m_axis_tdata,
        m_axis_tvalid => m_axis_tvalid,
        m_axis_tready => m_axis_tready,
        tx_en         => open,
        txd           => uart_rx,
        rxd           => uart_tx
    );

-- A single RX process owns the ACK capture. The monitor below only observes.
uart_ack_capture_pr : process(clk)
begin
    if rising_edge(clk) then
        if reset_n = '0' or rx_clear = '1' then
            rx_byte_count  <= 0;
            rx_frame_shift <= (others => '0');
        elsif m_axis_tvalid = '1' and m_axis_tready = '1' then
            if rx_byte_count < 9 then
                rx_frame_shift <= m_axis_tdata & rx_frame_shift(71 downto 8);
                rx_byte_count  <= rx_byte_count + 1;
            end if;
        end if;
    end if;
end process;

uart_monitor_pr : process
-- This process monitors UART output and displays it as a console.
variable line_buffer : string(1 to 256);
variable idx         : integer := 1;
variable char_val    : character;
begin
    wait until rising_edge(clk);
    while true loop
        wait until rising_edge(clk);
        if m_axis_tvalid = '1' and m_axis_tready = '1' then
            char_val := character'val(to_integer(unsigned(m_axis_tdata)));
            if char_val = LF or char_val = CR then
                -- Print the current line and reset buffer
                if idx > 1 then
                    report "UART RX: " & line_buffer(1 to idx-1);
                end if;
                idx := 1;
            else
                if idx <= line_buffer'length then
                    line_buffer(idx) := char_val;
                    idx := idx + 1;
                end if;
            end if;
        end if;
    end loop;
end process;

uart_rx_shift_pr : process(clk)
begin
    if rising_edge(clk) then
        if reset_n = '0' then
            uart_rx_last16 <= (others => (others => '0'));

        elsif m_axis_tvalid = '1' and m_axis_tready = '1' then

            for i in 15 downto 1 loop
                uart_rx_last16(i) <= uart_rx_last16(i-1);
            end loop;

            uart_rx_last16(0) <= m_axis_tdata;

        end if;
    end if;
end process;


end rtl;
