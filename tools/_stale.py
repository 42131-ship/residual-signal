import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
for pat in sys.argv[2:]:
    print(f"### {pat!r}  出现 {t.count(pat)} 次")
    for m in re.finditer(re.escape(pat), t):
        seg = t[max(0, m.start() - 140): m.start() + 90].replace("\n", " ")
        print("   …", re.sub(r"\s+", " ", seg))
    print()
