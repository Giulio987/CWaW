# Builds a playable level from the extracted assets:
# environment mesh + collision, entities (spawns, windows, debris, wall buys)
# and a navigation mesh baked at load time.
class_name Level
extends Node3D

signal navigation_ready
signal power_changed(on: bool)

const UNITS := 1.0 / 400.0
# Floor rebuilt from the original navmesh (CIwNavMesh, tools/navmesh.py) where the
# visible geometry has none: Shi No Numa spawns just past the shore and the plank
# bridges to the balconies. Only zombies and dogs stand on it (and the navmesh bake).
const NAV_FLOOR_LAYER := 64   # layer 7
const NAV_FLOOR_LEVELS := ["shinonuma"]
# Swamp water (Shi No Numa): flat planes at y = 0 with texture 72339cb6. In the original
# the walking surface is the navmesh, which runs 0.3-1 m under the surface (flag 2 and
# flag 0 triangles), so everybody wades: the planes are drawn but do not collide, the
# original triangles under them become a world floor (layer 1: player, zombies, dogs,
# grenades, bullets, navmesh bake). console.bin WaterMoveSpeedModifier = 2048/4096
# (next to MaxWalkMoveSpeed & co, the player's movement settings): the player wades
# at half speed.
const WATER_TEXTURES := ["72339cb6"]
const WATER_MOVE_SPEED := 0.5
const WATER_CELL := 0.5
var water_y := 0.0
var _water_faces := PackedVector3Array()   # world-space triangles of the water planes
var _water_cells := {}                     # Vector2i -> true, the planes' footprint

var level_name := ""
var entities := {}          # name -> entity dictionary from entities.json
var _by_lower := {}         # names come from case-insensitive hashes: look them up lower-cased
var windows := []           # Barricade nodes
var debris := []            # Debris nodes (bought to open areas)
var wall_buys := []         # {name, position, weapon, cost}
var boxes := []             # MysteryBox nodes
var perk_machines := []     # PerkMachine nodes (the power switch included)
var power_on := true        # false until the GeneratorSwitch is used on maps that have one
var player_spawn := Transform3D.IDENTITY
var traps := []             # Trap nodes (CActionBuyTrapSpec)
var interactables := []     # nodes with usable_from(pos) / prompt(player) / interact(player): traps, teleporters, Pack-a-Punch
var teleporters: TeleporterNetwork   # Der Riese
var pack_a_punch: PackAPunch         # Der Riese
var zipline: Zipline                 # Shi No Numa
var nav_region: NavigationRegion3D
var nav_ready := false      # set once the first bake has finished
var static_root: Node3D


func load_level(name: String) -> void:
	level_name = name
	var base := "res://assets/levels/%s/" % name
	# names entities.json only knows by hash, recovered by tools/resolve_names.py
	var aliases := {}
	if FileAccess.file_exists(base + "names.json"):
		aliases = JSON.parse_string(FileAccess.get_file_as_string(base + "names.json"))
	for e in JSON.parse_string(FileAccess.get_file_as_string(base + "entities.json")):
		e["glb_name"] = e["name"]   # environment.glb nodes keep the original "ent_<name>"
		if aliases.has(e["name"]):
			e["name"] = aliases[e["name"]]
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
	_build_perks()
	_build_traps()
	_build_power_doors()
	if has_entity("TeleporterMainFrame"):
		teleporters = TeleporterNetwork.new()
		teleporters.name = "Teleporters"
		nav_region.add_child(teleporters)
		teleporters.setup(self)
	if has_entity("ZipLine") and has_entity("ZiplineDoctorSwitch"):
		zipline = Zipline.new()
		zipline.name = "Zipline"
		add_child(zipline)   # outside the navmesh source: the car moves
		zipline.setup(self)
		interactables.append_array(zipline.interactables())
	if has_entity("packapunch"):
		pack_a_punch = PackAPunch.new()
		pack_a_punch.name = "PackAPunch"
		nav_region.add_child(pack_a_punch)
		pack_a_punch.setup(self, entity("packapunch")["name"])
		interactables.append(pack_a_punch)
	_release_dynamics()


func bake_navigation() -> void:
	if not _nav_floor_done:
		_nav_floor_done = true
		_build_nav_floor()
	if nav_region.is_baking():
		# a bake is running: bake again once it finishes so the latest geometry is used
		if not nav_region.bake_finished.is_connected(bake_navigation):
			nav_region.bake_finished.connect(bake_navigation, CONNECT_ONE_SHOT)
		return
	var t0 := Time.get_ticks_msec()
	nav_region.bake_finished.connect(func():
		if OS.get_cmdline_user_args().has("--nav-time"):
			print("[nav] bake %d ms" % (Time.get_ticks_msec() - t0))
		nav_ready = true
		navigation_ready.emit(), CONNECT_ONE_SHOT)
	nav_region.bake_navigation_mesh(true)


var _nav_floor_done := false


func _is_water(mat: StandardMaterial3D) -> bool:
	return level_name in NAV_FLOOR_LEVELS and mat != null \
		and String(mat.get_meta("extras", {}).get("texture0", "")) in WATER_TEXTURES


# the water planes' footprint on a 0.5 m grid
func _build_water_cells() -> void:
	for i in range(0, _water_faces.size() - 2, 3):
		var a := Vector2(_water_faces[i].x, _water_faces[i].z)
		var b := Vector2(_water_faces[i + 1].x, _water_faces[i + 1].z)
		var c := Vector2(_water_faces[i + 2].x, _water_faces[i + 2].z)
		water_y = _water_faces[i].y
		var lo := (a.min(b).min(c) / WATER_CELL).floor()
		var hi := (a.max(b).max(c) / WATER_CELL).ceil()
		for x in range(int(lo.x), int(hi.x) + 1):
			for z in range(int(lo.y), int(hi.y) + 1):
				var pt := (Vector2(x, z) + Vector2(0.5, 0.5)) * WATER_CELL
				if Geometry2D.point_is_inside_triangle(pt, a, b, c):
					_water_cells[Vector2i(x, z)] = true


# grid cells whose centre a triangle covers
static func _mark_cells(cells: Dictionary, a3: Vector3, b3: Vector3, c3: Vector3) -> void:
	var a := Vector2(a3.x, a3.z)
	var b := Vector2(b3.x, b3.z)
	var c := Vector2(c3.x, c3.z)
	var lo := (a.min(b).min(c) / WATER_CELL).floor()
	var hi := (a.max(b).max(c) / WATER_CELL).ceil()
	for x in range(int(lo.x), int(hi.x) + 1):
		for z in range(int(lo.y), int(hi.y) + 1):
			if Geometry2D.point_is_inside_triangle((Vector2(x, z) + Vector2(0.5, 0.5)) * WATER_CELL, a, b, c):
				cells[Vector2i(x, z)] = true


func _water_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / WATER_CELL), floori(p.z / WATER_CELL))


# under the swamp water (the player wades at WATER_MOVE_SPEED)
func in_water(p: Vector3) -> bool:
	return not _water_cells.is_empty() and p.y < water_y - 0.05 and _water_cells.has(_water_cell(p))


func _add_floor_body(name_: String, faces: PackedVector3Array, layer: int) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = name_
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	nav_region.add_child(body)


# Original navmesh triangles (split to <= 1.5 m) where the world has no surface within
# 0.3 m of the original height (plank bridges and stairs drawn with blended materials,
# which get no collision, ground past the edge of the visible terrain) become a
# zombie-only floor 5 cm below the original height. Flags: 4 stairs and ramps, always
# kept and lifted 15 cm (a smooth ramp over steps too tall for the bake), 2 under the
# swamp water. Triangles under the water planes become the swamp bed instead (layer 1).
# Needs the world colliders in the physics space (called on the first bake).
func _build_nav_floor() -> void:
	if not level_name in NAV_FLOOR_LEVELS:
		return
	var path := "res://assets/levels/%s/navmesh.json" % level_name
	if not FileAccess.file_exists(path):
		return
	_build_water_cells()
	var zombie_floor := not OS.get_cmdline_user_args().has("--no-nav-floor")
	var tris: Array = JSON.parse_string(FileAccess.get_file_as_string(path))["tris"]
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var faces := PackedVector3Array()
	var bed := PackedVector3Array()
	var bed_cells := {}
	var stack: Array = []
	for t in tris:
		stack.append([Vector3(t[0], t[1], t[2]), Vector3(t[3], t[4], t[5]), Vector3(t[6], t[7], t[8]), int(t[9]) == 4, int(t[9]) == 2])
	while not stack.is_empty():
		var tri: Array = stack.pop_back()
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var ab := a.distance_to(b)
		var bc := b.distance_to(c)
		var ca := c.distance_to(a)
		var longest := maxf(ab, maxf(bc, ca))
		if longest > 1.5:
			# split the longest edge
			if longest == ab:
				var m := (a + b) * 0.5
				stack.append([a, m, c, tri[3], tri[4]]); stack.append([m, b, c, tri[3], tri[4]])
			elif longest == bc:
				var m := (b + c) * 0.5
				stack.append([a, b, m, tri[3], tri[4]]); stack.append([a, m, c, tri[3], tri[4]])
			else:
				var m := (c + a) * 0.5
				stack.append([a, b, m, tri[3], tri[4]]); stack.append([m, b, c, tri[3], tri[4]])
			continue
		var p := (a + b + c) / 3.0
		if in_water(p):
			# swamp bed: everybody's floor
			for v in [a, b, c]:
				bed.append(v)
			_mark_cells(bed_cells, a, b, c)
			continue
		if tri[4]:
			continue   # flag 2 outside the water footprint
		q.from = p + Vector3.UP * 0.3
		q.to = p - Vector3.UP * 0.3
		if not tri[3] and not space.intersect_ray(q).is_empty():
			continue
		if not tri[3] and p.y < water_y + 1.0 and _water_cells.has(_water_cell(p)):
			# banks and mounds in the swamp the visible ground has no collision for
			for v in [a, b, c]:
				bed.append(v)
			_mark_cells(bed_cells, a, b, c)
			continue
		if not zombie_floor:
			continue
		# stairs: the original ramp cuts the step nosings, lift it clear of them
		for v in [a, b, c]:
			faces.append(v + Vector3.UP * (0.15 if tri[3] else -0.05))
	# water the original navmesh does not reach (behind fences, under huts, past the
	# edges): a floor below the deepest bed where the world has nothing either, so
	# nobody falls through
	var holes := PackedVector3Array()
	var deep := water_y - 1.25
	for cell: Vector2i in _water_cells:
		if bed_cells.has(cell):
			continue
		var c0 := Vector3(cell.x, 0, cell.y) * WATER_CELL
		q.from = c0 + Vector3(WATER_CELL * 0.5, water_y + 1.2, WATER_CELL * 0.5)
		q.to = q.from + Vector3.DOWN * 3.0
		if not space.intersect_ray(q).is_empty():
			continue
		var c1 := c0 + Vector3(WATER_CELL, 0, 0)
		var c2 := c0 + Vector3(WATER_CELL, 0, WATER_CELL)
		var c3 := c0 + Vector3(0, 0, WATER_CELL)
		for v in [c0, c1, c2, c0, c2, c3]:
			holes.append(Vector3(v.x, deep, v.z))
	if not bed.is_empty() or not holes.is_empty():
		bed.append_array(holes)
		_add_floor_body("SwampBed", bed, 1)
		print("[level] swamp bed: %d triangles from the original navmesh, %d filler cells" % [(bed.size() - holes.size()) / 3, holes.size() / 6])
	if faces.is_empty():
		return
	_add_floor_body("NavFloor", faces, NAV_FLOOR_LAYER)
	print("[level] nav floor: %d triangles from the original navmesh" % (faces.size() / 3))


# Await the first navmesh bake; returns at once if it already finished (a test that
# starts awaiting navigation_ready after a fast bake would otherwise wait forever).
func wait_navigation() -> void:
	if not nav_ready:
		await navigation_ready


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


# A transform stored with the identity quaternion keeps quarter turns about Y in the
# byte after it (tools/entities.py "flags"): 0x10 = -90°, 0x04 = 180°. Measured on the
# debris, whose doors and frames fill their doorways only with these turns (and whose
# colliders turn with them). Only Debris uses it so far: other entities are placed
# and tuned without it.
static func flag_transform(xf: Dictionary) -> Transform3D:
	var t := _to_transform(xf)
	var f = xf.get("flags")
	if f == null:
		return t
	var yaw := 0.0
	if int(f) & 0x10:
		yaw -= PI / 2
	if int(f) & 0x04:
		yaw += PI
	return Transform3D(Basis(Vector3.UP, yaw) * t.basis, t.origin)


func has_entity(name: String) -> bool:
	return entities.has(name) or _by_lower.has(name.to_lower())


func entity(name: String) -> Dictionary:
	return entities.get(name, _by_lower.get(name.to_lower(), {}))


# A static (unrigged) model by hash from the level's dynamics.glb, or a rigged one
# from characters/levels/<level>/dynamics; null when neither exists.
var _dyn_scene: Node


func dynamics_model(h: String) -> Node3D:
	var rigged := "res://assets/characters/levels/%s/dynamics/%s.glb" % [level_name, h]
	if ResourceLoader.exists(rigged):
		return (load(rigged) as PackedScene).instantiate()
	if _dyn_scene == null:
		var path := "res://assets/models/levels/%s/dynamics.glb" % level_name
		if not ResourceLoader.exists(path):
			return null
		_dyn_scene = (load(path) as PackedScene).instantiate()
	var n := _dyn_scene.find_child(h, true, false) as Node3D
	if n == null:
		return null
	var copy := n.duplicate() as Node3D
	copy.transform = Transform3D.IDENTITY
	return copy


func _release_dynamics() -> void:
	if _dyn_scene:
		_dyn_scene.free()
		_dyn_scene = null


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
static var ORIG_LODS := OS.get_cmdline_user_args().has("--orig-lods")
# Sky dome (Der Riese, Shi No Numa): a 6 m dome at the origin (entity 1bf48c85) the
# original draws around the camera. No collision, scaled up and kept on the camera.
const SKY_ENTITY := "ent_1bf48c85"
const SKY_SCALE := 60.0
var _sky: Node3D


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
		var holder := static_root.find_child("ent_" + String(entities[n].get("glb_name", n)), true, false)
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
		_lod_groups.append({"sectors": lod["sectors"], "nodes": nodes, "best": nodes.find(best)})
	_update_lods(Vector3(INF, INF, INF))


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if _sky and cam:
		_sky.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * SKY_SCALE), cam.global_position + Vector3.DOWN * 0.5 * SKY_SCALE)
	_lod_timer -= delta
	if _lod_timer > 0.0 or _lod_groups.is_empty():
		return
	_lod_timer = 0.15
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
		# The variants of the original are cut to what an armv6 phone could draw from each
		# sector, and they leave holes near sector borders (Verrückt's stair landing sees
		# the upper floor cut away). The most detailed one is always shown, unless
		# --orig-lods asks for the original switching.
		var lod: int = int(grp["sectors"].get(sector, 0)) if ORIG_LODS else grp["best"]
		for i in grp["nodes"].size():
			var node: Node3D = grp["nodes"][i]
			if node:
				node.visible = i == lod


func _prepare_meshes(root: Node) -> void:
	var sky := root.find_child(SKY_ENTITY, true, false) as Node3D
	if sky:
		_sky = sky
		for mi in sky.find_children("*", "MeshInstance3D", true, false) + ([sky] if sky is MeshInstance3D else []):
			_no_collision[mi] = true
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
				if mat:
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var faces := PackedVector3Array()
		var see_through := PackedVector3Array()   # upright cut-out surfaces (window grids, fences)
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
			if not effect and _is_water(mat):
				var xf: Transform3D = mi.global_transform
				for v in _surface_faces(mi.mesh, s):
					_water_faces.append(xf * v)
			elif not effect and mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				# the holes of window grids and fences let bullets through: their upright
				# faces only block bodies (layer 4, like the window blockers); flat ones
				# stay solid so grenades do not fall through grated floors
				var fs := _surface_faces(mi.mesh, s)
				for k in range(0, fs.size() - 2, 3):
					var nrm := (fs[k + 1] - fs[k]).cross(fs[k + 2] - fs[k]).normalized()
					var dst := see_through if absf((mi.global_basis * nrm).normalized().y) < 0.5 else faces
					dst.append(fs[k])
					dst.append(fs[k + 1])
					dst.append(fs[k + 2])
			elif not effect:
				faces.append_array(_surface_faces(mi.mesh, s))
			else:
				if OS.get_cmdline_user_args().has("--debug-fx"):
					var vs := _surface_faces(mi.mesh, s)
					if not vs.is_empty():
						var box := AABB(mi.global_transform * vs[0], Vector3.ZERO)
						for v in vs:
							box = box.expand(mi.global_transform * v)
						print("[fx] %s/%d blend %s tex %s centre %s size %s tris %d" % [mi.name, s, mat.get_meta("extras", {}).get("blend", ""), mat.get_meta("extras", {}).get("texture0", ""), box.get_center().snapped(Vector3(0.01, 0.01, 0.01)), box.size.snapped(Vector3(0.01, 0.01, 0.01)), vs.size() / 3])
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
		if not see_through.is_empty() and not _no_collision.has(mi):
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(see_through)
			shape.backface_collision = true
			var body := StaticBody3D.new()
			body.name = "SeeThrough"
			body.collision_layer = 4
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			mi.add_child(body)


const LAMP_CONE_ALPHA := 0.32
const SHAFT_SHADER := "res://shaders/light_shaft.gdshader"


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
		# not a flat card centred on its entity: a big fixed shaft (window beams) fades
		# when seen edge-on or from close by, so it does not look like a flat sheet
		if maxf(size.y, maxf(size.x, size.z)) > 2.0 and mat.albedo_texture:
			var sm := ShaderMaterial.new()
			sm.shader = load(SHAFT_SHADER)
			sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
			mi.set_surface_override_material(surface, sm)
		return
	if OS.get_cmdline_user_args().has("--debug-cones"):
		print("[cone] %s at %s size %s tex %s" % [mi.name, mi.global_position.snapped(Vector3(0.01, 0.01, 0.01)), size.snapped(Vector3(0.01, 0.01, 0.01)), mat.get_meta("extras", {}).get("texture0", "")])
	if size.y > 1.0:
		mat.albedo_color.a = LAMP_CONE_ALPHA   # lamp cones a little dimmer than the other glows
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
	# one active box per map, like the original; the teddy bear moves it to the
	# other locations (mystery_box.gd)
	var all := entities.keys().filter(func(n): return "CMysteryBoxSpec" in entities[n]["components"])
	var names := [all.pick_random()] if all.size() > 1 else all
	var forced := OS.get_cmdline_user_args().find("--box-at")   # tests: start at this location
	if forced >= 0 and OS.get_cmdline_user_args()[forced + 1] in all:
		names = [OS.get_cmdline_user_args()[forced + 1]]
	for n in names:
		if true:
			var b := MysteryBox.new()
			b.name = "Box"
			b.locations = all
			nav_region.add_child(b)
			b.setup(self, n)
			boxes.append(b)


# Perk-a-Cola machines. Maps with a GeneratorSwitch (Der Riese, Verrückt) need the
# power on first (--power starts with it on). Shi No Numa has one entity per perk at
# each of its four locations: each location shows a different perk, picked at random
# (the original cycles them in shinonuma.lua).
func _build_perks() -> void:
	var by_place := {}   # rounded position -> [entity names]
	for n in entities:
		if "CActionBuyPerkSpec" in entities[n]["components"] and Perks.kind_of(entities[n]) != "":
			var key := str(entity_transform(n).origin.snapped(Vector3(0.5, 0.5, 0.5)))
			if not by_place.has(key):
				by_place[key] = []
			by_place[key].append(n)
	var keys := by_place.keys()
	keys.sort()
	var order: Array = Perks.ORDER.duplicate()
	order.shuffle()
	for i in keys.size():
		var names: Array = by_place[keys[i]]
		names.sort()
		var pick: String = names[0]
		if names.size() > 1:
			for n in names:
				if Perks.kind_of(entities[n]) == order[i % order.size()]:
					pick = n
		_add_perk_machine(pick, Perks.kind_of(entities[pick]))
	var switch: Dictionary = _by_lower.get("generatorswitch", {})
	if not perk_machines.is_empty() and not switch.is_empty() and "CActionScriptableSpec" in switch["components"]:
		power_on = OS.get_cmdline_user_args().has("--power")
		_add_perk_machine(switch["name"], "power")
	PerkMachine.release_cache()


func _add_perk_machine(entity: String, kind: String) -> void:
	var m := PerkMachine.new()
	m.name = "Perk_" + entity
	nav_region.add_child(m)
	m.setup(self, entity, kind)
	perk_machines.append(m)


# Doors the generator opens (TurnOnGenerator "genTurnOn"): Verrückt's StartDoorLink
# keeps the German and American halves apart until the power is on. Built as a
# Debris that is not for sale (its collider blocks, power plays the opening).
const POWER_DOORS := ["StartDoorLink"]


func _build_power_doors() -> void:
	if power_on:
		return
	for n in POWER_DOORS:
		if not has_entity(n):
			continue
		var d := Debris.new()
		d.name = "PowerDoor_" + n
		nav_region.add_child(d)
		d.setup(self, entity(n)["name"])
		power_changed.connect(func(on: bool):
			if on and is_instance_valid(d):
				d.open()
				await get_tree().physics_frame
				await get_tree().physics_frame
				bake_navigation())


func _build_traps() -> void:
	for n in entities:
		var comps: Array = entities[n]["components"]
		if "CActionBuyTrapSpec" in comps and not "CZiplineSpec" in comps:
			var t := Trap.new()
			t.name = "Trap_" + n
			nav_region.add_child(t)
			t.setup(self, n)
			traps.append(t)
			interactables.append(t)


func turn_on_power() -> void:
	if power_on:
		return
	power_on = true
	power_changed.emit(true)
	Sfx.instance.play("pa_power_on")
	for m in perk_machines:
		if m.kind != "power":
			Sfx.instance.play_at(Sfx.iw_hash("perkpoweron"), m.global_position + Vector3.UP, -4.0)


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
