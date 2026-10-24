library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity soc is
    generic(
    G_SYS_FREQ : natural := 100_000_000;
    G_BAUDRATE : natural := 125_000
    );
    port (
        clk      : in  std_logic;
        reset_n  : in  std_logic;
        uart_rx  : in  std_logic;
        uart_tx  : out std_logic
    );
end entity;

architecture rtl of soc is

-- picorv32_axi signal

component picorv32_axi is
    generic (
        ENABLE_COUNTERS       : integer := 1;
        ENABLE_COUNTERS64     : integer := 1;
        ENABLE_REGS_16_31     : integer := 1;
        ENABLE_REGS_DUALPORT  : integer := 1;
        TWO_STAGE_SHIFT       : integer := 1;
        BARREL_SHIFTER        : integer := 0;
        TWO_CYCLE_COMPARE     : integer := 0;
        TWO_CYCLE_ALU         : integer := 0;
        COMPRESSED_ISA        : integer := 0;
        CATCH_MISALIGN        : integer := 1;
        CATCH_ILLINSN         : integer := 1;
        ENABLE_PCPI           : integer := 0;
        ENABLE_MUL            : integer := 0;
        ENABLE_FAST_MUL       : integer := 0;
        ENABLE_DIV            : integer := 0;
        ENABLE_IRQ            : integer := 0;
        ENABLE_IRQ_QREGS      : integer := 1;
        ENABLE_IRQ_TIMER      : integer := 1;
        ENABLE_TRACE          : integer := 0;
        REGS_INIT_ZERO        : integer := 0;

        MASKED_IRQ            : std_logic_vector(31 downto 0)
                              := x"00000000";
        LATCHED_IRQ           : std_logic_vector(31 downto 0)
                              := x"FFFFFFFF";
        PROGADDR_RESET        : std_logic_vector(31 downto 0)
                              := x"00000000";
        PROGADDR_IRQ          : std_logic_vector(31 downto 0)
                              := x"00000010";
        STACKADDR             : std_logic_vector(31 downto 0)
                              := x"FFFFFFFF"
    );
    port (
        clk                   : in  std_logic;
        resetn                : in  std_logic;
        trap                  : out std_logic;

        -- AXI4-Lite master write-address channel
        mem_axi_awvalid       : out std_logic;
        mem_axi_awready       : in  std_logic;
        mem_axi_awaddr        : out std_logic_vector(31 downto 0);
        mem_axi_awprot        : out std_logic_vector(2 downto 0);

        -- AXI4-Lite master write-data channel
        mem_axi_wvalid        : out std_logic;
        mem_axi_wready        : in  std_logic;
        mem_axi_wdata         : out std_logic_vector(31 downto 0);
        mem_axi_wstrb         : out std_logic_vector(3 downto 0);

        -- AXI4-Lite master write-response channel
        mem_axi_bvalid        : in  std_logic;
        mem_axi_bready        : out std_logic;

        -- AXI4-Lite master read-address channel
        mem_axi_arvalid       : out std_logic;
        mem_axi_arready       : in  std_logic;
        mem_axi_araddr        : out std_logic_vector(31 downto 0);
        mem_axi_arprot        : out std_logic_vector(2 downto 0);

        -- AXI4-Lite master read-data channel
        mem_axi_rvalid        : in  std_logic;
        mem_axi_rready        : out std_logic;
        mem_axi_rdata         : in  std_logic_vector(31 downto 0);

        -- Pico Co-Processor Interface
        pcpi_valid            : out std_logic;
        pcpi_insn             : out std_logic_vector(31 downto 0);
        pcpi_rs1              : out std_logic_vector(31 downto 0);
        pcpi_rs2              : out std_logic_vector(31 downto 0);
        pcpi_wr               : in  std_logic;
        pcpi_rd               : in  std_logic_vector(31 downto 0);
        pcpi_wait             : in  std_logic;
        pcpi_ready            : in  std_logic;

        -- IRQ interface
        irq                   : in  std_logic_vector(31 downto 0);
        eoi                   : out std_logic_vector(31 downto 0);

        -- Trace interface
        trace_valid           : out std_logic;
        trace_data            : out std_logic_vector(35 downto 0)
    );
end component;

signal picorv32_axi_trap              : std_logic;
signal picorv32_axi_mem_axi_awvalid   : std_logic;
signal picorv32_axi_mem_axi_awready   : std_logic;
signal picorv32_axi_mem_axi_awaddr    : std_logic_vector(31 downto 0);
signal picorv32_axi_mem_axi_awprot    : std_logic_vector(2 downto 0);
signal picorv32_axi_mem_axi_wvalid    : std_logic;
signal picorv32_axi_mem_axi_wready    : std_logic;
signal picorv32_axi_mem_axi_wdata     : std_logic_vector(31 downto 0);
signal picorv32_axi_mem_axi_wstrb     : std_logic_vector(3 downto 0);
signal picorv32_axi_mem_axi_bvalid    : std_logic;
signal picorv32_axi_mem_axi_bready    : std_logic;
signal picorv32_axi_mem_axi_arvalid   : std_logic;
signal picorv32_axi_mem_axi_arready   : std_logic;
signal picorv32_axi_mem_axi_araddr    : std_logic_vector(31 downto 0);
signal picorv32_axi_mem_axi_arprot    : std_logic_vector(2 downto 0);
signal picorv32_axi_mem_axi_rvalid    : std_logic;
signal picorv32_axi_mem_axi_rready    : std_logic;
signal picorv32_axi_mem_axi_rdata     : std_logic_vector(31 downto 0);
signal picorv32_axi_pcpi_valid        : std_logic;
signal picorv32_axi_pcpi_insn         : std_logic_vector(31 downto 0);
signal picorv32_axi_pcpi_rs1          : std_logic_vector(31 downto 0);
signal picorv32_axi_pcpi_rs2          : std_logic_vector(31 downto 0);
signal picorv32_axi_pcpi_wr           : std_logic;
signal picorv32_axi_pcpi_rd           : std_logic_vector(31 downto 0);
signal picorv32_axi_pcpi_wait         : std_logic;
signal picorv32_axi_pcpi_ready        : std_logic;
signal picorv32_axi_irq               : std_logic_vector(31 downto 0);
signal picorv32_axi_eoi               : std_logic_vector(31 downto 0);
signal picorv32_axi_trace_valid       : std_logic;
signal picorv32_axi_trace_data        : std_logic_vector(35 downto 0);

signal gpio_in                        : std_logic_vector(31 downto 0);
signal gpio_out                       : std_logic_vector(31 downto 0);

begin

picorv32_axi_inst: picorv32_axi
    generic map (
        ENABLE_COUNTERS      => 1,
        ENABLE_COUNTERS64    => 1,
        ENABLE_REGS_16_31    => 1,
        ENABLE_REGS_DUALPORT => 1,
        TWO_STAGE_SHIFT      => 1,
        BARREL_SHIFTER       => 0,
        TWO_CYCLE_COMPARE    => 0,
        TWO_CYCLE_ALU        => 0,
        COMPRESSED_ISA       => 0,
        CATCH_MISALIGN       => 1,
        CATCH_ILLINSN        => 1,
        ENABLE_PCPI          => 0,
        ENABLE_MUL           => 0,
        ENABLE_FAST_MUL      => 0,
        ENABLE_DIV           => 0,
        ENABLE_IRQ           => 0,
        ENABLE_IRQ_QREGS     => 1,
        ENABLE_IRQ_TIMER     => 1,
        ENABLE_TRACE         => 0,
        REGS_INIT_ZERO       => 0,
        MASKED_IRQ           => x"00000000",
        LATCHED_IRQ          => x"FFFFFFFF",
        PROGADDR_RESET       => x"00000000",
        PROGADDR_IRQ         => x"00000010",
        STACKADDR            => x"FFFFFFFF"
    )
    port map (
        clk               => clk,
        resetn            => reset_n,
        trap              => picorv32_axi_trap,
        mem_axi_awvalid   => picorv32_axi_mem_axi_awvalid,
        mem_axi_awready   => picorv32_axi_mem_axi_awready,
        mem_axi_awaddr    => picorv32_axi_mem_axi_awaddr,
        mem_axi_awprot    => picorv32_axi_mem_axi_awprot,
        mem_axi_wvalid    => picorv32_axi_mem_axi_wvalid,
        mem_axi_wready    => picorv32_axi_mem_axi_wready,
        mem_axi_wdata     => picorv32_axi_mem_axi_wdata,
        mem_axi_wstrb     => picorv32_axi_mem_axi_wstrb,
        mem_axi_bvalid    => picorv32_axi_mem_axi_bvalid,
        mem_axi_bready    => picorv32_axi_mem_axi_bready,
        mem_axi_arvalid   => picorv32_axi_mem_axi_arvalid,
        mem_axi_arready   => picorv32_axi_mem_axi_arready,
        mem_axi_araddr    => picorv32_axi_mem_axi_araddr,
        mem_axi_arprot    => picorv32_axi_mem_axi_arprot,
        mem_axi_rvalid    => picorv32_axi_mem_axi_rvalid,
        mem_axi_rready    => picorv32_axi_mem_axi_rready,
        mem_axi_rdata     => picorv32_axi_mem_axi_rdata,
        pcpi_valid        => picorv32_axi_pcpi_valid,
        pcpi_insn         => picorv32_axi_pcpi_insn,
        pcpi_rs1          => picorv32_axi_pcpi_rs1,
        pcpi_rs2          => picorv32_axi_pcpi_rs2,
        pcpi_wr           => picorv32_axi_pcpi_wr,
        pcpi_rd           => picorv32_axi_pcpi_rd,
        pcpi_wait         => picorv32_axi_pcpi_wait,
        pcpi_ready        => picorv32_axi_pcpi_ready,
        irq               => picorv32_axi_irq,
        eoi               => picorv32_axi_eoi,
        trace_valid       => picorv32_axi_trace_valid,
        trace_data        => picorv32_axi_trace_data
    );


    axi_soc_subsystem_inst: entity work.axi_soc_subsystem
        generic map (
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
            G_RAM_DEPTH  => 8192,
            G_SYS_FREQ   => G_SYS_FREQ,
            G_BAUDRATE   => G_BAUDRATE,
            G_TX_DEPTH   => 256,
            G_RX_DEPTH   => 256
        )
        port map (
            clk               => clk,
            resetn            => reset_n,
            mem_axi_awvalid   => picorv32_axi_mem_axi_awvalid,
            mem_axi_awready   => picorv32_axi_mem_axi_awready,
            mem_axi_awaddr    => picorv32_axi_mem_axi_awaddr,
            mem_axi_awprot    => picorv32_axi_mem_axi_awprot,
            mem_axi_wvalid    => picorv32_axi_mem_axi_wvalid,
            mem_axi_wready    => picorv32_axi_mem_axi_wready,
            mem_axi_wdata     => picorv32_axi_mem_axi_wdata,
            mem_axi_wstrb     => picorv32_axi_mem_axi_wstrb,
            mem_axi_bvalid    => picorv32_axi_mem_axi_bvalid,
            mem_axi_bready    => picorv32_axi_mem_axi_bready,
            mem_axi_arvalid   => picorv32_axi_mem_axi_arvalid,
            mem_axi_arready   => picorv32_axi_mem_axi_arready,
            mem_axi_araddr    => picorv32_axi_mem_axi_araddr,
            mem_axi_arprot    => picorv32_axi_mem_axi_arprot,
            mem_axi_rvalid    => picorv32_axi_mem_axi_rvalid,
            mem_axi_rready    => picorv32_axi_mem_axi_rready,
            mem_axi_rdata     => picorv32_axi_mem_axi_rdata,
            mem_axi_bresp     => open,
            mem_axi_rresp     => open,
            uart_rx           => uart_rx,
            uart_tx           => uart_tx,
            gpio_in           => gpio_in,
            gpio_out          => gpio_out
        );

gpio_in <= gpio_out;
    


end rtl;