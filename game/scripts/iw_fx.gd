# One model of the original effects group (assets/models/ingame/effects.glb) drawn as
# the game draws it: additive, unlit, vertex colours (the cards fade their ends with
# them), the material's texture cel animation (tools/material_cels.py: the offset of
# cel k, (k % numU * w, k / numU * h) texels, is added to the UVs every `period` ticks
# of 30 Hz; the arcs' 43266a5b scrolls its bolt sheet 32 texels per tick), and the
# entity's billboard flags (tools/ent_fx.py: 0x04 faces the camera, 0x08 turns about
# the up axis). Colour: every material used here has diffuse 0x80 (half), as the
# Wunderwaffe's sparks (wunderwaffe.gd SPARK_COLOR).
#
# Also loads tools/ent_fx.py's data: levels/<map>/ent_fx.json (template instances,
# nested child entities, ambient faders) and effect_specs.json (the effects group's
# CIwSpecLists: lifetime and the entities they spawn).
class_name IwFx
extends MeshInstance3D

const EFFECTS_GLB := "res://assets/models/ingame/effects.glb"
const CEL_TICKS := 30.0
const DIFFUSE := 128.0 / 255.0
const FLAG_BILLBOARD := 0x04
const FLAG_BILLBOARD_AXIS := 0x08

static var _meshes := {}
static var _cels := {}
static var _level_fx := {}
static var _specs := {}

var alpha := 1.0:
	set(v):
		alpha = v
		for m in _mats:
			(m[0] as StandardMaterial3D).albedo_color.a = v
var _mats := []      # [material, cel [num, numU, w, h, period] or null, texture size]
var _shown := -1


static func effect_mesh(h: String) -> Mesh:
	if not _meshes.has(h):
		var mesh: Mesh = null
		var scene := load(EFFECTS_GLB) as PackedScene
		if scene:
			var root := scene.instantiate()
			var mi := root.find_child(h, true, false) as MeshInstance3D
			if mi:
				mesh = mi.mesh
			root.free()
		_meshes[h] = mesh
	return _meshes[h]


static func make(model: String, flags := 0, color := DIFFUSE) -> IwFx:
	if _cels.is_empty() and FileAccess.file_exists("res://assets/material_cels.json"):
		_cels = JSON.parse_string(FileAccess.get_file_as_string("res://assets/material_cels.json"))
	var fx := IwFx.new()
	fx.name = "Fx_" + model
	fx.mesh = effect_mesh(model)
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fx.mesh == null:
		return fx
	for s in fx.mesh.get_surface_count():
		var src := fx.mesh.surface_get_material(s) as StandardMaterial3D
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(color, color, color, 1.0)
		if flags & FLAG_BILLBOARD:
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		elif flags & FLAG_BILLBOARD_AXIS:
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		var size := Vector2.ONE
		if src:
			m.albedo_texture = src.albedo_texture
			if src.albedo_texture:
				size = Vector2(src.albedo_texture.get_width(), src.albedo_texture.get_height())
		fx.set_surface_override_material(s, m)
		var cel = _cels.get(String(src.resource_name)) if src else null
		fx._mats.append([m, cel if cel is Array and int(cel[0]) > 1 else null, size])
	return fx


func _process(_delta: float) -> void:
	var tick := int(Time.get_ticks_msec() * CEL_TICKS / 1000.0)
	if tick == _shown:
		return
	_shown = tick
	for a in _mats:
		var cel = a[1]
		if cel == null:
			continue
		var k := (tick / maxi(int(cel[4]), 1)) % int(cel[0])
		var num_u := maxi(int(cel[1]), 1)
		var ofs := Vector2((k % num_u) * float(cel[2]), (k / num_u) * float(cel[3])) / (a[2] as Vector2)
		(a[0] as StandardMaterial3D).uv1_offset = Vector3(fposmod(ofs.x, 1.0), fposmod(ofs.y, 1.0), 0.0)


# tools/ent_fx.py output for a level ({} when missing)
static func level_data(level_name: String) -> Dictionary:
	if not _level_fx.has(level_name):
		var p := "res://assets/levels/%s/ent_fx.json" % level_name
		_level_fx[level_name] = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else {}
	return _level_fx[level_name]


# CIwAmbientFaderSpec of the entity a level card belongs to (light shafts, lamp beams,
# glows; tools/ent_fx.py "faders"): its alpha follows the camera's distance from the
# entity, min alpha up to `near`, max from `far`, linear in the squared distance between
# (kiwi va 0x162ee8; every fader of the four maps: min 0-25 / 255, max 255, near
# 0.75-2.5 m, far 6.25-7.5 m, none inverted). The shaft shader (light_shaft.gdshader)
# does it exactly; a billboard glow (StandardMaterial3D) gets Godot's distance fade
# (linear in the distance, from 0). Returns false when the card has no fader.
static func apply_fader(level_name: String, mi: MeshInstance3D, mat: Material) -> bool:
	var faders: Dictionary = level_data(level_name).get("faders", {})
	var f = faders.get(String(mi.name))
	if f == null and mi.get_parent():
		f = faders.get(String(mi.get_parent().name).trim_prefix("ent_"))
	if not (f is Dictionary):
		return false
	var origin: Vector3 = (mi.get_parent() as Node3D).global_position if mi.get_parent() is Node3D else mi.global_position
	var near := float(f["near"])
	var far := float(f["far"])
	var lo := float(f["min"]) / 255.0
	var hi := float(f["max"]) / 255.0
	if int(f.get("invert", 0)) != 0:
		var t := lo
		lo = hi - lo
		hi = hi - t
	if mat is ShaderMaterial:
		mat.set_shader_parameter("fader_on", true)
		mat.set_shader_parameter("fader_origin", origin)
		mat.set_shader_parameter("fader_near2", near * near)
		mat.set_shader_parameter("fader_far2", far * far)
		mat.set_shader_parameter("fader_min", lo)
		mat.set_shader_parameter("fader_max", hi)
	elif mat is StandardMaterial3D and far > near:
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		mat.distance_fade_min_distance = near
		mat.distance_fade_max_distance = far
	if OS.get_cmdline_user_args().has("--debug-cones"):
		print("[fader] %s near %.2f far %.2f alpha %.2f-%.2f %s" % [mi.name, near, far, lo, hi, mat.get_class()])
	return true


static func spec_lists() -> Dictionary:
	if _specs.is_empty() and FileAccess.file_exists("res://assets/effect_specs.json"):
		_specs = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effect_specs.json"))
	return _specs
