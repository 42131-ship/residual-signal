extends SceneTree
## GameShell 最小闭环门禁：load → new_game → 一次行动 → 存读 → 摘要。
## 运行：.tools/Godot_v4.7-stable_win64_console.exe --headless --path . \
##         --script res://game/tests/shell.gd
## 通过输出一行 `SHELL_OK ...`。

var _shell: GameShell


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_shell = GameShell.new()
	root.add_child(_shell)
	_shell.loop_done.connect(_on_loop_done)
	await process_frame
	_shell.run_minimal_loop()


func _on_loop_done(ok: bool, report: String) -> void:
	if ok:
		print("SHELL_OK " + report)
		quit(0)
		return
	push_error("SHELL_FAIL " + report)
	print("SHELL_FAIL " + report)
	quit(1)
