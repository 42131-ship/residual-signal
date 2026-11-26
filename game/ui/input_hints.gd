class_name InputHints
extends RefCounted
## 输入提示的唯一来源：**桌面（键鼠）**与**触屏**各一套，按当前平台取。
##
## 为什么要有它：同一个面板在 PC 上要告诉玩家按 W/S 选择、按 E 确认；
## 手机上这些提示是噪音——玩家根本按不出 W/S，看到只会觉得「电脑暴力移植」。
##
## 纪律：
## - `PC` 表是**冻结备份**（与 design/CONTROLS.md 的键位表一致），不要为了手游改动它；
##   桌面/门禁永远走这套，任何改动都必须同步 CONTROLS.md。
## - `TOUCH` 表为空字符串的条目 = 手机上不显示（触屏按钮自带标签：包/看/退/填/走/灯/打/E 与方向键）。
## - 触屏要交代操作的地方（比如装填）才写文案，且必须指向**看得见的按钮**。

const PC := {
	"menu_list": "W/S 选择   E 确认",
	"menu_toggle": "E 切换   Esc 返回",
	"menu_back": "Esc 返回",
	"travel_map": "W/S 选楼 · E 出发 · Esc 留下",
	"inspect_close": "ESC",
	"inventory_actions": "E 使用 Q 丢弃 TAB 关闭",
	"inventory_move": "W/S 选择",
	"reload_toast": "没有子弹，按 R 装填",
	"search_hold": "按住 E 搜索",
	"leave": "按 E 离场",
	"door_open": "E 开门",
	"door_close": "E 关门",
	"door_lock": "E 锁门",
	"door_pry": "E 撬开",
}

const TOUCH := {
	"menu_list": "",
	"menu_toggle": "",
	"menu_back": "",
	"travel_map": "",
	"inspect_close": "退",
	"inventory_actions": "",
	"inventory_move": "",
	"reload_toast": "没有子弹，点「填」装填",
	"search_hold": "按住「E」搜索",
	"leave": "点「E」离场",
	"door_open": "点「E」开门",
	"door_close": "点「E」关门",
	"door_lock": "点「E」锁门",
	"door_pry": "点「E」撬开",
}


## 手机（含 RS_TOUCH=1 的桌面模拟）走 TOUCH，其余走 PC。门禁在桌面跑，永远拿 PC 文案。
static func touch_mode() -> bool:
	return MobileSupport.enabled()


static func get_hint(key: String) -> String:
	var table: Dictionary = TOUCH if touch_mode() else PC
	return str(table.get(key, PC.get(key, "")))


## 兼容旧写法：`if not hint.empty(): draw(...)`。空提示直接不画。
static func has_hint(key: String) -> bool:
	return not get_hint(key).is_empty()
