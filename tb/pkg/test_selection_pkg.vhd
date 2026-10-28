-- Thee testcases fails (because the picorv32 does not have related ports or TB instrumented)

library ieee;
use ieee.std_logic_1164.all;

package test_selection_pkg is

    subtype case_id_type is natural range 1 to 63;
    type case_list_type is array (natural range <>) of case_id_type;

    constant tc_001_add                     : case_id_type := 1;
    constant tc_002_sub                     : case_id_type := 2;
    constant tc_003_xor                     : case_id_type := 3;
    constant tc_004_or                      : case_id_type := 4;
    constant tc_005_and                     : case_id_type := 5;
    constant tc_006_sll                     : case_id_type := 6;
    constant tc_007_srl                     : case_id_type := 7;
    constant tc_008_sra                     : case_id_type := 8;
    constant tc_009_slt                     : case_id_type := 9;
    constant tc_010_sltu                    : case_id_type := 10;
    constant tc_011_addi                    : case_id_type := 11;
    constant tc_012_xori                    : case_id_type := 12;
    constant tc_013_ori                     : case_id_type := 13;
    constant tc_014_andi                    : case_id_type := 14;
    constant tc_015_slli                    : case_id_type := 15;
    constant tc_016_srli                    : case_id_type := 16;
    constant tc_017_srai                    : case_id_type := 17;
    constant tc_018_slti                    : case_id_type := 18;
    constant tc_019_sltiu                   : case_id_type := 19;
    constant tc_020_lb                      : case_id_type := 20;
    constant tc_021_lh                      : case_id_type := 21;
    constant tc_022_lw                      : case_id_type := 22;
    constant tc_023_lbu                     : case_id_type := 23;
    constant tc_024_lhu                     : case_id_type := 24;
    constant tc_025_sb                      : case_id_type := 25;
    constant tc_026_sh                      : case_id_type := 26;
    constant tc_027_sw                      : case_id_type := 27;
    constant tc_028_beq                     : case_id_type := 28;
    constant tc_029_bne                     : case_id_type := 29;
    constant tc_030_blt                     : case_id_type := 30;
    constant tc_031_bge                     : case_id_type := 31;
    constant tc_032_bltu                    : case_id_type := 32;
    constant tc_033_bgeu                    : case_id_type := 33;
    constant tc_034_jal                     : case_id_type := 34;
    constant tc_035_jalr                    : case_id_type := 35;
    constant tc_036_lui                     : case_id_type := 36;
    constant tc_037_auipc                   : case_id_type := 37;
    constant tc_038_ecall                   : case_id_type := 38;
    constant tc_039_ebreak                  : case_id_type := 39;
    constant tc_040_mul                     : case_id_type := 40;
    constant tc_041_mulh                    : case_id_type := 41;
    constant tc_042_mulhsu                  : case_id_type := 42;
    constant tc_043_mulhu                   : case_id_type := 43;
    constant tc_044_div                     : case_id_type := 44;
    constant tc_045_divu                    : case_id_type := 45;
    constant tc_046_rem                     : case_id_type := 46;
    constant tc_047_remu                    : case_id_type := 47;
    constant tc_048_fence                   : case_id_type := 48;
    constant tc_049_illegal                 : case_id_type := 49;
    constant tc_050_fence_i                 : case_id_type := 50;
    constant tc_051_misaligned_lw           : case_id_type := 51;
    constant tc_052_misaligned_sh           : case_id_type := 52;
    constant tc_053_misaligned_jal          : case_id_type := 53;
    constant tc_054_misaligned_jalr         : case_id_type := 54;
    constant tc_055_misaligned_branch       : case_id_type := 55;
    constant tc_056_illegal_shift           : case_id_type := 56;
    constant tc_057_load_error              : case_id_type := 57; --Fails
    constant tc_058_store_error             : case_id_type := 58; --Fails
    constant tc_059_x0                      : case_id_type := 59;
    constant tc_060_untaken_misaligned_branch : case_id_type := 60;
    constant tc_061_gpio                    : case_id_type := 61;
    constant tc_062_register_bank           : case_id_type := 62; --Fails
    constant tc_063_uart_status             : case_id_type := 63;

    constant enabled_cases : case_list_type := (
        tc_001_add,
        tc_002_sub,
        tc_003_xor,
        tc_004_or,
        tc_005_and,
        tc_006_sll,
        tc_007_srl,
        tc_008_sra,
        tc_009_slt,
        tc_010_sltu,
        tc_011_addi,
        tc_012_xori,
        tc_013_ori,
        tc_014_andi,
        tc_015_slli,
        tc_016_srli,
        tc_017_srai,
        tc_018_slti,
        tc_019_sltiu,
        tc_020_lb,
        tc_021_lh,
        tc_022_lw,
        tc_023_lbu,
        tc_024_lhu,
        tc_025_sb,
        tc_026_sh,
        tc_027_sw,
        tc_028_beq,
        tc_029_bne,
        tc_030_blt,
        tc_031_bge,
        tc_032_bltu,
        tc_033_bgeu,
        tc_034_jal,
        tc_035_jalr,
        tc_036_lui,
        tc_037_auipc,
        tc_038_ecall,
        tc_039_ebreak,
        tc_040_mul,
        tc_041_mulh,
        tc_042_mulhsu,
        tc_043_mulhu,
        tc_044_div,
        tc_045_divu,
        tc_046_rem,
        tc_047_remu,
        tc_048_fence,
        tc_049_illegal,
        tc_050_fence_i,
        tc_051_misaligned_lw,
        tc_052_misaligned_sh,
        tc_053_misaligned_jal,
        tc_054_misaligned_jalr,
        tc_055_misaligned_branch,
        tc_056_illegal_shift,
        tc_057_load_error,
        tc_058_store_error,
        tc_059_x0,
        tc_060_untaken_misaligned_branch,
        tc_061_gpio,
        tc_062_register_bank,
        tc_063_uart_status
    );

end package;