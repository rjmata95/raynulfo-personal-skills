#!/usr/bin/env python3
"""Section headings (## / ###) present in the before file and absent in the after file."""
import re, sys, os
before_root, after_root = sys.argv[1], sys.argv[2]
def heads(p):
    out = set()
    for line in open(p, encoding="utf-8"):
        m = re.match(r"^#{2,3}\s+(.*)$", line)
        if m:
            h = re.sub(r"^\d+[a-z]?\.\s*", "", m.group(1)).strip()
            h = re.sub(r"\s*[—(].*$", "", h).strip().lower()
            out.add(h)
    return out
for f in sys.argv[3:]:
    b, a = os.path.join(before_root, f), os.path.join(after_root, f)
    gone = sorted(heads(b) - heads(a))
    if gone:
        print(f"== {f}")
        for h in gone: print(f"   {h}")
