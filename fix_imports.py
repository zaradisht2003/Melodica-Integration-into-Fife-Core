import os
import sys

# find all .bsv files in Melodica-3e.../src_bsv
melodica_dir = "/teamspace/studios/this_studio/Melodica-Integration-into-Fife-Core/Melodica-3e5cc630c0167e2ad2caf431dd30791859b87097/src_bsv"

files_to_fix = []
for root, dirs, files in os.walk(melodica_dir):
    for f in files:
        if f.endswith(".bsv"):
            path = os.path.join(root, f)
            with open(path, "r") as fp:
                content = fp.read()
            if "cur_cycle" in content and "Cur_Cycle" not in content:
                files_to_fix.append(path)

for path in files_to_fix:
    with open(path, "r") as fp:
        lines = fp.readlines()
    
    # insert after package name or first import
    out_lines = []
    inserted = False
    for line in lines:
        out_lines.append(line)
        if not inserted and (line.startswith("import") or line.startswith("package")):
            out_lines.append("import Cur_Cycle :: *;\n")
            inserted = True
    
    with open(path, "w") as fp:
        fp.writelines(out_lines)
    print(f"Fixed {path}")
