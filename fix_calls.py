import re
with open("Learn_Bluespec_and_RISCV_Design/Code/src_Fife/S5_Retire.bsv", "r") as f:
    text = f.read()

# Replace single-line calls
text = re.sub(r'fa_redirect_Fetch \(mispredicted, is_Halt_Req, x_rr_to_retire, tvec_pc\);',
              r'fa_redirect_Fetch (mispredicted, is_Halt_Req, x_rr_to_retire, tvec_pc, False, False, mispredicted);', text)
text = re.sub(r'fa_redirect_Fetch \(mispredicted, haltreq, x_rr_to_retire, next_pc\);',
              r'fa_redirect_Fetch (mispredicted, haltreq, x_rr_to_retire, next_pc, False, False, mispredicted);', text)

# Replace multi-line calls
# x2.next_pc); -> x2.next_pc, False, False, mispredicted);
# tvec_pc); -> tvec_pc, False, False, mispredicted);
# x_rr_to_retire.fallthru_pc); -> x_rr_to_retire.fallthru_pc, False, False, mispredicted);
# BUT only for the ones that don't already have it! (the one we fixed in rl_Retire_Control has branch_taken)

text = re.sub(r'x2\.next_pc\);\n\t csrs\.ma_incr_instret;', 
              r'x2.next_pc,\n\t\t\t    False, False, mispredicted);\n\t csrs.ma_incr_instret;', text)
text = re.sub(r'tvec_pc\);\n', 
              r'tvec_pc,\n\t\t\t    False, False, mispredicted);\n', text)
text = re.sub(r'x_rr_to_retire\.fallthru_pc\);\n\t csrs\.ma_incr_instret;', 
              r'x_rr_to_retire.fallthru_pc,\n\t\t\t    False, False, mispredicted);\n\t csrs.ma_incr_instret;', text)

with open("Learn_Bluespec_and_RISCV_Design/Code/src_Fife/S5_Retire.bsv", "w") as f:
    f.write(text)
