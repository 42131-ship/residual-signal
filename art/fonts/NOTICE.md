# 字体与第三方声明（NOTICE）

本文件由 `THIRD_PARTY_LICENSES.json` 引用，游戏内 credits 由该 JSON 生成。

## 凤凰点阵体 Vonwaon

- 用途：正文 12px
- 授权：CC0 1.0 Universal（公有领域奉献）
- 无保留字体名，无声明负担
- 来源以上游仓库 LICENSE 文本为准

## 缝合像素 Fusion

- 用途：标题 / 层级 8 / 10 / 12px
- 授权：SIL Open Font License 1.1
- **保留字体名（Reserved Font Name）**：修改版不得使用原名
- 分发时必须随包保留本 OFL 文本与版权声明

## PF-02 检查文本点阵

- 构建输入：本目录的 `NotoSansSC-VF.ttf`（Noto Sans SC，SIL OFL 1.1）。字体内置版权与授权和 [上游声明](https://github.com/google/fonts/blob/main/ofl/notosanssc/OFL.txt) 一致；完整原文见 [NOTOSANS-SC-OFL.txt](NOTOSANS-SC-OFL.txt)。
- `python tools/font_build.py` 从检查文本生成有限字集，游戏运行时只读 PNG 和字形索引。PF-02 没有沿用保留字体名 `Source`。
- `art/fonts/` 是构建素材目录，不参与 Godot 导入；分发时将 OFL 原文与版权声明随包一同提供。

> 待办：正式发布前把上面两款尚未核验的字体的 LICENSE 原文各复制一份到 `art/fonts/`，
> 并把 `THIRD_PARTY_LICENSES.json` 里的 `verified` 改成 `true`。
> 未核验前 R23 允许通过（字段齐全），但发布包不得带 `verified: false` 的字体。
