library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.axi_slave_reg_bank_pkg.all;
use work.timestamp_pkg.all;

entity axi_soc_subsystem is
    generic (
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
        resetn         : in  std_logic;                          -- Added active-low reset
        mem_axi_awvalid : in  std_logic;
        mem_axi_awready : out std_logic;
        mem_axi_awaddr  : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
        mem_axi_awprot  : in  std_logic_vector(2 downto 0);
        mem_axi_wvalid  : in  std_logic;
        mem_axi_wready  : out std_logic;
        mem_axi_wdata   : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
        mem_axi_wstrb   : in  std_logic_vector((G_DATA_WIDTH/8)-1 downto 0);
        mem_axi_bvalid  : out std_logic;
        mem_axi_bready  : in  std_logic;
        mem_axi_arvalid : in  std_logic;
        mem_axi_arready : out std_logic;
        mem_axi_araddr  : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
        mem_axi_arprot  : in  std_logic_vector(2 downto 0);
        mem_axi_rvalid  : out std_logic;
        mem_axi_rready  : in  std_logic;
        mem_axi_rdata   : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
        mem_axi_bresp   : out std_logic_vector(1 downto 0);
        mem_axi_rresp   : out std_logic_vector(1 downto 0);
        uart_rx         : in  std_logic;
        uart_tx         : out std_logic;
        gpio_in         : in std_logic_vector(31 downto 0);
        gpio_out        : out std_logic_vector(31 downto 0)
);
end entity;

architecture rtl of axi_soc_subsystem is

-- Constants
constant axi_lite_interconnect_1x4_BASE0_c  : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := G_BASE0  ;
constant axi_lite_interconnect_1x4_LIMIT0_c : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := G_LIMIT0 ;
constant axi_lite_interconnect_1x4_BASE1_c  : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := G_BASE1  ;
constant axi_lite_interconnect_1x4_LIMIT1_c : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := G_LIMIT1 ;
constant axi_lite_interconnect_1x4_BASE2_c  : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := G_BASE2  ;
constant axi_lite_interconnect_1x4_LIMIT2_c : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := G_LIMIT2 ;
constant axi_lite_interconnect_1x4_BASE3_c  : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := G_BASE3  ;
constant axi_lite_interconnect_1x4_LIMIT3_c : std_logic_vector(G_ADDR_WIDTH-1 downto 0) := G_LIMIT3 ;

-- AXI RAM constants
constant axi_ram_DEPTH_c : integer:= G_RAM_DEPTH;
constant C_RAM_VENDOR    : integer := 1;

-- AXI UART generics constants
constant axi_uart_SYS_FREQ_c  : natural := G_SYS_FREQ;
constant axi_uart_BAUDRATE_c  : natural := G_BAUDRATE;
constant axi_uart_TX_DEPTH_c  : natural := G_TX_DEPTH;
constant axi_uart_RX_DEPTH_c  : natural := G_RX_DEPTH;

-- Master side extra response  (top does not expose BRESP/RRESP)
signal axi_lite_interconnect_1x4_M_BRESP : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_M_RRESP : std_logic_vector(1 downto 0);

-- Slave 0 
signal axi_lite_interconnect_1x4_S0_AWADDR  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S0_AWVALID : std_logic;
signal axi_lite_interconnect_1x4_S0_AWREADY : std_logic;
signal axi_lite_interconnect_1x4_S0_WDATA   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S0_WSTRB   : std_logic_vector((G_DATA_WIDTH/8)-1 downto 0);
signal axi_lite_interconnect_1x4_S0_WVALID  : std_logic;
signal axi_lite_interconnect_1x4_S0_WREADY  : std_logic;
signal axi_lite_interconnect_1x4_S0_BRESP   : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_S0_BVALID  : std_logic;
signal axi_lite_interconnect_1x4_S0_BREADY  : std_logic;
signal axi_lite_interconnect_1x4_S0_ARADDR  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S0_ARVALID : std_logic;
signal axi_lite_interconnect_1x4_S0_ARREADY : std_logic;
signal axi_lite_interconnect_1x4_S0_RDATA   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S0_RRESP   : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_S0_RVALID  : std_logic;
signal axi_lite_interconnect_1x4_S0_RREADY  : std_logic;

-- Slave 1 
signal axi_lite_interconnect_1x4_S1_AWADDR  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S1_AWVALID : std_logic;
signal axi_lite_interconnect_1x4_S1_AWREADY : std_logic;
signal axi_lite_interconnect_1x4_S1_WDATA   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S1_WSTRB   : std_logic_vector((G_DATA_WIDTH/8)-1 downto 0);
signal axi_lite_interconnect_1x4_S1_WVALID  : std_logic;
signal axi_lite_interconnect_1x4_S1_WREADY  : std_logic;
signal axi_lite_interconnect_1x4_S1_BRESP   : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_S1_BVALID  : std_logic;
signal axi_lite_interconnect_1x4_S1_BREADY  : std_logic;
signal axi_lite_interconnect_1x4_S1_ARADDR  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S1_ARVALID : std_logic;
signal axi_lite_interconnect_1x4_S1_ARREADY : std_logic;
signal axi_lite_interconnect_1x4_S1_RDATA   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S1_RRESP   : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_S1_RVALID  : std_logic;
signal axi_lite_interconnect_1x4_S1_RREADY  : std_logic;

-- Slave 2 
signal axi_lite_interconnect_1x4_S2_AWADDR  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S2_AWVALID : std_logic;
signal axi_lite_interconnect_1x4_S2_AWREADY : std_logic;
signal axi_lite_interconnect_1x4_S2_WDATA   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S2_WSTRB   : std_logic_vector((G_DATA_WIDTH/8)-1 downto 0);
signal axi_lite_interconnect_1x4_S2_WVALID  : std_logic;
signal axi_lite_interconnect_1x4_S2_WREADY  : std_logic;
signal axi_lite_interconnect_1x4_S2_BRESP   : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_S2_BVALID  : std_logic;
signal axi_lite_interconnect_1x4_S2_BREADY  : std_logic;
signal axi_lite_interconnect_1x4_S2_ARADDR  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S2_ARVALID : std_logic;
signal axi_lite_interconnect_1x4_S2_ARREADY : std_logic;
signal axi_lite_interconnect_1x4_S2_RDATA   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S2_RRESP   : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_S2_RVALID  : std_logic;
signal axi_lite_interconnect_1x4_S2_RREADY  : std_logic;

-- Slave 3 
signal axi_lite_interconnect_1x4_S3_AWADDR  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S3_AWVALID : std_logic;
signal axi_lite_interconnect_1x4_S3_AWREADY : std_logic;
signal axi_lite_interconnect_1x4_S3_WDATA   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S3_WSTRB   : std_logic_vector((G_DATA_WIDTH/8)-1 downto 0);
signal axi_lite_interconnect_1x4_S3_WVALID  : std_logic;
signal axi_lite_interconnect_1x4_S3_WREADY  : std_logic;
signal axi_lite_interconnect_1x4_S3_BRESP   : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_S3_BVALID  : std_logic;
signal axi_lite_interconnect_1x4_S3_BREADY  : std_logic;
signal axi_lite_interconnect_1x4_S3_ARADDR  : std_logic_vector(G_ADDR_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S3_ARVALID : std_logic;
signal axi_lite_interconnect_1x4_S3_ARREADY : std_logic;
signal axi_lite_interconnect_1x4_S3_RDATA   : std_logic_vector(G_DATA_WIDTH-1 downto 0);
signal axi_lite_interconnect_1x4_S3_RRESP   : std_logic_vector(1 downto 0);
signal axi_lite_interconnect_1x4_S3_RVALID  : std_logic;
signal axi_lite_interconnect_1x4_S3_RREADY  : std_logic;

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

begin

-----------------------------------------------------------
--      AXI LITE INTECONNECT
-----------------------------------------------------------

-- Instantiation
u_axi_lite_interconnect_1x4 : entity work.axi_lite_interconnect_1x4
    generic map (
        G_ADDR_WIDTH => G_ADDR_WIDTH,
        G_DATA_WIDTH => G_DATA_WIDTH,
        G_BASE0      => axi_lite_interconnect_1x4_BASE0_c,
        G_LIMIT0     => axi_lite_interconnect_1x4_LIMIT0_c,
        G_BASE1      => axi_lite_interconnect_1x4_BASE1_c,
        G_LIMIT1     => axi_lite_interconnect_1x4_LIMIT1_c,
        G_BASE2      => axi_lite_interconnect_1x4_BASE2_c,
        G_LIMIT2     => axi_lite_interconnect_1x4_LIMIT2_c,
        G_BASE3      => axi_lite_interconnect_1x4_BASE3_c,
        G_LIMIT3     => axi_lite_interconnect_1x4_LIMIT3_c
    )
    port map (
        clk       => clk,
        resetn    => resetn,
        -- Master
        M_AWADDR  => mem_axi_awaddr,
        M_AWVALID => mem_axi_awvalid,
        M_AWREADY => mem_axi_awready,
        M_WDATA   => mem_axi_wdata,
        M_WSTRB   => mem_axi_wstrb,
        M_WVALID  => mem_axi_wvalid,
        M_WREADY  => mem_axi_wready,
        M_BRESP   => axi_lite_interconnect_1x4_M_BRESP,
        M_BVALID  => mem_axi_bvalid,
        M_BREADY  => mem_axi_bready,
        M_ARADDR  => mem_axi_araddr,
        M_ARVALID => mem_axi_arvalid,
        M_ARREADY => mem_axi_arready,
        M_RDATA   => mem_axi_rdata,
        M_RRESP   => axi_lite_interconnect_1x4_M_RRESP,
        M_RVALID  => mem_axi_rvalid,
        M_RREADY  => mem_axi_rready,
        -- Slave 0
        S0_AWADDR  => axi_lite_interconnect_1x4_S0_AWADDR,
        S0_AWVALID => axi_lite_interconnect_1x4_S0_AWVALID,
        S0_AWREADY => axi_lite_interconnect_1x4_S0_AWREADY,
        S0_WDATA   => axi_lite_interconnect_1x4_S0_WDATA,
        S0_WSTRB   => axi_lite_interconnect_1x4_S0_WSTRB,
        S0_WVALID  => axi_lite_interconnect_1x4_S0_WVALID,
        S0_WREADY  => axi_lite_interconnect_1x4_S0_WREADY,
        S0_BRESP   => axi_lite_interconnect_1x4_S0_BRESP,
        S0_BVALID  => axi_lite_interconnect_1x4_S0_BVALID,
        S0_BREADY  => axi_lite_interconnect_1x4_S0_BREADY,
        S0_ARADDR  => axi_lite_interconnect_1x4_S0_ARADDR,
        S0_ARVALID => axi_lite_interconnect_1x4_S0_ARVALID,
        S0_ARREADY => axi_lite_interconnect_1x4_S0_ARREADY,
        S0_RDATA   => axi_lite_interconnect_1x4_S0_RDATA,
        S0_RRESP   => axi_lite_interconnect_1x4_S0_RRESP,
        S0_RVALID  => axi_lite_interconnect_1x4_S0_RVALID,
        S0_RREADY  => axi_lite_interconnect_1x4_S0_RREADY,
        -- Slave 1
        S1_AWADDR  => axi_lite_interconnect_1x4_S1_AWADDR,
        S1_AWVALID => axi_lite_interconnect_1x4_S1_AWVALID,
        S1_AWREADY => axi_lite_interconnect_1x4_S1_AWREADY,
        S1_WDATA   => axi_lite_interconnect_1x4_S1_WDATA,
        S1_WSTRB   => axi_lite_interconnect_1x4_S1_WSTRB,
        S1_WVALID  => axi_lite_interconnect_1x4_S1_WVALID,
        S1_WREADY  => axi_lite_interconnect_1x4_S1_WREADY,
        S1_BRESP   => axi_lite_interconnect_1x4_S1_BRESP,
        S1_BVALID  => axi_lite_interconnect_1x4_S1_BVALID,
        S1_BREADY  => axi_lite_interconnect_1x4_S1_BREADY,
        S1_ARADDR  => axi_lite_interconnect_1x4_S1_ARADDR,
        S1_ARVALID => axi_lite_interconnect_1x4_S1_ARVALID,
        S1_ARREADY => axi_lite_interconnect_1x4_S1_ARREADY,
        S1_RDATA   => axi_lite_interconnect_1x4_S1_RDATA,
        S1_RRESP   => axi_lite_interconnect_1x4_S1_RRESP,
        S1_RVALID  => axi_lite_interconnect_1x4_S1_RVALID,
        S1_RREADY  => axi_lite_interconnect_1x4_S1_RREADY,
        -- Slave 2
        S2_AWADDR  => axi_lite_interconnect_1x4_S2_AWADDR,
        S2_AWVALID => axi_lite_interconnect_1x4_S2_AWVALID,
        S2_AWREADY => axi_lite_interconnect_1x4_S2_AWREADY,
        S2_WDATA   => axi_lite_interconnect_1x4_S2_WDATA,
        S2_WSTRB   => axi_lite_interconnect_1x4_S2_WSTRB,
        S2_WVALID  => axi_lite_interconnect_1x4_S2_WVALID,
        S2_WREADY  => axi_lite_interconnect_1x4_S2_WREADY,
        S2_BRESP   => axi_lite_interconnect_1x4_S2_BRESP,
        S2_BVALID  => axi_lite_interconnect_1x4_S2_BVALID,
        S2_BREADY  => axi_lite_interconnect_1x4_S2_BREADY,
        S2_ARADDR  => axi_lite_interconnect_1x4_S2_ARADDR,
        S2_ARVALID => axi_lite_interconnect_1x4_S2_ARVALID,
        S2_ARREADY => axi_lite_interconnect_1x4_S2_ARREADY,
        S2_RDATA   => axi_lite_interconnect_1x4_S2_RDATA,
        S2_RRESP   => axi_lite_interconnect_1x4_S2_RRESP,
        S2_RVALID  => axi_lite_interconnect_1x4_S2_RVALID,
        S2_RREADY  => axi_lite_interconnect_1x4_S2_RREADY,
        -- Slave 3
        S3_AWADDR  => axi_lite_interconnect_1x4_S3_AWADDR,
        S3_AWVALID => axi_lite_interconnect_1x4_S3_AWVALID,
        S3_AWREADY => axi_lite_interconnect_1x4_S3_AWREADY,
        S3_WDATA   => axi_lite_interconnect_1x4_S3_WDATA,
        S3_WSTRB   => axi_lite_interconnect_1x4_S3_WSTRB,
        S3_WVALID  => axi_lite_interconnect_1x4_S3_WVALID,
        S3_WREADY  => axi_lite_interconnect_1x4_S3_WREADY,
        S3_BRESP   => axi_lite_interconnect_1x4_S3_BRESP,
        S3_BVALID  => axi_lite_interconnect_1x4_S3_BVALID,
        S3_BREADY  => axi_lite_interconnect_1x4_S3_BREADY,
        S3_ARADDR  => axi_lite_interconnect_1x4_S3_ARADDR,
        S3_ARVALID => axi_lite_interconnect_1x4_S3_ARVALID,
        S3_ARREADY => axi_lite_interconnect_1x4_S3_ARREADY,
        S3_RDATA   => axi_lite_interconnect_1x4_S3_RDATA,
        S3_RRESP   => axi_lite_interconnect_1x4_S3_RRESP,
        S3_RVALID  => axi_lite_interconnect_1x4_S3_RVALID,
        S3_RREADY  => axi_lite_interconnect_1x4_S3_RREADY
    );

mem_axi_bresp <= axi_lite_interconnect_1x4_M_BRESP;
mem_axi_rresp <= axi_lite_interconnect_1x4_M_RRESP;

-----------------------------------------------------------
--      AXI RAM
-----------------------------------------------------------

-- AXI RAM <-> Interconnect bindings (slave 0)
axi_ram_mem_axi_awvalid <= axi_lite_interconnect_1x4_S0_AWVALID;
axi_lite_interconnect_1x4_S0_AWREADY <= axi_ram_mem_axi_awready;
axi_ram_mem_axi_awaddr <= axi_lite_interconnect_1x4_S0_AWADDR;
axi_ram_mem_axi_awprot <= (others => '0');

axi_ram_mem_axi_wvalid <= axi_lite_interconnect_1x4_S0_WVALID;
axi_lite_interconnect_1x4_S0_WREADY <= axi_ram_mem_axi_wready;
axi_ram_mem_axi_wdata <= axi_lite_interconnect_1x4_S0_WDATA;
axi_ram_mem_axi_wstrb <= axi_lite_interconnect_1x4_S0_WSTRB;

axi_lite_interconnect_1x4_S0_BVALID <= axi_ram_mem_axi_bvalid;
axi_ram_mem_axi_bready <= axi_lite_interconnect_1x4_S0_BREADY;
axi_lite_interconnect_1x4_S0_BRESP <= (others => '0');

axi_ram_mem_axi_arvalid <= axi_lite_interconnect_1x4_S0_ARVALID;
axi_lite_interconnect_1x4_S0_ARREADY <= axi_ram_mem_axi_arready;
axi_ram_mem_axi_araddr <= axi_lite_interconnect_1x4_S0_ARADDR;
axi_ram_mem_axi_arprot <= (others => '0');

axi_lite_interconnect_1x4_S0_RVALID <= axi_ram_mem_axi_rvalid;
axi_ram_mem_axi_rready <= axi_lite_interconnect_1x4_S0_RREADY;
axi_lite_interconnect_1x4_S0_RDATA <= axi_ram_mem_axi_rdata;
axi_lite_interconnect_1x4_S0_RRESP <= (others => '0');

-- AXI RAM instantiation
u_axi_ram : entity work.axi_ram
    generic map (
        G_DATA_WIDTH => G_DATA_WIDTH,
        G_ADDR_WIDTH => G_ADDR_WIDTH,
        G_DEPTH      => axi_ram_DEPTH_c,
        G_RAM_VENDOR => C_RAM_VENDOR
    )
    port map (
        clk             => clk,
        resetn          => resetn,
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
axi_uart_AWADDR  <= axi_lite_interconnect_1x4_S1_AWADDR;
axi_uart_AWVALID <= axi_lite_interconnect_1x4_S1_AWVALID;
axi_lite_interconnect_1x4_S1_AWREADY <= axi_uart_AWREADY;

-- Write data channel
axi_uart_WDATA   <= axi_lite_interconnect_1x4_S1_WDATA;
axi_uart_WSTRB   <= axi_lite_interconnect_1x4_S1_WSTRB(3 downto 0);
axi_uart_WVALID  <= axi_lite_interconnect_1x4_S1_WVALID;
axi_lite_interconnect_1x4_S1_WREADY <= axi_uart_WREADY;

-- Write response channel
axi_lite_interconnect_1x4_S1_BRESP  <= axi_uart_BRESP;
axi_lite_interconnect_1x4_S1_BVALID <= axi_uart_BVALID;
axi_uart_BREADY <= axi_lite_interconnect_1x4_S1_BREADY;

-- Read address channel
axi_uart_ARADDR  <= axi_lite_interconnect_1x4_S1_ARADDR;
axi_uart_ARVALID <= axi_lite_interconnect_1x4_S1_ARVALID;
axi_lite_interconnect_1x4_S1_ARREADY <= axi_uart_ARREADY;

-- Read data channel
axi_lite_interconnect_1x4_S1_RDATA  <= axi_uart_RDATA;
axi_lite_interconnect_1x4_S1_RRESP  <= axi_uart_RRESP;
axi_lite_interconnect_1x4_S1_RVALID <= axi_uart_RVALID;
axi_uart_RREADY <= axi_lite_interconnect_1x4_S1_RREADY;

-- UART pins
uart_tx <= axi_uart_uart_tx;
axi_uart_uart_rx <= uart_rx;

----------------------------------------------------------------
-- AXI UART instantiation
----------------------------------------------------------------
u_axi_uart : entity work.axi_uart
    generic map (
        G_SYS_FREQ => axi_uart_SYS_FREQ_c,
        G_BAUDRATE => axi_uart_BAUDRATE_c,
        G_TX_DEPTH => axi_uart_TX_DEPTH_c,
        G_RX_DEPTH => axi_uart_RX_DEPTH_c
    )
    port map (
        ACLK    => clk,
        ARESETn => resetn,
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
    axi_lite_interconnect_1x4_S2_AWREADY <= axi_gpio_awready;
    axi_gpio_awaddr  <= axi_lite_interconnect_1x4_S2_AWADDR;
    axi_gpio_awprot  <= (others => '0');
    axi_gpio_awvalid <= axi_lite_interconnect_1x4_S2_AWVALID;

    -- Write data channel
    axi_lite_interconnect_1x4_S2_WREADY <= axi_gpio_wready;
    axi_gpio_wdata  <= axi_lite_interconnect_1x4_S2_WDATA;
    axi_gpio_wstrb  <= axi_lite_interconnect_1x4_S2_WSTRB;
    axi_gpio_wvalid <= axi_lite_interconnect_1x4_S2_WVALID;

    -- Write response channel
    axi_lite_interconnect_1x4_S2_BRESP  <= axi_gpio_bresp;
    axi_lite_interconnect_1x4_S2_BVALID <= axi_gpio_bvalid;
    axi_gpio_bready <= axi_lite_interconnect_1x4_S2_BREADY;

    -- Read address channel
    axi_lite_interconnect_1x4_S2_ARREADY <= axi_gpio_arready;
    axi_gpio_araddr  <= axi_lite_interconnect_1x4_S2_ARADDR;
    axi_gpio_arprot  <= (others => '0');
    axi_gpio_arvalid <= axi_lite_interconnect_1x4_S2_ARVALID;

    -- Read data channel
    axi_lite_interconnect_1x4_S2_RDATA  <= axi_gpio_rdata;
    axi_lite_interconnect_1x4_S2_RRESP  <= axi_gpio_rresp;
    axi_lite_interconnect_1x4_S2_RVALID <= axi_gpio_rvalid;
    axi_gpio_rready <= axi_lite_interconnect_1x4_S2_RREADY;

    -- AXI GPIO instantiation
    u_axi_gpio : entity work.axi_gpio
        port map (
            s_axi_aclk    => clk,
            s_axi_aresetn => resetn,
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
    axi_lite_interconnect_1x4_S3_AWREADY <= axi_slave_reg_bank_awready;
    axi_slave_reg_bank_awvalid <= axi_lite_interconnect_1x4_S3_AWVALID;
    axi_slave_reg_bank_awaddr  <= axi_lite_interconnect_1x4_S3_AWADDR;

    axi_lite_interconnect_1x4_S3_WREADY <= axi_slave_reg_bank_wready;
    axi_slave_reg_bank_wvalid <= axi_lite_interconnect_1x4_S3_WVALID;
    axi_slave_reg_bank_wdata  <= axi_lite_interconnect_1x4_S3_WDATA;
    axi_slave_reg_bank_wstrb  <= axi_lite_interconnect_1x4_S3_WSTRB;

    axi_lite_interconnect_1x4_S3_BVALID <= axi_slave_reg_bank_bvalid;
    axi_slave_reg_bank_bready <= axi_lite_interconnect_1x4_S3_BREADY;
    axi_lite_interconnect_1x4_S3_BRESP  <= (others => '0');

    axi_slave_reg_bank_arvalid <= axi_lite_interconnect_1x4_S3_ARVALID;
    axi_lite_interconnect_1x4_S3_ARREADY <= axi_slave_reg_bank_arready;
    axi_slave_reg_bank_araddr  <= axi_lite_interconnect_1x4_S3_ARADDR;

    axi_lite_interconnect_1x4_S3_RVALID <= axi_slave_reg_bank_rvalid;
    axi_slave_reg_bank_rready <= axi_lite_interconnect_1x4_S3_RREADY;
    axi_lite_interconnect_1x4_S3_RDATA  <= axi_slave_reg_bank_rdata;
    axi_lite_interconnect_1x4_S3_RRESP  <= (others => '0');

    u_axi_slave_reg_bank : entity work.axi_slave_reg_bank
        generic map (
            G_ADDR_WIDTH => 32,
            G_DATA_WIDTH => 32
        )
        port map (
            clk                 => clk,
            resetn              => resetn,
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
            register_bank_rd    => register_bank_rd
        );

        -- Store date and time constants in the first register_bank_rd entry
        register_bank_rd(0)(7 downto 0)     <= C_DAY_HEX;
        register_bank_rd(0)(15 downto 8)    <= C_MONTH_HEX;
        register_bank_rd(0)(31 downto 16)   <= C_YEAR_HEX;
        register_bank_rd(1)(7 downto 0)     <= C_HOUR_HEX;
        register_bank_rd(1)(15 downto 8)    <= C_MINUTE_HEX;
        register_bank_rd(1)(23 downto 16)   <= C_SECOND_HEX;
        register_bank_rd(1)(31 downto 24)   <= (others=>'0');
        register_bank_rd(2)                 <= register_bank_wr(2); -- Test loopback
        ---- Connect write register bank to read register bank
        --for i in register_bank_rd'range loop
        --    register_bank_rd(i) <= register_bank_wr(i);
        --end loop;


end rtl;

