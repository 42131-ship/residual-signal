# 字体与第三方声明（NOTICE）

本文件由 `THIRD_PARTY_LICENSES.json` 引用，游戏内 credits 由该 JSON 生成。

## 缝合像素字体 Fusion（PF-02 图集的构建输入）

- 用途：**PF-02 中文/拉丁点阵图集的构建输入**（12px proportional zh_hans）
- 版本：`2026.11.10`（`fusion-pixel-12px-proportional-zh_hans.ttf`，7.0MB）
- 授权：SIL Open Font License 1.1，原文见 [`FUSION-PIXEL-OFL.txt`](FUSION-PIXEL-OFL.txt)；
  项目代码部分为 MIT，见 [`FUSION-PIXEL-MIT.txt`](FUSION-PIXEL-MIT.txt)
- 保留字体名（Reserved Font Name）：修改版不得使用原名；本项目只**栅格化成 PNG 图集**，不重分发 TTF
- 为什么换它：NotoSansSC 缩到 13px 再二值化，复杂汉字墨迹占格 41%~85%，笔画粘连
  （「残余信号」糊成一团）。Fusion 是**为 12px 设计**的点阵字体，墨迹最大 11×11、零降采样。

## Noto Sans SC（兜底构建输入）

- 用途：Fusion 极少数未覆盖字的兜底渲染（当前构建 0 个兜底字）
- 授权：SIL OFL 1.1，原文见 [`NOTOSANS-SC-OFL.txt`](NOTOSANS-SC-OFL.txt)
- 上游：<https://github.com/google/fonts/blob/main/ofl/notosanssc/OFL.txt>

## 凤凰点阵体 Vonwaon（已声明，当前未使用）

- `THIRD_PARTY_LICENSES.json` 里仍挂着 CC0-1.0 的声明，但**当前构建链没有用到它**
  （PF-01 是程序生成的 5×7，PF-02 用 Fusion）。
- 发行前二选一：真正接入（并核验 CC0 原文）或从台账移除。**不能"声明了却没用"**。

## 运行时

游戏运行时只读 `art/generated_candidates/fonts/` 下生成的 PNG 图集 + JSON 索引，
不加载任何 TTF；`art/fonts/` 是构建素材目录（Godot 侧不参与导入）。
