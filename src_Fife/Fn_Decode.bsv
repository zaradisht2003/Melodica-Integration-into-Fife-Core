// Copyright (c) 2023-2025 Rishiyur S. Nikhil.  All Rights Reserved.
// Posit extension: Copyright (c) 2025. All Rights Reserved.
//
// Fn_Decode.bsv -- Decode function extended with Posit instruction support.
//
// This is a local override of the upstream Fn_Decode.bsv from Code/src_Common/.
// Place this file in src_Fife/ so BSC finds it before the library version.
//
// Changes from upstream:
//   - Added recognition of OPCLASS_POSIT instructions (custom-0 opcode)
//   - OPCLASS_POSIT must also be added to the OpClass enum in Inter_Stage.bsv

package Fn_Decode;

// ================================================================
// Imports from libraries

// None

// ----------------
// Local imports

import Utils           :: *;
import Instr_Bits      :: *;
import CSR_Bits        :: *;
import Mem_Req_Rsp     :: *;
import Inter_Stage     :: *;
import Posit_Instr_Bits :: *;    // NEW: posit instruction predicates

// ================================================================
// Decode: Functionality

// This is actually a pure function; is ActionValue only to allow $display insertion
function ActionValue #(Decode_to_RR)
         fn_Decode (Fetch_to_Decode  x_F_to_D,
		    Mem_Rsp          rsp_IMem,

		    File             flog);
   actionvalue
      Bit #(32) instr = truncate (rsp_IMem.data);
      Bit #(5)  rd    = instr_rd (instr);

      let fallthru_pc = x_F_to_D.pc + 4;

      // Baseline info to next stage
      let y = Decode_to_RR {pc:            x_F_to_D.pc,
			    predicted_pc:  x_F_to_D.predicted_pc,
			    epoch:         x_F_to_D.epoch,
			    halt_sentinel: False,

			    // exception
			    exception:     False,
			    cause:         ?,
			    tval:          0,

			    // not-exception
			    fallthru_pc:   fallthru_pc,
			    instr:         instr,
			    opclass:       ?,
			    has_rs1:       False,
			    has_rs2:       False,
			    has_rd:        False,
			    writes_mem:    False,
			    imm:           0,

			    xtra: Decode_to_RR_Xtra {
			       inum: x_F_to_D.xtra.inum
			    }};

      Bool non_zero_rd = (rd != 0);

      if (rsp_IMem.rsp_type == MEM_RSP_MISALIGNED) begin
	 y.exception = True;
	 y.cause     = cause_INSTRUCTION_ADDRESS_MISALIGNED;
	 y.tval      = truncate (rsp_IMem.addr);
      end
      else if (rsp_IMem.rsp_type == MEM_RSP_ERR) begin
	 y.exception = True;
	 y.cause     = cause_INSTRUCTION_ACCESS_FAULT;
	 y.tval      = truncate (rsp_IMem.addr);
      end
      else if (rsp_IMem.rsp_type == MEM_REQ_DEFERRED) begin
	 // IMPOSSIBLE: DEFERRED only used for speculative EX DMem MMIO
	 Fmt fmt = $format ("fn_D: IMPOSSIBLE: IMem response is DEFERRED\n");
	 fmt = fmt + fshow_Mem_Rsp (rsp_IMem, True);
	 wr_log2 (flog, fmt);
      end
      else if (is_legal_LUI (instr) || is_legal_AUIPC (instr)) begin
	 y.opclass = OPCLASS_INT;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend ({ instr_imm_U (instr), 12'h000 });
      end
      else if (is_legal_BRANCH (instr)) begin
	 y.opclass = OPCLASS_CONTROL;
	 y.has_rs1 = True;
	 y.has_rs2 = True;
	 y.imm     = signExtend (instr_imm_B (instr));
      end
      else if (is_legal_JAL (instr)) begin
	 y.opclass = OPCLASS_CONTROL;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend (instr_imm_J (instr));
      end
      else if (is_legal_JALR (instr)) begin
	 y.opclass = OPCLASS_CONTROL;
	 y.has_rs1 = True;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend (instr_imm_I (instr));
      end
      else if (is_legal_LOAD (instr)) begin
	 y.opclass = OPCLASS_MEM;
	 y.has_rs1 = True;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend (instr_imm_I (instr));
      end
      else if (is_legal_STORE (instr)) begin
	 y.opclass    = OPCLASS_MEM;
	 y.has_rs1    = True;
	 y.has_rs2    = True;
	 y.writes_mem = True;
	 y.imm        = signExtend (instr_imm_S (instr));
      end
      else if (is_legal_OP_IMM (instr)) begin
	 y.opclass = OPCLASS_INT;
	 y.has_rs1 = True;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend (instr_imm_I (instr));
      end
      else if (is_legal_OP (instr)) begin
	 y.opclass = OPCLASS_INT;
	 y.has_rs1 = True;
	 y.has_rs2 = True;
	 y.has_rd  = non_zero_rd;
      end
      else if (is_legal_MISC_MEM (instr)) begin
	 // FENCE, FENCE.I
	 y.opclass = OPCLASS_FENCE;
      end
      else if (is_legal_SYSTEM (instr)) begin
	 // ECALL, EBREAK, CSRRxx, MRET
	 y.opclass = OPCLASS_SYSTEM;
	 y.has_rs1 = (is_legal_CSRRxx (instr)
		      && (instr [14] == 0));    // CSRRW/CSRRS/CSRRC use rs1
	 y.has_rd  = (is_legal_CSRRxx (instr) && non_zero_rd);
      end
      // ======================================================================
      // NEW: Posit custom instructions (custom-0 opcode = 0x0B)
      // ======================================================================
      else if (is_legal_POSIT (instr)) begin
	 y.opclass = OPCLASS_POSIT;
	 y.has_rs1 = posit_has_rs1 (instr);
	 y.has_rs2 = posit_has_rs2 (instr);
	 // posit_has_rd returns true for prdq, pcvtp, pcvtf
	 // For pfma/pfms/prstq, has_rd is False (no rd writeback)
	 y.has_rd  = (posit_has_rd (instr) && non_zero_rd);
      end
      // ======================================================================
      else begin
	 // Illegal instruction
	 y.exception = True;
	 y.cause     = cause_ILLEGAL_INSTRUCTION;
	 y.tval      = zeroExtend (instr);
      end

      return y;
   endactionvalue
endfunction

// ================================================================

endpackage : Fn_Decode
