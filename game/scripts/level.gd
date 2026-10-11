# Builds a playable level from the extracted assets:
# environment mesh + collision, entities (spawns, windows, debris, wall buys)
# and a navigation mesh baked at load time.
class_name Level
extends Node3D

signal navigation_ready

const UNITS := 1.0 / 400.0

var level_name := ""
var entities := {}          # name -> entity dictionary from entities.json
var _by_lower := {}         # names come from case-insensitive hashes: look them up lower-cased
var windows := []           # Barricade nodes
var debris := []            # Debris nodes (bought to open areas)
var wall_buys := []         # {name, position, weapon, cost}
var boxes := []             # MysteryBox nodes
var player_spawn := Transform3D.IDENTITY
var nav_region: NavigationRegion3D
var static_root: Node3D


func load_level(name: String) -> void:
	level_name = name
	var base := "res://assets/levels/%s/" % name
	for e in JSON.parse_string(FileAccess.get_file_as_string(base + "entities.json")):
		entities[e["name"]] = e
		_by_lower[String(e["name"]).to_lower()] = e

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.25
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.45
	nm.agent_max_slope = 50.0
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nav_region.navigation_mesh = nm
	add_child(nav_region)

	static_root = (load("res://assets/models/levels/%s/environment.glb" % name) as PackedScene).instantiate()
	static_root.name = "Environment"
	nav_region.add_child(static_root)
	_setup_lods(base)
	_prepare_meshes(static_root)

	player_spawn = entity_transform("Player1Spawn")
	_build_windows()
	_build_debris()
	_build_wall_buys()
	_build_boxes()


func bake_navigation() -> void:
	if nav_region.is_baking():
		# a bake is running: bake again once it finishes so the latest geometry is used
		nav_region.bake_finished.connect(bake_navigation, CONNECT_ONE_SHOT)
		return
	var t0 := Time.get_ticks_msec()
	nav_region.bake_finished.connect(func():
		if OS.get_cmdline_user_args().has("--nav-time"):
			print("[nav] bake %d ms" % (Time.get_ticks_msec() - t0))
		navigation_ready.emit(), CONNECT_ONE_SHOT)
	nav_region.bake_navigation_mesh(true)


# ---------------------------------------------------------------- helpers

func entity_transform(name: String, local := false) -> Transform3D:
	var e: Dictionary = entities.get(name, _by_lower.get(name.to_lower(), {}))
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


# ---------------------------------------------------------------- sector LODs
# CIwLODControllerCameraVolume entities show one of their model variants
# depending on the scene sector the camera is in (tools/entities.py).

var _sectors := []         # [{hash, aabb}]
var _lod_groups := []      # [{sectors: {hash: lod}, nodes: [Node3D per lod]}]
var _no_collision := {}    # MeshInstance3D -> true for variants that must not collide
var _lod_timer := 0.0
var _current_sector := ""


func _setup_lods(base: String) -> void:
	var path := base + "sectors.json"
	if FileAccess.file_exists(path):
		for sct in JSON.parse_string(FileAccess.get_file_as_string(path)):
			var lo := Vector3(sct["min"][0], sct["min"][1], sct["min"][2]) * UNITS
			var hi := Vector3(sct["max"][0], sct["max"][1], sct["max"][2]) * UNITS
			_sectors.append({"hash": sct["hash"], "aabb": AABB(lo, hi - lo)})
	for n in entities:
		var lod = entities[n].get("lod")
		if lod == null:
			continue
		var holder := static_root.find_child("ent_" + n, true, false)
		if holder == null:
			continue
		var nodes := []
		var best: Node3D = null
		var best_tris := -1
		for h in lod["lods"]:
			var node := holder.find_child(h, true, false) as Node3D
			nodes.append(node)
			if node == null:
				continue
			var tris := 0
			for mi in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
				for sfc in mi.mesh.get_surface_count():
					tris += mi.mesh.surface_get_array_index_len(sfc) / 3
			if tris > best_tris:
				best_tris = tris
				best = node
		# only the most detailed variant collides; the others are visual stand-ins
		for node in nodes:
			if node != null and node != best:
				for mi in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
					_no_collision[mi] = true
		_lod_groups.append({"sectors": lod["sectors"], "nodes": nodes})
	_update_lods(Vector3(INF, INF, INF))


func _process(delta: float) -> void:
	_lod_timer -= delta
	if _lod_timer > 0.0 or _lod_groups.is_empty():
		return
	_lod_timer = 0.15
	var cam := get_viewport().get_camera_3d()
	if cam:
		_update_lods(cam.global_position)


# Smallest scene sector containing a point ("" outside every sector).
func sector_at(at: Vector3) -> String:
	var best := ""
	var smallest := INF
	for sct in _sectors:
		var box: AABB = sct["aabb"]
		if box.grow(0.05).has_point(at) and box.get_volume() < smallest:
			smallest = box.get_volume()
			best = sct["hash"]
	return best


# True when the point is inside a room (any sector smaller than the whole map).
func is_indoors(at: Vector3) -> bool:
	var s := sector_at(at)
	if s == "":
		return false
	var biggest := 0.0
	for sct in _sectors:
		biggest = maxf(biggest, (sct["aabb"] as AABB).get_volume())
	for sct in _sectors:
		if sct["hash"] == s:
			return (sct["aabb"] as AABB).get_volume() < biggest
	return false


func _update_lods(at: Vector3) -> void:
	# the smallest sector containing the camera (sector_outside contains them all)
	var sector := sector_at(at)
	if sector == _current_sector and sector != "":
		return
	_current_sector = sector
	if OS.get_cmdline_user_args().has("--debug-lod"):
		print("[lod] camera %s sector %s" % [at.snapped(Vector3(0.1, 0.1, 0.1)), sector])
		for grp in _lod_groups:
			print("[lod]   show %d of %s" % [int(grp["sectors"].get(sector, 0)), grp["nodes"].map(func(nd): return "-" if nd == null else String(nd.name))])
	for grp in _lod_groups:
		var lod := int(grp["sectors"].get(sector, 0))
		for i in grp["nodes"].size():
			var node: Node3D = grp["nodes"][i]
			if node:
				node.visible = i == lod


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
					effect = true  # fire, smoke, glows, light shafts, decals, fog cards
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					# vertex colours fade the edges of shafts, glows and fog cards
					mat.vertex_color_use_as_albedo = true
					if blend == "add":
						# emissive effects ignore scene light
						mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
						mat.albedo_color = Color(1, 1, 1, 0.45)
					# alpha-blended decals (bushes, fences, mist) stay lit like the walls around them
			if effect and OS.get_cmdline_user_args().has("--hide-fx"):
				mi.set_surface_override_material(s, _hidden_material())
			if not effect:
				faces.append_array(_surface_faces(mi.mesh, s))
			else:
				_maybe_light_cone(mi, s)
		# collision from the solid surfaces only (a floor with a blood decal must stay solid)
		if not faces.is_empty() and not _no_collision.has(mi):
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			shape.backface_collision = true
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			mi.add_child(body)


# Lamp shafts and glows are flat additive cards (CIwAmbientFader entities) that
# the original turns towards the camera: tall ones around the vertical axis,
# square glows fully.
func _maybe_light_cone(mi: MeshInstance3D, surface: int) -> void:
	var mat := mi.mesh.surface_get_material(surface) as StandardMaterial3D
	if mat == null or mat.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
		return
	var verts: PackedVector3Array = _surface_faces(mi.mesh, surface)
	if verts.is_empty():
		return
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var size := hi - lo
	if minf(size.x, size.z) > 0.05 or (lo + hi).length() / 2 > 3.0:
		return  # not a flat card centred on its entity
	mat.billboard_keep_scale = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if size.y > 1.2 * maxf(size.x, size.z) * 0.5 and size.y > 1.0 else BaseMaterial3D.BILLBOARD_ENABLED


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


func _build_boxes() -> void:
	for n in entities:
		if "CMysteryBoxSpec" in entities[n]["components"]:
			var b := MysteryBox.new()
			b.name = "Box_" + n
			nav_region.add_child(b)
			b.setup(self, n)
			boxes.append(b)


func _build_wall_buys() -> void:
	for n in entities:
		if "CActionBuyWeaponSpec" in entities[n]["components"] and not "CCabinetSpec" in entities[n]["components"]:
			wall_buys.append({"name": n, "position": entity_transform(n).origin})


static var _hidden_mat: StandardMaterial3D


static func _hidden_material() -> StandardMaterial3D:
	if _hidden_mat == null:
		_hidden_mat = StandardMaterial3D.new()
		_hidden_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hidden_mat.albedo_color = Color(0, 0, 0, 0)
	return _hidden_mat
