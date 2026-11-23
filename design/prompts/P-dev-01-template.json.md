你的任务：产出 `data/templates/school.json`（模板 T0 学校）。只输出合法 JSON，不要 markdown 代码块、不要解释。

## 这个文件是什么

《残余信号》有 5 个角色模板，共享一份世界日历。模板**只决定入口**：谁、从世界第几天进场、在哪、带什么、能进哪、枪的比例。模板绝不可改写时间轴/变量定义/终局态枚举。

世界日历（已定，不可改）：
- Day 0 爆发日（活人极多、物资满、噪声敏感 0.2）
- Day 1 打砸抢（活人 0.8、丧尸点状极密、物资 0.85）
- Day 3 断电（活人 0.45、丧尸摊薄、物资 0.6、噪声敏感 0.7）
- Day 5 饥饿冒险（活人 0.25、丧尸街上密集但密度一般、物资 0.35、噪声敏感 0.8）
- Day 7 最后一次广播（活人 0.12、丧尸聚群、物资 0.25）
- Day 14 检查站撤走（物资 0.12）
- Day 30 收束（物资 0.05，噪声敏感 1.0）
收束日固定 Day 30。局内天数 = 30 − 进场日。

学校模板的背景：中学，16 个可进入节点（5 段主轴走廊 + 11 间纵深房：教室1/教室2/教室3、实验室、传达室（唯一能上锁，安全屋）、广播室、天台、办公室、食堂冷库、地下车库、配电间）。玩家是学生。

身份三样（不加任何数值）：
1. 钥匙/权限 —— 学生证、器材室钥匙；知道哪间实验室有东西、哪扇门能从里面锁上
2. 别人怎么认你 —— 同学老师认得你，但学生身份带来的是「被低估」而不是「被信赖」
3. 你一开始知道什么 —— 半张课表 + 校园平面图 = 初始知情度；会随记忆衰减一起模糊

## 必须满足的机器校验（不满足就是废件）

- **R18**：顶层**不得**出现 `timeline` / `variables` / `endings` / `end_state_enum` / `world_calendar` 任一键
- **R27**：`entry_days` 必须是非空整数数组，每个值 ∈ [0,14]
- **R28**：`noise_budget.cap` 必须是数值；且 `Σ(weapon_budget[*].rounds × weapon_budget[*].sediment_per_shot × 1.0) ≤ cap`
- **R29**：`safehouse_failure` 必须是对象，含 `card_id`（字符串）且 `trigger_once` 必须严格为 `true`（安全屋只失效一次，第二次玩家就学会了，恐怖变烦躁）
- **R05 背景**：学校只有一个可上锁节点（传达室），所以安全屋失效事件必须与它绑定

## 字段清单（照这个写，多余键不要加）

```
template_id        string  "school"
label              string  "学校"
entry_days         int[]   从 [0,1,3,5] 里挑 —— 你决定哪几天可以进场，并说明为什么（用 note 字段）
identity.key_permission      string[]   具体物件，不要抽象
identity.how_recognized      string     一句话
identity.initial_knowledge   string[]   具体信息条目（谁在哪间教室、哪条楼梯平时没人走）
weapon_budget      object  键为武器名；每项含 rounds(int) 与 sediment_per_shot(number)
noise_budget       object  {cap:int, night_multiplier:number}
safehouse_failure  object  {card_id, trigger_once:true, condition, manifestation}
identity_note      string  一句话：这个模板的「起点偏置」是什么
```

## 设计约束（会被人审）

1. **不加数值**：不要写任何伤害/血量/等级。枪在这里近乎为零 —— 学校模板的枪应当是「可能捡到、但没有弹」。
2. **噪声是账本**：`sediment_per_shot` 表示一次使用在该节点留下的沉积增量。冷兵器（撬棍）低但非零；枪即使有弹也极高。
3. **`condition` 要可判定**：必须是状态机读得出来的条件（变量阈值 / 日历 / 节点 tag），不能写「玩家感到不安时」。
4. **`manifestation` 要可证真**：表现必须是能被事件日志记录的一件事，而且要留痕迹 —— 参考方向：门是从**里面**被打开的、插销完好，屋里少了一件东西，没少别的。你可以改，但必须同样「少了一件东西」。
5. 中文文本简洁，不写抒情句。
