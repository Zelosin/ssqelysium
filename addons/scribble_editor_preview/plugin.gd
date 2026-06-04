@tool
extends EditorPlugin

## Drives scribble shader effect_time in the 2D editor (@tool _process is often paused there).

const SCRIBBLE_SHADER_PATH := "res://hand_drawn_scribble.gdshader"

var _anim_time: float = 0.0
var _saved_update_continuously: Variant = null


func _enter_tree() -> void:
	set_process(true)
	_enable_editor_continuous_update()


func _exit_tree() -> void:
	set_process(false)
	_restore_editor_continuous_update()


func _process(delta: float) -> void:
	if get_editor_interface().is_playing_scene():
		return
	_anim_time += delta
	var root := get_editor_interface().get_edited_scene_root()
	if root:
		_update_scribble_tree(root)
	var vp := get_editor_interface().get_editor_viewport_2d()
	if vp:
		vp.queue_redraw()


func _enable_editor_continuous_update() -> void:
	var es := get_editor_interface().get_editor_settings()
	var key := &"interface/editor/update_continuously"
	if not es.get_setting(key):
		_saved_update_continuously = false
		es.set_setting(key, true)


func _restore_editor_continuous_update() -> void:
	if _saved_update_continuously == null:
		return
	var es := get_editor_interface().get_editor_settings()
	es.set_setting(&"interface/editor/update_continuously", _saved_update_continuously)
	_saved_update_continuously = null


func _update_scribble_tree(node: Node) -> void:
	if node is CanvasItem:
		var item := node as CanvasItem
		var mat := item.material as ShaderMaterial
		if _is_scribble_material(mat):
			if node is Sprite2D:
				var spr := node as Sprite2D
				if spr.texture:
					mat.set_shader_parameter("source_texture", spr.texture)
			elif node is AnimatedSprite2D:
				var anim := node as AnimatedSprite2D
				if anim.sprite_frames and anim.animation != StringName():
					var ft := anim.sprite_frames.get_frame_texture(anim.animation, anim.frame)
					if ft:
						mat.set_shader_parameter("source_texture", ft)
			mat.set_shader_parameter("effect_time", _anim_time)
	for child in node.get_children():
		_update_scribble_tree(child)


func _is_scribble_material(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	var path := mat.shader.resource_path
	return path == SCRIBBLE_SHADER_PATH or path.ends_with("hand_drawn_scribble.gdshader")
