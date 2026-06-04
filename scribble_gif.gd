@tool
extends AnimatedSprite2D
class_name ScribbleSpritesheetPlayer

## Запечённый scribble-spritesheet + hover/reveal по клику.

enum HoverAreaMode {
	SPRITE,
	CUSTOM_RECT,
	SCENE_AREA,
}

@export_group("Spritesheet Files")
@export_file("*.png", "*.webp") var sheet_path: String = "":
	set(v):
		sheet_path = v
		_sync_meta_from_sheet()
		_request_reload()

@export_file("*.json", "*.spritesheet.json") var meta_path: String = "":
	set(v):
		meta_path = v
		_request_reload()


@export_group("Playback")
@export var animation_name: String = "default"
@export var play_on_load: bool = true
@export var loop: bool = true
@export var fps_override: float = 0.0


@export_group("Reveal")
@export var fade_duration: float = 0.35
@export var hidden_until_hover: bool = true
@export var hover_area_mode: HoverAreaMode = HoverAreaMode.SPRITE
@export var hover_padding: Vector2 = Vector2(16, 16)
@export var custom_hover_rect: Rect2 = Rect2(-80, -120, 160, 240)
@export var hover_area_path: NodePath


@export_group("Editor")
@export var reload_in_editor: bool = true


var _locked: bool = false
var _hovered: bool = false
var _fade_tween: Tween
var _fade_alpha: float = 1.0
var _shader_mat: ShaderMaterial
var _hover_area: Area2D
var _hover_ready: bool = false
var _reload_queued: bool = false


func _enter_tree() -> void:
	_sync_meta_from_sheet()
	_reload_sheet()


func _ready() -> void:
	if not _hover_ready:
		call_deferred("_setup_reveal")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if hover_area_mode == HoverAreaMode.SCENE_AREA:
		return
	if not _use_hidden_until_hover() or _locked:
		return
	var hovered := _is_mouse_over()
	if hovered != _hovered:
		_hovered = hovered
		_fade_to(1.0 if hovered else 0.0)


func _sync_meta_from_sheet() -> void:
	if not meta_path.is_empty() and not _looks_like_bad_meta_path(meta_path):
		return
	var resolved := _resolved_sheet_path()
	if not resolved.is_empty():
		meta_path = resolved.get_basename() + ".spritesheet.json"


func _looks_like_bad_meta_path(path: String) -> bool:
	return path.begins_with("uid://") and not FileAccess.file_exists(path)


func _resolved_sheet_path() -> String:
	if sheet_path.is_empty():
		return ""
	if sheet_path.begins_with("uid://"):
		var res := load(sheet_path)
		if res != null and res.resource_path:
			return res.resource_path
		return ""
	return sheet_path


func _resolved_meta_path() -> String:
	if not meta_path.is_empty() and not _looks_like_bad_meta_path(meta_path):
		if meta_path.begins_with("uid://"):
			var res := load(meta_path)
			if res != null and res.resource_path:
				return res.resource_path
		return meta_path
	var sheet := _resolved_sheet_path()
	if sheet.is_empty():
		return ""
	return sheet.get_basename() + ".spritesheet.json"


func _request_reload() -> void:
	if not reload_in_editor and Engine.is_editor_hint():
		return
	if not is_inside_tree() and not Engine.is_editor_hint():
		return
	if _reload_queued:
		return
	_reload_queued = true
	call_deferred("_deferred_reload")


func _deferred_reload() -> void:
	_reload_queued = false
	_reload_sheet()


func _reload_sheet() -> void:
	var resolved_sheet := _resolved_sheet_path()
	if resolved_sheet.is_empty():
		return

	var resolved_meta := _resolved_meta_path()
	if resolved_meta.is_empty() or not FileAccess.file_exists(resolved_meta):
		push_error(
			"ScribbleSpritesheetPlayer: missing meta for %s (expected %s)"
			% [name, resolved_meta]
		)
		return

	var frames := build_sprite_frames(
		resolved_sheet, resolved_meta, StringName(animation_name), fps_override, loop
	)
	if frames == null:
		return

	sprite_frames = frames
	animation = StringName(animation_name)
	if play_on_load and frames.has_animation(StringName(animation_name)):
		play(StringName(animation_name))
	elif Engine.is_editor_hint():
		frame = 0
		queue_redraw()
	_setup_reveal()


func _use_hidden_until_hover() -> bool:
	return hidden_until_hover and not Engine.is_editor_hint()


func _setup_reveal() -> void:
	if sprite_frames == null or sprite_frames.get_animation_names().is_empty():
		push_warning("ScribbleSpritesheetPlayer: no frames on %s (check Sheet Path)" % name)
		modulate = Color(1, 1, 1, 1)
		return
	_setup_material()
	_apply_fade(0.0 if _use_hidden_until_hover() else 1.0)
	if Engine.is_editor_hint():
		modulate = Color(1, 1, 1, 1)
	if not Engine.is_editor_hint():
		_setup_hover_area()
	_hover_ready = true


func _setup_material() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		_shader_mat = null
		return
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mat.resource_local_to_scene = true
		material = mat
	_shader_mat = mat


func _setup_hover_area() -> void:
	match hover_area_mode:
		HoverAreaMode.SCENE_AREA:
			_hover_area = _find_scene_hover_area()
			if _hover_area == null:
				push_warning("ScribbleSpritesheetPlayer: SCENE_AREA but no Area2D at %s" % hover_area_path)
				return
		HoverAreaMode.CUSTOM_RECT:
			if custom_hover_rect.size == Vector2.ZERO:
				push_warning("ScribbleSpritesheetPlayer: CUSTOM_RECT has zero size")
				return
			_hover_area = _create_rect_area(custom_hover_rect)
			add_child(_hover_area)
		HoverAreaMode.SPRITE:
			var sprite_rect := _sprite_hover_rect()
			if sprite_rect.size == Vector2.ZERO:
				return
			_hover_area = _create_rect_area(sprite_rect)
			add_child(_hover_area)
	if _hover_area:
		_bind_hover_area(_hover_area)
	_remove_runtime_hover_area()


func _remove_runtime_hover_area() -> void:
	var stale := get_node_or_null(^"HoverArea")
	if stale and stale != _hover_area:
		stale.queue_free()


func _find_scene_hover_area() -> Area2D:
	if not hover_area_path.is_empty():
		var n := get_node_or_null(hover_area_path)
		if n is Area2D:
			return n
		if n is CollisionShape2D:
			var parent := n.get_parent()
			if parent is Area2D:
				return parent
		push_warning(
			"ScribbleSpritesheetPlayer: hover_area_path must point to Area2D or CollisionShape2D"
		)
		return null
	for child in get_children():
		if child is Area2D and child.name != &"HoverArea":
			return child
	return null


func _create_rect_area(rect: Rect2) -> Area2D:
	var area := Area2D.new()
	area.name = &"HoverArea"
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	col.position = rect.position + rect.size * 0.5
	area.add_child(col)
	return area


func _bind_hover_area(area: Area2D) -> void:
	area.input_pickable = true
	if not area.mouse_entered.is_connected(_on_mouse_entered):
		area.mouse_entered.connect(_on_mouse_entered)
	if not area.mouse_exited.is_connected(_on_mouse_exited):
		area.mouse_exited.connect(_on_mouse_exited)
	if not area.input_event.is_connected(_on_area_input):
		area.input_event.connect(_on_area_input)


func _on_mouse_entered() -> void:
	if _locked or _hovered:
		return
	_hovered = true
	if _use_hidden_until_hover():
		_fade_to(1.0)


func _on_mouse_exited() -> void:
	if not _use_hidden_until_hover():
		_hovered = false
		return
	if _locked or not _hovered:
		return
	_hovered = false
	_fade_to(0.0)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_locked = true
		_hovered = true
		_fade_to(1.0)


func _fade_to(target: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_method(_apply_fade, _fade_alpha, target, fade_duration)


func _apply_fade(value: float) -> void:
	_fade_alpha = value
	if _shader_mat:
		_shader_mat.set_shader_parameter("fade_alpha", value)
	else:
		var m := modulate
		m.a = value
		modulate = m


func _is_mouse_over() -> bool:
	var rect := _get_hover_rect_local()
	if rect.size == Vector2.ZERO:
		return false
	return rect.has_point(to_local(get_global_mouse_position()))


func _get_hover_rect_local() -> Rect2:
	match hover_area_mode:
		HoverAreaMode.CUSTOM_RECT:
			return custom_hover_rect
		HoverAreaMode.SPRITE:
			return _sprite_hover_rect()
		HoverAreaMode.SCENE_AREA:
			return _rect_from_scene_area()
	return Rect2()


func _sprite_hover_rect() -> Rect2:
	var size := _hit_size()
	if size == Vector2.ZERO:
		return Rect2()
	size += hover_padding
	return Rect2(-size * 0.5, size)


func _rect_from_scene_area() -> Rect2:
	if _hover_area == null:
		return Rect2()
	for child in _hover_area.get_children():
		if child is CollisionShape2D:
			var col := child as CollisionShape2D
			if col.shape is RectangleShape2D:
				var shape := col.shape as RectangleShape2D
				var size := shape.size
				var center := to_local(col.global_position)
				return Rect2(center - size * 0.5, size)
	return Rect2()


func _hit_size() -> Vector2:
	if sprite_frames == null:
		return Vector2.ZERO
	var anim_name := animation
	if anim_name.is_empty():
		var names := sprite_frames.get_animation_names()
		if names.is_empty():
			return Vector2.ZERO
		anim_name = names[0]
	var tex := sprite_frames.get_frame_texture(anim_name, 0)
	if tex:
		return tex.get_size() * scale.abs()
	return Vector2.ZERO


static func build_sprite_frames(
	sheet_res_path: String,
	meta_res_path: String,
	anim_name: StringName = &"default",
	fps_override_value: float = 0.0,
	should_loop: bool = true
) -> SpriteFrames:
	if sheet_res_path.is_empty():
		push_error("ScribbleSpritesheetPlayer: sheet_path is empty")
		return null

	if not FileAccess.file_exists(sheet_res_path):
		push_error("ScribbleSpritesheetPlayer: missing sheet %s" % sheet_res_path)
		return null

	if not FileAccess.file_exists(meta_res_path):
		push_error("ScribbleSpritesheetPlayer: missing meta %s" % meta_res_path)
		return null

	var meta_file := FileAccess.open(meta_res_path, FileAccess.READ)
	var meta: Dictionary = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	if meta == null:
		push_error("ScribbleSpritesheetPlayer: invalid JSON %s" % meta_res_path)
		return null

	var texture := load(sheet_res_path) as Texture2D
	if texture == null:
		push_error("ScribbleSpritesheetPlayer: cannot load %s" % sheet_res_path)
		return null

	var columns: int = maxi(int(meta.get("columns", 1)), 1)
	var frame_count: int = maxi(int(meta.get("frame_count", 1)), 1)
	var fps: float = fps_override_value if fps_override_value > 0.001 else float(meta.get("fps", 12.0))
	var rows: int = int(meta.get("rows", ceili(float(frame_count) / float(columns))))

	var sheet_size := texture.get_size()
	var cell_w := int(meta.get("frame_width", 0))
	var cell_h := int(meta.get("frame_height", 0))
	if cell_w <= 0:
		cell_w = int(sheet_size.x / columns)
	if cell_h <= 0:
		cell_h = int(sheet_size.y / maxi(rows, 1))

	var frames := SpriteFrames.new()
	if not frames.has_animation(anim_name):
		frames.add_animation(anim_name)
	else:
		frames.clear(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, should_loop)

	for i in frame_count:
		var col := i % columns
		var row := int(float(i) / float(columns))
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(col * cell_w, row * cell_h, cell_w, cell_h)
		frames.add_frame(anim_name, atlas)

	return frames
