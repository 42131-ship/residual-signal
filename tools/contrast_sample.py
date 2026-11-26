#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从渲染出来的 PNG 里取色，算 HUD 文字对暗底的 WCAG 对比度（验收 C 的「取色器实测」）。

用法：
    python tools/contrast_sample.py design/previews/MOBILE_hud_contrast.png

做法：把图上像素按出现次数排序——最多的那个就是底色；
文字色取「与底色差得最远」的那一簇（同色像素至少 20 个，排除抗锯齿边缘）。
比值用 WCAG 2.1 的相对亮度公式，和浏览器/取色器一致。
"""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

from PIL import Image


def luminance(rgb: tuple[int, int, int]) -> float:
    def channel(value: int) -> float:
        v = value / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = rgb
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def ratio(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: contrast_sample.py <png>")
        return 2
    path = Path(argv[0])
    image = Image.open(path).convert("RGB")
    counts = Counter(image.getdata())

    for name, box in (("void", (0, 0, image.width, image.height // 2)),
                      ("wall", (0, image.height // 2, image.width, image.height))):
        region = image.crop(box)
        region_counts = Counter(region.getdata())
        bg = region_counts.most_common(1)[0][0]
        # 文字色：出现 >= 20 次、且与底色亮度差最大的颜色
        candidates = [(c, n) for c, n in region_counts.items() if n >= 20 and c != bg]
        if not candidates:
            print("%s: no text pixels" % name)
            continue
        fg = max(candidates, key=lambda item: abs(luminance(item[0]) - luminance(bg)))[0]
        print("%-5s bg=#%02X%02X%02X fg=#%02X%02X%02X  contrast=%.2f:1" % (
            name, bg[0], bg[1], bg[2], fg[0], fg[1], fg[2], ratio(fg, bg)))

    print("total colours in image:", len(counts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
