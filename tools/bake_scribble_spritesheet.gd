extends Node

## Запекает scribble-шейдер в spritesheet.
##
## Один объект:
##   godot --path <project> res://tools/bake_capture.tscn -- Book
##
## Все объекты (кроме Chair и Jacket):
##   godot --path <project> res://tools/bake_capture.tscn -- --batch
##
## Важно: НЕ используй --headless — GPU-рендер SubViewport в нём не работает.
##
## Файлы: res://obj/<slug>/baked_<slug>.png + .spritesheet.json

const FRAMES: int = 120
const COLUMNS: int = 12
const FPS: float = 30.0
const DURATION_SEC: float = 4.0
const MARGIN_PX: int = 24
const SHADER_PATH := "res://hand_drawn_scribble.gdshader"

@export var object_name: String = ""
@export var target_path: NodePath
@export var output_basename: String = ""
@export var batch_mode: bool = false
@export var batch_exclude: PackedStringArray = ["Chair", "Jacket"]

var _visibility_backup: Dictionary = {}


func _ready() -> void:
	_apply_cmdline_args()
	if _is_headless_no_gpu():
		push_error(
			"bake: флаг --headless не поддерживается (нет GPU-рендера). "
			+ "Запускай без --headless, окно закроется само после экспорта."
		)
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame

	if batch_mode:
		var ok_batch := await _batch_bake_all()
		get_tree().quit(0 if ok_batch else 1)
		return

	var sprite := _resolve_target()
	if sprite == null:
		push_error("bake: Sprite2D not found (object_name=%s, target_path=%s)" % [object_name, target_path])
		get_tree().quit(1)
		return

	var ok := await _bake_one(sprite)
	get_tree().quit(0 if ok else 1)


func _apply_cmdline_args() -> void:
	var user_args := OS.get_cmdline_user_args()
	var positional := true
	for arg in user_args:
		if arg == "--batch" or arg == "--batch-all":
			batch_mode = true
			positional = false
		elif arg.begins_with("--exclude="):
			batch_exclude = PackedStringArray(arg.substr("--exclude=".length()).split(",", false))
			positional = false
		elif arg.begins_with("--object="):
			object_name = arg.substr("--object=".length())
			positional = false
		elif arg.begins_with("--object-name="):
			object_name = arg.substr("--object-name=".length())
			positional = false
		elif arg.begins_with("--output="):
			output_basename = arg.substr("--output=".length())
			positional = false
		elif arg.begins_with("--output-basename="):
			output_basename = arg.substr("--output-basename=".length())
			positional = false
		elif positional and not arg.begins_with("-"):
			object_name = arg
			positional = false


func _batch_bake_all() -> bool:
	var main := get_node_or_null("Main")
	if main == null:
		push_error("bake: Main node missing")
		return false

	var targets: Array[Sprite2D] = []
	_collect_scribble_sprites(main, targets)
	targets.sort_custom(func(a: Sprite2D, b: Sprite2D) -> bool: return a.name < b.name)

	var any_ok := false
	var failed: Array[String] = []

	for sprite in targets:
		if sprite.name in batch_exclude:
			print("bake: skip %s (excluded)" % sprite.name)
			continue
		print("bake: start %s" % sprite.name)
		output_basename = ""
		var ok := await _bake_one(sprite)
		if ok:
			any_ok = true
		else:
			failed.append(sprite.name)

	_restore_scene_visibility()

	if failed.is_empty():
		print("bake: batch done (%d objects)" % targets.size())
		return any_ok

	push_error("bake: batch failed for: %s" % ", ".join(failed))
	return false


func _bake_one(sprite: Sprite2D) -> bool:
	var basename := output_basename
	if basename.is_empty():
		basename = _default_output_basename(sprite.name)
	var out_dir := _output_dir_for(sprite.name)

	_isolate_for_bake(sprite)
	var ok := await _bake(sprite, out_dir, basename)
	_restore_scene_visibility()

	if ok:
		print("bake: saved %s/%s.png + .spritesheet.json (%d frames, node=%s)" % [
			out_dir, basename, FRAMES, sprite.name
		])
	return ok


func _object_slug(node_name: String) -> String:
	var slug := node_name.to_lower()
	slug = slug.replace(" ", "_").replace("(", "_").replace(")", "")
	while "__" in slug:
		slug = slug.replace("__", "_")
	return slug.strip_edges().trim_suffix("_")


func _default_output_basename(node_name: String) -> String:
	var slug := _object_slug(node_name)
	return "baked_%s" % slug if not slug.is_empty() else "baked_scribble"


func _output_dir_for(node_name: String) -> String:
	var slug := _object_slug(node_name)
	return "res://obj/%s" % slug if not slug.is_empty() else "res://obj/_unknown"


func _is_headless_no_gpu() -> bool:
	for arg in OS.get_cmdline_args():
		if arg == "--headless":
			return true
	return false


func _resolve_target() -> Sprite2D:
	if target_path != NodePath():
		var n := get_node_or_null(target_path)
		if n is Sprite2D:
			return n
		push_error("bake: target_path is not Sprite2D: %s" % target_path)
		return null

	var main := get_node_or_null("Main")
	if main == null:
		return null

	if not object_name.is_empty():
		var by_name := main.find_child(object_name, true, false)
		if by_name is Sprite2D:
			return by_name
		push_error("bake: no Sprite2D named '%s' under Main" % object_name)
		return null

	return _find_scribble_sprite(main)


func _collect_scribble_sprites(root: Node, out: Array[Sprite2D]) -> void:
	for child in root.get_children():
		if child is Sprite2D:
			var spr := child as Sprite2D
			if _is_scribble_material(spr.material as ShaderMaterial):
				out.append(spr)
		_collect_scribble_sprites(child, out)


func _find_scribble_sprite(root: Node) -> Sprite2D:
	for child in root.get_children():
		if child is Sprite2D:
			var spr := child as Sprite2D
			if _is_scribble_material(spr.material as ShaderMaterial):
				return spr
		var nested := _find_scribble_sprite(child)
		if nested:
			return nested
	return null


func _is_scribble_material(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	var path: String = mat.shader.resource_path
	return path == SHADER_PATH or path.ends_with("hand_drawn_scribble.gdshader")


func _isolate_for_bake(target: Sprite2D) -> void:
	var main := get_node_or_null("Main")
	if main == null:
		return
	_visibility_backup.clear()
	_isolate_node(main, target)


func _isolate_node(node: Node, target: Sprite2D) -> void:
	if node is CanvasItem:
		var ci := node as CanvasItem
		var path := node.get_path()
		if not _visibility_backup.has(path):
			_visibility_backup[path] = ci.visible
		if node is Sprite2D or node is AnimatedSprite2D:
			ci.visible = (node == target)
	for child in node.get_children():
		_isolate_node(child, target)


func _restore_scene_visibility() -> void:
	for path in _visibility_backup:
		var node := get_node_or_null(path)
		if node is CanvasItem:
			(node as CanvasItem).visible = _visibility_backup[path]
	_visibility_backup.clear()


func _ensure_output_dir(dir_path: String) -> bool:
	var abs := ProjectSettings.globalize_path(dir_path)
	if DirAccess.dir_exists_absolute(abs):
		return true
	var err := DirAccess.make_dir_recursive_absolute(abs)
	if err != OK:
		push_error("bake: cannot create dir %s (%s)" % [dir_path, error_string(err)])
		return false
	return true


func _bake(sprite: Sprite2D, out_dir: String, basename: String) -> bool:
	if sprite.texture == null:
		push_error("bake: %s has no texture" % sprite.name)
		return false

	var mat_src := sprite.material as ShaderMaterial
	if mat_src == null:
		push_error("bake: %s has no ShaderMaterial" % sprite.name)
		return false

	if not _ensure_output_dir(out_dir):
		return false

	var tex_size := sprite.texture.get_size()
	var frame_size := Vector2i(
		int(ceil(tex_size.x * absf(sprite.scale.x))) + MARGIN_PX * 2,
		int(ceil(tex_size.y * absf(sprite.scale.y))) + MARGIN_PX * 2
	)
	frame_size.x = maxi(frame_size.x, 8)
	frame_size.y = maxi(frame_size.y, 8)

	var rows := int(ceil(float(FRAMES) / float(COLUMNS)))
	var sheet_size := Vector2i(frame_size.x * COLUMNS, frame_size.y * rows)
	var sheet := Image.create(sheet_size.x, sheet_size.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))

	var subvp := SubViewport.new()
	subvp.size = frame_size
	subvp.transparent_bg = true
	subvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(subvp)

	var clone := Sprite2D.new()
	clone.texture = sprite.texture
	clone.centered = sprite.centered
	clone.flip_h = sprite.flip_h
	clone.flip_v = sprite.flip_v
	clone.scale = sprite.scale
	clone.material = _duplicate_material(mat_src)
	clone.position = Vector2(frame_size) * 0.5
	subvp.add_child(clone)

	var bake_mat := clone.material as ShaderMaterial

	for i in FRAMES:
		var t := DURATION_SEC * float(i) / float(maxi(FRAMES - 1, 1))
		bake_mat.set_shader_parameter("effect_time", t)
		subvp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

		var tex := subvp.get_texture()
		if tex == null:
			push_error("bake: %s frame %d render failed" % [sprite.name, i])
			subvp.queue_free()
			return false
		var img := tex.get_image()
		if img == null or img.is_empty():
			push_error("bake: %s frame %d image empty" % [sprite.name, i])
			subvp.queue_free()
			return false

		var col := i % COLUMNS
		var row := i / COLUMNS
		var dest := Vector2i(col * frame_size.x, row * frame_size.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, frame_size), dest)

	subvp.queue_free()

	var sheet_path := "%s/%s.png" % [out_dir, basename]
	var err := sheet.save_png(sheet_path)
	if err != OK:
		push_error("bake: save png failed %s" % error_string(err))
		return false

	var meta := {
		"columns": COLUMNS,
		"frame_count": FRAMES,
		"rows": rows,
		"fps": FPS,
		"frame_width": frame_size.x,
		"frame_height": frame_size.y,
		"duration_sec": DURATION_SEC,
		"sheet_png": sheet_path,
		"source_node": sprite.name,
	}
	var json_path := "%s/%s.spritesheet.json" % [out_dir, basename]
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf == null:
		push_error("bake: cannot write %s" % json_path)
		return false
	jf.store_string(JSON.stringify(meta, "\t"))
	jf.close()
	return true


func _duplicate_material(src: ShaderMaterial) -> ShaderMaterial:
	var dup := src.duplicate() as ShaderMaterial
	dup.resource_local_to_scene = true
	dup.set_shader_parameter("fade_alpha", 1.0)
	return dup
