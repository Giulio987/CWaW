# Effect materials of the first-person weapon models (child of the weapon, viewmodel.gd).
# The glTF export (tools/export_gltf.py) marks additive only the materials whose texture is
# mostly transparent; a byte-3 = 2 (additive) material on a mostly black sheet stays opaque
# and draws black. Here byte 3 = 2 with a texture cel animation (tools/material_cels.py), or
# the export's "add", becomes additive, unshaded, vertex-coloured, and the cels play.
# Wunderwaffe (f8b1223d, 83a84399, f8b6d772): the bulb's bolt material e3bb8b55 / 56e3b94a,
# texture 2bcadef2 (4 x 2 bolt frames on black), cels [8, 4 per row, 64 x 64 texels, period 2]:
# its vertices fade the bolt to black (vertex colour 0). The cel size is in a 256 x 128 sheet
# while the PNG is 512 x 256, so the offset is one cel of the 4 x 2 grid (1/4, 1/2), not
# texels / PNG size. The DG-3 uses the same model and the same bolt (its material set has the
# same texture), so the bulb does not change colour.
extends Node

const CEL_TICKS := 30.0   # as level.gd: the game's 30 Hz update
static var _cels := {}

var _anims := []          # [material, cel, shown]


static func apply(weapon: Node) -> void:
	var n = load("res://scripts/weapon_materials.gd").new()
	n.name = "WeaponMaterials"
	weapon.add_child(n)
	n._fix(weapon)


func _fix(weapon: Node) -> void:
	if _cels.is_empty() and FileAccess.file_exists("res://assets/material_cels.json"):
		_cels = JSON.parse_string(FileAccess.get_file_as_string("res://assets/material_cels.json"))
	var done := {}
	for mi: MeshInstance3D in weapon.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null or not mat.has_meta("extras"):
				continue
			var ex: Dictionary = mat.get_meta("extras")
			var cel = _cels.get(String(mat.resource_name))
			var additive: bool = ex.get("blend", "") == "add" or (String(ex.get("iw_flags", "")).substr(6, 2) == "02" and cel != null)
			if not additive:
				continue
			if not done.has(mat):
				var m := mat.duplicate() as StandardMaterial3D
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				m.vertex_color_use_as_albedo = true
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				done[mat] = m
				if cel != null and int(cel[0]) > 1:
					_anims.append([m, cel, -1])
			mi.set_surface_override_material(s, done[mat])


func _process(_delta: float) -> void:
	var tick := int(Time.get_ticks_msec() * CEL_TICKS / 1000.0)
	for a in _anims:
		var cel: Array = a[1]
		var num := int(cel[0])
		var num_u := maxi(int(cel[1]), 1)
		var k := (tick / maxi(int(cel[4]), 1)) % num
		if k == a[2]:
			continue
		a[2] = k
		var rows := int(ceil(float(num) / num_u))
		(a[0] as StandardMaterial3D).uv1_offset = Vector3(float(k % num_u) / num_u, float(k / num_u) / rows, 0.0)
