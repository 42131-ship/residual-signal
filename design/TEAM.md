# TEAM · 常驻派发规矩

> 三个执行模型常驻。**每一轮都派活，不用人提醒。** 这份文件定义谁干什么、活怎么算完。

---

## 一、席位

| 席位 | 模型 | 职责 | 不干什么 |
|---|---|---|---|
| **dev** | gpt-6.2-sol | 代码：运行时、测试、工具脚本 | 不拍板设计取舍，不改时间轴与变量定义 |
| **dev2** | gpt-6.2-astra | 内容与结构：数据批次、schema 一致性、对比表 | 不写量产代码，不做美术取舍 |
| **aux** | claude-opus-5-5 | 评审：找漏洞、当反方、给附加条件 | 不做量产产出（prompt 基线 7.4k，只当裁判） |
| **执行侧** | 本地会话 | 验证、拍板、写 DEC、门禁执行 | 不代替人签核 |

---

## 二、派发规则（每轮）

1. **一人一件。** 同一轮里不许给同一个席位两件事。
2. **每件事必须带验收命令。** 没有验收命令的任务不许派——那说明还没想清楚。
3. **产出不合格不许进 manifest。** 门禁不过就退回，不手工放行。
4. **规则改动必须重跑 `tools/selftest.py`。** 踩过两次：改 R14、改 R20 之后 fixture 静默失效。
5. **brief 必须包含物料。** 要它改文件就把文件内容或完整契约贴进去——上一轮 dev 因为没拿到文件，
   回了句「请把文件贴给我」，那句话被写进了 `card_engine.gd`。
6. **派发后执行侧必须自己跑验收。** 模型说完成不算完成。
7. **连续两次交回不可用产物，执行侧直接接管。** 不耗第三轮——三轮里 dev 触发过两次
   （用了不存在的 `new()` 签名、遍历 Callable），第三次是我自己写的。**接管要记进汇报。**
8. **给模型的 card_id / 文件名 / 字段名，必须来自仓库实际值，不许凭印象编。**
   踩过：我给 dev2 的四个 S 卡 card_id 是编的，而模板里早写死了另外四个，白做一轮。
9. **新增 `class_name` 或新增 PNG 之后，必须先跑一次 `--import` 再编译。**
   不跑的话：`Identifier "Xxx" not declared`（类没注册）、
   `No loader found for resource`（图没导入）。两条都踩过，而且**报错信息完全不提 import**。

---

## 三、验收命令速查（派活时直接抄）

```powershell
$PY = "C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
$G  = ".tools\Godot_v4.7-stable_win64_console.exe"

# 规则
& $PY tools/validate.py
& $PY tools/selftest.py
# 编译（工程根 = 仓库根）
& $G --headless --path . --check-only --script res://game/runtime/main.gd
# 真引擎冒烟
& $G --headless --path . --script res://game/tests/smoke.gd
# 数据语义
& $PY tools/headless_30d.py --seeds 3
# 像素
& $PY tools/pixelpipe.py gate <png> --palette art/palettes/master.gpl --max-colors 16
# 入库
& $PY tools/asset_intake.py --spec <candidates.json>
```

---

## 四、当前轮次的派发（2026-11-23）

| 席位 | 任务 | 验收 |
|---|---|---|
| dev | 修 `smoke.gd` 的 L0 计数；新增 `game/tests/replay_30d.gd`（3 种子 × 30 天，5 条不变量） | `check-only` 通过 + `REPLAY_OK` |
| dev2 | NPC 池补到 12（重生成上次括号不平衡的 `npc_fan` + 1 个新共享） | `normalize_npcs` + R12/R13/R36 通过 |
| aux | 评审测试断言设计：哪几条不变量是「永远成立的假断言」 | 一份点名的清单 |

---

## 五、轮转原则

- **dev 优先**：他卡住的东西别人做不了（运行时是所有验证的地基）
- **dev2 填空**：dev 不需要等他的时候，去补数据密度
- **aux 只审**：每 2–3 轮审一次，不要每轮都审（他的价值在外部视角，不在于次数）

**遇到下面两种情况必须停下开会**（`tools/council.py --roles dev,aux,dev2`）：

- 验收命令写不出来
- 两条路都能过验收，但代价不同
