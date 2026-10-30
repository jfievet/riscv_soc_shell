-- Behavioral SDR SDRAM model for IS42S16400-class devices.
-- 4 banks x 4096 rows x 256 columns x 16 bits (8 MiB), SDR, BL=2, CL=3.
-- VHDL-2008, simulation ONLY. No initialization of signals at declaration.
-- Commands sampled on rising CLK. DQ read data launched after CLK edges
-- with G_T_AC delay. The memory array is initialized to X for simulation.
-- Simplified auto-precharge/refresh timing; not a vendor timing signoff model.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_model is
    generic (
        G_T_AC          : time := 1 ns;
        G_T_RCD_CYCLES : positive := 3;
        G_T_RP_CYCLES  : positive := 3;
        G_T_RFC_CYCLES : positive := 8;
        G_T_RAS_CYCLES : positive := 5;
        G_T_WR_CYCLES  : positive := 2;
        G_CHECK_TIMING  : boolean := true
    );
    port (
        i_clk   : in std_logic;
        i_cke   : in std_logic;
        i_cs_n  : in std_logic;
        i_ras_n : in std_logic;
        i_cas_n : in std_logic;
        i_we_n  : in std_logic;
        i_ba    : in std_logic_vector(1 downto 0);
        i_addr  : in std_logic_vector(11 downto 0);
        i_dqm   : in std_logic_vector(1 downto 0);
        io_dq   : inout std_logic_vector(15 downto 0)
    );
end entity;

architecture behavioral of sdram_model is
    type t_memory is array (0 to 4194303) of std_logic_vector(15 downto 0);
    type t_rows is array (0 to 3) of natural range 0 to 4095;
    type t_flags is array (0 to 3) of boolean;
    type t_cycles is array (0 to 3) of integer;
    signal dq_out_i : std_logic_vector(15 downto 0);
    signal dq_oe_i  : std_logic;
    signal dq_in_i  : std_logic_vector(15 downto 0);
    function index_of(b : natural; r : natural; c : natural) return natural is
    begin
        return b * 1048576 + r * 256 + (c mod 256);
    end function;
    function f_max(a, b : integer) return integer is
    begin
        if a > b then
            return a;
        else
            return b;
        end if;
    end function;
begin
    io_dq <= dq_out_i when dq_oe_i = '1' else (others => 'Z');
    dq_in_i <= io_dq;

    process(i_clk)
        variable mem : t_memory := (others => (others => 'X'));
        variable opened : t_flags := (others => false);
        variable row : t_rows := (others => 0);
        variable activated_at : t_cycles := (others => -100000);
        variable available_at : t_cycles := (others => 0);
        variable cycle : integer := 0;
        variable global_ready : integer := 0;
        variable initialized : boolean := false;
        variable mode_loaded : boolean := false;
        variable burst_length : natural := 0;
        variable cas_latency : natural := 0;
        variable refresh_count : natural := 0;
        variable write_remaining : natural := 0;
        variable write_bank : natural := 0;
        variable write_col : natural := 0;
        variable write_auto : boolean := false;
        variable read_remaining : natural := 0;
        variable read_bank : natural := 0;
        variable read_col : natural := 0;
        variable read_due : integer := 0;
        variable read_auto : boolean := false;
        variable close_at : t_cycles := (others => -1);
        variable b : natural;
        variable col : natural;
        variable cmd : std_logic_vector(2 downto 0);
        variable word_v : std_logic_vector(15 downto 0);
        variable any_open : boolean;
        variable dqm_previous : std_logic_vector(1 downto 0) := "11";
        variable dqm_two_clocks_ago : std_logic_vector(1 downto 0) := "11";
    begin
        if rising_edge(i_clk) then
            cycle := cycle + 1;
            dq_oe_i <= '0' after G_T_AC;
            dq_out_i <= (others => '0') after G_T_AC;

            -- Complete scheduled auto-precharges before accepting commands.
            for k in 0 to 3 loop
                if close_at(k) >= 0 and cycle >= close_at(k) then
                    opened(k) := false;
                    available_at(k) := cycle + G_T_RP_CYCLES;
                    close_at(k) := -1;
                end if;
            end loop;

            -- Second and subsequent write beats (first beat is sampled on WRITE).
            if write_remaining > 0 then
                word_v := mem(index_of(write_bank, row(write_bank), write_col));
                if i_dqm(0) = '0' then word_v(7 downto 0) := dq_in_i(7 downto 0); end if;
                if i_dqm(1) = '0' then word_v(15 downto 8) := dq_in_i(15 downto 8); end if;
                mem(index_of(write_bank, row(write_bank), write_col)) := word_v;
                write_col := (write_col + 1) mod 256;
                write_remaining := write_remaining - 1;
                if write_remaining = 0 and write_auto then
                    close_at(write_bank) := f_max(cycle + G_T_WR_CYCLES,
                                                       activated_at(write_bank) + G_T_RAS_CYCLES);
                end if;
            end if;

            -- CL=3: output first beat at READ edge + 2, so the controller
            -- can capture it on READ edge + 3. Next beat one edge later.
            if read_remaining > 0 and cycle >= read_due then
                -- Each read byte is masked by DQM sampled two clocks earlier.
                word_v := mem(index_of(read_bank, row(read_bank), read_col));
                if dqm_two_clocks_ago(0) /= '0' then
                    word_v(7 downto 0) := (others => 'Z');
                end if;
                if dqm_two_clocks_ago(1) /= '0' then
                    word_v(15 downto 8) := (others => 'Z');
                end if;
                dq_out_i <= word_v after G_T_AC;
                dq_oe_i <= '1' after G_T_AC;
                read_col := (read_col + 1) mod 256;
                read_remaining := read_remaining - 1;
                read_due := cycle + 1;
                if read_remaining = 0 and read_auto then
                    close_at(read_bank) := f_max(cycle + 1,
                                                      activated_at(read_bank) + G_T_RAS_CYCLES);
                end if;
            end if;

            -- Advance history after using the sample from two edges earlier.
            dqm_two_clocks_ago := dqm_previous;
            dqm_previous := i_dqm;

            if i_cke = '1' and i_cs_n = '0' then
                b := to_integer(unsigned(i_ba));
                cmd := i_ras_n & i_cas_n & i_we_n;
                case cmd is
                    when "011" => -- ACTIVE
                        if G_CHECK_TIMING then
                            assert cycle >= global_ready report "SDRAM: ACTIVE during refresh recovery" severity error;
                            assert not opened(b) report "SDRAM: ACTIVE on open bank" severity error;
                            assert cycle >= available_at(b) report "SDRAM: tRP violation" severity error;
                        end if;
                        row(b) := to_integer(unsigned(i_addr));
                        opened(b) := true;
                        activated_at(b) := cycle;
                    when "101" => -- READ
                        if G_CHECK_TIMING then
                            assert mode_loaded report "SDRAM: READ before mode register" severity error;
                            assert opened(b) report "SDRAM: READ on closed bank" severity error;
                            assert cycle - activated_at(b) >= G_T_RCD_CYCLES report "SDRAM: read tRCD violation" severity error;
                            assert read_remaining = 0 report "SDRAM: overlapping reads unsupported" severity error;
                        end if;
                        col := to_integer(unsigned(i_addr(7 downto 0)));
                        read_bank := b;
                        read_col := col;
                        read_remaining := burst_length;
                        read_due := cycle + integer(cas_latency) - 1;
                        read_auto := (i_addr(10) = '1');
                    when "100" => -- WRITE
                        if G_CHECK_TIMING then
                            assert mode_loaded report "SDRAM: WRITE before mode register" severity error;
                            assert opened(b) report "SDRAM: WRITE on closed bank" severity error;
                            assert cycle - activated_at(b) >= G_T_RCD_CYCLES report "SDRAM: write tRCD violation" severity error;
                            assert write_remaining = 0 report "SDRAM: overlapping writes unsupported" severity error;
                        end if;
                        col := to_integer(unsigned(i_addr(7 downto 0)));
                        word_v := mem(index_of(b, row(b), col));
                        if i_dqm(0) = '0' then word_v(7 downto 0) := dq_in_i(7 downto 0); end if;
                        if i_dqm(1) = '0' then word_v(15 downto 8) := dq_in_i(15 downto 8); end if;
                        mem(index_of(b, row(b), col)) := word_v;
                        write_bank := b;
                        write_col := (col + 1) mod 256;
                        write_remaining := burst_length - 1;
                        write_auto := (i_addr(10) = '1');
                        if write_remaining = 0 and write_auto then
                            close_at(b) := f_max(cycle + G_T_WR_CYCLES,
                                                       activated_at(b) + G_T_RAS_CYCLES);
                        end if;
                    when "010" => -- PRECHARGE
                        for k in 0 to 3 loop
                            if i_addr(10) = '1' or k = b then
                                opened(k) := false;
                                close_at(k) := -1;
                                available_at(k) := cycle + G_T_RP_CYCLES;
                            end if;
                        end loop;
                    when "001" => -- AUTO REFRESH
                        any_open := false;
                        for k in 0 to 3 loop
                            if opened(k) then any_open := true; end if;
                            if G_CHECK_TIMING then
                                assert cycle >= available_at(k) report "SDRAM: REFRESH during tRP" severity error;
                            end if;
                        end loop;
                        if G_CHECK_TIMING then
                            assert not any_open report "SDRAM: REFRESH with open bank" severity error;
                            assert cycle >= global_ready report "SDRAM: tRFC violation" severity error;
                        end if;
                        global_ready := cycle + G_T_RFC_CYCLES;
                        refresh_count := refresh_count + 1;
                    when "000" => -- LOAD MODE REGISTER
                        if G_CHECK_TIMING then
                            assert refresh_count >= 2 report "SDRAM: MRS before two initialization refreshes" severity error;
                            assert i_addr(2 downto 0) = "001" report "SDRAM: model requires BL=2" severity failure;
                            assert i_addr(6 downto 4) = "011" report "SDRAM: model requires CL=3" severity failure;
                            assert i_addr(3) = '0' report "SDRAM: interleaved burst unsupported" severity failure;
                        end if;
                        burst_length := 2;
                        cas_latency := 3;
                        mode_loaded := true;
                        initialized := true;
                    when "111" => null; -- NOP
                    when others =>
                        assert false report "SDRAM: unsupported command" severity warning;
                end case;
            end if;
        end if;
    end process;
end architecture;
