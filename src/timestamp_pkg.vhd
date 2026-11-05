library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package timestamp_pkg is

    -- Date register (raw hex: 05112026)
    constant C_DATE_REGISTER_HEX   : std_logic_vector(31 downto 0) := x"05112026";

    -- Time register (raw hex: 00081100)
    constant C_TIME_REGISTER_HEX   : std_logic_vector(31 downto 0) := x"00081100";

    -- Individual date fields
    constant C_DAY_HEX    : std_logic_vector(7 downto 0)  := x"05";
    constant C_MONTH_HEX  : std_logic_vector(7 downto 0)  := x"0B";
    constant C_YEAR_HEX   : std_logic_vector(15 downto 0) := x"07EA";

    -- Individual time fields
    constant C_HOUR_HEX   : std_logic_vector(7 downto 0)  := x"08";
    constant C_MINUTE_HEX : std_logic_vector(7 downto 0)  := x"0B";
    constant C_SECOND_HEX : std_logic_vector(7 downto 0)  := x"07";

end package;
