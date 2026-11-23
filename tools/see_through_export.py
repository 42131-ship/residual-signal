#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把角色导出成 see-through 语义层结构（分层 PNG + ORA + JSON），并验证可无损合回。

为什么这么接：
    see-through（SIGGRAPH 2026，Apache-2.0）本身是 PyTorch 研究管线（LayerDiff3D + Marigold +
    SAM + LaMa，8–16GB 显存），本机 GTX 1060 跑不动它的模型。但它真正被生态消费的是**输出契约**：
    「23 个语义层名 + 每层一张带偏移的透明图 + 绘制顺序」，Stretchy Studio / Anime2.5DRig 都按它认层。
    所以这里做的是**契约层**的接入：我们的角色按同一套层名拆层导出，
    将来用真模型跑出 PSD，同一个层名结构可以直接替换进来。

诚实说明：我们的角色是 32×32 blockout，这里用**几何分带**映射到官方层名（不是语义分割）。
分带是行的严格划分，所以「所有层按顺序叠回去 == 原图」是像素级成立的，门禁就查这一条。

产出：
    art/generated_candidates/characters/layers/<id>/<NN>_<层名>.png   每层（带 bbox 裁切）
    art/generated_candidates/characters/layers/<id>.json              层表（名字/顺序/bbox/枢轴）
    art/generated_candidates/characters/layers/<id>.ora               OpenRaster（Krita/GIMP 可开）
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CHARS = ROOT / "art" / "generated_candidates" / "characters"
OUT = CHARS / "layers"
TAGS = ROOT / "data" / "see_through" / "bodytags_v3.json"

# 从头顶到脚底的行带 → 官方层名（自下而上绘制，所以列表是「从下到上」）。
BANDS = [
    ("footwear", 0.88, 1.00),
    ("legwear", 0.68, 0.88),
    ("bottomwear", 0.50, 0.68),
    ("topwear", 0.34, 0.50),
    ("neck", 0.30, 0.34),
    ("face", 0.18, 0.30),
    ("front hair", 0.00, 0.18),
]


def layer_bands(image: Image.Image) -> list[tuple[str, int, int]]:
    """把可见高度切成互不重叠的行带，返回 [(层名, top, bottom)]（自下而上）。"""
    bbox = image.getbbox()
    if not bbox:
        raise SystemExit("empty sprite")
    top, bottom = bbox[1], bbox[3]
    height = max(1, bottom - top)
    out: list[tuple[str, int, int]] = []
    for name, start, end in BANDS:
        band_top = top + int(round(height * start))
        band_bottom = top + int(round(height * end))
        band_top = max(top, min(band_top, bottom))
        band_bottom = max(band_top, min(band_bottom, bottom))
        if band_bottom > band_top:
            out.append((name, band_top, band_bottom))
    if not out:
        raise SystemExit("no bands produced")
    return out


def crop_layer(image: Image.Image, top: int, bottom: int) -> tuple[Image.Image, list[int]]:
    band = image.crop((0, top, image.width, bottom))
    bbox = band.getbbox()
    if not bbox:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0)), [0, 0, 0, 0]
    cropped = band.crop(bbox)
    return cropped, [bbox[0], top + bbox[1], bbox[2] - bbox[0], bbox[3] - bbox[1]]


def write_ora(path: Path, image: Image.Image, layers: list[tuple[str, Image.Image, list[int]]]) -> None:
    """OpenRaster：一个 zip，stack.xml 描述层，data/ 放 PNG。Krita/GIMP 直接打开。"""
    width, height = image.size
    xml = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<image version="0.0.3" w="{width}" h="{height}">',
        "  <stack>",
    ]
    for index, (name, layer, rect) in enumerate(layers):
        xml.append(
            f'    <layer name="{name}" src="data/layer{index:02d}.png" '
            f'x="{rect[0]}" y="{rect[1]}" visibility="visible"/>'
        )
    xml.append("  </stack>")
    xml.append("</image>")
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr("mimetype", "image/openraster", compress_type=zipfile.ZIP_STORED)
        bundle.writestr("stack.xml", "\n".join(xml))
        for index, (_name, layer, _rect) in enumerate(layers):
            buffer = Path(path).with_suffix(f".layer{index:02d}.tmp.png")
            layer.save(buffer)
            bundle.write(buffer, f"data/layer{index:02d}.png")
            buffer.unlink()
        merged = Path(path).with_suffix(".merged.tmp.png")
        image.save(merged)
        bundle.write(merged, "mergedimage.png")
        merged.unlink()


def main() -> int:
    if not TAGS.exists():
        raise SystemExit(f"missing layer names, run tools/see_through_sync.py first: {TAGS}")
    official = json.loads(TAGS.read_text(encoding="utf-8"))
    official_names = list(official.keys())
    anims = json.loads((CHARS / "anim" / "anims.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)

    written = 0
    for entry in anims["characters"]:
        char_id = entry["id"]
        source = ROOT / entry["source"]
        image = Image.open(source).convert("RGBA")
        bands = layer_bands(image)
        ordered = list(reversed(bands))  # 自下而上
        layers: list[tuple[str, Image.Image, list[int]]] = []
        index_rows = []
        for order, (name, top, bottom) in enumerate(ordered):
            if name not in official_names:
                raise SystemExit(f"layer {name} is not in the official taxonomy")
            layer, rect = crop_layer(image, top, bottom)
            folder = OUT / char_id
            folder.mkdir(parents=True, exist_ok=True)
            filename = f"{order:02d}_{name.replace(' ', '_')}.png"
            layer.save(folder / filename)
            layers.append((name, layer, rect))
            index_rows.append({
                "order": order,
                "layer": name,
                "file": f"{char_id}/{filename}",
                "rect": rect,
                "pivot": [rect[0] + rect[2] // 2, rect[1] + rect[3]],
            })
            written += 1

        # 无损校验：按顺序把层贴回去，必须与原图逐像素一致。
        rebuilt = Image.new("RGBA", image.size, (0, 0, 0, 0))
        for _name, layer, rect in layers:
            rebuilt.alpha_composite(layer, (rect[0], rect[1]))
        if rebuilt.tobytes() != image.tobytes():
            raise SystemExit(f"{char_id}: layers do not reassemble into the source sprite")

        write_ora(OUT / f"{char_id}.ora", image, layers)
        (OUT / f"{char_id}.json").write_text(json.dumps({
            "schema": "see-through-layers.v1",
            "character": char_id,
            "source": entry["source"],
            "size": list(image.size),
            "anchor": entry.get("anchor", [image.width // 2, image.height]),
            "decomposition": "band",  # 几何分带，不是 ML 语义分割
            "taxonomy": "shitagaki-lab/see-through bodytags_v3",
            "layers": index_rows,
        }, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"characters={len(anims['characters'])} layers_written={written} -> {OUT.relative_to(ROOT)}")
    print("verify=lossless (every sprite reassembles pixel-perfect)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
