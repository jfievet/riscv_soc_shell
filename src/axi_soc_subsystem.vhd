library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.axi_slave_reg_bank_pkg.all;
use work.timestamp_pkg.all;
use work.axi_lite_interconnect_pkg.all;

entity axi_soc_subsystem is
    generic (
        USE_ASYNC_RESET    : boolean   := TRUE;
        USE_SYNC_RESET     : boolean   := TRUE;
        ASYNC_RESET_ACTIVE : std_logic := '1';
        SYNC_RESET_ACTIVE  : std_logic := '1';
        G_ADDR_WIDTH : positive := 32;
        G_DATA_WIDTH : positive := 32;

        -- AXI-Lite interconnect address map
        G_BASE0  : std_logic_vector(32-1 downto 0) := (others => '0');
        G_LIMIT0 : std_logic_vector(32-1 downto 0) := x"000FFFFF"; -- 64 kB  0x10000 <=> 65536
        G_BASE1  : std_logic_vector(32-1 downto 0) := x"00100000";
        G_LIMIT1 : std_logic_vector(32-1 downto 0) := x"001FFFFF";
        G_BASE2  : std_logic_vector(32-1 downto 0) := x"00200000";
        G_LIMIT2 : std_logic_vector(32-1 downto 0) := x"002FFFFF";
        G_BASE3  : std_logic_vector(32-1 downto 0) := x"00300000";
        G_LIMIT3 : std_logic_vector(32-1 downto 0) := x"003FFFFF";

        -- AXI RAM
        G_RAM_DEPTH : positive := 1024;

        -- AXI UART
        G_SYS_FREQ : natural := 50_000_000;
        G_BAUDRATE : natural := 115200;
        G_TX_DEPTH : natural := 16;
        G_RX_DEPTH : natural := 16
    );
    port (
        clk            : in  std_logic;                          -- Added clock
        async_reset : in std_logic;
        sync_reset  : in std_logic;                          -- Added active-low reset
        cpu_axi_awvalid : in  std_logic;
        cpu_axi_awready : out std_logic;
        cpu_axi_awaddr  : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
        cpu_axi_awprot  : in  std_logic_vector(2 downto 0);
        cpu_axi_wvalid  : in  std_logic;
        cpu_axi_wready  : out std_logic;
        cpu_axi_wdata   : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
        cpu_axi_wstrb   : in  std_logic_vector((G_DATA_WIDTH/8)-1 downto 0);
        cpu_axi_bvalid  : out std_logic;
        cpu_axi_bready  : in  std_logic;
        cpu_axi_arvalid : in  std_logic;
        cpu_axi_arready : out std_logic;
        cpu_axi_araddr  : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
        cpu_axi_arprot  : in  std_logic_vector(2 downto 0);
        cpu_axi_rvalid  : out std_logic;
        cpu_axi_rready  : in  std_logic;
        cpu_axi_rdata   : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
        cpu_axi_bresp   : out std_logic_vector(1 downto 0);
        cpu_axi_rresp   : out std_logic_vector(1 downto 0);
        ext_axi_awvalid : in  std_logic;
        ext_axi_awready : out std_logic;
        ext_axi_awaddr  : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
        ext_axi_awprot  : in  std_logic_vector(2 downto 0);
        ext_axi_wvalid  : in  std_logic;
        ext_axi_wready  : out std_logic;
        ext_axi_wdata   : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
        ext_axi_wstrb   : in  std_logic_vector((G_DATA_WIDTH/8)-1 downto 0);
        ext_axi_bvalid  : out std_logic;
        ext_axi_bready  : in  std_logic;
        ext_axi_arvalid : in  std_logic;
        ext_axi_arready : out std_logic;
        ext_axi_araddr  : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
        ext_axi_arprot  : in  std_logic_vector(2 downto 0);
        ext_axi_rvalid  : out std_logic;
        ext_axi_rready  : in  std_logic;
        ext_axi_rdata   : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
        ext_axi_bresp   : out std_logic_vector(1 downto 0);
        ext_axi_rresp   : out std_logic_vector(1 downto 0);
        uart_rx         : in  std_logic;
        uart_tx         : out std_logic;
        gpio_in         : in std_logic_vector(31 downto 0);
        gpio_out        : out std_logic_vector(31 downto 0)
);
end entity;

architecture rtl of axi_soc_subsystem is

-- Interconnect configuration
constant C_NB_MASTERS : integer := 2; -- CPU and external initiators
constant C_NB_SLAVES  : integer := 4; -- RAM, UART, GPIO, register bank

constant C_ADDR_START : axi_32b_bus_type := (
    0 => G_BASE0,
    1 => G_BASE1,
    2 => G_BASE2,
    3 => G_BASE3,
    others => (others => '0')
);

constant C_ADDR_END : axi_32b_bus_type := (
    0 => G_LIMIT0,
    1 => G_LIMIT1,
    2 => G_LIMIT2,
    3 => G_LIMIT3,
    others => (others => '0')
);

constant C_ADDR_OFFSET : axi_32b_bus_type := (
    0 => G_BASE0,
    1 => G_BASE1,
    2 => G_BASE2,
    3 => G_BASE3,
    others => (others => '0')
);

-- Array ports: initiators are indexed 0=CPU, 1=external.
-- The interconnect package must support the corresponding array bounds.
    -- AXI-Lite Interconnect Slave
    signal ic_s_awvalid : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_awready : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_awaddr  : axi_32b_bus_type;
    signal ic_s_wvalid  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_wready  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_wdata   : axi_32b_bus_type;
    signal ic_s_wstrb   : axi_4b_bus_type;
    signal ic_s_bvalid  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_bready  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_bresp   : axi_2b_bus_type;
    signal ic_s_arvalid : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_arready : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_araddr  : axi_32b_bus_type;
    signal ic_s_rvalid  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_rready  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_s_rdata   : axi_32b_bus_type;
    signal ic_s_rresp   : axi_2b_bus_type;

    -- AXI-Lite Interconnect Master
    signal ic_m_awvalid : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_awready : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_awaddr  : axi_32b_bus_type;
    signal ic_m_wvalid  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_wready  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_wdata   : axi_32b_bus_type;
    signal ic_m_wstrb   : axi_4b_bus_type;
    signal ic_m_bvalid  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_bready  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_bresp   : axi_2b_bus_type;
    signal ic_m_arvalid : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_arready : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_araddr  : axi_32b_bus_type;
    signal ic_m_rvalid  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_rready  : std_logic_vector(nb_axi_lite_array - 1 downto 0);
    signal ic_m_rdata   : axi_32b_bus_type;
    signal ic_m_rresp   : axi_2b_bus_type;

-- AXI RAM constants
constant axi_ram_DEPTH_c : integer := G_RAM_DEPTH;
constant C_RAM_VENDOR : integer := 1;
-- AXI UART generics constants
constant axi_uart_SYS_FREQ_c : natural := G_SYS_FREQ;
constant axi_uart_BAUDRATE_c : natural := G_BAUDRATE;
constant axi_uart_TX_DEPTH_c : natural := G_TX_DEPTH;
constant axi_uart_RX_DEPTH_c : natural := G_RX_DEPTH;

-- AXI RAM 
signal axi_ram_mem_axi_awvalid : std_logic;
signal axi_ram_mem_axi_awready : std_logic;
signal axi_ram_mem_axi_awaddr  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_ram_mem_axi_awprot  : std_logic_vector(2 downto 0);
signal axi_ram_mem_axi_wvalid  : std_logic;
signal axi_ram_mem_axi_wready  : std_logic;
signal axi_ram_mem_axi_wdata   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_ram_mem_axi_wstrb   : std_logic_vector((G_DATA_WIDTH/8)-1 downto 0);
signal axi_ram_mem_axi_bvalid  : std_logic;
signal axi_ram_mem_axi_bready  : std_logic;
signal axi_ram_mem_axi_arvalid : std_logic;
signal axi_ram_mem_axi_arready : std_logic;
signal axi_ram_mem_axi_araddr  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_ram_mem_axi_arprot  : std_logic_vector(2 downto 0);
signal axi_ram_mem_axi_rvalid  : std_logic;
signal axi_ram_mem_axi_rready  : std_logic;
signal axi_ram_mem_axi_rdata   : std_logic_vector(G_DATA_WIDTH-1 downto 0);

-- AXI UART interface signals
signal axi_uart_AWADDR  : std_logic_vector(31 downto 0);
signal axi_uart_AWVALID : std_logic;
signal axi_uart_AWREADY : std_logic;
signal axi_uart_WDATA   : std_logic_vector(31 downto 0);
signal axi_uart_WSTRB   : std_logic_vector(3 downto 0);
signal axi_uart_WVALID  : std_logic;
signal axi_uart_WREADY  : std_logic;
signal axi_uart_BRESP   : std_logic_vector(1 downto 0);
signal axi_uart_BVALID  : std_logic;
signal axi_uart_BREADY  : std_logic;
signal axi_uart_ARADDR  : std_logic_vector(31 downto 0);
signal axi_uart_ARVALID : std_logic;
signal axi_uart_ARREADY : std_logic;
signal axi_uart_RDATA   : std_logic_vector(31 downto 0);
signal axi_uart_RRESP   : std_logic_vector(1 downto 0);
signal axi_uart_RVALID  : std_logic;
signal axi_uart_RREADY  : std_logic;

-- AXI GPIO interface signals
signal axi_gpio_awaddr      : std_logic_vector(32-1 downto 0);
signal axi_gpio_awprot      : std_logic_vector(2 downto 0);
signal axi_gpio_awvalid     : std_logic;
signal axi_gpio_awready     : std_logic;
signal axi_gpio_wdata       : std_logic_vector(32-1 downto 0);
signal axi_gpio_wstrb       : std_logic_vector((32/8)-1 downto 0);
signal axi_gpio_wvalid      : std_logic;
signal axi_gpio_wready      : std_logic;
signal axi_gpio_bresp       : std_logic_vector(1 downto 0);
signal axi_gpio_bvalid      : std_logic;
signal axi_gpio_bready      : std_logic;
signal axi_gpio_araddr      : std_logic_vector(32-1 downto 0);
signal axi_gpio_arprot      : std_logic_vector(2 downto 0);
signal axi_gpio_arvalid     : std_logic;
signal axi_gpio_arready     : std_logic;
signal axi_gpio_rdata       : std_logic_vector(32-1 downto 0);
signal axi_gpio_rresp       : std_logic_vector(1 downto 0);
signal axi_gpio_rvalid      : std_logic;
signal axi_gpio_rready      : std_logic;
signal axi_gpio_gpio_in     : std_logic_vector(31 downto 0);
signal axi_gpio_gpio_out    : std_logic_vector(31 downto 0);

-- UART
signal axi_uart_uart_tx  : std_logic;
signal axi_uart_uart_rx  : std_logic;

-- Axi slave reg bank signals
signal axi_slave_reg_bank_awvalid : std_logic;
signal axi_slave_reg_bank_awready : std_logic;
signal axi_slave_reg_bank_awaddr  : std_logic_vector(32-1 downto 0);
signal axi_slave_reg_bank_awprot  : std_logic_vector(2 downto 0);
signal axi_slave_reg_bank_wvalid  : std_logic;
signal axi_slave_reg_bank_wready  : std_logic;
signal axi_slave_reg_bank_wdata   : std_logic_vector(32-1 downto 0);
signal axi_slave_reg_bank_wstrb   : std_logic_vector(3 downto 0);
signal axi_slave_reg_bank_bvalid  : std_logic;
signal axi_slave_reg_bank_bready  : std_logic;
signal axi_slave_reg_bank_arvalid : std_logic;
signal axi_slave_reg_bank_arready : std_logic;
signal axi_slave_reg_bank_araddr  : std_logic_vector(32-1 downto 0);
signal axi_slave_reg_bank_arprot  : std_logic_vector(2 downto 0);
signal axi_slave_reg_bank_rvalid  : std_logic;
signal axi_slave_reg_bank_rready  : std_logic;
signal axi_slave_reg_bank_rdata   : std_logic_vector(32-1 downto 0);

-- Register bank signals
signal register_bank_wr    : reg_bank_t;
signal register_bank_wr_en : std_logic_vector(C_DEPTH-1 downto 0);
signal register_bank_rd    : reg_bank_t;
signal register_bank_rd_en : std_logic_vector(C_DEPTH-1 downto 0);

-- Time enlpased signal
signal elapsed_time : std_logic_vector(63 downto 0);

begin
    assert G_ADDR_WIDTH = 32 and G_DATA_WIDTH = 32
        report "axi_lite_interconnect requires 32-bit address/data" severity failure;

-----------------------------------------------------------
-- AXI-Lite interconnect: 2 initiators, 4 targets
-----------------------------------------------------------
u_axi_lite_interconnect : entity work.axi_lite_interconnect(rtl)
    generic map (
        USE_ASYNC_RESET    => USE_ASYNC_RESET,
        USE_SYNC_RESET     => USE_SYNC_RESET,
        ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
        SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
        nb_slave_ports     => C_NB_MASTERS,
        nb_master_ports    => C_NB_SLAVES,
        addr_start         => C_ADDR_START,
        addr_end           => C_ADDR_END,
        addr_offset        => C_ADDR_OFFSET
    )
    port map (
        clock       => clk,
        async_reset => async_reset,
        sync_reset => sync_reset,

        s_axi_awvalid => ic_s_awvalid,
        s_axi_awready => ic_s_awready,
        s_axi_awaddr => ic_s_awaddr,
        s_axi_wvalid => ic_s_wvalid,
        s_axi_wready => ic_s_wready,
        s_axi_wdata => ic_s_wdata,
        s_axi_wstrb => ic_s_wstrb,
        s_axi_bvalid => ic_s_bvalid,
        s_axi_bready => ic_s_bready,
        s_axi_bresp => ic_s_bresp,
        s_axi_arvalid => ic_s_arvalid,
        s_axi_arready => ic_s_arready,
        s_axi_araddr => ic_s_araddr,
        s_axi_rvalid => ic_s_rvalid,
        s_axi_rready => ic_s_rready,
        s_axi_rdata => ic_s_rdata,
        s_axi_rresp => ic_s_rresp,
        m_axi_awvalid => ic_m_awvalid,
        m_axi_awready => ic_m_awready,
        m_axi_awaddr => ic_m_awaddr,
        m_axi_wvalid => ic_m_wvalid,
        m_axi_wready => ic_m_wready,
        m_axi_wdata => ic_m_wdata,
        m_axi_wstrb => ic_m_wstrb,
        m_axi_bvalid => ic_m_bvalid,
        m_axi_bready => ic_m_bready,
        m_axi_bresp => ic_m_bresp,
        m_axi_arvalid => ic_m_arvalid,
        m_axi_arready => ic_m_arready,
        m_axi_araddr => ic_m_araddr,
        m_axi_rvalid => ic_m_rvalid,
        m_axi_rready => ic_m_rready,
        m_axi_rdata => ic_m_rdata,
        m_axi_rresp => ic_m_rresp
    );

ic_s_awvalid(0) <= cpu_axi_awvalid;
cpu_axi_awready <= ic_s_awready(0);
ic_s_awaddr(0) <= cpu_axi_awaddr;
ic_s_wvalid(0) <= cpu_axi_wvalid;
cpu_axi_wready <= ic_s_wready(0);
ic_s_wdata(0) <= cpu_axi_wdata;
ic_s_wstrb(0) <= cpu_axi_wstrb;
cpu_axi_bvalid <= ic_s_bvalid(0);
ic_s_bready(0) <= cpu_axi_bready;
cpu_axi_bresp <= ic_s_bresp(0);
ic_s_arvalid(0) <= cpu_axi_arvalid;
cpu_axi_arready <= ic_s_arready(0);
ic_s_araddr(0) <= cpu_axi_araddr;
cpu_axi_rvalid <= ic_s_rvalid(0);
ic_s_rready(0) <= cpu_axi_rready;
cpu_axi_rdata <= ic_s_rdata(0);
cpu_axi_rresp <= ic_s_rresp(0);
ic_s_awvalid(1) <= ext_axi_awvalid;
ext_axi_awready <= ic_s_awready(1);
ic_s_awaddr(1) <= ext_axi_awaddr;
ic_s_wvalid(1) <= ext_axi_wvalid;
ext_axi_wready <= ic_s_wready(1);
ic_s_wdata(1) <= ext_axi_wdata;
ic_s_wstrb(1) <= ext_axi_wstrb;
ext_axi_bvalid <= ic_s_bvalid(1);
ic_s_bready(1) <= ext_axi_bready;
ext_axi_bresp <= ic_s_bresp(1);
ic_s_arvalid(1) <= ext_axi_arvalid;
ext_axi_arready <= ic_s_arready(1);
ic_s_araddr(1) <= ext_axi_araddr;
ext_axi_rvalid <= ic_s_rvalid(1);
ic_s_rready(1) <= ext_axi_rready;
ext_axi_rdata <= ic_s_rdata(1);
ext_axi_rresp <= ic_s_rresp(1);

-----------------------------------------------------------
--      AXI RAM
-----------------------------------------------------------

-- AXI RAM <-> Interconnect bindings (slave 0)
axi_ram_mem_axi_awvalid <= ic_m_awvalid(0);
ic_m_awready(0) <= axi_ram_mem_axi_awready;
axi_ram_mem_axi_awaddr <= ic_m_awaddr(0);
axi_ram_mem_axi_awprot <= (others => '0');

axi_ram_mem_axi_wvalid <= ic_m_wvalid(0);
ic_m_wready(0) <= axi_ram_mem_axi_wready;
axi_ram_mem_axi_wdata <= ic_m_wdata(0);
axi_ram_mem_axi_wstrb <= ic_m_wstrb(0);

ic_m_bvalid(0) <= axi_ram_mem_axi_bvalid;
axi_ram_mem_axi_bready <= ic_m_bready(0);
ic_m_bresp(0) <= (others => '0');

axi_ram_mem_axi_arvalid <= ic_m_arvalid(0);
ic_m_arready(0) <= axi_ram_mem_axi_arready;
axi_ram_mem_axi_araddr <= ic_m_araddr(0);
axi_ram_mem_axi_arprot <= (others => '0');

ic_m_rvalid(0) <= axi_ram_mem_axi_rvalid;
axi_ram_mem_axi_rready <= ic_m_rready(0);
ic_m_rdata(0) <= axi_ram_mem_axi_rdata;
ic_m_rresp(0) <= (others => '0');

-- AXI RAM instantiation
u_axi_ram : entity work.axi_ram
    generic map (
        USE_ASYNC_RESET    => USE_ASYNC_RESET,
        USE_SYNC_RESET     => USE_SYNC_RESET,
        ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
        SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
        G_DATA_WIDTH => G_DATA_WIDTH,
        G_ADDR_WIDTH => G_ADDR_WIDTH,
        G_DEPTH      => axi_ram_DEPTH_c,
        G_RAM_VENDOR => C_RAM_VENDOR
    )
    port map (
        clk             => clk,
        async_reset => async_reset,
        sync_reset => sync_reset,

        mem_axi_awvalid => axi_ram_mem_axi_awvalid,
        mem_axi_awready => axi_ram_mem_axi_awready,
        mem_axi_awaddr  => axi_ram_mem_axi_awaddr,
        mem_axi_awprot  => axi_ram_mem_axi_awprot,
        mem_axi_wvalid  => axi_ram_mem_axi_wvalid,
        mem_axi_wready  => axi_ram_mem_axi_wready,
        mem_axi_wdata   => axi_ram_mem_axi_wdata,
        mem_axi_wstrb   => axi_ram_mem_axi_wstrb,
        mem_axi_bvalid  => axi_ram_mem_axi_bvalid,
        mem_axi_bready  => axi_ram_mem_axi_bready,
        mem_axi_arvalid => axi_ram_mem_axi_arvalid,
        mem_axi_arready => axi_ram_mem_axi_arready,
        mem_axi_araddr  => axi_ram_mem_axi_araddr,
        mem_axi_arprot  => axi_ram_mem_axi_arprot,
        mem_axi_rvalid  => axi_ram_mem_axi_rvalid,
        mem_axi_rready  => axi_ram_mem_axi_rready,
        mem_axi_rdata   => axi_ram_mem_axi_rdata
    );

-----------------------------------------------------------
--      AXI UART
-----------------------------------------------------------


-- AXI UART <-> Interconnect bindings (slave 1) 

-- Write address channel
axi_uart_AWADDR  <= ic_m_awaddr(1);
axi_uart_AWVALID <= ic_m_awvalid(1);
ic_m_awready(1) <= axi_uart_AWREADY;

-- Write data channel
axi_uart_WDATA   <= ic_m_wdata(1);
axi_uart_WSTRB   <= ic_m_wstrb(1)(3 downto 0);
axi_uart_WVALID  <= ic_m_wvalid(1);
ic_m_wready(1) <= axi_uart_WREADY;

-- Write response channel
ic_m_bresp(1)  <= axi_uart_BRESP;
ic_m_bvalid(1) <= axi_uart_BVALID;
axi_uart_BREADY <= ic_m_bready(1);

-- Read address channel
axi_uart_ARADDR  <= ic_m_araddr(1);
axi_uart_ARVALID <= ic_m_arvalid(1);
ic_m_arready(1) <= axi_uart_ARREADY;

-- Read data channel
ic_m_rdata(1)  <= axi_uart_RDATA;
ic_m_rresp(1)  <= axi_uart_RRESP;
ic_m_rvalid(1) <= axi_uart_RVALID;
axi_uart_RREADY <= ic_m_rready(1);

-- UART pins
uart_tx <= axi_uart_uart_tx;
axi_uart_uart_rx <= uart_rx;

----------------------------------------------------------------
-- AXI UART instantiation
----------------------------------------------------------------
u_axi_uart : entity work.axi_uart
    generic map (
        USE_ASYNC_RESET    => USE_ASYNC_RESET,
        USE_SYNC_RESET     => USE_SYNC_RESET,
        ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
        SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
        G_SYS_FREQ => axi_uart_SYS_FREQ_c,
        G_BAUDRATE => axi_uart_BAUDRATE_c,
        G_TX_DEPTH => axi_uart_TX_DEPTH_c,
        G_RX_DEPTH => axi_uart_RX_DEPTH_c
    )
    port map (
        ACLK    => clk,
        async_reset => async_reset,
        sync_reset => sync_reset,

        AWADDR  => axi_uart_AWADDR,
        AWVALID => axi_uart_AWVALID,
        AWREADY => axi_uart_AWREADY,
        WDATA   => axi_uart_WDATA,
        WSTRB   => axi_uart_WSTRB,
        WVALID  => axi_uart_WVALID,
        WREADY  => axi_uart_WREADY,
        BRESP   => axi_uart_BRESP,
        BVALID  => axi_uart_BVALID,
        BREADY  => axi_uart_BREADY,
        ARADDR  => axi_uart_ARADDR,
        ARVALID => axi_uart_ARVALID,
        ARREADY => axi_uart_ARREADY,
        RDATA   => axi_uart_RDATA,
        RRESP   => axi_uart_RRESP,
        RVALID  => axi_uart_RVALID,
        RREADY  => axi_uart_RREADY,
        uart_tx => axi_uart_uart_tx,
        uart_rx => axi_uart_uart_rx
    );


    -----------------------------------------------------------
    --      AXI GPIO (Slave 2)
    -----------------------------------------------------------

    -- AXI GPIO <-> Interconnect bindings (slave 2)
    -- Write address channel
    ic_m_awready(2) <= axi_gpio_awready;
    axi_gpio_awaddr  <= ic_m_awaddr(2);
    axi_gpio_awprot  <= (others => '0');
    axi_gpio_awvalid <= ic_m_awvalid(2);

    -- Write data channel
    ic_m_wready(2) <= axi_gpio_wready;
    axi_gpio_wdata  <= ic_m_wdata(2);
    axi_gpio_wstrb  <= ic_m_wstrb(2);
    axi_gpio_wvalid <= ic_m_wvalid(2);

    -- Write response channel
    ic_m_bresp(2)  <= axi_gpio_bresp;
    ic_m_bvalid(2) <= axi_gpio_bvalid;
    axi_gpio_bready <= ic_m_bready(2);

    -- Read address channel
    ic_m_arready(2) <= axi_gpio_arready;
    axi_gpio_araddr  <= ic_m_araddr(2);
    axi_gpio_arprot  <= (others => '0');
    axi_gpio_arvalid <= ic_m_arvalid(2);

    -- Read data channel
    ic_m_rdata(2)  <= axi_gpio_rdata;
    ic_m_rresp(2)  <= axi_gpio_rresp;
    ic_m_rvalid(2) <= axi_gpio_rvalid;
    axi_gpio_rready <= ic_m_rready(2);

    -- AXI GPIO instantiation
    u_axi_gpio : entity work.axi_gpio
        generic map (
            USE_ASYNC_RESET    => USE_ASYNC_RESET,
            USE_SYNC_RESET     => USE_SYNC_RESET,
            ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
            SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE
        )
        port map (
            s_axi_aclk    => clk,
            async_reset => async_reset,
            sync_reset => sync_reset,

            s_axi_awaddr  => axi_gpio_awaddr,
            s_axi_awprot  => axi_gpio_awprot,
            s_axi_awvalid => axi_gpio_awvalid,
            s_axi_awready => axi_gpio_awready,
            s_axi_wdata   => axi_gpio_wdata,
            s_axi_wstrb   => axi_gpio_wstrb,
            s_axi_wvalid  => axi_gpio_wvalid,
            s_axi_wready  => axi_gpio_wready,
            s_axi_bresp   => axi_gpio_bresp,
            s_axi_bvalid  => axi_gpio_bvalid,
            s_axi_bready  => axi_gpio_bready,
            s_axi_araddr  => axi_gpio_araddr,
            s_axi_arprot  => axi_gpio_arprot,
            s_axi_arvalid => axi_gpio_arvalid,
            s_axi_arready => axi_gpio_arready,
            s_axi_rdata   => axi_gpio_rdata,
            s_axi_rresp   => axi_gpio_rresp,
            s_axi_rvalid  => axi_gpio_rvalid,
            s_axi_rready  => axi_gpio_rready,
            gpio_in       => axi_gpio_gpio_in,
            gpio_out      => axi_gpio_gpio_out
        );

-- Connect top-level GPIO ports to AXI GPIO signals
axi_gpio_gpio_in  <= gpio_in;
gpio_out          <= axi_gpio_gpio_out;

    -----------------------------------------------------------
    --      AXI SLAVE REGISTER BANK (Slave 3)
    -----------------------------------------------------------

    -- AXI Slave Reg Bank <-> Interconnect bindings (slave 3)
    ic_m_awready(3) <= axi_slave_reg_bank_awready;
    axi_slave_reg_bank_awvalid <= ic_m_awvalid(3);
    axi_slave_reg_bank_awaddr  <= ic_m_awaddr(3);

    ic_m_wready(3) <= axi_slave_reg_bank_wready;
    axi_slave_reg_bank_wvalid <= ic_m_wvalid(3);
    axi_slave_reg_bank_wdata  <= ic_m_wdata(3);
    axi_slave_reg_bank_wstrb  <= ic_m_wstrb(3);

    ic_m_bvalid(3) <= axi_slave_reg_bank_bvalid;
    axi_slave_reg_bank_bready <= ic_m_bready(3);
    ic_m_bresp(3)  <= (others => '0');

    axi_slave_reg_bank_arvalid <= ic_m_arvalid(3);
    ic_m_arready(3) <= axi_slave_reg_bank_arready;
    axi_slave_reg_bank_araddr  <= ic_m_araddr(3);

    ic_m_rvalid(3) <= axi_slave_reg_bank_rvalid;
    axi_slave_reg_bank_rready <= ic_m_rready(3);
    ic_m_rdata(3)  <= axi_slave_reg_bank_rdata;
    ic_m_rresp(3)  <= (others => '0');

    axi_slave_reg_bank_awprot <= (others => '0');
    axi_slave_reg_bank_arprot <= (others => '0');

    u_axi_slave_reg_bank : entity work.axi_slave_reg_bank
        generic map (
            USE_ASYNC_RESET    => USE_ASYNC_RESET,
            USE_SYNC_RESET     => USE_SYNC_RESET,
            ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
            SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
            G_ADDR_WIDTH => 32,
            G_DATA_WIDTH => 32
        )
        port map (
            clk                 => clk,
            async_reset => async_reset,
            sync_reset => sync_reset,

            mem_axi_awvalid     => axi_slave_reg_bank_awvalid,
            mem_axi_awready     => axi_slave_reg_bank_awready,
            mem_axi_awaddr      => axi_slave_reg_bank_awaddr,
            mem_axi_awprot      => axi_slave_reg_bank_awprot,
            mem_axi_wvalid      => axi_slave_reg_bank_wvalid,
            mem_axi_wready      => axi_slave_reg_bank_wready,
            mem_axi_wdata       => axi_slave_reg_bank_wdata,
            mem_axi_wstrb       => axi_slave_reg_bank_wstrb,
            mem_axi_bvalid      => axi_slave_reg_bank_bvalid,
            mem_axi_bready      => axi_slave_reg_bank_bready,
            mem_axi_arvalid     => axi_slave_reg_bank_arvalid,
            mem_axi_arready     => axi_slave_reg_bank_arready,
            mem_axi_araddr      => axi_slave_reg_bank_araddr,
            mem_axi_arprot      => axi_slave_reg_bank_arprot,
            mem_axi_rvalid      => axi_slave_reg_bank_rvalid,
            mem_axi_rready      => axi_slave_reg_bank_rready,
            mem_axi_rdata       => axi_slave_reg_bank_rdata,
            register_bank_wr    => register_bank_wr,
            register_bank_wr_en => register_bank_wr_en,
            register_bank_rd    => register_bank_rd,
            register_bank_rd_en => register_bank_rd_en
        );

        -- Store date and time constants in the first register_bank_rd entry

        -- AXI 0x00
        register_bank_rd(0)(7 downto 0)     <= C_DAY_HEX;
        register_bank_rd(0)(15 downto 8)    <= C_MONTH_HEX;
        register_bank_rd(0)(31 downto 16)   <= C_YEAR_HEX;

        -- AXI 0x04
        register_bank_rd(1)(7 downto 0)     <= C_HOUR_HEX;
        register_bank_rd(1)(15 downto 8)    <= C_MINUTE_HEX;
        register_bank_rd(1)(23 downto 16)   <= C_SECOND_HEX;
        register_bank_rd(1)(31 downto 24)   <= (others => '0');

        -- AXI 0x08
        register_bank_rd(2)                 <= register_bank_wr(2); -- Test loopback


        -- AXI 0x0C
        register_bank_rd(3)                 <= std_logic_vector(to_unsigned(G_SYS_FREQ,32));

        -- AXI 0x10
        register_bank_rd(4)                 <= elapsed_time(31 downto 0);

        -- AXI 0x14
        register_bank_rd(5)                 <= elapsed_time(63 downto 32);

        ---- Connect write register bank to read register bank
        --for i in register_bank_rd'range loop
        --    register_bank_rd(i) <= register_bank_wr(i);
        --end loop;


    time_elapsed_inst : entity work.time_elapsed
        generic map (
            G_USE_ASYNC_RESET    => USE_ASYNC_RESET ,
            G_USE_SYNC_RESET     => USE_SYNC_RESET,
            G_ASYNC_RESET_ACTIVE => '1',
            G_SYNC_RESET_ACTIVE  => '1'
        )
        port map (
            clk          => clk,
            async_reset  => async_reset,
            sync_reset   => sync_reset,
            sync_pulse   => register_bank_rd_en(3),
            elapsed_time => elapsed_time
        );


end rtl;

