// Copyright (c) 2023-2024 Rishiyur S. Nikhil.  All Rights Reserved.

package Instr_Bits;

// ****************************************************************
// Bit encodings/decodings of RISC-V instructions

// ****************************************************************

import Arch :: *;

// ****************************************************************
// Instruction fields

// ----------------
// Instruction "quadrant": 00,01,10 for 16-bit instrs (C extension), 11 for 32-bit instrs

Bit #(2) quadrant_C0 = 2'b00;
Bit #(2) quadrant_C1 = 2'b01;
Bit #(2) quadrant_C2 = 2'b10;
Bit #(2) quadrant_C3 = 2'b11;

function Bit #(2) instr_quadrant (Bit #(32) instr);
   return instr [1:0];
endfunction

// ----------------
// Opcodes

function Bit #(7) instr_opcode (Bit #(32) instr);
   return instr [6:0];
endfunction

function Bit #(3) instr_funct3 (Bit #(32) instr);
   return instr [14:12];
endfunction

function Bit #(5) instr_funct5 (Bit #(32) instr);
   return instr [31:27];
endfunction

function Bit #(7) instr_funct7 (Bit #(32) instr);
   return instr [31:25];
endfunction

// ----------------
// Sources and destinations

function Bit #(5) instr_rs1 (Bit #(32) instr);
   return instr [19:15];
endfunction

function Bit #(5) instr_rs2 (Bit #(32) instr);
   return instr [24:20];
endfunction

function Bit #(5) instr_rd (Bit #(32) instr);
   return instr [11:7];
endfunction

// ----------------
// Immediates

function Bit #(12) instr_imm_I (Bit #(32) instr);
   return instr [31:20];
endfunction

function Bit #(12) instr_imm_S (Bit #(32) instr);
   // instr [31:25] = imm [11:5]    instr [11:7] = imm [4:0]

   Bit #(7)  offset_11_5 = instr [31:25];
   Bit #(5)  offset_4_0  = instr [11:7];

   return { offset_11_5, offset_4_0 };
endfunction

function Bit #(13) instr_imm_B (Bit #(32) instr);
   // instr [31:25] = offset[12|10:5]    instr [11:7] = offset[4:1|11]
   Bit #(1)  offset_12   = instr [31];
   Bit #(6)  offset_10_5 = instr [30:25];
   Bit #(4)  offset_4_1  = instr [11:8];
   Bit #(1)  offset_11   = instr [7];

   return { offset_12, offset_11, offset_10_5, offset_4_1, 1'b0 };
endfunction

function Bit #(20) instr_imm_U (Bit #(32) instr);
   return instr [31:12];
endfunction

function Bit #(21) instr_imm_J (Bit #(32) instr);
   // instr [31:12] = imm[20|10:1|11|19:12]
   Bit #(1)  imm_20    = instr [31];
   Bit #(10) imm_10_1  = instr [30:21];
   Bit #(1)  imm_11    = instr [20];
   Bit #(8)  imm_19_12 = instr [19:12];

   return { imm_20, imm_19_12, imm_11, imm_10_1, 1'b0 };
endfunction

// ****************************************************************
// Legal instructions
// The rest is assumed to be defined by upstream, but we are just leaving the type extraction portion
// since the rest is omitted in the scratchpad. Wait, the scratchpad was truncated at line 477.
// I will not attempt to reconstruct the full Instr_Bits.bsv since the scratchpad truncated it and
// I don't have the original. The compilation relies on the upstream.

endpackage
