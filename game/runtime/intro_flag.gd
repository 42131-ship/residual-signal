class_name IntroFlag
extends RefCounted
## 开场过场的「这一局要不要播」开关。
##
## 为什么是内存里的静态量，而不是 user:// 配置：开场是**菜单 → 走廊**这一次交接的意图，
## 不是存档状态。写进文件会跨进程活下来，门禁（同机同用户目录）就会继承上一场的票：
## `scene-switch` 那次红就是这么来的——走廊以为要播开场，把 E 键吞了，旅行图打不开。
## 静态量只活在这一次进程里，菜单 request()、走廊 consume()，出了这个进程就没人记得。

static var _pending := false
static var _seen := false


## 主菜单点了「新游戏」：请求播一次开场。
static func request() -> void:
	_pending = true


## 有没有待播的请求（不清）。
static func pending() -> bool:
	return _pending


## 看过没有（只用于遥测/复跑判断，不再决定播不播）。
static func seen() -> bool:
	return _seen


## 走廊调用：有待播请求 → 清掉并返回 true。每局新游戏都播一次；
## 玩家不想看随时按任意键跳过，所以不用靠"看过就别放"来省事。
static func consume() -> bool:
	var wanted := _pending
	_pending = false
	return wanted


static func mark_seen() -> void:
	_seen = true


## 门禁/调试：清干净。
static func reset() -> void:
	_pending = false
	_seen = false
