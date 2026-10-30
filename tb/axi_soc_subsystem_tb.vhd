library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp_pkg.all;

library vunit_lib;
context vunit_lib.vunit_context;
context vunit_lib.com_context;

use vunit_lib.axi_pkg.all;
use vunit_lib.bus_master_pkg.all;
use vunit_lib.axi_lite_master_pkg.all;

entity axi_soc_subsystem_tb is
  generic (runner_cfg : string);
end entity;

architecture a of axi_soc_subsystem_tb is


constant num_random_tests : integer := 128;

constant G_ADDR_WIDTH : integer := 32;
constant G_DATA_WIDTH : integer := 32;
constant C_ENABLE_SDRAM : boolean := TRUE;

signal ref_DAY_HEX    : std_logic_vector(7 downto 0)  := C_DAY_HEX;
signal ref_MONTH_HEX  : std_logic_vector(7 downto 0)  := C_MONTH_HEX;
signal ref_YEAR_HEX   : std_logic_vector(15 downto 0) := C_YEAR_HEX;
signal ref_HOUR_HEX   : std_logic_vector(7 downto 0)  := C_HOUR_HEX;
signal ref_MINUTE_HEX : std_logic_vector(7 downto 0)  := C_MINUTE_HEX;
signal ref_SECOND_HEX : std_logic_vector(7 downto 0)  := C_SECOND_HEX;

signal clk    : std_logic := '0';
signal arready : std_logic := '0';
signal arvalid : std_logic;
signal araddr  : std_logic_vector(31 downto 0);

signal rready  : std_logic := '0';
signal rvalid  : std_logic;
signal rdata   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal rresp   : std_logic_vector(1 downto 0);

signal awready : std_logic := '0';
signal awvalid : std_logic;
signal awaddr  : std_logic_vector(31 downto 0);

signal wready  : std_logic := '0';
signal wvalid  : std_logic;
signal wdata   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal wstrb   : std_logic_vector(G_DATA_WIDTH/8-1 downto 0);

signal bvalid  : std_logic := '0';
signal bready  : std_logic;
signal bresp   : std_logic_vector(1 downto 0);

constant bus_handle : bus_master_t := new_bus(data_length => wdata'length,
                                            address_length => awaddr'length);

-- Reset
signal resetn : std_logic := '0';

-- CPU AXI-Lite interface: driven by the existing VUnit master
-- CPU interface
signal cpu_axi_awvalid : std_logic;
signal cpu_axi_awready : std_logic;
signal cpu_axi_awaddr : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal cpu_axi_awprot : std_logic_vector(2 downto 0) := (others => '0');
signal cpu_axi_wvalid : std_logic;
signal cpu_axi_wready : std_logic;
signal cpu_axi_wdata : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal cpu_axi_wstrb : std_logic_vector(G_DATA_WIDTH/8-1 downto 0);
signal cpu_axi_bvalid : std_logic;
signal cpu_axi_bready : std_logic;
signal cpu_axi_bresp : std_logic_vector(1 downto 0);
signal cpu_axi_arvalid : std_logic;
signal cpu_axi_arready : std_logic;
signal cpu_axi_araddr : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal cpu_axi_arprot : std_logic_vector(2 downto 0) := (others => '0');
signal cpu_axi_rvalid : std_logic;
signal cpu_axi_rready : std_logic;
signal cpu_axi_rdata : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal cpu_axi_rresp : std_logic_vector(1 downto 0);

-- EXT interface
signal ext_axi_awvalid : std_logic := '0';
signal ext_axi_awready : std_logic;
signal ext_axi_awaddr : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := (others => '0');
signal ext_axi_awprot : std_logic_vector(2 downto 0) := (others => '0');
signal ext_axi_wvalid : std_logic := '0';
signal ext_axi_wready : std_logic;
signal ext_axi_wdata : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others => '0');
signal ext_axi_wstrb : std_logic_vector(G_DATA_WIDTH/8-1 downto 0) := (others => '0');
signal ext_axi_bvalid : std_logic;
signal ext_axi_bready : std_logic := '0';
signal ext_axi_bresp : std_logic_vector(1 downto 0);
signal ext_axi_arvalid : std_logic := '0';
signal ext_axi_arready : std_logic;
signal ext_axi_araddr : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := (others => '0');
signal ext_axi_arprot : std_logic_vector(2 downto 0) := (others => '0');
signal ext_axi_rvalid : std_logic;
signal ext_axi_rready : std_logic := '0';
signal ext_axi_rdata : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal ext_axi_rresp : std_logic_vector(1 downto 0);

signal axi_soc_subsystem_uart_rx : std_logic := '1';
signal axi_soc_subsystem_uart_tx : std_logic;
signal axi_soc_subsystem_gpio_in  : std_logic_vector(31 downto 0);
signal axi_soc_subsystem_gpio_out : std_logic_vector(31 downto 0);

-- Checking signal
signal rx_data                           : std_logic_vector(31 downto 0);

-- SDRAM signals
-- SDRAM interface
signal sdram_cke   : std_logic;
signal sdram_cs_n  : std_logic;
signal sdram_ras_n : std_logic;
signal sdram_cas_n : std_logic;
signal sdram_we_n  : std_logic;
signal sdram_ba    : std_logic_vector(1 downto 0);
signal sdram_addr  : std_logic_vector(11 downto 0);
signal sdram_dqm   : std_logic_vector(1 downto 0);
signal sdram_dq    : std_logic_vector(15 downto 0);

begin

-- Clock
clk <= not clk after 5 ns; 

-- Reset release
reset_gen : process
begin
    resetn <= '0';
    wait for 50 ns;
    resetn <= '1';
    wait;
end process;

--GPIO loopback
axi_soc_subsystem_gpio_in <= axi_soc_subsystem_gpio_out;

-----------------------------------------
-- Main process with testcases
-----------------------------------------
test_runner : process
variable v_data_read : std_logic_vector(31 downto 0);
variable v_day    : std_logic_vector(7 downto 0);
variable v_month  : std_logic_vector(7 downto 0);
variable v_year   : std_logic_vector(15 downto 0);
variable v_hour   : std_logic_vector(7 downto 0);
variable v_minute : std_logic_vector(7 downto 0);
variable v_second : std_logic_vector(7 downto 0);
begin
    test_runner_setup(runner, runner_cfg);

    if run("test_001_write_read_1_work_ram") then
        wait until rising_edge(resetn);
        wait for 1 us;

        write_bus(net, bus_handle, x"00000000", x"1234");
        wait for 1 us;

        read_bus(net, bus_handle, x"00000000", v_data_read);
        wait for 1 us;

        check_equal(v_data_read, std_logic_vector'(x"00001234"), "Readback mismatch for test_001_write_read_1_work_ram");

    end if;

    if run("test_002_write_read_loop_work_ram") then
        wait until rising_edge(resetn);
        wait for 1 us;

        for i in 0 to 1023 loop
            write_bus(net, bus_handle, std_logic_vector(to_unsigned(i * 4, 32)), std_logic_vector(to_unsigned(i, 32)));
            info("Write Addr=" & to_hstring(std_logic_vector(to_unsigned(i * 4, 32))) & " Data=" & to_hstring(std_logic_vector(to_unsigned(i, 32))));
        end loop;

        wait for 1 us;

        for i in 0 to 1023 loop
            read_bus(net, bus_handle, std_logic_vector(to_unsigned(i * 4, 32)), v_data_read);
            info("Read Addr=" & to_hstring(std_logic_vector(to_unsigned(i * 4, 32))) & " Data=" & to_hstring(v_data_read));
            check_equal(v_data_read, std_logic_vector(to_unsigned(i, 32)), "Readback mismatch at address " & integer'image(i * 4));
        end loop;

        wait for 1 us;

    end if;

    if run("test_003_uart_write_read_x1") then
        wait until rising_edge(resetn);
        wait for 1 us;

        -- Write data
        write_bus(net, bus_handle, x"00100000", x"0083");
        info("UART write operation completed");
        wait for 50 us;

        --Check fifo TX level
        read_bus(net, bus_handle, x"00100008",v_data_read);
        wait for 0 us;
        info("UART TX FIFO level read: " & to_hstring(v_data_read));
        wait for 1 us;

        --Check fifo RX level
        read_bus(net, bus_handle, x"0010000C",v_data_read);
        wait for 0 us;
        info("UART RX FIFO level read: " & to_hstring(v_data_read));
        wait for 1 us;

        -- Read data
        read_bus(net, bus_handle, x"00100004",v_data_read);
        wait for 0 us;
        info("UART RX FIFO data read: " & to_hstring(v_data_read));
        wait for 1 us;

        -- Check that the value read from RX FIFO matches what was written
        check_equal(v_data_read, std_logic_vector'(x"00000083"), "UART RX FIFO data mismatch for test_003_uart_write_read_x1");

        --Check fifo RX level
        read_bus(net, bus_handle, x"0010000C",v_data_read);
        wait for 0 us;
        info("UART RX FIFO level after read: " & to_hstring(v_data_read));
        wait for 1 us;

        -- Check
        check_equal(v_data_read, std_logic_vector'(x"00000000"), "UART RX FIFO level data mismatch for test_003_uart_write_read_x1");


    end if;

    if run("test_004_uart_write_read_x16") then

        wait until rising_edge(resetn);
        wait for 1 us;

        -- Send counter values 0x80..0x8F to UART TX FIFO in a loop
        for i in 0 to 15 loop
            write_bus(net, bus_handle, x"00100000", std_logic_vector(to_unsigned(16#80#+i, 32)));
            info("UART write operation completed, data=" & to_hstring(std_logic_vector(to_unsigned(16#80#+i, 32))));
            wait for 50 us;

            -- Check TX FIFO level
            read_bus(net, bus_handle, x"00100008", v_data_read);
            info("UART TX FIFO level read: " & to_hstring(v_data_read));
            wait for 1 us;
        end loop;

        -- Check RX FIFO level before reading
        read_bus(net, bus_handle, x"0010000C", v_data_read);
        info("UART RX FIFO level before read: " & to_hstring(v_data_read));
        wait for 1 us;

        -- Read back all 16 values from RX FIFO
        for i in 0 to 15 loop
            read_bus(net, bus_handle, x"00100004", v_data_read);
            info("UART RX FIFO data read: " & to_hstring(v_data_read));
            check_equal(v_data_read, std_logic_vector(to_unsigned(16#80#+i, 32)), "UART RX FIFO data mismatch at index " & integer'image(i));
            wait for 1 us;
        end loop;

        -- Check RX FIFO level after reading
        read_bus(net, bus_handle, x"0010000C", v_data_read);
        info("UART RX FIFO level after read: " & to_hstring(v_data_read));
        wait for 1 us;

    end if;

    if run("test_005_single_gpio") then

        wait until rising_edge(resetn);
        wait for 1 us;

        write_bus(net, bus_handle, x"00200000", std_logic_vector'(x"12345678"));
        info("Write on AXI GPIO 32 bits");
        wait for 10 us;

        read_bus(net, bus_handle, x"00200004", v_data_read);
        info("GPIO read: " & to_hstring(v_data_read));
        check_equal(v_data_read, std_logic_vector'(x"12345678"), " GPIO read error");
        wait for 1 us;

    end if;

    if run("test_006_single_gpio_x256") then

        wait until rising_edge(resetn);
        wait for 1 us;

        for i in 0 to 255 loop
            write_bus(net, bus_handle, x"00200000", std_logic_vector(to_unsigned(i, 32)));
            info("GPIO write: " & to_hstring(std_logic_vector(to_unsigned(i, 32))));
            wait for 10 us;

            read_bus(net, bus_handle, x"00200004", v_data_read);
            info("GPIO read: " & to_hstring(v_data_read));
            check_equal(v_data_read, std_logic_vector(to_unsigned(i, 32)), "GPIO read error at index " & integer'image(i));
            wait for 1 us;
        end loop;

    end if;

    if run("test_007_read_timestamp") then

        wait until rising_edge(resetn);
        wait for 1 us;

            read_bus(net, bus_handle, x"00300000", v_data_read);
            info("AXI slave register bank read 0: " & to_hstring(v_data_read));

            wait for 1 us;

            read_bus(net, bus_handle, x"00300004", v_data_read);
            info("AXI slave register bank read 1: " & to_hstring(v_data_read));

            info("Retrieve and display timestamp fields from register_bank_rd(0) and (1)");
            -- Read register_bank_rd(0)
            read_bus(net, bus_handle, x"00300000", v_data_read);
            v_day   := v_data_read(7 downto 0);
            v_month := v_data_read(15 downto 8);
            v_year  := v_data_read(31 downto 16);

            -- Read register_bank_rd(1)
            read_bus(net, bus_handle, x"00300004", v_data_read);
            v_hour   := v_data_read(7 downto 0);
            v_minute := v_data_read(15 downto 8);
            v_second := v_data_read(23 downto 16);

            info("Timestamp: " &
                 "Year="   & integer'image(to_integer(unsigned(v_year)))   & " " &
                 "Month="  & integer'image(to_integer(unsigned(v_month)))  & " " &
                 "Day="    & integer'image(to_integer(unsigned(v_day)))    & " " &
                 "Hour="   & integer'image(to_integer(unsigned(v_hour)))   & " " &
                 "Minute=" & integer'image(to_integer(unsigned(v_minute))) & " " &
                 "Second=" & integer'image(to_integer(unsigned(v_second)))
            );

            -- Compare the read timestamp fields with the reference values
            check_equal(v_day,    ref_DAY_HEX,    "Day mismatch in timestamp");
            check_equal(v_month,  ref_MONTH_HEX,  "Month mismatch in timestamp");
            check_equal(v_year,   ref_YEAR_HEX,   "Year mismatch in timestamp");
            check_equal(v_hour,   ref_HOUR_HEX,   "Hour mismatch in timestamp");
            check_equal(v_minute, ref_MINUTE_HEX, "Minute mismatch in timestamp");
            check_equal(v_second, ref_SECOND_HEX, "Second mismatch in timestamp");

            wait for 1 us;
            info("Finished");

    end if;

    if run("test_008_test_slot_4_loopback") then

        wait until rising_edge(resetn);
        wait for 1 us;

        info("Write to 0x300008");
        write_bus(net, bus_handle, x"00300008", x"12345678");

        info("Read from 0x300008");
        read_bus(net, bus_handle, x"00300008", v_data_read);

        check_equal(v_data_read,    std_logic_vector'(x"12345678"),    "Loop register mismatch");

        wait for 1 ms;

        info("Finished");

    end if;

    if run("test_009_time_elapsed") then

        wait until rising_edge(resetn);
        wait for 1 us;

        info("Read from 0x30000C");
        read_bus(net, bus_handle, x"0030000C", v_data_read);

        info("Read from 0x300010");
        read_bus(net, bus_handle, x"00300010", v_data_read);
        check_equal(v_data_read,    std_logic_vector'(x"0000006C"),    "Time elapsed lsb mismatch");

        info("Read from 0x300014");
        read_bus(net, bus_handle, x"00300014", v_data_read);
        check_equal(v_data_read,    std_logic_vector'(x"00000000"),    "Time elapsed msb mismatch");

        wait for 10 us;

        info("Read from 0x30000C");
        read_bus(net, bus_handle, x"0030000C", v_data_read);
        check_equal(v_data_read, std_logic_vector(to_unsigned(100_000_000, 32)), "Time elapsed reference frequency read");

        info("Read from 0x300010");
        read_bus(net, bus_handle, x"00300010", v_data_read);
        check_equal(v_data_read,    std_logic_vector'(x"00000487"),    "Time elapsed lsb mismatch");

        info("Read from 0x300014");
        read_bus(net, bus_handle, x"00300014", v_data_read);
        check_equal(v_data_read,    std_logic_vector'(x"00000000"),    "Time elapsed msb mismatch");

        info("Finished");

    end if;

    if run("test_010_trng_read") then

        wait until rising_edge(resetn);
        wait for 1 us;

        info("Starting AXI TRNG test");

        -- Check initial status = IDLE
        read_bus(net, bus_handle, x"00400004", v_data_read);
        check_equal(v_data_read, std_logic_vector'(x"00000000"),
                    "TRNG initial status is not IDLE");

        -- Configure accumulation cycles = 1000
        write_bus(net, bus_handle, x"0040000C", x"000003E8");

        -- Read back accumulation configuration
        read_bus(net, bus_handle, x"0040000C", v_data_read);
        check_equal(v_data_read, std_logic_vector'(x"000003E8"),
                    "TRNG accumulation configuration mismatch");

        -- Start acquisition
        info("TRNG START");
        write_bus(net, bus_handle, x"00400000", x"00000001");

        -- Check status = BUSY
        read_bus(net, bus_handle, x"00400004", v_data_read);
        check_equal(v_data_read, std_logic_vector'(x"00000001"),
                    "TRNG status is not BUSY");

        -- Poll STATUS until DONE
        for i in 0 to 2000 loop

            read_bus(net, bus_handle, x"00400004", v_data_read);

            exit when v_data_read = x"00000002";

            wait for 100 ns;

        end loop;

        -- Check acquisition completed
        check_equal(v_data_read, std_logic_vector'(x"00000002"),
                    "TRNG acquisition timeout");

        -- Read random data
        read_bus(net, bus_handle, x"00400008", v_data_read);

        info("TRNG RANDOM DATA = 0x" & to_hstring(v_data_read));

        -- Clear acquisition
        info("TRNG CLEAR");
        write_bus(net, bus_handle, x"00400000", x"00000002");

        -- Check status = IDLE
        read_bus(net, bus_handle, x"00400004", v_data_read);
        check_equal(v_data_read, std_logic_vector'(x"00000000"),
                    "TRNG status is not IDLE after CLEAR");

        -- Check random data cleared
        read_bus(net, bus_handle, x"00400008", v_data_read);
        check_equal(v_data_read, std_logic_vector'(x"00000000"),
                    "TRNG RANDOM_DATA not cleared");

        info("Finished");

    end if;

    if run("test_011_sdram_write_read") then

        if C_ENABLE_SDRAM then

            wait until rising_edge(resetn);

            -- Wait for SDRAM initialization (200 us + margin)
            wait for 250 us;

            info("Starting SDRAM write/read test");

            -- Write one 32-bit word
            write_bus(net,bus_handle,x"00500000",x"12345678");
            info("SDRAM write completed");

            -- Read back
            read_bus(net,bus_handle,x"00500000",v_data_read);
            info("SDRAM read data = 0x" & to_hstring(v_data_read));
            -- Verify
            check_equal(v_data_read,std_logic_vector'(x"12345678"),"SDRAM readback mismatch");
            info("SDRAM write/read test PASSED");
        else
            info("SDRAM test skipped (C_ENABLE_SDRAM = FALSE)");
        end if;

    end if;

    if run("test_012_sdram_write_read_1024") then
        if C_ENABLE_SDRAM then
            wait until rising_edge(resetn);
            wait for 250 us;

            for i in 0 to 1023 loop
                write_bus(net, bus_handle,
                    std_logic_vector(to_unsigned(16#00500000# + i*4, 32)),
                    std_logic_vector(to_unsigned(i, 32)));
            end loop;

            for i in 0 to 1023 loop
                read_bus(net, bus_handle,
                    std_logic_vector(to_unsigned(16#00500000# + i*4, 32)),
                    v_data_read);
                check_equal(v_data_read, std_logic_vector(to_unsigned(i, 32)),
                    "SDRAM mismatch at index " & integer'image(i));
            end loop;

            info("SDRAM 1024 words test PASSED");
        end if;
    end if;

    test_runner_cleanup(runner);
end process;

----------------------------------------------------------------------------
-- UART addresses
----------------------------------------------------------------------------

--  Address	        Name	        Function/Description
--  0x00000000	    TX_DATA	        Write: Send byte to UART TX FIFO
--  0x00000004	    RX_DATA	        Read: Get byte from UART RX FIFO
--  0x00000008	    TX_LEVEL	    Read: TX FIFO fill level
--  0x0000000C	    RX_LEVEL	    Read: RX FIFO fill level
--  0x00000010	    RESET	        Write: Pulse to reset FIFOs

-- Bridge assignments between VUnit master and CPU AXI-Lite interface
cpu_axi_awvalid <= awvalid;
awready <= cpu_axi_awready;
cpu_axi_awaddr <= awaddr;
cpu_axi_wvalid <= wvalid;
wready <= cpu_axi_wready;
cpu_axi_wdata <= wdata;
cpu_axi_wstrb <= wstrb;
bvalid <= cpu_axi_bvalid;
cpu_axi_bready <= bready;
bresp <= cpu_axi_bresp;
cpu_axi_arvalid <= arvalid;
arready <= cpu_axi_arready;
cpu_axi_araddr <= araddr;
rvalid <= cpu_axi_rvalid;
cpu_axi_rready <= rready;
rdata <= cpu_axi_rdata;
rresp <= cpu_axi_rresp;

----------------------------------------------------------------
-- AXI SOC SUBSYSTEM
----------------------------------------------------------------

-- Instantiation
axi_soc_subsystem_inst : entity work.axi_soc_subsystem
    generic map (
        G_SIM           => TRUE,
        G_ENABLE_SDRAM   => C_ENABLE_SDRAM,
        USE_ASYNC_RESET => FALSE,
        USE_SYNC_RESET => TRUE,
        G_ADDR_WIDTH => 32,
        G_DATA_WIDTH => 32,
        G_BASE0      => (others => '0'),
        G_LIMIT0     => x"000FFFFF",
        G_BASE1      => x"00100000",
        G_LIMIT1     => x"001FFFFF",
        G_BASE2      => x"00200000",
        G_LIMIT2     => x"002FFFFF",
        G_BASE3      => x"00300000",
        G_LIMIT3     => x"003FFFFF",
        G_BASE4      => x"00400000",
        G_LIMIT4     => x"004FFFFF",
        G_BASE5      => x"00500000",
        G_LIMIT5     => x"00CFFFFF",
        G_RAM_DEPTH  => 1024,
        G_SYS_FREQ   => 100_000_000,
        G_BAUDRATE   => 781248,
        G_TX_DEPTH   => 16,
        G_RX_DEPTH   => 16
    )
    port map (
        clk => clk,
        async_reset => not resetn,
        sync_reset  => not resetn, 
        cpu_axi_awvalid => cpu_axi_awvalid,
        cpu_axi_awready => cpu_axi_awready,
        cpu_axi_awaddr => cpu_axi_awaddr,
        cpu_axi_awprot => cpu_axi_awprot,
        cpu_axi_wvalid => cpu_axi_wvalid,
        cpu_axi_wready => cpu_axi_wready,
        cpu_axi_wdata => cpu_axi_wdata,
        cpu_axi_wstrb => cpu_axi_wstrb,
        cpu_axi_bvalid => cpu_axi_bvalid,
        cpu_axi_bready => cpu_axi_bready,
        cpu_axi_bresp => cpu_axi_bresp,
        cpu_axi_arvalid => cpu_axi_arvalid,
        cpu_axi_arready => cpu_axi_arready,
        cpu_axi_araddr => cpu_axi_araddr,
        cpu_axi_arprot => cpu_axi_arprot,
        cpu_axi_rvalid => cpu_axi_rvalid,
        cpu_axi_rready => cpu_axi_rready,
        cpu_axi_rdata => cpu_axi_rdata,
        cpu_axi_rresp => cpu_axi_rresp,
        ext_axi_awvalid => ext_axi_awvalid,
        ext_axi_awready => ext_axi_awready,
        ext_axi_awaddr => ext_axi_awaddr,
        ext_axi_awprot => ext_axi_awprot,
        ext_axi_wvalid => ext_axi_wvalid,
        ext_axi_wready => ext_axi_wready,
        ext_axi_wdata => ext_axi_wdata,
        ext_axi_wstrb => ext_axi_wstrb,
        ext_axi_bvalid => ext_axi_bvalid,
        ext_axi_bready => ext_axi_bready,
        ext_axi_bresp => ext_axi_bresp,
        ext_axi_arvalid => ext_axi_arvalid,
        ext_axi_arready => ext_axi_arready,
        ext_axi_araddr => ext_axi_araddr,
        ext_axi_arprot => ext_axi_arprot,
        ext_axi_rvalid => ext_axi_rvalid,
        ext_axi_rready => ext_axi_rready,
        ext_axi_rdata => ext_axi_rdata,
        ext_axi_rresp => ext_axi_rresp,
        uart_rx => axi_soc_subsystem_uart_rx,
        uart_tx => axi_soc_subsystem_uart_tx,
        gpio_in => axi_soc_subsystem_gpio_in,
        gpio_out => axi_soc_subsystem_gpio_out,
        sdram_cke   => sdram_cke,
        sdram_cs_n  => sdram_cs_n,
        sdram_ras_n => sdram_ras_n,
        sdram_cas_n => sdram_cas_n,
        sdram_we_n  => sdram_we_n,
        sdram_ba    => sdram_ba,
        sdram_addr  => sdram_addr,
        sdram_dqm   => sdram_dqm,
        sdram_dq    => sdram_dq
    );

-- UART loopback
axi_soc_subsystem_uart_rx <= axi_soc_subsystem_uart_tx;

----------------------------------------------------------------
-- VUNIT axi_lite_master
----------------------------------------------------------------
axi_lite_master_inst : entity vunit_lib.axi_lite_master
generic map (
    bus_handle => bus_handle)
port map (
    aclk    => clk,
    arready => arready,
    arvalid => arvalid,
    araddr  => araddr,
    rready  => rready,
    rvalid  => rvalid,
    rdata   => rdata,
    rresp   => rresp,
    awready => awready,
    awvalid => awvalid,
    awaddr  => awaddr,
    wready  => wready,
    wvalid  => wvalid,
    wdata   => wdata,
    wstrb   => wstrb,
    bvalid  => bvalid,
    bready  => bready,
    bresp   => bresp);

-----------------------------------------------------------
-- SDRAM MODEL
-----------------------------------------------------------
gen_sdram_model : if C_ENABLE_SDRAM generate
    u_sdram_model : entity work.sdram_model
        generic map (
            G_T_AC          => 1 ns,
            G_T_RCD_CYCLES => 3,
            G_T_RP_CYCLES  => 3,
            G_T_RFC_CYCLES => 8,
            G_T_RAS_CYCLES => 5,
            G_T_WR_CYCLES  => 2,
            G_CHECK_TIMING  => TRUE
        )
        port map (
            i_clk   => clk,
            i_cke   => sdram_cke,
            i_cs_n  => sdram_cs_n,
            i_ras_n => sdram_ras_n,
            i_cas_n => sdram_cas_n,
            i_we_n  => sdram_we_n,

            i_ba    => sdram_ba,
            i_addr  => sdram_addr,
            i_dqm   => sdram_dqm,
            io_dq   => sdram_dq
        );
end generate gen_sdram_model;

end architecture;