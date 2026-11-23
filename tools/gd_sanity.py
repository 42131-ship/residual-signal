#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GDScript 离线结构检查（不是编译器）

这台机器没有 Godot，也没有 gdtoolkit。所以在拿到真编译器之前，
用这个脚本把「一定会被编译器和 review 抓到的低级错」先抓掉：

  1. 缩进混用（GDScript 硬错：同一文件里 tab 与空格混排）
  2. 括号 / 引号不平衡（跳过字符串与注释）
  3. 缺 `extends` / `class_name`
  4. 出现 `print(` ——本项目规定只发 signal，不 print
  5. 必需的 API 是否齐全（按清单）
  6. 单个函数超过 80 行（提示拆分，不算错）

**它不能证明代码能编译。** 能证明编译通过的东西只有 Godot 本身：
    godot --headless --check-only --script res://game/runtime/data_layer.gd

用法：
    python tools/gd_sanity.py game/runtime/data_layer.gd
    python tools/gd_sanity.py --require "func load_all,func node,func calendar_at" file.gd
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def strip_code(text: str) -> str:
    """去掉注释与字符串内容，只留结构字符（用于括号平衡检查）。"""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c in "\"'":
            q = c
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == q:
                    i += 1
                    break
                i += 1
            out.append("S")
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check_balance(code: str) -> list[str]:
    pairs = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    line = 1
    errs = []
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack:
                errs.append(f"第 {line} 行多出一个 '{ch}'")
                continue
            open_ch, open_line = stack.pop()
            if open_ch != pairs[ch]:
                errs.append(f"第 {line} 行的 '{ch}' 与第 {open_line} 行的 '{open_ch}' 不匹配")
    for ch, ln in stack:
        errs.append(f"第 {ln} 行的 '{ch}' 没有闭合")
    return errs


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="GDScript 离线结构检查")
    ap.add_argument("files", nargs="+")
    ap.add_argument("--require", default="", help="必需 API，逗号分隔，如 func load_all")
    ap.add_argument("--allow-print", action="store_true",
                    help="允许 print（仅限游戏壳 main.gd 这类唯一入口）")
    args = ap.parse_args(argv)

    required = [x.strip() for x in args.require.split(",") if x.strip()]
    problems = 0

    for f in args.files:
        p = Path(f)
        if not p.exists():
            print(f"[MISS] {p}")
            problems += 1
            continue
        raw = p.read_text(encoding="utf-8", errors="replace")
        lines = raw.splitlines()
        issues: list[str] = []
        warns: list[str] = []

        # 1. 缩进混用
        tab_lines = sum(1 for ln in lines if ln.startswith("\t"))
        sp_lines = sum(1 for ln in lines if re.match(r"^ {1,}\S", ln))
        if tab_lines and sp_lines:
            issues.append(f"缩进混用：{tab_lines} 行用 tab，{sp_lines} 行用空格")

        # 2. 括号平衡
        issues.extend(check_balance(strip_code(raw)))

        # 3. extends / class_name（允许 `class_name X extends Y` 单行写法）
        has_extends = re.search(r"^extends\s+\S+", raw, re.M) or re.search(
            r"^class_name\s+\w+\s+extends\s+\S+", raw, re.M)
        if not has_extends:
            issues.append("缺 extends（GDScript 根对象必须声明）")
        cn = re.findall(r"^class_name\s+(\w+)", raw, re.M)
        if not cn:
            warns.append("没有 class_name（若只做内部脚本可忽略）")
        elif len(cn) > 1:
            issues.append(f"class_name 声明了 {len(cn)} 次：{cn}")

        # 4. print
        for i, ln in enumerate(lines, 1):
            s = ln.split("#")[0]
            if re.search(r"\bprint(_debug|_raw)?\s*\(", s) and not args.allow_print:
                issues.append(f"第 {i} 行有 print()（本项目只发 signal）")
            if s.rstrip() != s:
                warns.append(f"第 {i} 行有行尾空白")

        # 5. 必需 API
        for req in required:
            if req.startswith("func "):
                name = req[5:].strip()
                if not re.search(rf"^func\s+{re.escape(name)}\s*\(", raw, re.M):
                    issues.append(f"缺必需函数 {name}()")
            elif req.startswith("signal "):
                name = req[7:].strip()
                if not re.search(rf"^signal\s+{re.escape(name)}\b", raw, re.M):
                    issues.append(f"缺必需信号 {name}")

        # 6. 超长函数
        for m in re.finditer(r"^func\s+(\w+)\s*\(", raw, re.M):
            start = raw[: m.start()].count("\n")
            rest = raw[m.start():].split("\n")
            body = 0
            for ln in rest[1:]:
                if ln and not ln.startswith(("\t", " ")):
                    break
                body += 1
            if body > 80:
                warns.append(f"函数 {m.group(1)}() 有 {body} 行，考虑拆分")

        status = "PASS" if not issues else "FAIL"
        print(f"[{status}] {p}  {len(lines)} 行  func {len(re.findall(r'^func ', raw, re.M))} 个")
        for x in issues:
            print(f"        ✗ {x}")
        for x in warns[:6]:
            print(f"        · {x}")
        problems += len(issues)

    print(f"\n结构问题 {problems} 个。**这不等于编译通过** —— 真编译要 Godot --headless --check-only。")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
