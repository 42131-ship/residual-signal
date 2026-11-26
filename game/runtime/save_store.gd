class_name SaveStore
extends RefCounted
## 原子存档：主档 + 备份 + 临时档（D17 / W1）。
##
## 写顺序（每一步都可能被断电或杀进程打断，但任何时刻磁盘上至少有一份可解析的完整状态）：
##   1) 写 TMP 并回读校验（写了一半就报失败，不碰主档）
##   2) 旧 MAIN 降级为 BAK（先删更旧的 BAK）
##   3) TMP 提升为 MAIN
##
## 读顺序（前一份不行才往后退，退成功后把那份提升成 MAIN，自愈）：
##   TMP > MAIN > BAK
##
## 为什么 TMP 排第一：写成功的路径会把 TMP rename 掉，所以「磁盘上还留着一份能解析的 TMP」
## 只可能意味着「上一次写完了 TMP 但没来得及提升为主档」—— 它才是最新的那份。
## 反过来先读 MAIN 会把最后一次存档悄悄丢掉（断电测试专门盯这个）。
##
## 为什么不是「先写 MAIN 再写 BAK」：MAIN 写一半就两份都没了。
## 为什么不靠 rename 覆盖主档：rename 的覆盖语义跨平台不保证原子，所以先用 BAK 把上一份兜住。
##
## 注意版本线有两条，别混：
##   - 这里管的是**一局 RunState 存档**（`run-state.vN`，文件 user://run.json）；
##   - `schema/migrations/save_v*.json` 是**世界状态快照**的版本（sediment int -> {amount,last_noise_day}），
##     读写在 WorldState 侧，不经过本类。

const MAIN := "user://run.json"
const BAK := "user://run.bak"
const TMP := "user://run.tmp"

## 「这是一份存档」的判定：存的是状态字典本身，版本由 RunState 迁移。
## 空 schema = v0 老档（本项目最早那批），也要能读回来。
const ACCEPT_SCHEMAS := ["", "run-state.v0", "run-state.v1", "run-state.v2"]


static func paths() -> Dictionary:
	return {"main": MAIN, "bak": BAK, "tmp": TMP}


static func exists_any() -> bool:
	return FileAccess.file_exists(MAIN) or FileAccess.file_exists(BAK) or FileAccess.file_exists(TMP)


static func is_save_dict(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	return ACCEPT_SCHEMAS.has(str((data as Dictionary).get("schema", "")))


## 三份全清。测试与新游戏开局都要用它——只删主档会留下 BAK/TMP 污染下一次读取。
static func clear() -> void:
	_remove(MAIN)
	_remove(BAK)
	_remove(TMP)


static func write(payload: Dictionary) -> bool:
	var text := JSON.stringify(payload, "  ")
	if not _write_verify(TMP, text):
		push_error("SAVE_WRITE_FAILED: " + TMP)
		return false

	# 2) 主档降级成备份。备份只是「上一份」，允许不存在。
	if FileAccess.file_exists(MAIN):
		_remove(BAK)
		if not _rename(MAIN, BAK):
			push_error("SAVE_DEMOTE_FAILED: " + MAIN + " -> " + BAK)
			return false

	# 3) 临时档提升成主档。
	if not _rename(TMP, MAIN):
		push_error("SAVE_PROMOTE_FAILED: " + TMP + " -> " + MAIN)
		# 退化路径：至少把这次内容直接写进主档，别丢掉一整天进度。
		var ok := _write_verify(MAIN, text)
		if ok:
			_remove(TMP)
		return ok
	return true


## 返回第一份可解析且被认作存档的字典；全坏返回 null。
static func read() -> Variant:
	for path: String in [TMP, MAIN, BAK]:
		var parsed: Variant = _read_dict(path)
		if is_save_dict(parsed):
			if path != MAIN:
				_promote(path)
			return parsed
	return null


# ── 内部 ────────────────────────────────────────────────────────────────

static func _read_dict(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return null
	return _parse(text)


## 用 JSON 实例解析：坏档是「预期内」的情况，不能让引擎把 parse 错误刷进 stderr。
static func _parse(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


static func _write_verify(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	# 回读校验：断电最可能伤到的是「写了一半」，解析不过就当这次写没成功。
	return is_save_dict(_parse(FileAccess.get_file_as_string(path)))


static func _promote(from_path: String) -> void:
	_remove(MAIN)
	if not _rename(from_path, MAIN):
		push_warning("SAVE_PROMOTE_SOFT_FAILED: " + from_path)


static func _rename(from_path: String, to_path: String) -> bool:
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path)
	)
	return err == OK


static func _remove(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
