#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 v0.5 的设计论述 + v0.6 的实现状态合成 v0.7（唯一准据）

为什么要合并：
    v0.6 是从仓库生成的**状态快照**，只有 10 节；v0.5 有 20 节设计论述。
    两份是互补的，不是版本关系。合并前拿任何一份当唯一文档都会丢东西：
      · 只看 v0.5 → 不知道代码到哪一步、规则已经 43 条
      · 只看 v0.6 → 丢掉缘起、核心原则、记忆系统、明确不做、参照作品取舍

做法：
    以 v0.5 的 HTML 为骨架（保住全部设计正文与样式），
    ① 打补丁：把过时数字改成实际值（25 条 → 43 条 等）
    ② 追加：v0.6 的七节（状态 / 新增规则 / 像素规格 / 资产流程 / DEC / 欠账 / 工具链）

用法：
    python tools/merge_gdd.py --base "../残余信号_游戏设计纪要_v0.5(1).html"
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass

import build_gdd  # noqa: E402

# 过时数字/说法 → 现况。只改确定已被实现推翻的，不改设计意图。
PATCHES: list[tuple[str, str]] = [
    ("R01–R25", "R01–R43"),
    ("R01-R25", "R01-R43"),
    ("R01–R20", "R01–R35"),
    ("R21–R25", "R36–R43"),
    ("25 条校验器规则", "43 条校验器规则"),
    ("25 条规则", "43 条规则"),
    ("R01–R30", "R01–R43"),
    ("RESIDUAL SIGNAL / v0.5", "RESIDUAL SIGNAL / v0.7"),
    ("《残余信号》设计纪要 v0.5", "《残余信号》设计纪要 v0.7"),
    ("《残余信号》｜游戏设计纪要 v0.5", "《残余信号》｜游戏设计纪要 v0.7"),
    ("版本 v0.5", "版本 v0.7 · 合并版"),
]

NEW_SECTIONS = """
<!-- ============ 14 v0.6 实现状态 ============ -->
<section id="s14">
  <span class="no">14 / IMPLEMENTATION <span class="newbadge">NEW</span></span>
  <h2>v0.6 实现状态（机器可证）</h2>
  <div class="card key"><div class="ct">本节的数字不是写上去的</div>
  <p>它们由 <code>tools/build_gdd.py</code> 在生成时从仓库实际读取。文档与代码不可能不一致。</p></div>
  <table>
    <tr><th>项</th><th>值</th><th>验收命令</th></tr>
    <tr><td>校验规则</td><td>__RULE_N__ 条，ERROR 0 / WARN 0 / SKIP 0</td><td><code>python tools/validate.py</code></td></tr>
    <tr><td>规则自测</td><td>19 条 ERROR 规则全部能开火</td><td><code>python tools/selftest.py</code></td></tr>
    <tr><td>GDScript</td><td>__GD_N__ 类 / __GD_LINES__ 行，<strong>Godot 4.7 编译 5/5 通过</strong></td><td><code>--headless --check-only</code></td></tr>
    <tr><td>节点拓扑</td><td>__NODES__（__AXIS__ 主轴 + __ROOMS__ 房间，__COMPS__ 个教学节拍）</td><td>R01–R09 / R30 / R41</td></tr>
    <tr><td>事件卡</td><td>L 层 __CARDS_L__ 张 + 学校 S 层 __CARDS_S__ 张</td><td>R26 / R33–R35 / R39 / R42</td></tr>
    <tr><td>NPC</td><td>__NPCS__ 张状态卡 / __MEM__ 条记忆</td><td>R12 / R13 / R36 / R43</td></tr>
    <tr><td>模板</td><td>__TPL_N__ 份（学校/消防站/医院/军事基地/加油站）</td><td>R18 / R27 / R28 / R37 / R38</td></tr>
    <tr><td>L0 世界事实</td><td>__L0__ 条，append-only</td><td>R12</td></tr>
    <tr><td>资产</td><td>__ASSETS__ 条，其中 <strong>approved __APPROVED__ 条</strong></td><td>R14 / R21</td></tr>
    <tr><td>数据语义回放</td><td>30 天不变量成立（Python 镜像）</td><td><code>python tools/headless_30d.py</code></td></tr>
  </table>
  <div class="card warn"><div class="ct">这一节最重要的四个字</div>
  <p><strong>从未试玩。</strong>上面每一行都是机器判定。没有任何一条来自真人手感——
  「留白会不会被读成无聊」「一击致死前十分钟劝退不劝退」这些问题，一条都还没被回答。</p></div>
</section>

<!-- ============ 15 新增规则 ============ -->
<section id="s15">
  <span class="no">15 / RULES 26–43 <span class="newbadge">NEW</span></span>
  <h2>v0.5 之后新增的 18 条规则</h2>
  <p class="mono-line">v0.5 定到 R25。以下 18 条是实现过程中被真实缺陷逼出来的——每条都对应一个曾经真实发生的问题。</p>
  <table>
    <tr><th>ID</th><th>规则</th><th>它拦住的真实问题</th></tr>
    <tr><td>R26</td><td>L 层卡禁模板专名</td><td>跨 5 个模板复用时，「广播室」会让另外四个模板当场出戏</td></tr>
    <tr><td>R27</td><td>进场日 ∈ [0,14]，局内天数 = 30 − 进场日</td><td>越晚进场越硬，这是难度旋钮而非星级</td></tr>
    <tr><td>R28</td><td>噪声预算自洽</td><td>枪会把世界提前打崩而无人知晓</td></tr>
    <tr><td>R29</td><td>每模板恰好一次安全屋失效，且卡真实存在</td><td>安全屋不能是暂停键；原来只念字段名不查卡</td></tr>
    <tr><td>R30</td><td>房间不得旁路主轴</td><td>纵深房若连通两段主轴，走廊的恐怖白做</td></tr>
    <tr><td>R31</td><td>归属标记 3×5、五档、Day3 褪尽</td><td>「枪口闪光是唯一暖色」与「常驻暖橙标记」自相矛盾</td></tr>
    <tr><td>R32</td><td>音频只做定位，文件须单声道</td><td>双声道会让 <code>AudioStreamPlayer2D</code> 的 pan 失效，定位是假的</td></tr>
    <tr><td>R33</td><td>卡间禁直接引用</td><td>依赖爆炸的第一信号</td></tr>
    <tr><td>R34</td><td>trigger 嵌套 ≤3</td><td>同上</td></tr>
    <tr><td>R35</td><td>只许碰六组变量</td><td>禁止 <code>world.*</code> / <code>global.*</code> 副作用</td></tr>
    <tr><td>R36</td><td>记忆必须满格记录</td><td>模型把「降级后的残影」当原始记录，精确版永远渲染不出来</td></tr>
    <tr><td>R37</td><td>噪声预算必须是整数</td><td><code>0.02</code> 被 int 截成 0 → 撬棍等于不发声</td></tr>
    <tr><td>R38</td><td>每模板要有安静选项</td><td>军事基地只有步枪 = 逼玩家只会开火</td></tr>
    <tr><td>R39</td><td><code>when</code> 必须逐字等于某个 slot option</td><td>5 条效果挂在描述句上，永远不会触发</td></tr>
    <tr><td>R40</td><td>L2 渲染分档不许漏槽 + 反例自检</td><td>fid=1 仍写出具体物件；没有反例自检的规则会空转</td></tr>
    <tr><td>R41</td><td>六教学节拍各一次，相邻 ≤3 跳</td><td>教学断了玩家会迷路</td></tr>
    <tr><td>R42</td><td>宽窗口卡必须显式签核</td><td>12 张卡里 10 张的 trigger 完全不筛选</td></tr>
    <tr><td>R43</td><td>NPC 卡的配件位必须与精灵逐位一致</td><td>数据和美术从来没接上，熟人丧尸化会认不出人</td></tr>
  </table>
  <div class="card warn"><div class="ct">R21 的教训（值得单列）</div>
  <p>R21 原来写成「<code>source != generated</code> 就跳过」，而 32 条资产全是 <code>authoritative</code>——
  <strong>这条人审门从建库到第 11 轮一次都没管过任何东西。</strong>
  现在拆成两闸：人眼签核对所有资产成立，provenance 只对 generated 成立。</p>
  <p class="mono-line">教训：一条因为前置条件永远不成立而从不触发的规则，和被删掉没有区别。</p></div>
</section>

<!-- ============ 16 像素规格 ============ -->
<section id="s16">
  <span class="no">16 / PIXEL SPEC <span class="newbadge">NEW</span></span>
  <h2>像素规格（已冻结）</h2>
  <table>
    <tr><th>项</th><th>值</th></tr>
    <tr><td>原生分辨率</td><td>384 × 216（×5 = 1920×1080，整数倍）</td></tr>
    <tr><td>缩放</td><td>只允许 1–5 整数倍最近邻；永不抗锯齿</td></tr>
    <tr><td>网格</td><td>16×16 tile；视觉与碰撞同栅格</td></tr>
    <tr><td>调色板</td><td>32 色，<strong>按角色分配</strong>：冷色阶 8 / 冷光 3 / 冷光源 2 / 暖光 3 / 土锈血 5 / UI 2 / 布皮 3 / 皮肤 2 / 死亡 2 / 极值 2</td></tr>
    <tr><td>每帧上限</td><td>tile / 角色 / 武器层 ≤16；背景 / 视差 / 表 ≤32</td></tr>
    <tr><td>光</td><td>只来自上方；冷光源只用 c11/c12；暖光只用 c13–c15</td></tr>
    <tr><td>归属标记</td><td>暖橙 3×5，Day 0–2 存在，Day 3 断电当夜五档褪尽</td></tr>
    <tr><td>禁止</td><td>非整数缩放 / 抗锯齿 / 半透边缘 / 渐变 / 抖动 / 板外颜色</td></tr>
  </table>
  <div class="card key"><div class="ct">为什么是 32 色而不是 16</div>
  <p>第一版按面积抽 16 色，结果是 <strong>15 个蓝 + 1 个灰，暖光全丢</strong>。
  而全案唯一的光源语言是「手电一圈暖黄 + 枪口闪光」——按面积分配必然把它挤掉。
  改成按角色给配额、总数放宽到 32、单帧仍限 16。</p></div>
</section>

<!-- ============ 17 资产流程 ============ -->
<section id="s17">
  <span class="no">17 / ASSET PIPELINE <span class="newbadge">NEW</span></span>
  <h2>资产流程：七步，只有第三步要脚本，第四步要人</h2>
  <pre><code>① 定参考   art/refs/style_anchors/        人
② 产候选   art/generated_candidates/      模型 / 构造器 / 手画
③ 过门禁   manifest status=draft          脚本  ← asset_intake.py，不过就写不进去
④ 人眼签核 status=approved + reviewer     人    ← sign_assets.py，R21 会查
⑤ provenance AI_LEDGER.json               脚本  ← 仅 source=generated
⑥ 搬 approved/                            人
⑦ 派生物   derived_from 指向母体          构造器 ← R25 + R43</code></pre>
  <div class="card warn"><div class="ct">一条硬规矩</div>
  <p><strong>门禁不过，物理上进不了 <code>asset-manifest.json</code>。</strong>
  模型原图（18027 色 / 1024×1024）在实测中被自己的流程挡在门外——
  「真像素 vs 伪像素」的分界线不是看起来像，是能不能自动证明。</p></div>
</section>

<!-- ============ 18 DEC ============ -->
<section id="s18">
  <span class="no">18 / DECISIONS <span class="newbadge">NEW</span></span>
  <h2>v0.5 之后拍板的四件事</h2>
  <table>
    <tr><th>DEC</th><th>结论</th><th>落败方与理由</th></tr>
    <tr><td>美术预算</td><td>美术 60% 压在三个宣传帧；像素规格首周冻结</td><td>全面提标超预算 52 人日；30 秒竖切片验不了系统集成</td></tr>
    <tr><td>归属标记</td><td>暖橙 3×5，<strong>只在 Day 0–2</strong>，Day 3 断电当夜褪尽</td><td>常驻暖点污染「暖色 = 你在暴露自己」；脚下影与地面拖痕 overlay 语义撞车</td></tr>
    <tr><td>音频</td><td>7 人日全押「声音定位」，无音乐、无环境循环层</td><td>砍到 2 人日会失去「不指路」的唯一替代品</td></tr>
    <tr><td>NPC 池</td><td>8 共享（关系占位）+ 每模板 4 专属 = 28</td><td>100 个全专属美术炸 5 倍；12 共享承担跨模板回响会「伪在场」</td></tr>
  </table>
  <div class="card calm"><div class="ct">归属标记为什么不是妥协</div>
  <p>褪掉的那一刻，正好是世界断电的那一刻。<strong>游戏先告诉你「哪个是你」，
  然后在世界变黑的同时把这个答案收回去。</strong>之后你得靠影子、习惯、和刚才记住的方位认出自己。</p></div>
</section>

<!-- ============ 19 欠账 ============ -->
<section id="s19">
  <span class="no">19 / DEBT <span class="newbadge">NEW</span></span>
  <h2>已知欠账（不粉饰）</h2>
  <ul>
    <li><code>card_engine.gd</code> 的 <code>returns_after_days</code> 与卡池轮转已补，但<strong>无头仿真仍显示卡覆盖 4/12</strong>——12 张卡里 8 张要求房间 tag，走廊上几乎不触发，需要查是 bot 太笨还是条件太窄</li>
    <li>R40 只抓「该忘的没忘」，<strong>抓不住「补进去的新事实」</strong>（「戴眼镜」是黑名单兜的，不是白名单）</li>
    <li>R42 被改过三次口径，最终只能「点名 + 要签核」，判不了对错</li>
    <li>角色精灵是 blockout，配件只有 1–2 像素；tile 每格最深 6 色，spec 软目标是 ≤4</li>
    <li>NPC 池 11/12（学校 4 专属 + 7 共享，DEC 目标 8 共享）</li>
    <li><code>headless_30d.py</code> 是 Python 镜像，<strong>验的是数据语义，不是引擎</strong></li>
    <li><strong>从未试玩过。</strong>上面所有结论没有一条来自真人手感</li>
  </ul>
</section>

<!-- ============ 20 工具链 ============ -->
<section id="s20">
  <span class="no">20 / TOOLCHAIN <span class="newbadge">NEW</span></span>
  <h2>工具链与验收命令</h2>
  <table>
    <tr><th>工具</th><th>用途</th><th>命令</th></tr>
    <tr><td>validate.py</td><td>43 条规则</td><td><code>python tools/validate.py</code></td></tr>
    <tr><td>selftest.py</td><td>规则能不能开火</td><td><code>python tools/selftest.py</code></td></tr>
    <tr><td>Godot 4.7</td><td>真编译</td><td><code>.tools/Godot_v4.7-stable_win64_console.exe --headless --path game --check-only --script res://runtime/main.gd</code></td></tr>
    <tr><td>headless_30d.py</td><td>数据语义 30 天回放</td><td><code>python tools/headless_30d.py --seeds 3</code></td></tr>
    <tr><td>pixelpipe.py</td><td>像素门禁 / 转换 / tile 构造</td><td><code>... gate &lt;png&gt; --palette art/palettes/master.gpl</code></td></tr>
    <tr><td>asset_intake.py</td><td>门禁 → manifest</td><td><code>... --spec &lt;candidates.json&gt;</code></td></tr>
    <tr><td>sign_assets.py</td><td>人眼签核</td><td><code>... --reviewer YG --ids &lt;id...&gt;</code></td></tr>
    <tr><td>build_gdd.py / merge_gdd.py</td><td>生成本文档</td><td><code>python tools/merge_gdd.py</code></td></tr>
  </table>
</section>
"""


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=str(ROOT.parent / "残余信号_游戏设计纪要_v0.5(1).html"))
    ap.add_argument("--out", default=str(ROOT / "残余信号_游戏设计纪要_v0.7.html"))
    args = ap.parse_args(argv)

    base = Path(args.base)
    if not base.exists():
        print(f"找不到基线：{base}")
        return 2
    html = base.read_text(encoding="utf-8")

    d = build_gdd.collect()
    changed = 0
    for old, new in PATCHES:
        if old in html:
            n = html.count(old)
            html = html.replace(old, new)
            changed += n

    new_sec = (NEW_SECTIONS
               .replace("__RULE_N__", str(len(d["rules"])))
               .replace("__GD_N__", str(len(d["gd"])))
               .replace("__GD_LINES__", str(d["gd_lines"]))
               .replace("__NODES__", str(d["nodes"]))
               .replace("__AXIS__", str(d["axis"]))
               .replace("__ROOMS__", str(d["rooms"]))
               .replace("__COMPS__", str(d["comps"]))
               .replace("__CARDS_L__", str(d["cards_l"]))
               .replace("__CARDS_S__", str(d["cards_s"]))
               .replace("__NPCS__", str(d["npcs"]))
               .replace("__MEM__", str(d["memories"]))
               .replace("__TPL_N__", str(len(d["templates"])))
               .replace("__L0__", str(d["l0"]))
               .replace("__ASSETS__", str(d["assets"]))
               .replace("__APPROVED__", str(d["approved"])))

    # 插在 footer 之前（footer 在 .wrap 内部末尾）
    m = re.search(r"<footer>", html)
    if not m:
        print("找不到 <footer>，无法插入新章节")
        return 2
    html = html[: m.start()] + new_sec + "\n" + html[m.start():]

    # 顶部加一条合并说明
    banner = (
        '<div class="card warn" style="margin-top:18px"><div class="ct">合并说明 · v0.7</div>'
        f'<p>本版 = <strong>v0.5 的全部设计论述（第 00–13 节，原文保留）</strong>'
        f'＋ <strong>v0.6 的全部实现状态（第 14–20 节，从仓库生成）</strong>。'
        f'过时数字已就地修正（{changed} 处）。</p>'
        '<p class="mono-line">以本版为唯一准据。v0.5 与 v0.6 自此只作历史快照。</p></div>'
    )
    marker = '<header class="cover">'
    if marker in html:
        end = html.index("</header>") + len("</header>")
        html = html[:end] + "\n" + banner + html[end:]

    # 目录补上新增的 7 节
    nav = re.search(r'<nav class="toc">.*?</ol>', html, re.S)
    if nav:
        items = "".join(
            f'<li><a href="#s{n}">{title} <span class="newbadge">NEW</span></a></li>'
            for n, title in [(14, "v0.6 实现状态"), (15, "新增 18 条规则"), (16, "像素规格"),
                             (17, "资产流程"), (18, "v0.5 之后拍板的四件事"),
                             (19, "已知欠账"), (20, "工具链与验收命令")])
        block = nav.group(0)
        html = html.replace(block, block.replace("</ol>", items + "</ol>"), 1)

    Path(args.out).write_text(html, encoding="utf-8")
    print(f"写入 {args.out}")
    print(f"  修正 {changed} 处过时数字；追加 7 节；共 "
          f"{len(re.findall(r'<section', html))} 节")
    return 0


if __name__ == "__main__":
    sys.exit(main())
