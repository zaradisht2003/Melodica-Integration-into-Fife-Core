// Copyright (c) 2025.  All Rights Reserved.
//
// Posit Custom Instruction Encoding for Fife RISC-V Pipeline
//
// Uses the RISC-V custom-0 opcode space (opcode = 7'b000_1011 = 0x0B).
// All instructions are R-type format.
//
// Instruction set (custom-0 extension P32):
//
//   pfma  rd, rs1, rs2  -- quire += rs1 * rs2   (posit FMA)
//   pfms  rd, rs1, rs2  -- quire -= rs1 * rs2   (posit FMS)
//   prdq  rd            -- rd = posit(quire)     (quire read -> posit)
//   prstq               -- quire = 0             (reset quire)
//   pcvtp rd, rs1       -- rd = float_to_posit(rs1)
//   pcvtf rd, rs1       -- rd = posit_to_float(rs1)
//
// Encoding: All are R-type.  funct3 = 3'b000.  funct7 distinguishes operations.
//
//  31       25 24     20 19     15 14   12 11      7 6        0
// |  funct7   |  rs2    |  rs1    |funct3 |   rd    | opcode  |
//
// opcode   = 7'b000_1011  (custom-0)
// funct3   = 3'b000
// funct7   encodes the posit operation (see below)

package Posit_Instr_Bits;

import Instr_Bits :: *;

// ================================================================
// Opcode for all posit custom instructions (custom-0)
Bit #(7) opcode_POSIT = 7'b000_1011;

// funct3 for all posit instructions
Bit #(3) funct3_POSIT = 3'b000;

// funct7 values that distinguish individual posit operations
Bit #(7) funct7_PFMA  = 7'b000_0000;   // posit fused multiply-accumulate
Bit #(7) funct7_PFMS  = 7'b000_0001;   // posit fused multiply-subtract (quire -= a*b)
Bit #(7) funct7_PRDQ  = 7'b000_0010;   // read quire -> posit -> rd
Bit #(7) funct7_PRSTQ = 7'b000_0011;   // reset quire to zero
Bit #(7) funct7_PCVTP = 7'b000_0100;   // convert float (rs1) -> posit -> rd
Bit #(7) funct7_PCVTF = 7'b000_0101;   // convert posit (rs1) -> float -> rd

// ================================================================
// Predicates to decode posit instructions

// Is this instruction a posit custom instruction?
function Bool is_legal_POSIT (Bit #(32) instr);
   return (   (instr_opcode (instr) == opcode_POSIT)
           && (instr_funct3 (instr) == funct3_POSIT));
endfunction

// Individual posit instruction predicates
function Bool is_PFMA  (Bit #(32) instr);
   return (is_legal_POSIT (instr) && (instr_funct7 (instr) == funct7_PFMA));
endfunction

function Bool is_PFMS  (Bit #(32) instr);
   return (is_legal_POSIT (instr) && (instr_funct7 (instr) == funct7_PFMS));
endfunction

function Bool is_PRDQ  (Bit #(32) instr);
   return (is_legal_POSIT (instr) && (instr_funct7 (instr) == funct7_PRDQ));
endfunction

function Bool is_PRSTQ (Bit #(32) instr);
   return (is_legal_POSIT (instr) && (instr_funct7 (instr) == funct7_PRSTQ));
endfunction

function Bool is_PCVTP (Bit #(32) instr);
   return (is_legal_POSIT (instr) && (instr_funct7 (instr) == funct7_PCVTP));
endfunction

function Bool is_PCVTF (Bit #(32) instr);
   return (is_legal_POSIT (instr) && (instr_funct7 (instr) == funct7_PCVTF));
endfunction

// ================================================================
// Operand usage for each posit instruction.
// These are used by the Decode stage to set has_rs1/has_rs2/has_rd.

// Does this posit instruction write a result to rd?
// pfma/pfms: rd is ignored (result goes to quire) -- no rd write
// prdq:  writes rd
// prstq: no rd
// pcvtp: writes rd
// pcvtf: writes rd
function Bool posit_has_rd (Bit #(32) instr);
   Bit #(7) f7 = instr_funct7 (instr);
   return (   (f7 == funct7_PRDQ)
           || (f7 == funct7_PCVTP)
           || (f7 == funct7_PCVTF));
endfunction

// Does this posit instruction read rs1?
// pfma/pfms: rs1 is posit operand A
// prdq/prstq: no rs1
// pcvtp/pcvtf: rs1 is the input
function Bool posit_has_rs1 (Bit #(32) instr);
   Bit #(7) f7 = instr_funct7 (instr);
   return (   (f7 == funct7_PFMA)
           || (f7 == funct7_PFMS)
           || (f7 == funct7_PCVTP)
           || (f7 == funct7_PCVTF));
endfunction

// Does this posit instruction read rs2?
// pfma/pfms: rs2 is posit operand B
// others: no rs2
function Bool posit_has_rs2 (Bit #(32) instr);
   Bit #(7) f7 = instr_funct7 (instr);
   return (   (f7 == funct7_PFMA)
           || (f7 == funct7_PFMS));
endfunction

// ================================================================

endpackage : Posit_Instr_Bits
