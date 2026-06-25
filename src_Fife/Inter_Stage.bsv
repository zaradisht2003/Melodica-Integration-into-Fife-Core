// Copyright (c) 2023-2025 Rishiyur S. Nikhil.  All Rights Reserved.
// Posit extension: Copyright (c) 2025. All Rights Reserved.
//
// Inter_Stage.bsv -- Pipeline inter-stage types extended with Posit support.
//
// This is a local override of the upstream Inter_Stage.bsv from Code/src_Common/.
// Place this file in src_Fife/ so BSC finds it before the library version.
//
// Changes from upstream:
//   1. Added OPCLASS_POSIT to the OpClass enum
//   2. Added EXEC_TAG_POSIT to the Exec_Tag enum
//
// All other types and structures are identical to the upstream.

package Inter_Stage;

// ================================================================
// Imports from libraries

import Vector :: *;

// ----------------
// Local imports

import Arch       :: *;
import Instr_Bits :: *;
import CSR_Bits   :: *;

// ================================================================

`include "Inter_Stage_Xtra.bsvi"

// ================================================================
// Pipeline forward flow

typedef 2              W_Epoch;
typedef Bit #(W_Epoch) Epoch;

// ================================================================
// Fetch => Decode

typedef struct {
   Bit #(XLEN)  pc;

   Bit #(XLEN)  predicted_pc;     // for branch-prediction only
   Epoch        epoch;            // for branch-prediction only
   Bool         halt_sentinel;    // Debugger support

   Fetch_to_Decode_Xtra  xtra;
} Fetch_to_Decode
deriving (Bits, FShow);

// ================================================================
// Decode => Register Read

// NEW: OPCLASS_POSIT added for posit custom instructions
typedef enum {OPCLASS_SYSTEM,     // EBREAK, ECALL, CSRRxx
              OPCLASS_CONTROL,    // BRANCH, JAL, JALR
	      OPCLASS_INT,
	      OPCLASS_MEM,        // LOAD, STORE, AMO
	      OPCLASS_FENCE,      // FENCE
	      OPCLASS_POSIT       // NEW: Posit arithmetic (custom-0)
} OpClass
deriving (Bits, Eq, FShow);

typedef struct {
   Bit #(XLEN)  pc;

   Bit #(XLEN)  predicted_pc;     // For branch-prediction only
   Epoch        epoch;            // For branch-prediction only
   Bool         halt_sentinel;    // Debugger support

   // If exception
   Bool         exception;  // Fetch exception/ decode illegal instr
   Bit #(4)     cause;
   Bit #(XLEN)  tval;

   // If not exception
   Bit #(XLEN)  fallthru_pc;
   Bit #(32)    instr;
   OpClass      opclass;
   Bool         has_rs1;
   Bool         has_rs2;
   Bool         has_rd;
   Bool         writes_mem;   // All mem ops other than LOAD
   Bit #(XLEN)  imm;          // Canonical (bit-swizzled)

   Decode_to_RR_Xtra  xtra;
} Decode_to_RR
deriving (Bits, FShow);

// ================================================================
// Register Read => Retire Direct
// Controls Retire's merge of results from execution pipelines

// NEW: EXEC_TAG_POSIT added for posit execution unit
typedef enum {EXEC_TAG_DIRECT,
	      EXEC_TAG_CONTROL,
	      EXEC_TAG_INT,
	      EXEC_TAG_DMEM,
	      EXEC_TAG_POSIT    // NEW: Posit arithmetic execution unit
} Exec_Tag
deriving (Bits, Eq, FShow);

typedef struct {
   Exec_Tag     exec_tag;    // ``flow'' for this instr

   Bit #(XLEN)  pc;

   Bit #(XLEN)  predicted_pc;  // For branch-prediction only
   Epoch        epoch;         // for branch-prediction only
   Bool         halt_sentinel;

   // If exception
   Bool         exception;   // Fetch exception, decode illegal instr
   Bit #(4)     cause;
   Bit #(XLEN)  tval;

   // If not exception
   Bit #(XLEN)  fallthru_pc;
   Bit #(32)    instr;
   Bit #(XLEN)  rs1_val;
   Bool         has_rd;
   Bool         writes_mem;

   RR_to_Retire_Xtra  xtra;
} RR_to_Retire
deriving (Bits, FShow);

// ================================================================
// RR => EX_Control

typedef struct {
   Bit #(XLEN)  pc;
   Bit #(XLEN)  fallthru_pc;
   Bit #(32)    instr;
   Bit #(XLEN)  rs1_val;
   Bit #(XLEN)  rs2_val;
   Bit #(XLEN)  imm;

   RR_to_EX_Control_Xtra  xtra;
} RR_to_EX_Control
deriving (Bits, FShow);

// ================================================================
// RR => EX (Integer ALU and Posit -- shared type)
// NOTE: Posit uses the same RR_to_EX structure as integer EX.
//       rs1_val and rs2_val carry the raw posit bit patterns.

typedef struct {
   Bit #(32)    instr;
   Bit #(XLEN)  rs1_val;
   Bit #(XLEN)  rs2_val;
   Bit #(XLEN)  imm;

   RR_to_EX_Xtra  xtra;
} RR_to_EX
deriving (Bits, FShow);

// ================================================================
// EX => Retire (results from any execution unit)

typedef struct {
   Bool         exception;
   Bit #(4)     cause;
   Bit #(XLEN)  tval;
   Bit #(XLEN)  data;          // result value (rd_val)

   EX_to_Retire_Xtra  xtra;
} EX_to_Retire
deriving (Bits, FShow);

// ================================================================
// EX_Control => Retire

typedef struct {
   Bool         exception;
   Bit #(4)     cause;
   Bit #(XLEN)  tval;
   Bit #(XLEN)  data;          // rd_val (link address for JAL/JALR)
   Bit #(XLEN)  next_pc;

   EX_Control_to_Retire_Xtra  xtra;
} EX_Control_to_Retire
deriving (Bits, FShow);

// ================================================================
// Retire => Fetch (redirection, backward)

typedef struct {
   Bit #(XLEN)  next_pc;
   Epoch        next_epoch;
   Bool         haltreq;

   Fetch_from_Retire_Xtra  xtra;
} Fetch_from_Retire
deriving (Bits, FShow);

// ================================================================
// Retire => Register Write (backward)

typedef struct {
   Bit #(5)     rd;
   Bool         commit;
   Bit #(XLEN)  data;

   RW_from_Retire_Xtra  xtra;
} RW_from_Retire
deriving (Bits, FShow);

// ================================================================
// Retire => DMem commit

typedef struct {
   Bool commit;
   Bit #(64) inum;    // instruction number for ordering
} Retire_to_DMem_Commit
deriving (Bits, FShow);

// ================================================================

endpackage : Inter_Stage
