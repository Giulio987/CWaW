# Builds a playable level from the extracted assets:
# environment mesh + collision, entities (spawns, windows, debris, wall buys)
# and a navigation mesh baked at load time.
class_name Level
extends Node3D

signal navigation_ready

const UNITS := 1.0 / 400.0

var level_name := ""
var entities := {}          # name -> entity dictionary from entities.json
var windows := []           # Barricade nodes
var debris := []            # Debris nodes (bought to open areas)
var wall_buys := []         # {name, position, weapon, cost}
var player_spawn := Transform3D.IDENTITY
var nav_region: NavigationRegion3D
var static_root: Node3D


func load_level(name: String) -> void:
	level_name = name
	var base := "res://assets/levels/%s/" % name
	for e in JSON.parse_string(FileAccess.get_file_as_string(base + "entities.json")):
		entities[e["name"]] = e

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.35
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.45
	nm.agent_max_slope = 50.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nav_region.navigation_mesh = nm
	add_child(nav_region)

	static_root = (load("res://assets/models/levels/%s/environment.glb" % name) as PackedScene).instantiate()
	static_root.name = "Environment"
	nav_region.add_child(static_root)
	_prepare_meshes(static_root)

	player_spawn = entity_transform("Player1Spawn")
	_build_windows()
	_build_debris()
	_build_wall_buys()


func bake_navigation() -> void:
	if nav_region.is_baking():
		# a bake is running: bake again once it finishes so the latest geometry is used
		nav_region.bake_finished.connect(bake_navigation, CONNECT_ONE_SHOT)
		return
	nav_region.bake_finished.connect(func(): navigation_ready.emit(), CONNECT_ONE_SHOT)
	nav_region.bake_navigation_mesh(true)


# ---------------------------------------------------------------- helpers

func entity_transform(name: String, local := false) -> Transform3D:
	var e: Dictionary = entities.get(name, {})
	if e.is_empty():
		push_warning("missing entity " + name)
		return Transform3D.IDENTITY
	var xf: Dictionary = e["transform"]
	var t := _to_transform(xf)
	if local and not e["children"].is_empty():
		t = t * _to_transform(e["children"][-1])
	return t


static func _to_transform(xf: Dictionary) -> Transform3D:
	var p: Array = xf["pos"]
	var q: Array = xf["rot_wxyz"]
	return Transform3D(Basis(Quaternion(q[1], q[2], q[3], q[0]).normalized()),
		Vector3(p[0], p[1], p[2]) * UNITS)


func entities_matching(prefix: String) -> Array:
	var out := []
	for n in entities:
		if n.to_lower().begins_with(prefix.to_lower()):  # names come from case-insensitive hashes
			out.append(n)
	out.sort()
	return out


func _prepare_meshes(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var faces := PackedVector3Array()
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			var effect := false
			if mat != null:
				_apply_lightmap(mat)
				var blend: String = mat.get_meta("extras", {}).get("blend", "")
				if blend != "":
					effect = true  # fire, smoke, glows, light shafts, fog cards
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					# vertex colours fade the edges of shafts and glows; keep them subtle
					mat.vertex_color_use_as_albedo = true
					if blend == "add":
						mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
						mat.albedo_color = Color(1, 1, 1, 0.45)
			if not effect:
				faces.append_array(_surface_faces(mi.mesh, s))
		# collision from the solid surfaces only (a floor with a blood decal must stay solid)
		if not faces.is_empty():
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			shape.backface_collision = true
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			mi.add_child(body)


static func _surface_faces(mesh: Mesh, surface: int) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	var idx = arrays[Mesh.ARRAY_INDEX]
	if idx == null or (idx as PackedInt32Array).is_empty():
		return verts
	for i in idx:
		out.append(verts[i])
	return out


func _apply_lightmap(mat: StandardMaterial3D) -> void:
	if not mat.has_meta("extras"):
		return
	var extras: Dictionary = mat.get_meta("extras")
	if not extras.has("lightmap"):
		return
	var path: String = "res://assets/models/levels/%s/%s" % [level_name, extras["lightmap"]]
	path = path.simplify_path()
	if not ResourceLoader.exists(path):
		return
	mat.detail_enabled = true
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	mat.detail_albedo = load(path)
	mat.detail_mask = null


func _build_windows() -> void:
	for n in entities:
		if "CBarricadeSpec" in entities[n]["components"]:
			var w := Barricade.new()
			w.name = n
			add_child(w)
			w.setup(self, n)
			windows.append(w)


func _build_debris() -> void:
	# entities that are bought to open a link between areas (Lua Script.Level.Links)
	for n in entities:
		var comps: Array = entities[n]["components"]
		if "CActionBuySpec" in comps and "CAnimatedScenerySpec" in comps:
			var d := Debris.new()
			d.name = n
			nav_region.add_child(d)
			d.setup(self, n)
			debris.append(d)


func _build_wall_buys() -> void:
	for n in entities:
		if "CActionBuyWeaponSpec" in entities[n]["components"] and not "CCabinetSpec" in entities[n]["components"]:
			wall_buys.append({"name": n, "position": entity_transform(n).origin})
