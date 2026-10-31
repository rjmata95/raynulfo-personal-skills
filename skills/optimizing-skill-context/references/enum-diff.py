#!/usr/bin/env python3
"""For each changed skill/shared file: backticked tokens present before but absent after.
Flags whether the token still exists anywhere in the after tree (moved) or nowhere (dropped)."""
import re, sys, os, glob

before_root, after_root = sys.argv[1], sys.argv[2]
files = sys.argv[3:]

def tokens(text):
    out = set()
    for t in re.findall(r"`([^`\n]{2,80})`", text):
        t = t.strip()
        if re.fullmatch(r"[-\w./:<>|*\[\] ?=+#]+", t):  # skip prose-y snippets
            out.add(t)
    return out

after_all = ""
for p in glob.glob(os.path.join(after_root, "**", "*.md"), recursive=True):
    after_all += open(p, encoding="utf-8").read() + "\n"

for f in files:
    b = os.path.join(before_root, f); a = os.path.join(after_root, f)
    if not (os.path.exists(b) and os.path.exists(a)): continue
    bt, at = tokens(open(b, encoding="utf-8").read()), tokens(open(a, encoding="utf-8").read())
    at_text = open(a, encoding="utf-8").read()
    dropped = sorted(t for t in bt - at if t not in at_text)
    if not dropped: continue
    print(f"== {f}")
    for t in dropped:
        where = "moved" if f"`{t}`" in after_all or t in after_all else "DROPPED"
        print(f"   {where:8} {t}")
