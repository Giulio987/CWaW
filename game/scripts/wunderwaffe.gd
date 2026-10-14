# Wunderwaffe DG-2 (Shi No Numa / Der Riese), as in the original iOS game:
#
# Gun (CItemGun "wunderwaffe", tools/weapon_stats.py): 3 shots + 24 spare, 0.599 s per shot,
# 5.5 s reload; the "_upgrade" gun (Wunderwaffe DG-3 JZ, Pack-a-Punch) 6 + 30, 4.714 s.
# It fires a projectile (CItemGun 0x88: CIwEntSpec 44b05373, upgraded 7474262e) whose
# CProjectileSpec is byte for byte the Ray Gun's (same speed / flags: RaygunBolt.SPEED);
# only the entity spawned on impact differs: b5df66a3 (upgraded 15c8ab5e), a
# CRadialEffectWunderwaffe. Its spec (CRadialEffectWunderwaffeSpec::Serialise, kiwi va
# 0x1ed698, after the CRadialEffectSpec base at va 0x18f328):
#   base 0x14  duration ms           1000   (upgraded 1500)
#   base 0x18  growth, units/s       1600   (2000)       -> radius = growth x elapsed
#   base 0x1c  stat category         "wunderwaffe"
#        0x3c  gun                   wunderwaffe (kill credit)
#        0x40  damage type           6      (6 = electric; the zombie's dismemberment mask 0xc1 has it)
#        0x44  fizzle radius, units  600    (2000)
#        0x48  damage flag           0
#        0x4c  max kills             10     (10)
# Update (kiwi va 0x1d9f2c / 0x1da270, base 0x148ac0): every frame the sphere grows; every
# zombie or dog whose origin is inside it, with nothing solid in between (0x1da2b8 traces
# from the centre), is hit once with damage = its whole health (0x10f2f4 gets the target's
# health as the amount: an instant kill at any round) until 10 are dead; the hit points
# are kept (centre first, then each victim) for the arcs. If nothing has been killed when
# the radius reaches the fizzle radius (1.5 m, upgraded 5 m) the effect ends early; else
# it lasts its duration: 4 m of reach (upgraded 7.5 m). At the end the base effect writes
# the "<category>.zombieskillssimu" / "dogskillssimu" stats (kiwi va 0x148a00), used by the
# "Face Melter" achievement (8 zombies with one shot).
# Not decoded (drawn here by eye): the renderable streak of the projectile
# (CRenderableEffectWunderwaffe, kiwi va 0x1edc00: a beam stretched from the previous to the
# current position), the arcs between the hit points, the victims' electrocution (an
# effect hung on the zombie, kiwi va 0x13af84) and the impact sound (the dogs' lightning,
# dog_spawn, stands in). The effects group has the electric textures in blue / pink pairs
# (pink = the upgraded gun, as the Ray Gun's green / red): 371a697e / a944f9de thin bolt,
# 82f40e26 / dd30b286 crackle sprites (4x2), plus 7fef4319 (four bolt strips), fda76742
# (a beam with sparks: the projectile streak), d7e401dc (blue-white flash).
extends Node3D

const SPEED := RaygunBolt.SPEED
const U := 400.0   # world units per metre
# [duration s, growth m/s, fizzle radius m, max kills]
const RADIAL := {false: [1000.0 / 1000.0, 1600.0 / U, 600.0 / U, 10],
	true: [1500.0 / 1000.0, 2000.0 / U, 2000.0 / U, 10]}
# textures (assets/textures/ingame/effects), [normal, upgraded]
const ARC_TEX := ["7fef4319", "a944f9de"]      # arcs: four 8:1 bolt strips / one 2:1 bolt
const CRACKLE_TEX := ["82f40e26", "dd30b286"]  # 4x2 sheet of little sparks
const STREAK_TEX := "fda76742"                 # 4:1 beam with sparks
const FLASH_TEX := "d7e401dc"
const DOT_TEX := "2b12c691"                    # white glow
const COLOR := Color(0.55, 0.65, 1.0)
const COLOR_UP := Color(1.0, 0.45, 0.85)

var player: Player
var upgraded := false
var max_range := 100.0

var _dir := Vector3.FORWARD
var _from := Vector3.ZERO
var _travelled := 0.0
var _visual_offset := Vector3.ZERO
var _trail := []          # recent visual positions (streak)
var _done := false
var _glow: Node3D
var _streak: MeshInstance3D

# radial effect
var _radial := false
var _t := 0.0
var _hit := {}            # zombie -> true
var _nodes := []          # hit points: centre first, then victims (kiwi: array at member 0x30)
var _kills := 0
var _dog_kills := 0
var _arcs: MeshInstance3D
var _arc_t := 0.0
var _arc_row := 0
var _fade := 0.0


static func fire(p: Player, w: Dictionary, s: Dictionary, cam: Camera3D) -> void:
	var b = load("res://scripts/wunderwaffe.gd").new()
	b.player = p
	b.upgraded = bool(w.get("upgraded", false))
	b.max_range = float(s.get("range", 100.0))
	p.game.add_child(b)
	b.launch(cam.global_position, p._viewmodel.muzzle_position(), -cam.global_basis.z)


func color() -> Color:
	return COLOR_UP if upgraded else COLOR


func launch(eye: Vector3, muzzle: Vector3, dir: Vector3) -> void:
	_dir = dir.normalized()
	_from = eye
	global_position = eye
	_visual_offset = muzzle - eye
	_glow = Node3D.new()
	add_child(_glow)
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := WeaponFx.sprite_mat(FLASH_TEX, true, false).duplicate() as StandardMaterial3D
	m.albedo_color = color().lightened(0.3)
	q.material = m
	var ball := MeshInstance3D.new()
	ball.mesh = q
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.add_child(ball)
	var core := MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.2, 0.2)
	q2.material = WeaponFx.sprite_mat(DOT_TEX, true, false)
	core.mesh = q2
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.add_child(core)
	var l := OmniLight3D.new()
	l.light_color = color()
	l.light_energy = 2.5
	l.omni_range = 3.5
	l.light_cull_mask = ~Viewmodel.LAYER
	_glow.add_child(l)
	_streak = _strip_node(STREAK_TEX)
	_place_visual()


func _place_visual() -> void:
	var k := clampf(1.0 - _travelled / 6.0, 0.0, 1.0)
	_glow.position = _visual_offset * k
	_trail.push_front(_glow.global_position)
	if _trail.size() > 4:
		_trail.pop_back()


func _physics_process(delta: float) -> void:
	if _radial:
		_update_radial(delta)
		return
	if _done:
		return
	var to := global_position + _dir * SPEED * delta
	var q := PhysicsRayQueryParameters3D.create(_from, to, 1 | 2)
	if player and is_instance_valid(player):
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_impact(hit)
		return
	global_position = to
	_from = to
	_travelled += SPEED * delta
	_place_visual()
	if _travelled > max_range:
		queue_free()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _streak and not _done and _trail.size() >= 2:
		_build_strip(_streak, [_trail[_trail.size() - 1], _trail[0]], 0.3, cam.global_position, 0, 1, 4.0)
	if _arcs:
		_arc_t -= delta
		if _arc_t <= 0.0:   # the bolts flicker: another strip of the texture
			_arc_t = 0.05
			_arc_row = randi() % 4
		var a := 1.0 if _fade <= 0.0 else clampf(_fade / 0.3, 0.0, 1.0)
		(_arcs.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, a)
		if upgraded:
			_build_strip(_arcs, _nodes, 0.5, cam.global_position, 0, 1, 2.0)
		else:
			_build_strip(_arcs, _nodes, 0.6, cam.global_position, _arc_row, 4, 8.0)


# ------------------------------------------------------------------ impact: radial effect

func _impact(hit: Dictionary) -> void:
	_done = true
	var pos: Vector3 = hit["position"] + hit["normal"] * 0.1
	global_position = pos
	_glow.visible = false
	_streak.visible = false
	_radial = true
	_nodes = [pos]
	var parent := get_parent()
	WeaponFx.flash(parent, pos, color(), 7.0, 5.0, 0.5)
	WeaponFx.pop(parent, pos, FLASH_TEX, 0.7, 4.0, 0.35, Color.WHITE)
	WeaponFx.burst(parent, pos, DOT_TEX, {"amount": 18, "lifetime": 0.45, "size": 0.1, "grow": 0.4,
		"speed": 5.0, "color": color().lightened(0.4), "gravity": Vector3(0, -4, 0), "rotate": false})
	if Sfx.instance:
		Sfx.instance.play_at("dog_spawn", pos, -4.0)
	_arcs = _strip_node(ARC_TEX[int(upgraded)])
	# the arcs end inside the bodies (chest height): drawn over them, not hidden
	(_arcs.material_override as StandardMaterial3D).no_depth_test = true
	# the zombie the bolt hit is inside the sphere from the first frame
	var target: Object = hit["collider"]
	if target is Zombie:
		_zap(target as Zombie)


func _update_radial(delta: float) -> void:
	if _fade > 0.0:
		_fade -= delta
		if _fade <= 0.0:
			queue_free()
		return
	var spec: Array = RADIAL[upgraded]
	_t += delta
	var r: float = float(spec[1]) * minf(_t, float(spec[0]))
	var centre: Vector3 = _nodes[0]
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("zombies"):
		if _kills + _dog_kills >= int(spec[3]):
			break
		var z := n as Zombie
		if z == null or _hit.has(z) or z.state == Zombie.State.DEAD:
			continue
		if z.global_position.distance_to(centre) > r:   # the entity's origin, as the original
			continue
		var body := z.global_position + Vector3.UP * (0.4 if z is Dog or z.crawler else 1.0)
		var q := PhysicsRayQueryParameters3D.create(centre, body, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		_zap(z)
	if (_kills + _dog_kills == 0 and r >= float(spec[2])) or _t >= float(spec[0]):
		_end()


func _zap(z: Zombie) -> void:
	_hit[z] = true
	_nodes.append(z.global_position + Vector3.UP * (0.4 if z is Dog or z.crawler else 1.1))
	if z is Dog:
		_dog_kills += 1
	else:
		_kills += 1
	electrocute(z, color(), upgraded)
	z.take_damage(maxf(z.health, 1.0), false, player)   # damage = the target's health


func _end() -> void:
	_fade = 0.35
	if Achievements.instance:   # CRadialEffect end: "<category>.zombieskillssimu"
		Achievements.instance._set_max("wunderwaffe.zombieskillssimu", _kills)
		Achievements.instance._set_max("wunderwaffe.dogskillssimu", _dog_kills)
	if _nodes.size() < 2:
		_arcs.visible = false


# Electrocuted zombie: crackling bolts over the body and a blue light while it dies.
static func electrocute(z: Node3D, col: Color, up := false) -> void:
	var fx := Node3D.new()
	fx.name = "Electrocuted"
	z.add_child(fx)
	fx.position = Vector3.UP * (0.4 if z is Dog else 1.0)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.0
	l.omni_range = 2.5
	fx.add_child(l)
	var p := WeaponFx.particles(CRACKLE_TEX[int(up)], {"amount": 12, "lifetime": 0.15, "size": 0.45, "grow": 1.0,
		"speed": 0.0, "one_shot": false, "color": Color.WHITE, "box": Vector3(0.25, 0.6, 0.25), "local": true,
		"frames": Vector2i(4, 2)})
	fx.add_child(p)
	p.emitting = true
	var tw := fx.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(l, "light_energy", 0.0, 0.3)
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(0.3)
	tw.tween_callback(fx.queue_free)


# ------------------------------------------------------------------ bolt strips

func _strip_node(tex_hash: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := WeaponFx.sprite_mat(tex_hash, true, false).duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.albedo_color = Color.WHITE   # the textures are coloured
	mi.material_override = m
	add_child(mi)
	return mi


# A camera-facing quad strip along pts (each segment its own quad), texture row `row`
# of `rows`, tiled along the length (`aspect` = width / height of one row).
static func _build_strip(mi: MeshInstance3D, pts: Array, width: float, eye: Vector3, row: int, rows: int, aspect: float) -> void:
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	mi.global_transform = Transform3D.IDENTITY   # vertices are world positions
	if pts.size() < 2:
		return
	var any := false
	for i in pts.size() - 1:
		any = any or (pts[i + 1] - pts[i]).length() >= 0.01
	if not any:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var v0 := float(row) / rows
	var v1 := float(row + 1) / rows
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var axis := b - a
		var len := axis.length()
		if len < 0.01:
			continue
		var side := axis.cross(((a + b) * 0.5 - eye)).normalized() * width * 0.5
		var u := len / (width * aspect)
		var o := randf()   # each frame the bolt slides: it crackles
		var quad := [[a - side, Vector2(o, v1)], [a + side, Vector2(o, v0)], [b + side, Vector2(o + u, v0)],
			[a - side, Vector2(o, v1)], [b + side, Vector2(o + u, v0)], [b - side, Vector2(o + u, v1)]]
		for vtx in quad:
			im.surface_set_color(Color.WHITE)
			im.surface_set_uv(vtx[1])
			im.surface_add_vertex(vtx[0])
	im.surface_end()
