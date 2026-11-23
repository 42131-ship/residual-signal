你的任务：修正 `data/cards/layer_l.json` 与 `data/cards/layer_s_school.json` 里 **effects 的 `when` 字段**，让每条效果都挂在真实的插槽选项上。只输出一个 JSON，结构如下，不要围栏、不要解释：

```json
{"fixes": [{"file": "layer_l", "card_id": "l_night_encounter", "effects": [ ...修正后的 effects 数组... ]}]}
```

## 为什么

离线校验器新加了 **R39**：`effects[].when` 必须**逐字等于**本卡某个 slot 的某个 option 字符串。否则引擎在运行时永远匹配不上，这条效果**永远不会触发**——而且不会报错，只会让世界安静得不像话。

现在的卡里，`when` 写的是「停下并给出所求」这种描述句，而 slots 的 option 是「停下」「继续走」「隔着距离回应」——对不上。

## 怎么改

1. 先看这张卡有哪些 slots、每个 slot 有哪些 options。
2. 把每条 effect 的 `when` 改成**某个 slot 里的某个 option 的原文**，逐字一致（含标点）。
3. 一条 effect 只能挂一个 option；如果一张卡需要两个选项导致同一效果，就拆成两条 effect。
4. `vars` 只能动六组：`trust` `reputation` `supplies` `control` `knowledge` `time`。
5. `evidence` 保持 `evt_` 开头，不要改已有 id。
6. 效果数量只能增（拆分）不能减；确实挂不上的，改成挂到最接近的那个 option，并在该条加 `"note": "近似"`。

## 必须遵守的边界

- **不许改** `slots` / `trigger` / `text` / `leftover` / `returns_after_days` / `card_id`。
- 只交 `effects` 数组。
- 两张文件里所有卡都要覆盖（`layer_l` 8 张，`layer_s_school` 2 张）。某张卡的 effects 本来就合规，也照样列出来，原样返回。
