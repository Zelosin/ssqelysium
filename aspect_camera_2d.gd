@tool
extends Camera2D
## Keeps a 21:9 (2.333…) visible area; letterboxes when the window aspect differs.

const ASPECT_W := 21.0
const ASPECT_H := 9.0
const TARGET_ASPECT := ASPECT_W / ASPECT_H

@export var base_height: float = 540.0:
	set(v):
		base_height = maxf(v, 64.0)
		_update_zoom()


func _ready() -> void:
	make_current()
	enabled = true
	_update_zoom()


func _process(_delta: float) -> void:
	_update_zoom()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_update_zoom()


func _update_zoom() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var view_size := vp.get_visible_rect().size
	if view_size.y < 1.0:
		return
	var window_aspect := view_size.x / view_size.y
	# Design frame: ASPECT_W × base_height (e.g. 1260×540).
	var design_w := base_height * TARGET_ASPECT
	var design_h := base_height
	var zoom_x := view_size.x / design_w
	var zoom_y := view_size.y / design_h
	if window_aspect > TARGET_ASPECT:
		# Wider than 21:9 — fit height, pillarbox sides.
		zoom = Vector2.ONE * zoom_y
	else:
		# Narrower than 21:9 — fit width, letterbox top/bottom.
		zoom = Vector2.ONE * zoom_x
