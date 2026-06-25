// Copyright (c) 2023-2025 Rishiyur S. Nikhil.  All Rights Reserved.
// Posit extension: Copyright (c) 2025. All Rights Reserved.
//
// Fn_Dispatch.bsv -- Register-read-and-dispatch extended with Posit support.
//
// This is a local override of the upstream Fn_Dispatch.bsv from Code/src_Common/.
// Place this file in src_Fife/ so BSC finds it before the library version.
//
// Changes from upstream:
//   - Added EXEC_TAG_POSIT case in exec_tag computation
//   - OPCLASS_POSIT -> EXEC_TAG_POSIT mapping

package Fn_Dispatch;

// ================================================================
// Imports from libraries

import Cur_Cycle :: *;

// ----------------
// Local imports

import Utils       :: *;
import Arch        :: *;
import Instr_Bits  :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

// ================================================================

Integer verbosity = 0;

// ================================================================
// Register-read dispatch to execute steps

typedef struct {
   RR_to_Retire      to_Retire;
   RR_to_EX_Control  to_EX_Control;
   RR_to_EX          to_EX;
   Mem_Req           to_EX_DMem;
} Result_Dispatch
deriving (Bits, FShow);

// This is actually a pure function; is ActionValue only to allow easy
// $display insertion for debugging
function ActionValue #(Result_Dispatch)
         fn_Dispatch (Decode_to_RR         x,
		      Bit #(XLEN)          rs1_val,
		      Bit #(XLEN)          rs2_val,

		      File                 flog);
   actionvalue
      // Compute tag to control merging at Retire
      Exec_Tag exec_tag = EXEC_TAG_DIRECT;    // exceptions and OPCLASS_SYSTEM
      if (! x.exception) begin
	 if      (x.opclass == OPCLASS_CONTROL) exec_tag = EXEC_TAG_CONTROL;
	 else if (x.opclass == OPCLASS_INT)     exec_tag = EXEC_TAG_INT;
	 else if (x.opclass == OPCLASS_MEM)     exec_tag = EXEC_TAG_DMEM;
	 else if (x.opclass == OPCLASS_FENCE)   exec_tag = EXEC_TAG_DMEM;
	 // NEW: posit instructions dispatch to posit execution unit
	 else if (x.opclass == OPCLASS_POSIT)   exec_tag = EXEC_TAG_POSIT;
      end

      let to_Retire = RR_to_Retire {exec_tag:      exec_tag,

				    pc:            x.pc,

				    predicted_pc:  x.predicted_pc,
				    epoch:         x.epoch,
				    halt_sentinel: False,

				    exception:    x.exception,
				    cause:        x.cause,
				    tval:         x.tval,

				    fallthru_pc:  x.fallthru_pc,
				    instr:        x.instr,
				    rs1_val:      rs1_val,
				    has_rd:       x.has_rd,
				    writes_mem:   x.writes_mem,

				    xtra: RR_to_Retire_Xtra {
				       inum:    x.xtra.inum,
				       rs2_val: rs2_val}
				    };
      // ----------------
      // Info for EX_Control
      let to_EX_Control = RR_to_EX_Control {pc:           x.pc,
					    fallthru_pc:  x.fallthru_pc,
					    instr:        x.instr,
					    rs1_val:      rs1_val,
					    rs2_val:      rs2_val,
					    imm:          x.imm,

					    xtra: RR_to_EX_Control_Xtra {
					       inum: x.xtra.inum}
					    };
      // ----------------
      // Info for Execute Int pipe (also reused for posit pipe -- same RR_to_EX type)
      let to_EX  = RR_to_EX {instr:   x.instr,
			     rs1_val: rs1_val,
			     rs2_val: rs2_val,
			     imm:     x.imm,

			     xtra: RR_to_EX_Xtra {
				inum:    x.xtra.inum,
				pc:      x.pc}
			     };
      // ----------------
      // Info for Execute DMem pipe
      Bit #(XLEN)  eaddr    = rs1_val + x.imm;
      Mem_Req_Size mrq_size = unpack (x.instr [13:12]);  // B, H, W or D
      Mem_Req_Type mrq_type = (is_LOAD (x.instr) ? funct5_LOAD
			       : (is_STORE (x.instr) ? funct5_STORE
				  : (is_FENCE (x.instr) ? funct5_FENCE
				     : (is_FENCE_I (x.instr) ? funct5_FENCE_I
					: funct5_INVAL))));

      let to_EX_DMem = Mem_Req {req_type: mrq_type,
				size:     mrq_size,
				addr:     zeroExtend (eaddr),
				data:     zeroExtend (rs2_val),
				epoch:    x.epoch,

				xtra: Mem_Req_Xtra {
				   inum:  x.xtra.inum,
				   pc:    x.pc,
				   instr: x.instr}
				};

      if (verbosity > 0)
	 $display ("%0d: Fn_Dispatch: ", cur_cycle, fshow (exec_tag),
		   " pc %0h instr %08h", x.pc, x.instr);

      return (Result_Dispatch {to_Retire:    to_Retire,
			       to_EX_Control: to_EX_Control,
			       to_EX:         to_EX,
			       to_EX_DMem:    to_EX_DMem});
   endactionvalue
endfunction

// ================================================================

endpackage : Fn_Dispatch
