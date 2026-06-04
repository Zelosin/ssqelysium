@tool
extends Sprite2D

## Runtime driver for scribble shader. Editor animation is handled by scribble_editor_preview plugin.

var _anim_time: float = 0.0


func _enter_tree() -> void:
	_ensure_unique_material()
	_apply_shader_state()


func _ready() -> void:
	_ensure_unique_material()
	_apply_shader_state()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_anim_time += delta
	_apply_shader_state()
	queue_redraw()


func _ensure_unique_material() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	if not mat.resource_local_to_scene:
		material = mat.duplicate()
		material.resource_local_to_scene = true


func _apply_shader_state() -> void:
	var mat := material as ShaderMaterial
	if mat == null or texture == null:
		return
	mat.set_shader_parameter("source_texture", texture)
	mat.set_shader_parameter("effect_time", _anim_time)
