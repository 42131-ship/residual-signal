class_name DayCycle
extends RefCounted
## 一天怎么结束：把「今天发生了什么」折算进世界状态，然后翻页。
##
## 只做结算，不做演出。演出由场景负责。
## 数据约束来自 school 模板：30 天一个模板、sediment 上限 40（smoke 门禁里 sediment_max=40）。

const MAX_DAY := 30
const SEDIMENT_CAP := 40
const EXTRACT_SEDIMENT := 1
const LOST_SEDIMENT := 2

var day := 0
var sediment := 0
var finished := false
var _settled_days := 0


func new_run() -> void:
	day = 0
	sediment = 0
	finished = false
	_settled_days = 0


## outcome 允许的键：
##   extracted(bool) 是否成功离场；supplies(float) 当天净变化；health(float) 收工时体力；
##   kills(int) 击杀数；noise(int) 当天累计噪声。
## 返回：{day, next_day, sediment, health, supplies, lines[], finished}
func settle(outcome: Dictionary) -> Dictionary:
	var extracted := bool(outcome.get("extracted", false))
	var supplies_in := clampf(float(outcome.get("supplies", 0.0)), 0.0, 1.0)
	var supplies := supplies_in
	var health := clampf(float(outcome.get("health", 1.0)), 0.0, 1.0)
	var kills := maxi(0, int(outcome.get("kills", 0)))
	var noise := maxi(0, int(outcome.get("noise", 0)))

	var before_day := day
	var before_sediment := sediment
	sediment = mini(SEDIMENT_CAP, sediment + (EXTRACT_SEDIMENT if extracted else LOST_SEDIMENT))

	# 收工后体力回一点：睡觉是唯一的恢复手段。
	var rested := clampf(health + (0.25 if extracted else 0.1), 0.0, 1.0)
	# 没离场的那天，物资会被自己消耗掉一点。
	if not extracted:
		supplies = clampf(supplies - 0.05, 0.0, 1.0)

	day = mini(MAX_DAY, day + 1)
	_settled_days += 1
	if day >= MAX_DAY:
		finished = true

	var lines: Array[String] = []
	lines.append("第 %d 天结束（%s）" % [before_day + 1, "已离场" if extracted else "没能离场"])
	lines.append("沉积 %d→%d · 体力 %d · 物资 %d" % [
		before_sediment, sediment, int(round(rested * 100.0)), int(round(supplies * 100.0))])
	if kills > 0:
		lines.append("今晚安静些了：击杀 %d" % kills)
	if noise >= 10:
		lines.append("你吵醒了一些东西。")

	return {
		"day": before_day,
		"next_day": day,
		"sediment": sediment,
		"health": rested,
		"supplies": supplies,
		# M2a 第 3 步：调用方拿这个增量去写，不要覆盖整个字段。
		"supplies_delta": supplies - supplies_in,
		"lines": lines,
		"finished": finished,
	}


func settled_days() -> int:
	return _settled_days


func day_label() -> String:
	return "第 %d / %d 天" % [mini(day + 1, MAX_DAY), MAX_DAY]
