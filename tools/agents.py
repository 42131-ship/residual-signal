#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""残余信号 · 模型编排层（三把钥匙 / 三个角色）

角色分工（写死在 config/agents.json，不改代码就改不了角色）：
    dev   gpt-6.2-sol        主力开发：代码 / 数据 / 校验器 / 工具
    aux   claude-opus-5-5    辅助与评审：架构取舍 / 对齐会主席 / 反方
    image gpt-image-2.6-flare 像素资产：风格锚点 / tile / 立绘候选

设计约束：
  - 纯 stdlib（与 validate.py 一致，进 CI 不需要装依赖）
  - 文件进出，不走 shell 字符串（Windows 引号地狱 + 中文编码）
  - 每次调用写 logs/usage.jsonl，用于控成本
  - 图像一律落 art/generated_candidates/（R21：AI 产出默认 draft）

用法：
    python tools/agents.py ping
    python tools/agents.py models
    python tools/agents.py chat --role dev --prompt-file p.md --out out.md
    python tools/agents.py image --prompt-file p.txt --name style_a --size 1024x1024
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config" / "agents.json"
LOG = ROOT / "logs" / "usage.jsonl"

# 中转站前面挂着 Cloudflare：默认的 Python-urllib UA 会被 1010 拦掉。
# 这里伪装成常规客户端；换 host 时若再被拦，优先怀疑这一行。
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def load_config() -> dict[str, Any]:
    if CONFIG.exists():
        cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    else:
        cfg = {"base_url": os.environ.get("RESIDUAL_BASE_URL", ""), "roles": {}}
    # 环境变量优先，便于 CI 不落盘密钥
    for role, spec in (cfg.get("roles") or {}).items():
        env = os.environ.get(f"RESIDUAL_KEY_{role.upper()}")
        if env:
            spec["key"] = env
    return cfg


def role_spec(cfg: dict[str, Any], role: str) -> dict[str, Any]:
    spec = (cfg.get("roles") or {}).get(role)
    if not spec:
        raise SystemExit(f"未配置角色 '{role}'，可选：{list((cfg.get('roles') or {}).keys())}")
    if not spec.get("key"):
        raise SystemExit(f"角色 '{role}' 缺 key（config/agents.json 或 RESIDUAL_KEY_{role.upper()}）")
    return spec


def _headers(key: str, json_body: bool) -> dict[str, str]:
    h = {
        "Authorization": f"Bearer {key}",
        "User-Agent": UA,
        "Accept": "application/json",
    }
    if json_body:
        h["Content-Type"] = "application/json"
    return h


def _post(url: str, key: str, payload: dict[str, Any], timeout: int = 300) -> dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=_headers(key, True), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:800]
        raise SystemExit(f"HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        # 连接被对端关闭（RemoteDisconnected）不是 URLError，是 OSError 子类，
        # 所以这里也要接住，统一转成 SystemExit 交给 chat() 的重试逻辑。
        raise SystemExit(f"连接失败: {exc}") from exc
    except OSError as exc:
        raise SystemExit(f"连接中断: {type(exc).__name__}: {exc}") from exc


def _get(url: str, key: str, timeout: int = 30) -> dict[str, Any]:
    req = urllib.request.Request(url, headers=_headers(key, False))
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _log(record: dict[str, Any]) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    record["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    with LOG.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


# ------------------------------------------------------------------ chat


def chat(
    role: str,
    user: str,
    system: str | None = None,
    max_tokens: int = 4000,
    temperature: float | None = None,
    retries: int = 2,
) -> str:
    cfg = load_config()
    spec = role_spec(cfg, role)
    msgs: list[dict[str, str]] = []
    if system:
        msgs.append({"role": "system", "content": system})
    msgs.append({"role": "user", "content": user})

    payload: dict[str, Any] = {"model": spec["model"], "messages": msgs, "max_tokens": max_tokens}
    if temperature is not None:
        payload["temperature"] = temperature

    last = ""
    for attempt in range(retries + 1):
        try:
            data = _post(f"{cfg['base_url']}/chat/completions", spec["key"], payload)
            usage = data.get("usage") or {}
            _log({"role": role, "model": spec["model"], "usage": usage, "attempt": attempt})
            return data["choices"][0]["message"]["content"]
        except SystemExit as exc:  # 4xx/5xx 都落到这里
            last = str(exc)
            if attempt < retries:
                time.sleep(2 + 3 * attempt)
                continue
            raise SystemExit(f"[{role}] 调用失败：{last}") from None
    return ""


# ------------------------------------------------------------------ image


def image(
    prompt: str,
    name: str,
    size: str = "1024x1024",
    role: str = "image",
    n: int = 1,
) -> list[Path]:
    cfg = load_config()
    spec = role_spec(cfg, role)
    data = _post(
        f"{cfg['base_url']}/images/generations",
        spec["key"],
        {"model": spec["model"], "prompt": prompt, "size": size, "n": n},
        timeout=600,
    )
    _log({"role": role, "model": spec["model"], "usage": data.get("usage") or {}, "kind": "image"})

    outdir = ROOT / "art" / "generated_candidates" / "style_anchors"
    outdir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for i, item in enumerate(data.get("data") or []):
        suffix = f"_{i}" if n > 1 else ""
        path = outdir / f"{name}{suffix}.png"
        if item.get("b64_json"):
            path.write_bytes(base64.b64decode(item["b64_json"]))
        elif item.get("url"):
            with urllib.request.urlopen(item["url"], timeout=300) as resp:
                path.write_bytes(resp.read())
        else:
            raise SystemExit("图像响应里既没有 b64_json 也没有 url")
        paths.append(path)
    return paths


# ------------------------------------------------------------------ cli


def _read(path: str | None) -> str:
    if not path:
        return sys.stdin.read()
    p = Path(path)
    if not p.exists():
        raise SystemExit(f"文件不存在：{path}")
    return p.read_text(encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="残余信号 模型编排层")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ping")
    sub.add_parser("models")

    c = sub.add_parser("chat")
    c.add_argument("--role", required=True, help="角色名，取自 config/agents.json 的 roles")
    c.add_argument("--prompt-file")
    c.add_argument("--system-file")
    c.add_argument("--out")
    c.add_argument("--max-tokens", type=int, default=4000)
    c.add_argument("--json-out", action="store_true", help="剥掉 ``` 围栏并校验 JSON 后再写")
    c.add_argument("--strip-fences", action="store_true", help="只剥代码围栏（写 .gd/.py 用）")

    i = sub.add_parser("image")
    i.add_argument("--prompt-file", required=True)
    i.add_argument("--name", required=True)
    i.add_argument("--size", default="1024x1024")
    i.add_argument("--n", type=int, default=1)

    args = ap.parse_args(argv)
    cfg = load_config()

    if args.cmd == "ping":
        for role in (cfg.get("roles") or {}):
            spec = cfg["roles"][role]
            t0 = time.time()
            if role == "image":
                # 图像模型不走 /chat/completions，用 /models 探活即可
                try:
                    data = _get(f"{cfg['base_url']}/models", spec["key"])
                    n = len(data.get("data", []))
                    print(f"[OK]   {role:<6} {spec['model']:<24} {n} models  ({time.time() - t0:.1f}s)")
                except Exception as exc:  # noqa: BLE001
                    print(f"[FAIL] {role:<6} {exc}")
                continue
            try:
                reply = chat(role, "只回两个字：在线", max_tokens=16)
                print(f"[OK]   {role:<6} {spec['model']:<24} {reply.strip()[:20]}  ({time.time() - t0:.1f}s)")
            except SystemExit as exc:
                print(f"[FAIL] {role:<6} {exc}")
        return 0

    if args.cmd == "models":
        for role, spec in (cfg.get("roles") or {}).items():
            try:
                data = _get(f"{cfg['base_url']}/models", spec["key"])
                ids = sorted(m["id"] for m in data.get("data", []))
                print(f"{role:<6} {len(ids)} models: {', '.join(ids)}")
            except Exception as exc:  # noqa: BLE001
                print(f"{role:<6} FAIL {exc}")
        return 0

    if args.cmd == "chat":
        system = _read(args.system_file) if args.system_file else None
        out = chat(args.role, _read(args.prompt_file), system=system, max_tokens=args.max_tokens)
        if args.json_out or args.strip_fences:
            import re as _re

            out = _re.sub(r"^\s*```[a-zA-Z]*\s*", "", out.strip())
            out = _re.sub(r"\s*```\s*$", "", out).strip()
        if args.json_out:
            try:
                out = json.dumps(json.loads(out), ensure_ascii=False, indent=2)
            except json.JSONDecodeError as exc:
                print(f"[warn] 不是合法 JSON：{exc}", file=sys.stderr)
        if args.out:
            p = Path(args.out)
            # 护栏：模型有时会回一句「请把文件贴给我」而不是代码。
            # 这个回答曾经被原样写进 card_engine.gd，把 282 行的引擎覆盖成 92 个字的废话。
            suffix = p.suffix.lower()
            min_chars = 800 if suffix == ".gd" else (200 if suffix in (".py", ".json") else 80)
            looks_like_talk = out.startswith(("请", "我无法", "抱歉", "Sure", "I ", "以下"))
            if len(out) < min_chars or looks_like_talk:
                print(f"[拒写] {p} —— 输出只有 {len(out)} 字符"
                      f"（{suffix} 至少要 {min_chars}），疑似模型在说话而不是给内容。"
                      f"原文件未改动。", file=sys.stderr)
                print(f"       开头：{out[:120]}", file=sys.stderr)
                return 3
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(out, encoding="utf-8")
            print(f"已写入 {p}  ({len(out)} 字符)")
        else:
            print(out)
        return 0

    if args.cmd == "image":
        paths = image(_read(args.prompt_file), args.name, size=args.size, n=args.n)
        for p in paths:
            print(p)
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
