#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""对齐会：三方各述立场 → 交叉质询 → 主席收敛 → 落 DEC 决策记录

为什么要有这个：D1 门禁要求「必须输出对比 + 写明落败理由」，而这条约束
对人、对 AI 都成立。council.py 就是这条约束的执行器 —— 没有 DEC 文档，
就等于没拍板。

用法：
    python tools/council.py --topic design/topics/T01.md --slug art-budget
    python tools/council.py --topic ... --cross        # 加一轮交叉质询（更贵，更准）

议题文件格式（markdown，四段）：
    ## 议题
    ## 背景（已知事实 / 约束）
    ## 候选（A / B / C，各一句）
    ## 不可让步（红线）
"""

from __future__ import annotations

import argparse
import sys
import textwrap
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agents  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DEC_DIR = ROOT / "design" / "decisions"

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass

SHARED = """你在参与《残余信号》项目的对齐会。这是一款 2D 横版像素丧尸末世求生游戏：
- 世界按 Day 0–30 烂下去，不因玩家而停；调度器不读玩家状态
- 事实只由状态机产生，AI 只负责措辞
- 双模式：剧情（30 天收束、可存档）/ 无尽（一击致死、无存档）
- 5 个角色模板 × 随机进场日；入口随机，出口必然
- 不指路、无万能互动键、一击致死
- 已验证：校验器 R01–R30 可跑；数据层 1/23 就位；程序 86 人日、美术 48、文本 19、音频 7、试玩 8

规矩：
1. 只谈取舍，不谈愿景。每条主张必须能回答「不这么做会怎样」。
2. 明确说出你放弃什么 —— 没有代价的方案不是方案。
3. 300 字以内。不要复述议题。"""

ROLE_BRIEF = {
    "dev": "你是**主力开发**（gpt-6.2-sol）。你从「能不能在一周内跑起来」看问题：实现成本、依赖、返工概率。",
    "aux": "你是**辅助评审**（opus）。你从「哪条路最不容易在三个月后返工」看问题，并负责当反方。",
    "image": "你是**资产侧**（图像模型）。你从「美术/资产预算与生产管线」看问题：产多少、谁签收、会不会返工。",
    "dev2": "你是**第三席**（系统与内容结构）。你只回答一个问题：这套结构在第 N 个内容单元会不会长歪。只谈结构与复用，不谈手艺与审美。",
}


def ask(role: str, topic: str, extra: str = "") -> str:
    brief = ROLE_BRIEF.get(role, f"你是**{role}**，从你被分配的职责视角回答。")
    prompt = f"{SHARED}\n\n{brief}\n\n---\n\n{topic}\n{extra}"
    try:
        return agents.chat(role, prompt, max_tokens=900, temperature=0.4).strip()
    except SystemExit as exc:
        return f"（{role} 调用失败：{exc}）"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="三方对齐会")
    ap.add_argument("--topic", required=True)
    ap.add_argument("--slug", default="decision")
    ap.add_argument("--cross", action="store_true", help="加一轮交叉质询")
    ap.add_argument("--roles", default="dev,aux,image", help="参会角色，逗号分隔（开会时可排除 image）")
    ap.add_argument("--chair", default="aux", help="主席角色")
    args = ap.parse_args(argv)
    roles = [r.strip() for r in args.roles.split(",") if r.strip()]

    tp = Path(args.topic)
    if not tp.exists():
        raise SystemExit(f"议题不存在：{tp}")
    topic = tp.read_text(encoding="utf-8")

    t0 = time.time()
    print("① 各述立场（并行）…")
    with ThreadPoolExecutor(max_workers=len(roles)) as pool:
        futures = {r: pool.submit(ask, r, topic) for r in roles}
        views = {r: f.result() for r, f in futures.items()}
    for r, v in views.items():
        print(f"   [{r}] {len(v)} 字")

    cross_block = ""
    if args.cross:
        print("② 交叉质询 …")
        table = "\n\n".join(f"### {r}\n{v}" for r, v in views.items())
        with ThreadPoolExecutor(max_workers=len(roles)) as pool:
            futures = {
                r: pool.submit(
                    ask,
                    r,
                    topic,
                    f"\n\n---\n以下是另外几方的立场：\n{table}\n\n"
                    "只回答两件事：① 你最不同意谁、为什么（一句）② 你愿意让掉什么（一句）。",
                )
                for r in roles
            }
            cross = {r: f.result() for r, f in futures.items()}
        cross_block = "\n\n".join(f"**{r}**：{v}" for r, v in cross.items())

    print("③ 主席收敛（aux）…")
    chair_prompt = f"""你是本次对齐会的主席。下面是三方立场{f'与交叉质询' if args.cross else ''}。

议题：
{topic}

三方立场：
{chr(10).join(f'### {r}{chr(10)}{v}' for r, v in views.items())}
{f'{chr(10)}交叉质询：{chr(10)}{cross_block}' if cross_block else ''}

输出一份 DEC 决策记录，严格四段，不要多余的话：

## 结论
一句话。必须指名选哪条路（或哪条路先做）。

## 落败方与理由
逐条：哪条路落败、输在哪个维度。**没有落败理由视为未拍板。**

## 未决项
只列真的没定的，每条给默认值。

## 执行动作
3–5 条，每条以动词开头，带可验收的产物名。"""

    try:
        decision = agents.chat(args.chair, chair_prompt, max_tokens=1600, temperature=0.2).strip()
    except SystemExit as exc:
        # 主席掉线不能吃掉整场会：换一席重试，再不行就落一份「未裁定」的记录
        fallback = next((r for r in roles if r != args.chair), None)
        print(f"   主席 {args.chair} 失败，改用 {fallback} …")
        try:
            decision = agents.chat(fallback, chair_prompt, max_tokens=1600, temperature=0.2).strip()
            decision = f"（主席 {args.chair} 调用失败，由 {fallback} 代裁）\n\n" + decision
        except SystemExit as exc2:
            decision = (f"## 未裁定\n\n主席与代理主席均调用失败：\n- {exc}\n- {exc2}\n\n"
                        "各方立场与交叉质询已完整保存，请人工收敛后再落 DEC。")

    DEC_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d")
    out = DEC_DIR / f"DEC-{stamp}-{args.slug}.md"
    body = textwrap.dedent(
        f"""# DEC-{stamp}-{args.slug}

> 对齐会 · {time.strftime('%Y-%m-%d %H:%M')} · 议题源：`{tp.as_posix()}`
> {len(views)} 方参会{f' + 交叉质询' if args.cross else ''} · 耗时 {time.time() - t0:.0f}s

## 议题

{topic.strip()}

## 各方立场

"""
    )
    for r in roles:
        body += f"### {r}\n\n{views[r]}\n\n"
    if cross_block:
        body += f"## 交叉质询\n\n{cross_block}\n\n"
    body += f"## 主席裁定\n\n{decision}\n"

    out.write_text(body, encoding="utf-8")
    print(f"\n已落 {out}\n")
    print(decision)
    return 0


if __name__ == "__main__":
    sys.exit(main())
