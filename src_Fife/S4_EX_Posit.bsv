// Copyright (c) 2025.  All Rights Reserved.
//
// S4_EX_Posit: Execution pipeline stage for Posit Arithmetic Instructions.
//
// This module integrates Melodica's PositCore (posit arithmetic unit) as a
// new functional unit in the Fife pipeline, alongside EX_Control and EX_Int.
//
// Supported operations (via custom-0 RISC-V instructions):
//   pfma  rd, rs1, rs2  -- quire += rs1 * rs2
//   pfms  rd, rs1, rs2  -- quire -= rs1 * rs2
//   prdq  rd            -- rd = posit_from_quire (normalize quire to posit)
//   prstq               -- reset quire to zero
//   pcvtp rd, rs1       -- rd = float_to_posit(rs1)
//   pcvtf rd, rs1       -- rd = posit_to_float(rs1)
//
// Posit format: posit32 (32-bit posit, es=2).  Posit bits stored in int GPRs.
//
// Architecture notes:
//   - The quire is persistent state within mkPositCore (one quire per CPU core).
//   - pfma/pfms/prstq do NOT write rd: they update quire state only.
//     The retire stage handles these as "no rd write" operations.
//   - prdq reads the quire and writes a posit value to rd.
//   - The posit unit is multi-cycle; the RR scoreboard stalls until rd is released.
//   - Compilation flag: -D STANDALONE -D ONLY_POSITS -D P32

package S4_EX_Posit;

// ================================================================
// Imports from libraries

import FIFOF        :: *;
import SpecialFIFOs :: *;    // mkPipelineFIFOF, mkBypassFIFOF
import GetPut       :: *;
import ClientServer :: *;
import FloatingPoint :: *;

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports (Fife)

import Utils       :: *;
import Arch        :: *;
import Instr_Bits  :: *;
import Inter_Stage :: *;

import Posit_Instr_Bits :: *;

// ----------------
// Melodica imports (Posit Arithmetic Unit)
// Compiled with -D STANDALONE -D ONLY_POSITS -D P32

import PositCore :: *;

// ================================================================
// Interface

interface EX_Posit_IFC;
   method Action init (Initial_Params initial_params);

   // Forward in: from RR/Dispatch stage
   interface FIFOF_I #(RR_to_EX)     fi_RR_to_EX_Posit;
   // Forward out: to Retire stage
   interface FIFOF_O #(EX_to_Retire) fo_EX_Posit_to_Retire;
endinterface

// ================================================================
// Verbosity: 0 = quiet, 1 = display at each posit op, 2 = verbose

Integer verbosity = 0;

// ================================================================
// Module

(* synthesize *)
module mkEX_Posit (EX_Posit_IFC);
   Reg #(File) rg_flog <- mkReg (InvalidFile);    // debugging log file

   // ----------------------------------------------------------------
   // Forward FIFOs

   // In from RR/Dispatch
   FIFOF #(RR_to_EX)      f_RR_to_EX_Posit     <- mkPipelineFIFOF;
   // Out to Retire
   FIFOF #(EX_to_Retire)  f_EX_Posit_to_Retire  <- mkBypassFIFOF;

   // ----------------------------------------------------------------
   // The Melodica PositCore instance
   // mkPositCore is parameterized by verbosity (Bit#(2))
   // It presents a Server interface for posit requests/responses.
   //
   // Request  type: Tuple4 #(FloatU, FloatU, RoundMode, PositCmds)
   // Response type: Tuple2 #(FloatU, FloatingPoint::Exception)  (Fpu_Rsp)

   PositCore_IFC posit_core <- mkPositCore (fromInteger (verbosity));

   // ----------------------------------------------------------------
   // FIFO to carry the instruction forward from request to response
   // (posit operations are multi-cycle pipelines)
   FIFOF #(RR_to_EX) f_pending <- mkSizedFIFOF (4);

   // ----------------------------------------------------------------
   // Round mode: always use round-nearest-even for posit operations
   FloatingPoint::RoundMode rnd = Rnd_Nearest_Even;

   // ================================================================
   // BEHAVIOR

   // ----------------------------------------------------------------
   // Stage 1: Accept instruction from RR, issue request to PositCore

   rule rl_EX_Posit_issue;
      let x <- pop_o (to_FIFOF_O (f_RR_to_EX_Posit));
      let instr   = x.instr;
      let rs1_val = x.rs1_val;
      let rs2_val = x.rs2_val;

      // Pack rs1/rs2 as FloatU posit values (raw bit patterns)
      FloatU op1 = tagged P truncate (rs1_val);
      FloatU op2 = tagged P truncate (rs2_val);

      // Map instruction to PositCmds
      PositCmds cmd;
      if      (is_PFMA  (instr)) cmd = FMA_P;
      else if (is_PFMS  (instr)) cmd = FMS_P;
      else if (is_PRDQ  (instr)) cmd = FCVT_P_R;    // quire -> posit
      else if (is_PRSTQ (instr)) cmd = FCVT_R_P;    // posit -> quire (init quire to 0)
      else if (is_PCVTP (instr)) cmd = FCVT_P_S;    // float32 -> posit
      else if (is_PCVTF (instr)) cmd = FCVT_S_P;    // posit -> float32
      else begin
         // Should never reach here if decode is correct
         cmd = FMA_P;
         $display ("%0d: S4_EX_Posit: ERROR: unknown posit instr %08h", cur_cycle, instr);
      end

      // For PRSTQ (reset quire), we send posit value 0 as init value
      // FCVT_R_P = "posit-to-quire" initializer: sets quire = posit(op1)
      // So PRSTQ encodes as: FCVT_R_P with op1 = posit(0) = 0
      if (is_PRSTQ (instr)) begin
         op1 = tagged P 0;
         op2 = tagged P 0;
      end

      // For PCVTP (float->posit): op1 is a single-precision float
      // We need to pack it as FloatU tagged S
      if (is_PCVTP (instr)) begin
         // rs1 holds raw IEEE 754 single-precision bits
         // FloatU.S = FloatingPoint#(8,23)
         FSingle fs = FSingle {
            sign : unpack (rs1_val [31]),
            exp  : rs1_val [30:23],
            sfd  : rs1_val [22:0]
         };
         op1 = tagged S fs;
      end

      // Send request to PositCore
      posit_core.server_core.request.put (tuple4 (op1, op2, rnd, cmd));

      // Carry instruction metadata forward to the response rule
      // NOTE: pfma/pfms/prstq do NOT produce a posit output into the
      // response FIFO in the original PositCore design --
      // they update the quire silently.  We still need a response token
      // to drive the Retire stage, which we handle below.
      f_pending.enq (x);

      if (verbosity > 0)
         $display ("%0d: S4_EX_Posit.rl_issue: instr %08h cmd %0d rs1=%08h rs2=%08h",
                   cur_cycle, instr, pack (cmd), rs1_val, rs2_val);
   endrule

   // ----------------------------------------------------------------
   // Stage 2: Collect response from PositCore, forward to Retire

   rule rl_EX_Posit_collect;
      let x   = f_pending.first;
      let instr = x.instr;

      // FMA_P / FMS_P / FCVT_R_P do not produce output on ffO in PositCore
      // -- they update the quire and the CPU treats rd as "no writeback".
      // For these, we manufacture a zero result token.
      //
      // FCVT_P_R (prdq), FCVT_P_S (pcvtp), FCVT_S_P (pcvtf) DO produce output.

      Bool needs_response = (   is_PRDQ  (instr)
                             || is_PCVTP (instr)
                             || is_PCVTF (instr));

      Bit #(XLEN) rd_val = 0;
      Bool        exception = False;

      if (needs_response) begin
         // Block here until PositCore has its response ready
         match { .fpu_out, .excep } <- posit_core.server_core.response.get ();
         f_pending.deq;

         // Extract result bits
         case (fpu_out) matches
            tagged P .p: begin
               // posit result: pack into lower XLEN bits
               rd_val = zeroExtend (p);
            end
            tagged S .fs: begin
               // float result: reconstruct IEEE 754 bits
               rd_val = zeroExtend ({pack (fs.sign), fs.exp, fs.sfd});
            end
            tagged D .fd: begin
               // double not expected from posit unit; return 0
               rd_val = 0;
            end
         endcase

         exception = excep.invalid_op || excep.divide_0;

         if (verbosity > 0)
            $display ("%0d: S4_EX_Posit.rl_collect: instr %08h rd_val=%08h exception=%0d",
                      cur_cycle, instr, rd_val, pack (exception));
      end
      else begin
         // Non-output-producing operations (pfma, pfms, prstq):
         // The PositCore has *no* response on ffO for these operations
         // (it just updates quire).  We do NOT call response.get().
         // We simply dequeue and pass a zero token to Retire.
         f_pending.deq;

         if (verbosity > 0)
            $display ("%0d: S4_EX_Posit.rl_collect: instr %08h (quire op, no rd write)",
                      cur_cycle, instr);
      end

      // Build EX_to_Retire packet
      let y = EX_to_Retire {
         exception: exception,
         cause:     (exception ? cause_ILLEGAL_INSTRUCTION : ?),
         tval:      (exception ? zeroExtend (instr)        : ?),
         data:      rd_val,
         xtra:      EX_to_Retire_Xtra { inum: x.xtra.inum,
                                        pc:   x.xtra.pc }
      };

      f_EX_Posit_to_Retire.enq (y);
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog <= initial_params.flog;
   endmethod

   // Forward in
   interface fi_RR_to_EX_Posit = to_FIFOF_I (f_RR_to_EX_Posit);
   // Forward out
   interface fo_EX_Posit_to_Retire = to_FIFOF_O (f_EX_Posit_to_Retire);

endmodule

// ================================================================

endpackage : S4_EX_Posit
