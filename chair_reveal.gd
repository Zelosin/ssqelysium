extends Node2D

## Legacy: только для Sprite2D со шейдером на Node2D-обёртке.
## Для AnimatedSprite2D используй scribble_gif.gd (ScribbleSpritesheetPlayer).

enum HoverAreaMode {
	SPRITE, ## Размер текстуры / первого кадра + Hover Padding
	CUSTOM_RECT, ## Свой прямоугольник в локальных координатах визуала (инспектор)
	SCENE_AREA, ## Своя Area2D в сцене (любая форма CollisionShape2D)
}

@export_group("Reveal")
@export var fade_duration: float = 0.35
@export var hidden_until_hover: bool = true
@export var auto_play_visual: bool = true
@export var visual_path: NodePath

@export_group("Hover Area")
@export var hover_area_mode: HoverAreaMode = HoverAreaMode.SPRITE
@export var hover_padding: Vector2 = Vector2(16, 16)
## Локальный Rect2 относительно визуала: position = левый верх, size = ширина/высота зоны.
@export var custom_hover_rect: Rect2 = Rect2(-80, -120, 160, 240)
## Путь к своей Area2D (от узла со скриптом). Дочерний CollisionShape2D — любой (прямоугольник, круг, полигон).
@export var hover_area_path: NodePath

var _locked: bool = false
var _hovered: bool = false
var _fade_tween: Tween
var _fade_alpha: float = 0.0
var _visual: Node2D
var _shader_mat: ShaderMaterial
var _hover_area: Area2D


func _ready() -> void:
	_visual = _resolve_visual()
	if _visual == null:
		push_warning("chair_reveal: no Sprite2D/AnimatedSprite2D found on %s" % name)
		return
	_ensure_animated_sprite_playing()
	_setup_material()
	_apply_fade(0.0 if hidden_until_hover else 1.0)
	_setup_hover_area()


func _process(_delta: float) -> void:
	# SCENE_AREA: только сигналы Area2D (точная форма CollisionShape2D).
	if hover_area_mode == HoverAreaMode.SCENE_AREA:
		return
	if not hidden_until_hover or _locked or _visual == null:
		return
	var hovered := _is_mouse_over()
	if hovered != _hovered:
		_hovered = hovered
		_fade_to(1.0 if hovered else 0.0)


func _resolve_visual() -> Node2D:
	if not visual_path.is_empty():
		var n := get_node_or_null(visual_path)
		if n is Node2D:
			return n
	if is_instance_of(self, Sprite2D) or is_instance_of(self, AnimatedSprite2D):
		return self
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			return child
	return null


func _ensure_animated_sprite_playing() -> void:
	if not auto_play_visual or not is_instance_of(_visual, AnimatedSprite2D):
		return
	var anim := _visual as AnimatedSprite2D
	if anim.sprite_frames == null:
		return
	if anim.animation.is_empty():
		var names := anim.sprite_frames.get_animation_names()
		if not names.is_empty():
			anim.animation = names[0]
	if anim.is_playing():
		return
	if not anim.animation.is_empty():
		anim.play()


func _setup_material() -> void:
	if _visual is not CanvasItem:
		return
	var mat := (_visual as CanvasItem).material as ShaderMaterial
	if mat == null:
		_shader_mat = null
		return
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mat.resource_local_to_scene = true
		(_visual as CanvasItem).material = mat
	_shader_mat = mat


func _setup_hover_area() -> void:
	match hover_area_mode:
		HoverAreaMode.SCENE_AREA:
			_hover_area = _find_scene_hover_area()
			if _hover_area == null:
				push_warning("chair_reveal: SCENE_AREA but no Area2D at %s" % hover_area_path)
				return
		HoverAreaMode.CUSTOM_RECT:
			if custom_hover_rect.size == Vector2.ZERO:
				push_warning("chair_reveal: CUSTOM_RECT has zero size")
				return
			_hover_area = _create_rect_area(custom_hover_rect)
			_visual.add_child(_hover_area)
		HoverAreaMode.SPRITE:
			var sprite_rect := _sprite_hover_rect()
			if sprite_rect.size == Vector2.ZERO:
				return
			_hover_area = _create_rect_area(sprite_rect)
			_visual.add_child(_hover_area)
	if _hover_area:
		_bind_hover_area(_hover_area)
	_remove_runtime_hover_area()


func _remove_runtime_hover_area() -> void:
	if _visual == null:
		return
	var stale := _visual.get_node_or_null(^"HoverArea")
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
			"chair_reveal: hover_area_path must point to Area2D or CollisionShape2D, got %s"
			% (n.get_class() if n else "null")
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
	if hidden_until_hover:
		_fade_to(1.0)


func _on_mouse_exited() -> void:
	if not hidden_until_hover:
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
	elif _visual is CanvasItem:
		var c := _visual as CanvasItem
		var m := c.modulate
		m.a = value
		c.modulate = m


func _is_mouse_over() -> bool:
	if _visual == null:
		return false
	var rect := _get_hover_rect_local()
	if rect.size == Vector2.ZERO:
		return false
	return rect.has_point(_visual.to_local(get_global_mouse_position()))


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
	if _visual is Sprite2D and not (_visual as Sprite2D).centered:
		return Rect2(Vector2.ZERO, size)
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
				var center := _hover_area.to_local(col.global_position)
				if _visual:
					center = _visual.to_local(col.global_position)
				return Rect2(center - size * 0.5, size)
	return Rect2()


func _hit_size() -> Vector2:
	if _visual is Sprite2D:
		var spr := _visual as Sprite2D
		if spr.texture:
			return spr.texture.get_size() * spr.scale.abs()
	if _visual is AnimatedSprite2D:
		var anim := _visual as AnimatedSprite2D
		if anim.sprite_frames == null:
			return Vector2.ZERO
		var anim_name := anim.animation
		if anim_name.is_empty():
			var names := anim.sprite_frames.get_animation_names()
			if names.is_empty():
				return Vector2.ZERO
			anim_name = names[0]
		var tex := anim.sprite_frames.get_frame_texture(anim_name, 0)
		if tex:
			return tex.get_size() * anim.scale.abs()
	return Vector2.ZERO
