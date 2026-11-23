#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 starryapi 的 image 角色出图（OpenAI 兼容 /images/generations）。

key 只从 config/agents.json 的 roles.image 读，绝不回显、不写进日志。
出图后**不做任何美术处理**——量化与门禁交给 tools/quantize_map.py，
这样「谁出图」和「能不能进游戏」是两件事。

用法：
    python tools/imagegen.py --prompt "..." --out art/raw/menu_bg.png --size 1536x1024
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config" / "agents.json"


def load_image_role() -> tuple[str, str, str]:
    if not CONFIG.exists():
        raise SystemExit(f"missing local config: {CONFIG}")
    data = json.loads(CONFIG.read_text(encoding="utf-8"))
    base = str(data.get("base_url", "")).rstrip("/")
    role = (data.get("roles", {}) or {}).get("image", {})
    model = str(role.get("model", ""))
    key = str(role.get("key", ""))
    if not (base and model and key):
        raise SystemExit("image role is not configured (base_url / model / key)")
    return base, model, key


def generate(prompt: str, size: str, model: str, base: str, key: str) -> bytes:
    body = json.dumps({
        "model": model,
        "prompt": prompt,
        "n": 1,
        "size": size,
        "response_format": "b64_json",
    }).encode("utf-8")
    request = urllib.request.Request(
        base + "/images/generations",
        data=body,
        headers={
            "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
            # 网关前面有 Cloudflare：不带浏览器 UA 会被 1010 拦掉。
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:400]
        raise SystemExit(f"IMAGE_HTTP_{error.code}: {detail}") from None
    except Exception as error:  # noqa: BLE001
        raise SystemExit(f"IMAGE_ERROR: {type(error).__name__}: {error}") from None

    rows = payload.get("data") or []
    if not rows:
        raise SystemExit("IMAGE_EMPTY: response has no data")
    first = rows[0]
    if first.get("b64_json"):
        return base64.b64decode(first["b64_json"])
    if first.get("url"):
        with urllib.request.urlopen(first["url"], timeout=300) as response:
            return response.read()
    raise SystemExit("IMAGE_FORMAT: neither b64_json nor url in response")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="starryapi 出图")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--size", default="1536x1024")
    args = parser.parse_args(argv)

    base, model, key = load_image_role()
    raw = generate(args.prompt, args.size, model, base, key)
    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(raw)
    print(f"IMAGE_OK {target} bytes={len(raw)} model={model}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
