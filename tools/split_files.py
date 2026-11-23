#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把「一次回复里多个文件」的输出切开落地

模型一次回多个文件时，常见毛病：
  · 开头先来一段"我会先核对字段…"的废话
  · 分隔符被写成 `<<<FILE: x.json >>>`、`<<< FILE: x.json >>>`、`### x.json` 三种样子
  · 每个文件外面还裹一层 ``` 围栏

这个脚本把这些都吃掉，只留 JSON 本体。

用法：
    python tools/split_files.py raw.txt --outdir data/templates
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass

MARK = re.compile(r"<<<\s*FILE:\s*([A-Za-z0-9_./\\\-]+)\s*>>>")


def clean(block: str) -> str:
    block = block.strip()
    block = re.sub(r"^\s*```[a-zA-Z]*\s*", "", block)
    block = re.sub(r"\s*```\s*$", "", block)
    return block.strip()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="切开多文件输出")
    ap.add_argument("raw")
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args(argv)

    text = Path(args.raw).read_text(encoding="utf-8", errors="replace")
    marks = list(MARK.finditer(text))
    if not marks:
        print("没找到 <<<FILE: ... >>> 分隔符")
        return 1

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    ok = 0
    for i, m in enumerate(marks):
        name = m.group(1)
        start = m.end()
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        body = clean(text[start:end])
        path = outdir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if name.endswith(".json"):
            try:
                data = json.loads(body)
            except json.JSONDecodeError as exc:
                print(f"[FAIL] {name}  JSON 非法：{exc}")
                continue
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"[OK]   {path}  {len(json.dumps(data, ensure_ascii=False))} 字符")
        else:
            # 代码文件：只剥围栏，不做语法校验（那是 gd_sanity / 编译器的活）
            if len(body) < 80:
                print(f"[FAIL] {name}  只有 {len(body)} 字符，疑似模型在说话")
                continue
            path.write_text(body + "\n", encoding="utf-8")
            print(f"[OK]   {path}  {len(body)} 字符（{body.count(chr(10)) + 1} 行）")
        ok += 1

    print(f"\n落地 {ok}/{len(marks)} 个文件")
    return 0 if ok == len(marks) else 1


if __name__ == "__main__":
    sys.exit(main())
