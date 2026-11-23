#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""同步 see-through 的语义层名表（bodytags_v3.json）。

为什么需要它：see-through（SIGGRAPH 2026，Apache-2.0）把人物拆成 23 个语义层并导出分层 PSD，
下游工具（Stretchy Studio / Anime2.5DRig）认的是**层名**。我们导出自己的分层资产时，
层名必须来自上游这份表，不能凭记忆写。

用法：
    # 1) 直接从 GitHub 拉（需要能访问 api.github.com）
    python tools/see_through_sync.py

    # 2) 离线：从已经保存下来的 API 响应里解出来
    python tools/see_through_sync.py --from-response <已保存的 json 文本>
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "see_through" / "bodytags_v3.json"
API = "https://api.github.com/repos/shitagaki-lab/see-through/contents/common/assets/bodytags_v3.json"


def decode_response(text: str) -> dict:
    match = re.search(r'"content":"(.*?)","encoding":"base64"', text, re.S)
    if not match:
        raise SystemExit("response has no base64 content field")
    raw = match.group(1).replace("\\n", "\n")
    return json.loads(base64.b64decode(raw).decode("utf-8"))


def fetch() -> dict:
    request = urllib.request.Request(API, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "residual-signal/see-through-sync",
    })
    with urllib.request.urlopen(request, timeout=60) as response:
        return decode_response(response.read().decode("utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="同步 see-through 语义层名表")
    parser.add_argument("--from-response", help="已保存的 GitHub API 响应文本")
    args = parser.parse_args(argv)

    data = decode_response(Path(args.from_response).read_text(encoding="utf-8", errors="replace")) \
        if args.from_response else fetch()
    if not isinstance(data, dict) or not data:
        raise SystemExit("unexpected bodytags payload")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"layers={len(data)} -> {OUT.relative_to(ROOT)}")
    for name, tags in data.items():
        print(f"  {name}: {len(tags)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
