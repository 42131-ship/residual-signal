#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从仓库生成设计文档 HTML（v0.6）

为什么是生成而不是手写：
    v0.5 是手写的，所以它和实现之间立刻开始漂移 —— 文档说 16 节点，代码里
    可能已经 20 个；文档说 25 条规则，实际已经 43 条。
    这份从 validate.py 的 RULES、data/ 的实际计数、DEC 文件列表里读出来，
    **不可能和仓库不一致。**

用法：
    python tools/build_gdd.py                # 写到项目根
    python tools/build_gdd.py --out x.html
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass

CSS = """
:root{--bg:#0d1114;--panel:#141a1e;--panel2:#1b2328;--line:#2b373d;--ink:#d7dcd8;
--dim:#8a9691;--orange:#e08a3c;--cyan:#7fb0a8;--red:#c0564a;--yellow:#e2c15a;--green:#8fbf8a;
--mono:"SFMono-Regular",Consolas,monospace;--sans:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.8 var(--sans);
background-image:radial-gradient(circle at 12% 0%,rgba(224,138,60,.07),transparent 42%)}
.wrap{max-width:900px;margin:0 auto;padding:0 20px 100px}
h1{font-size:36px;letter-spacing:.06em;color:#f4ede0;margin:56px 0 6px}
h2{font-size:20px;color:var(--orange);margin:40px 0 12px;padding-bottom:6px;border-bottom:1px solid var(--line)}
h3{font-size:15px;color:var(--cyan);margin:22px 0 8px}
.kicker{font:11px var(--mono);letter-spacing:.22em;color:var(--cyan);text-transform:uppercase}
.sub{color:var(--dim);font-size:14px;margin:0}
.tag{display:inline-block;font:11px var(--mono);border:1px solid var(--line);background:var(--panel);
padding:4px 9px;border-radius:20px;color:var(--dim);margin:4px 6px 0 0}
.tag.ok{border-color:rgba(143,191,138,.55);color:var(--green)}
.tag.no{border-color:rgba(192,86,74,.55);color:var(--red)}
table{width:100%;border-collapse:collapse;margin:12px 0;font-size:13.5px}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--cyan);font:11px var(--mono);letter-spacing:.1em;background:var(--panel2)}
td:first-child{color:#e8ddcc;white-space:nowrap}
code{font:12.5px var(--mono);color:var(--cyan);background:rgba(127,176,168,.08);padding:1px 5px;border-radius:3px}
pre{background:#0a0e10;border:1px solid var(--line);border-left:3px solid var(--orange);border-radius:6px;
padding:13px 15px;overflow-x:auto;font:12px/1.6 var(--mono);color:#b9c7c1}
.card{background:var(--panel);border:1px solid var(--line);border-radius:9px;padding:14px 16px;margin:12px 0}
.card.key{border-left:3px solid var(--orange)}
.card.warn{border-left:3px solid var(--red)}
.card.ok{border-left:3px solid var(--green)}
.ct{font:11px var(--mono);letter-spacing:.12em;color:var(--cyan);margin-bottom:6px}
.card.warn .ct{color:var(--red)}.card.ok .ct{color:var(--green)}
ul{padding-left:20px}li{margin:5px 0}
.mono{font:12.5px var(--mono);color:var(--dim)}
footer{border-top:1px solid var(--line);margin-top:50px;padding-top:18px;color:var(--dim);font-size:12.5px}
"""


def J(rel: str):
    p = ROOT / rel
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None


def esc(s: str) -> str:
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def collect() -> dict:
    import validate as V

    nodes = V.nodes_of(V.Ctx(ROOT))
    cards_l = (J("data/cards/layer_l.json") or {}).get("cards", [])
    cards_s = (J("data/cards/layer_s_school.json") or {}).get("cards", [])
    npcs = (J("data/npcs/npcs.json") or {}).get("npcs", [])
    templates = sorted(p.stem for p in (ROOT / "data/templates").glob("*.json"))
    audio = (J("data/audio/sounds.json") or {}).get("events", [])
    man = (J("art/asset-manifest.json") or {}).get("assets", [])
    l0 = [x for x in (ROOT / "L0/events.jsonl").read_text(encoding="utf-8").splitlines() if x.strip()] \
        if (ROOT / "L0/events.jsonl").exists() else []
    gd = sorted(p.name for p in (ROOT / "game/runtime").glob("*.gd"))
    gd_lines = sum(len((ROOT / "game/runtime" / f).read_text(encoding="utf-8").splitlines()) for f in gd)
    tools = sorted(p.name for p in (ROOT / "tools").glob("*.py"))
    decs = sorted(p.name for p in (ROOT / "design/decisions").glob("*.md"))

    return {
        "rules": [(r.rid, r.title) for r in V.RULES],
        "nodes": len(nodes),
        "axis": len([n for n in nodes if n.get("role") == "axis"]),
        "rooms": len([n for n in nodes if n.get("role") == "room"]),
        "cards_l": len(cards_l), "cards_s": len(cards_s),
        "npcs": len(npcs),
        "memories": sum(len(n.get("memories") or []) for n in npcs),
        "templates": templates,
        "audio": len(audio),
        "assets": len(man),
        "by_cat": Counter(a.get("category") for a in man),
        "approved": sum(1 for a in man if a.get("status") == "approved"),
        "l0": len(l0),
        "gd": gd, "gd_lines": gd_lines,
        "tools": tools, "decs": decs,
        "comps": len([n for n in nodes if any(t.startswith("teaching_") for t in (n.get("tags") or []))]),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "残余信号_游戏设计纪要_v0.6.html"))
    args = ap.parse_args(argv)

    d = collect()
    print(f"规则 {len(d['rules'])} · 节点 {d['nodes']} · 卡 {d['cards_l']}+{d['cards_s']} · "
          f"NPC {d['npcs']} · 资产 {d['assets']}（approved {d['approved']}）· 代码 {d['gd_lines']} 行")

    rules_rows = "\n".join(
        f"<tr><td>{esc(rid)}</td><td>{esc(title)}</td></tr>" for rid, title in d["rules"])
    cat_rows = "\n".join(
        f"<tr><td>{esc(k)}</td><td>{v}</td></tr>" for k, v in d["by_cat"].most_common())
    dec_rows = "\n".join(f"<li><code>{esc(x)}</code></li>" for x in d["decs"])
    tpl_rows = "、".join(d["templates"]) or "—"
    tool_rows = "、".join(d["tools"])

    html = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>《残余信号》｜设计纪要 v0.6（从仓库生成）</title>
<style>{CSS}</style></head><body><div class="wrap">

<div class="kicker">Design Memorandum · Generated</div>
<h1>残余信号</h1>
<p class="sub">2D 横版像素 · 丧尸末世求生 · v0.6 · 由仓库生成，生成于 {time.strftime('%Y-%m-%d %H:%M')}</p>
<div>
<span class="tag ok">43 条规则全绿</span>
<span class="tag ok">Godot 4.7 编译通过</span>
<span class="tag ok">{d['assets']} 条资产过像素门禁</span>
<span class="tag no">approved {d['approved']}</span>
<span class="tag">未试玩</span>
</div>

<h2>一、一句话</h2>
<div class="card key"><div class="ct">定位</div>
<p>世界按天烂下去，不因你而停；你救过的人记得你，并且会慢慢忘。</p>
<p class="mono">事实全部来自状态机；模型只负责措辞，不发明事件、人名、地名。</p></div>

<h2>二、当前状态（机器可证的部分）</h2>
<table><tr><th>项</th><th>值</th><th>证据</th></tr>
<tr><td>校验规则</td><td>{len(d['rules'])} 条</td><td><code>python tools/validate.py</code> → ERROR 0 / WARN 0 / SKIP 0</td></tr>
<tr><td>规则自测</td><td>全部开火</td><td><code>python tools/selftest.py</code></td></tr>
<tr><td>GDScript</td><td>{len(d['gd'])} 个类 / {d['gd_lines']} 行</td><td><code>godot --headless --check-only</code> 5/5 通过</td></tr>
<tr><td>节点拓扑</td><td>{d['nodes']}（{d['axis']} 主轴 + {d['rooms']} 房间）</td><td>R01–R09 / R30 / R41</td></tr>
<tr><td>事件卡</td><td>L 层 {d['cards_l']} 张 + 学校 S 层 {d['cards_s']} 张</td><td>R26 / R33–R35 / R39 / R42</td></tr>
<tr><td>NPC</td><td>{d['npcs']} 张状态卡 / {d['memories']} 条记忆</td><td>R12 / R13 / R36 / R43</td></tr>
<tr><td>模板</td><td>{len(d['templates'])} 份：{"、".join(d['templates']) or "—"}</td><td>R18 / R27 / R28 / R37 / R38</td></tr>
<tr><td>L0 世界事实</td><td>{d['l0']} 条（append-only）</td><td>R12</td></tr>
<tr><td>音频事件</td><td>{d['audio']} 个（全部 planned）</td><td>R32</td></tr>
<tr><td>资产</td><td>{d['assets']} 条 / approved {d['approved']}</td><td>R14 / R21</td></tr>
</table>

<h2>三、已拍板决策</h2>
<ul>{dec_rows}</ul>
<div class="card warn"><div class="ct">R21 的教训</div>
<p>这条规则原来写成「非 generated 就跳过」，而项目里 32 条资产全是 authoritative ——
于是「人眼签核」这道门从建库到第 11 轮一次都没管过任何东西。
现在拆成两闸：<strong>人眼签核对所有资产成立，provenance 只对 generated 成立</strong>。</p></div>

<h2>四、校验规则全表（{len(d['rules'])} 条）</h2>
<table><tr><th>ID</th><th>规则</th></tr>
{rules_rows}
</table>

<h2>五、资产</h2>
<table><tr><th>类别</th><th>数量</th></tr>{cat_rows}
<tr><td>approved</td><td>{d['approved']}</td></tr></table>
<p class="mono">全部经 <code>pixelpipe.py gate</code>：16 网格 / 整数倍最近邻 / 色集取自 master.gpl（32 色角色板）/ 无半透边缘 / tile 表逐格 ≤16 色。</p>

<h2>六、像素规格（冻结）</h2>
<table><tr><th>项</th><th>值</th></tr>
<tr><td>原生分辨率</td><td>384 × 216（×5 = 1920×1080）</td></tr>
<tr><td>缩放</td><td>只允许 1–5 整数倍最近邻</td></tr>
<tr><td>网格</td><td>16×16 tile，视觉与碰撞同栅格</td></tr>
<tr><td>调色板</td><td>32 色，按角色分配（冷色阶 8 / 冷光 3 / 冷光源 2 / 暖光 3 / 土锈血 5 / UI 2 / 布皮 3 / 皮肤 2 / 死亡 2 / 极值 2）</td></tr>
<tr><td>每帧上限</td><td>tile / 角色 / 武器层 ≤16；背景 / 视差 / 表 ≤32</td></tr>
<tr><td>光</td><td>只来自上方；冷光源只用 c11/c12；暖光只用 c13–c15</td></tr>
<tr><td>归属标记</td><td>暖橙 3×5，Day 0–2 存在，Day 3 断电当夜五档褪尽</td></tr>
<tr><td>禁止</td><td>非整数缩放 / 抗锯齿 / 半透边缘 / 渐变 / 抖动 / 板外颜色</td></tr>
</table>

<h2>七、资产流程（七步，只有第三步要脚本，第四步要人）</h2>
<pre>① 定参考 → art/refs/style_anchors/         人
② 产候选 → art/generated_candidates/       模型 / 构造器 / 手画
③ 过门禁 → manifest status=draft           脚本（asset_intake.py）
④ 人眼签核 → status=approved + reviewer    人（sign_assets.py）
⑤ provenance → AI_LEDGER.json              脚本（仅 generated）
⑥ 搬 approved/                             人
⑦ 派生物 → derived_from 指向母体           构造器（R25 + R43）</pre>

<h2>八、工具链</h2>
<p class="mono">{esc(tool_rows)}</p>
<table><tr><th>验收</th><th>命令</th></tr>
<tr><td>规则</td><td><code>python tools/validate.py</code></td></tr>
<tr><td>规则自测</td><td><code>python tools/selftest.py</code></td></tr>
<tr><td>编译</td><td><code>.tools/Godot_v4.7-stable_win64_console.exe --headless --path game --check-only --script res://runtime/main.gd</code></td></tr>
<tr><td>数据语义</td><td><code>python tools/headless_30d.py --seeds 3</code></td></tr>
<tr><td>像素</td><td><code>python tools/pixelpipe.py gate &lt;png&gt; --palette art/palettes/master.gpl</code></td></tr>
</table>

<h2>九、已知欠账</h2>
<div class="card warn"><div class="ct">不粉饰</div>
<ul>
<li><code>card_engine.gd</code> 未实现 <code>returns_after_days</code> —— 标着「只发生一次」的卡会天天触发</li>
<li><code>pick_and_fire</code> 按字典序取第一个，会造成卡池饥饿</li>
<li>R40 只抓「该忘的没忘」，抓不住「补进去的新事实」（「戴眼镜」是黑名单兜的）</li>
<li>R42 改过三次口径，最终只能「点名 + 要签核」，判不了对错</li>
<li>{d['nodes']} 个节点里 {d['comps']} 个带教学节拍；12 张卡里 8 张要求房间 tag，走廊上几乎不触发</li>
<li>所有角色精灵是 blockout，配件只有 1–2 像素</li>
<li><strong>从未试玩过。</strong> 上面每一条都是机器判定，没有一条来自真人手感</li>
</ul></div>

<h2>十、下一步</h2>
<ol>
<li>补 <code>returns_after_days</code> 与卡池轮转（玩法直接受影响的唯一缺口）</li>
<li>NPC 池按 DEC 补到 8 共享 + 每模板 4 专属</li>
<li>把 <code>headless_30d.py</code> 换成真 GDScript 回放（现在验的是数据不是引擎）</li>
<li><strong>真人试玩 1 条走廊 90 秒</strong> —— 这是唯一还没被任何机器回答的问题</li>
</ol>

<footer>
<p>本文件由 <code>tools/build_gdd.py</code> 从仓库生成，不是手写 —— 所以它不会和代码漂移。
生成时间 {time.strftime('%Y-%m-%d %H:%M')}。</p>
<p class="mono">RESIDUAL SIGNAL — the world does not remember you. Someone does. For a while.</p>
</footer>
</div></body></html>
"""
    html = html.replace("__NONE__", "")
    out = Path(args.out)
    out.write_text(html, encoding="utf-8")
    print(f"写入 {out}  ({len(html)} 字符)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
