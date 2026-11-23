# 资产生产流程 v1.0

> 一句话：**门禁不过，物理上进不了 `asset-manifest.json`。**
> 执行器是 `tools/asset_intake.py`，不是这份文档。

---

## 七步，只有第三步要人

| # | 步骤 | 谁做 | 产物 | 拒收条件 |
|---|---|---|---|---|
| 1 | **定参考** | 人 | `art/refs/style_anchors/`（≤32 色、16 网格） | 门禁 R14 |
| 2 | **产候选** | 模型 / 构造器 / 手画 | `art/generated_candidates/<category>/` | 无（这里是草稿区） |
| 3 | **过门禁** | 脚本 | manifest 里 `status=draft` + `pixel_gate=pass` | R14a–R14f 任一不过 |
| 4 | **人眼签核** | 人 | `status=approved` + `reviewer` + `approved_at` | R21（无人签 = 进不了 approved） |
| 5 | **登记 provenance** | 脚本 | `AI_LEDGER.json` | R20（缺 model/provider/input_assets/reviewer/date） |
| 6 | **搬进 approved** | 人 | `art/approved/` | 目录混放即失败（§8c 红线） |
| 7 | **派生物** | 构造器 | `zombie_variant.derived_from` 指向母体 | R25（配件位不一致） |

**第 3 步之后所有环节都可以被 CI 判定。第 4 步永远不能。**

---

## 三条命令

```powershell
$PY = "C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"

# ① 模型参考 → 真像素（四步管线：裁切 / BOX降采样 / 中值去噪 / 吸附调色板）
& $PY tools/pixelpipe.py convert <源.png> --palette art/palettes/master.gpl `
    --out art/refs/style_anchors/SA-xx.png --ratio 8:5 --scale 8 --denoise 3

# ② 门禁单查
& $PY tools/pixelpipe.py gate <文件.png> --palette art/palettes/master.gpl --max-colors 16

# ③ 入库（不过就不写 manifest）
& $PY tools/asset_intake.py --files a.png b.png --category character `
    --id-prefix chr_school --source authoritative
```

---

## 「一致」怎么保证：三层，逐层收紧

| 层 | 手段 | 违反后 |
|---|---|---|
| 取色 | 只允许从 `master.gpl` **按角色名**取色（`c04_floor`），不许按亮度猜 | R14c |
| 构造 | 同类资产共用**一个参数表**：人物共用 `BODY`，配件共用 `ACCESSORY`；改表就是改全体 | 人眼（R21） |
| 变换 | 派生只允许改三个轴：肤色 / 眼 / 姿态。配件位原样不动 | R25 |

人物是范例：`tools/char_build.py` 里
- `BODY` 只有学生 / 老师两套身高体型参数
- `ACCESSORY` 只有 `[badge, backpack, strap]` 与 `[glasses, lanyard, papers]` 两组
- 感染只做 `skin → pallid`、`eye → dead_black`、`leg → 弯`、`badge 下一点 dried`
- 四个角色 → 同一张表 → **不可能不一致**

---

## 当前台账（2026-11-22）

| 资产 | 状态 | 色数 | 门禁 |
|---|---|---|---|
| `chr_school_00..03`（学生/老师/学生丧尸/老师丧尸 32×32） | draft | 9–10 | PASS |
| `tl_corridor_01`（8 个 16×16 tile 横表） | draft | 15 | PASS |
| `SA-01_corridor_d3_128x80`（风格锚点） | draft | 20 | PASS |
| `CH-0*_raw`（三张模型原图） | **拒收** | 18027 | FAIL |

> 拒收的三张不是废料——它们是设计参考。参考进 `refs/`，不进 `approved/`。

---

## 下一步缺口

- `approved/` 目录还是空的：需要人签第一条（R21 第一次触发）
- `AI_LEDGER.json` 还没有：第一张 `source=generated` 的正式资产入库时必须建（R20）
- `THIRD_PARTY_LICENSES.json` 还没有：字体定稿了（Vonwaon + Fusion），但授权台账没落（R23）
