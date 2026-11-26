class_name ScreenLayout
extends RefCounted
## 呈现尺寸的唯一入口：设计空间恒为 384×216，手机 expand 后画布会变大（555×256）。
##
## 为什么要有它：桌面/门禁是 384×216，手机填满屏幕后画布是 555×256；
## 如果所有 UI 继续按固定坐标画，就会变成「电脑画面左上角 + 右边一片黑」——正是
## 「暴力移植」的样子。这里统一给内容一个**居中原点**，让设计空间落在画布中间。

const DESIGN := Vector2i(384, 216)


## 当前画布尺寸（>= 设计尺寸）。桌面/门禁恒等于 DESIGN。
static func canvas_of(node: Node) -> Vector2i:
	if node == null or not node.is_inside_tree():
		return DESIGN
	var visible := node.get_viewport().get_visible_rect().size
	return Vector2i(maxi(DESIGN.x, int(visible.x)), maxi(DESIGN.y, int(visible.y)))


## 设计空间左上角在画布里的位置（居中）。桌面/门禁恒为 (0,0)，不会引入任何偏移。
static func origin_of(node: Node) -> Vector2i:
	var canvas := canvas_of(node)
	return Vector2i((canvas.x - DESIGN.x) / 2, (canvas.y - DESIGN.y) / 2)


static func is_expanded(node: Node) -> bool:
	return canvas_of(node) != DESIGN


## 内容宽度：设计空间的宽度（文本折行、面板宽度都按它算，不按画布算）。
static func content_width() -> int:
	return DESIGN.x
