library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity soc is
    generic (
        USE_ASYNC_RESET    : boolean   := TRUE;
        USE_SYNC_RESET     : boolean   := TRUE;
        ASYNC_RESET_ACTIVE : std_logic := '1';
        SYNC_RESET_ACTIVE  : std_logic := '1';
        G_SYS_FREQ : natural := 100_000_000;
        G_BAUDRATE : natural := 125_000
    );
    port (
        clk         : in std_logic;
        async_reset : in std_logic;
        sync_reset  : in std_logic;
        cpu_reset_i : in std_logic := '0';
        uart_rx     : in std_logic;
        uart_tx     : out std_logic;

        -- Riscv core direct
        stall_i : in std_logic;
        fault_i : in std_logic;
        fault_o : out std_logic;
        registers_debug_o : out std_logic_vector(1023 downto 0);
        pc_debug_o : out std_logic_vector(31 downto 0);
        previous_pc_debug_o : out std_logic_vector(31 downto 0);

        -- External AXI4-Lite initiator
        ext_axi_awvalid : in  std_logic;
        ext_axi_awready : out std_logic;
        ext_axi_awaddr  : in  std_logic_vector(31 downto 0);
        ext_axi_awprot  : in  std_logic_vector(2 downto 0);
        ext_axi_wvalid  : in  std_logic;
        ext_axi_wready  : out std_logic;
        ext_axi_wdata   : in  std_logic_vector(31 downto 0);
        ext_axi_wstrb   : in  std_logic_vector(3 downto 0);
        ext_axi_bvalid  : out std_logic;
        ext_axi_bready  : in  std_logic;
        ext_axi_arvalid : in  std_logic;
        ext_axi_arready : out std_logic;
        ext_axi_araddr  : in  std_logic_vector(31 downto 0);
        ext_axi_arprot  : in  std_logic_vector(2 downto 0);
        ext_axi_rvalid  : out std_logic;
        ext_axi_rready  : in  std_logic;
        ext_axi_rdata   : out std_logic_vector(31 downto 0);
        ext_axi_bresp   : out std_logic_vector(1 downto 0);
        ext_axi_rresp   : out std_logic_vector(1 downto 0)
    );
end entity;

architecture rtl of soc is

    signal reset : std_logic;
    signal cpu_sync_reset : std_logic;
    signal gpio_in  : std_logic_vector(31 downto 0);
    signal gpio_out : std_logic_vector(31 downto 0);

    signal axi_awaddr : std_logic_vector(31 downto 0);
    signal axi_awprot : std_logic_vector(2 downto 0);
    signal axi_awvalid : std_logic;
    signal axi_awready : std_logic;
    signal axi_wdata : std_logic_vector(31 downto 0);
    signal axi_wstrb : std_logic_vector(3 downto 0);
    signal axi_wvalid : std_logic;
    signal axi_wready : std_logic;
    signal axi_bresp : std_logic_vector(1 downto 0);
    signal axi_bvalid : std_logic;
    signal axi_bready : std_logic;
    signal axi_araddr : std_logic_vector(31 downto 0);
    signal axi_arprot : std_logic_vector(2 downto 0);
    signal axi_arvalid : std_logic;
    signal axi_arready : std_logic;
    signal axi_rdata : std_logic_vector(31 downto 0);
    signal axi_rresp : std_logic_vector(1 downto 0);
    signal axi_rvalid : std_logic;
    signal axi_rready : std_logic;

begin
    reset <= '1' when (USE_ASYNC_RESET and async_reset = ASYNC_RESET_ACTIVE) or
                      (USE_SYNC_RESET and (sync_reset = SYNC_RESET_ACTIVE or cpu_reset_i = '1')) else '0';
    cpu_sync_reset <= SYNC_RESET_ACTIVE when sync_reset = SYNC_RESET_ACTIVE or cpu_reset_i = '1'
                      else not SYNC_RESET_ACTIVE;

    --------------------------------------------------------------------
    -- RISC-V CPU wrapper
    --------------------------------------------------------------------
    riscv_wrapper_inst : entity work.riscv_wrapper
        generic map (
            USE_ASYNC_RESET    => USE_ASYNC_RESET,
            USE_SYNC_RESET     => USE_SYNC_RESET,
            ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
            SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
            start_address      => x"00000000",
            enable_multiplier  => false,
            enable_divider     => false
        )
        port map (
            -- Clock and reset
            clock_i       => clk,
            async_reset => async_reset,
            sync_reset => cpu_sync_reset,

            -- CPU control
            stall_i => stall_i,
            fault_i => fault_i,
            fault_o => fault_o,

            -- Debug interface
            registers_debug_o   => registers_debug_o,
            pc_debug_o          => pc_debug_o,
            previous_pc_debug_o => previous_pc_debug_o,

            -- AXI4-Lite write address channel
            m_axi_awaddr_o  => axi_awaddr,
            m_axi_awprot_o  => axi_awprot,
            m_axi_awvalid_o => axi_awvalid,
            m_axi_awready_i => axi_awready,

            -- AXI4-Lite write data channel
            m_axi_wdata_o  => axi_wdata,
            m_axi_wstrb_o  => axi_wstrb,
            m_axi_wvalid_o => axi_wvalid,
            m_axi_wready_i => axi_wready,

            -- AXI4-Lite write response channel
            m_axi_bresp_i  => axi_bresp,
            m_axi_bvalid_i => axi_bvalid,
            m_axi_bready_o => axi_bready,

            -- AXI4-Lite read address channel
            m_axi_araddr_o  => axi_araddr,
            m_axi_arprot_o  => axi_arprot,
            m_axi_arvalid_o => axi_arvalid,
            m_axi_arready_i => axi_arready,

            -- AXI4-Lite read data channel
            m_axi_rdata_i  => axi_rdata,
            m_axi_rresp_i  => axi_rresp,
            m_axi_rvalid_i => axi_rvalid,
            m_axi_rready_o => axi_rready
        );    

    axi_soc_subsystem_inst : entity work.axi_soc_subsystem
        generic map (
            USE_ASYNC_RESET    => USE_ASYNC_RESET,
            USE_SYNC_RESET     => USE_SYNC_RESET,
            ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
            SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
            G_ADDR_WIDTH => 32,
            G_DATA_WIDTH => 32,
            G_BASE0      => x"00000000",
            G_LIMIT0     => x"000FFFFF",
            G_BASE1      => x"00100000",
            G_LIMIT1     => x"001FFFFF",
            G_BASE2      => x"00200000",
            G_LIMIT2     => x"002FFFFF",
            G_BASE3      => x"00300000",
            G_LIMIT3     => x"003FFFFF",
            G_RAM_DEPTH  => 8192,
            G_SYS_FREQ   => G_SYS_FREQ,
            G_BAUDRATE   => G_BAUDRATE,
            G_TX_DEPTH   => 256,
            G_RX_DEPTH   => 256
        )
        port map (
            clk                => clk,
            async_reset => async_reset,
            sync_reset => sync_reset,

            cpu_axi_awaddr     => axi_awaddr,
            cpu_axi_awprot     => axi_awprot,
            cpu_axi_awvalid    => axi_awvalid,
            cpu_axi_awready    => axi_awready,
            cpu_axi_wdata      => axi_wdata,
            cpu_axi_wstrb      => axi_wstrb,
            cpu_axi_wvalid     => axi_wvalid,
            cpu_axi_wready     => axi_wready,
            cpu_axi_bresp      => axi_bresp,
            cpu_axi_bvalid     => axi_bvalid,
            cpu_axi_bready     => axi_bready,
            cpu_axi_araddr     => axi_araddr,
            cpu_axi_arprot     => axi_arprot,
            cpu_axi_arvalid    => axi_arvalid,
            cpu_axi_arready    => axi_arready,
            cpu_axi_rdata      => axi_rdata,
            cpu_axi_rresp      => axi_rresp,
            cpu_axi_rvalid     => axi_rvalid,
            cpu_axi_rready     => axi_rready,
            ext_axi_awaddr     => ext_axi_awaddr,
            ext_axi_awprot     => ext_axi_awprot,
            ext_axi_awvalid    => ext_axi_awvalid,
            ext_axi_awready    => ext_axi_awready,
            ext_axi_wdata      => ext_axi_wdata,
            ext_axi_wstrb      => ext_axi_wstrb,
            ext_axi_wvalid     => ext_axi_wvalid,
            ext_axi_wready     => ext_axi_wready,
            ext_axi_bresp      => ext_axi_bresp,
            ext_axi_bvalid     => ext_axi_bvalid,
            ext_axi_bready     => ext_axi_bready,
            ext_axi_araddr     => ext_axi_araddr,
            ext_axi_arprot     => ext_axi_arprot,
            ext_axi_arvalid    => ext_axi_arvalid,
            ext_axi_arready    => ext_axi_arready,
            ext_axi_rdata      => ext_axi_rdata,
            ext_axi_rresp      => ext_axi_rresp,
            ext_axi_rvalid     => ext_axi_rvalid,
            ext_axi_rready     => ext_axi_rready,
            uart_rx            => uart_rx,
            uart_tx            => uart_tx,
            gpio_in            => gpio_in,
            gpio_out           => gpio_out
        );

    gpio_in <= gpio_out;

end architecture rtl;
