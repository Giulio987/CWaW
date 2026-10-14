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
#
# Look (effects group; ? = not decoded, estimated here):
#  - Projectile, CRenderableEffectWunderwaffeSpec (Serialise kiwi va 0x1f7714, update
#    0x1edc00): a streak of at most 6 segments; a point is laid every 2 m of flight, moved
#    +-40 units off the line and turned +-~25 deg about it, 1 m wide, alpha fading to the
#    tail (material 6a62c407, texture 371a697e: one bolt, 2:1, whole texture per segment).
#    A second streak (a4d939ae) is one segment, 1 m wide, +-20 units and +-204/4096 of a turn
#    (material 8282c377, same texture). DG-3: materials a6d970e7 / c4cba857, pink a944f9de.
#    Disc model 89566990 (0.3 m, texture 41a63f86; DG-3 4b7aa8f1, 225c93e6) and the spark
#    emitter bf86e4e4 (CIwGFXEmitterSpec: endless, life 300-400 ms, velocity +-700 in x/z,
#    material 9387600f = 4x2 sheet 82f40e26 at half colour; ? spark size and rate).
#  - Impact: the emitter c97e388a (DG-3 9537f40b): sparks of the 4x2 sheet 82f40e26
#    (pink dd30b286) in a flat box +-2.5 m around the centre (? rate, life, size). No light,
#    no flash, no impact sound in the original (the gun's fire sound only).
#  - Each victim: CAttachEffect "wunderwaffe" of the zombie's CAttachEffectSpec (zombiesbase
#    c9872545 @0x4cd, serialiser kiwi va 0x1801f4) spawns 5 effects entities:
#      c1f66495 CRenderableEffectRadialArc on the Spine bone, 400 ms (below)
#      00c3776d model 3b7a79a3 (glow 1.1 x 1.6 m, texture 41a63f86) on Spine2, no lifetime:
#               stays on the body
#      00c696b1 model 8417c9c1 (small glow ~0.33 m) on Neck, no lifetime
#      8e080817 model a8a9f968 (4.15 x 2.7 m sheet, texture dd692a14), not attached, 1000 ms
#      00c8c90a model 30e29332 (4 bolt strips on the ground, texture 7fef4319), 3000 ms
#    Dogs (1d1ca339): glow 3b7a79a3, strips 30e29332 (1000 ms) and the arc, on bone 47ae13db.
#    The DG-3 uses the same (blue) victim effects. ? CLifeTimeSpec's second value (1000 ms)
#    is read as the fade-out time.
#  - CRenderableEffectRadialArc (Serialise kiwi va 0x1f4158, init 0x1e3600, update 0x1e3764,
#    render 0x17e29c): material 6a62c407 (texture 371a697e), width 200 units, search radius
#    25 m, attach bone 0x68d69859 (Spine): one quad from the victim's Spine to the Spine of
#    the nearest other zombie / dog within 25 m; at each end the quad spreads +-width/2 along
#    that bone's x axis (not a billboard), whole texture, white, no jitter; gone with the target.
#  - Death: damage type 6 picks one of the ZombieNumDeathsLightning = 2 lightning deaths of
#    the zombie state machine f402afc2 (states 34 / 35, after the normal deaths 24-26):
#    407213ce (4541 ms) and 407213cf (4125 ms) (zombie.gd LIGHTNING_DEATHS).
#  - Not done: the DG-3's extra splash (no damage).
extends Node3D

const SPEED := RaygunBolt.SPEED
const U := 400.0   # world units per metre
# [duration s, growth m/s, fizzle radius m, max kills]
const RADIAL := {false: [1000.0 / 1000.0, 1600.0 / U, 600.0 / U, 10],
	true: [1500.0 / 1000.0, 2000.0 / U, 2000.0 / U, 10]}
const EFFECTS_GLB := "res://assets/models/ingame/effects.glb"
# [normal, upgraded]
const BOLT_TEX := ["371a697e", "a944f9de"]
const SPARK_TEX := ["82f40e26", "dd30b286"]
const DISC := ["89566990", "4b7aa8f1"]
const DISC_TEX := ["41a63f86", "225c93e6"]
const SPARK_COLOR := Color(0.5, 0.5, 0.5)     # material 9387600f diffuse 0x80
# projectile streak
const TRAIL_STEP := 800.0 / U                 # 2 m between points
const TRAIL_SEGMENTS := 6
const TRAIL_WIDTH := 1.0
const TRAIL_JITTER := 40.0 / U
const TRAIL_ROLL := 0.44                      # ~25 deg
const CHILD_JITTER := 20.0 / U
const CHILD_ROLL := 204.0 / 4096.0 * TAU
# victim effects
const BONE_SPINE := "105f39c4"                # iw_hash("Spine") (arc attach 0x68d69859)
const BONE_SPINE2 := "1c467276"
const BONE_NECK := "7c9b1c06"
const BONE_DOG := "47ae13db"
const GLOW := "3b7a79a3"
const GLOW_NECK := "8417c9c1"
const SHEET := "a8a9f968"
const STRIPS := "30e29332"
const GLOW_TEX := "41a63f86"
const SHEET_TEX := "dd692a14"
const STRIPS_TEX := "7fef4319"
const SHEET_TIME := 1.0
const STRIPS_TIME := 3.0
const DOG_STRIPS_TIME := 1.0
const FADE_TIME := 1.0
const ARC_WIDTH := 200.0 / U
const ARC_RANGE := 25.0
const ARC_TIME := 0.4

static var _meshes := {}

var player: Player
var upgraded := false
var max_range := 100.0

var _dir := Vector3.FORWARD
var _from := Vector3.ZERO
var _travelled := 0.0
var _visual_offset := Vector3.ZERO
var _done := false
var _head: Node3D
var _sparks: CPUParticles3D
var _trail: MeshInstance3D
var _child: MeshInstance3D
var _points := []         # streak points: [position, roll]
var _since := 0.0         # metres flown since the last point

# radial effect
var _radial := false
var _t := 0.0
var _hit := {}            # zombie -> true
var _centre := Vector3.ZERO
var _kills := 0
var _dog_kills := 0
var _fade := 0.0
var _burst: CPUParticles3D


static func fire(p: Player, w: Dictionary, s: Dictionary, cam: Camera3D) -> void:
	var b = load("res://scripts/wunderwaffe.gd").new()
	b.player = p
	b.upgraded = bool(w.get("upgraded", false))
	b.max_range = float(s.get("range", 100.0))
	p.game.add_child(b)
	b.launch(cam.global_position, p._viewmodel.muzzle_position(), -cam.global_basis.z)


# ------------------------------------------------------------------ models and materials

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


# additive, unshaded, vertex colours (the models fade their edges with them); own copy
# so it can be faded
static func fx_mat(tex_hash: String, billboard := false) -> StandardMaterial3D:
	var m := WeaponFx.sprite_mat(tex_hash, true, false).duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	m.albedo_color = Color.WHITE
	return m


static func fx_model(h: String, tex_hash: String, billboard := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Fx_" + h
	mi.mesh = effect_mesh(h)
	mi.material_override = fx_mat(tex_hash, billboard)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _strip_node(parent: Node, tex_hash: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = fx_mat(tex_hash)
	parent.add_child(mi)
	mi.global_transform = Transform3D.IDENTITY   # vertices are world positions
	return mi


# one quad a-b, spread by sa at a and sb at b; u from ua to ub, v across
static func _quad(im: ImmediateMesh, a: Vector3, b: Vector3, sa: Vector3, sb: Vector3, ua: float, ub: float,
		ca := Color.WHITE, cb := Color.WHITE) -> void:
	var vs := [[a - sa, Vector2(ua, 1), ca], [a + sa, Vector2(ua, 0), ca], [b + sb, Vector2(ub, 0), cb],
		[a - sa, Vector2(ua, 1), ca], [b + sb, Vector2(ub, 0), cb], [b - sb, Vector2(ub, 1), cb]]
	for v in vs:
		im.surface_set_color(v[2])
		im.surface_set_uv(v[1])
		im.surface_add_vertex(v[0])


func color() -> Color:   # kept for callers: the gun's colour (blue / DG-3 pink)
	return Color(1.0, 0.45, 0.85) if upgraded else Color(0.55, 0.65, 1.0)


# ------------------------------------------------------------------ projectile

func launch(eye: Vector3, muzzle: Vector3, dir: Vector3) -> void:
	_dir = dir.normalized()
	_from = eye
	global_position = eye
	_visual_offset = muzzle - eye
	_head = Node3D.new()
	add_child(_head)
	var up := int(upgraded)
	var disc := fx_model(DISC[up], DISC_TEX[up], true)
	_head.add_child(disc)
	# bf86e4e4: endless, 300-400 ms, +-700 x 1000/4096 units/s in x/z (0.43 m/s)
	_sparks = WeaponFx.particles(SPARK_TEX[0], {"amount": 10, "lifetime": 0.35, "size": 0.12, "grow": 1.0,
		"speed": 0.43, "dir": Vector3.RIGHT, "spread": 180.0, "one_shot": false, "local": false,
		"color": SPARK_COLOR, "frames": Vector2i(4, 2)})
	_head.add_child(_sparks)
	_sparks.emitting = true
	_trail = _strip_node(self, BOLT_TEX[up])
	_child = _strip_node(self, BOLT_TEX[up])
	_place_visual()
	_points = [[_head.global_position, randf_range(-TRAIL_ROLL, TRAIL_ROLL)]]


func _place_visual() -> void:
	var k := clampf(1.0 - _travelled / 6.0, 0.0, 1.0)
	_head.position = _visual_offset * k


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
	_since += SPEED * delta
	_place_visual()
	while _since >= TRAIL_STEP:   # a new point every 2 m, off the line and turned
		_since -= TRAIL_STEP
		var side := _dir.cross(Vector3.UP if absf(_dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var off := side.rotated(_dir, randf() * TAU) * randf_range(-TRAIL_JITTER, TRAIL_JITTER)
		_points.append([_head.global_position - _dir * _since + off, randf_range(-TRAIL_ROLL, TRAIL_ROLL)])
		if _points.size() > TRAIL_SEGMENTS:
			_points.pop_front()
	if _travelled > max_range:
		queue_free()


func _process(_delta: float) -> void:
	if _done:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or _head == null:
		return
	var eye := cam.global_position
	var head := _head.global_position
	# main streak: points + the head, alpha 1 at the head down to 0 at the tail
	var im := _trail.mesh as ImmediateMesh
	im.clear_surfaces()
	var pts := _points.duplicate()
	pts.append([head, 0.0])
	if pts.size() >= 2:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := pts.size() - 1
		for i in n:
			var a: Vector3 = pts[i][0]
			var b: Vector3 = pts[i + 1][0]
			if a.distance_to(b) < 0.01:
				continue
			var sa := _side(a, eye, float(pts[i][1]), TRAIL_WIDTH)
			var sb := _side(b, eye, float(pts[i + 1][1]), TRAIL_WIDTH)
			var ub := 1.0 if i < n - 1 else a.distance_to(b) / TRAIL_STEP
			# the oldest point fades out as the next one is laid
			var tail := float(i) - (_since / TRAIL_STEP if pts.size() > TRAIL_SEGMENTS else 0.0)
			var ca := Color(1, 1, 1, clampf(tail / n, 0.0, 1.0))
			var cb := Color(1, 1, 1, clampf(float(i + 1) / n, 0.0, 1.0))
			_quad(im, a, b, sa, sb, 0.0, ub, ca, cb)
		im.surface_end()
	# second streak: one segment behind the head, shaken every frame
	var ic := _child.mesh as ImmediateMesh
	ic.clear_surfaces()
	var back := minf(TRAIL_STEP, _travelled)
	if back > 0.05:
		var side := _dir.cross(Vector3.UP if absf(_dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var tail := head - _dir * back + side.rotated(_dir, randf() * TAU) * randf_range(-CHILD_JITTER, CHILD_JITTER)
		var roll := randf_range(-CHILD_ROLL, CHILD_ROLL)
		ic.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(ic, tail, head, _side(tail, eye, roll, TRAIL_WIDTH), _side(head, eye, roll, TRAIL_WIDTH), 0.0, back / TRAIL_STEP,
			Color(1, 1, 1, 0.0), Color.WHITE)
		ic.surface_end()


# half-width vector at p: across the flight line facing the eye, turned by roll about the line
func _side(p: Vector3, eye: Vector3, roll: float, width: float) -> Vector3:
	var s := _dir.cross(p - eye)
	if s.length_squared() < 1e-6:
		s = _dir.cross(Vector3.UP)
	return s.normalized().rotated(_dir, roll) * width * 0.5


# ------------------------------------------------------------------ impact: radial effect

func _impact(hit: Dictionary) -> void:
	_done = true
	var pos: Vector3 = hit["position"] + hit["normal"] * 0.1
	global_position = pos
	_head.visible = false
	_sparks.emitting = false
	_trail.visible = false
	_child.visible = false
	_radial = true
	_centre = pos
	# c97e388a: crackle sprites in a flat +-2.5 m box around the centre while it lasts
	_burst = WeaponFx.particles(SPARK_TEX[int(upgraded)], {"amount": 28, "lifetime": 0.25, "size": 0.35, "grow": 1.0,
		"speed": 0.8, "dir": Vector3.UP, "spread": 20.0, "one_shot": false, "local": false,
		"color": SPARK_COLOR * 2.0, "frames": Vector2i(4, 2), "box": Vector3(2.5, 0.05, 2.5)})
	add_child(_burst)
	_burst.global_position = pos
	_burst.emitting = true
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
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("zombies"):
		if _kills + _dog_kills >= int(spec[3]):
			break
		var z := n as Zombie
		if z == null or _hit.has(z) or z.state == Zombie.State.DEAD:
			continue
		if z.global_position.distance_to(_centre) > r:   # the entity's origin, as the original
			continue
		var body := z.global_position + Vector3.UP * (0.4 if z is Dog or z.crawler else 1.0)
		var q := PhysicsRayQueryParameters3D.create(_centre, body, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		_zap(z)
	if (_kills + _dog_kills == 0 and r >= float(spec[2])) or _t >= float(spec[0]):
		_end()


func _zap(z: Zombie) -> void:
	_hit[z] = true
	if z is Dog:
		_dog_kills += 1
	else:
		_kills += 1
		z.electric_death = true   # damage type 6: a lightning death
	attach_effect(z)
	z.take_damage(maxf(z.health, 1.0), false, player)   # damage = the target's health


func _end() -> void:
	_fade = 0.35
	if _burst:
		_burst.emitting = false
	if Achievements.instance:   # CRadialEffect end: "<category>.zombieskillssimu"
		Achievements.instance._set_max("wunderwaffe.zombieskillssimu", _kills)
		Achievements.instance._set_max("wunderwaffe.dogskillssimu", _dog_kills)


# ------------------------------------------------------------------ victim: CAttachEffect "wunderwaffe"

static func _skel(z: Node) -> Skeleton3D:
	var s := z.find_children("*", "Skeleton3D", true, false)
	return s[0] as Skeleton3D if not s.is_empty() else null


static func _bone(skel: Skeleton3D, h: String) -> int:
	if skel:
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).ends_with(h):   # exported as "boneNN_<hash>"
				return i
	return -1


static func _on_bone(skel: Skeleton3D, bone: int, child: Node3D) -> void:
	var att := BoneAttachment3D.new()
	att.name = "WunderAttach"
	att.bone_idx = bone
	skel.add_child(att)
	att.add_child(child)


# a model left in the world at xf for `life` s, fading out over the last FADE_TIME
static func _timed(parent: Node, mi: MeshInstance3D, xf: Transform3D, life: float) -> void:
	parent.add_child(mi)
	mi.global_transform = xf
	var m := mi.material_override as StandardMaterial3D
	var tw := mi.create_tween()
	tw.tween_interval(maxf(life - FADE_TIME, 0.0))
	tw.tween_property(m, "albedo_color:a", 0.0, minf(FADE_TIME, life))
	tw.tween_callback(mi.queue_free)


static func attach_effect(z: Zombie) -> void:
	var skel := _skel(z)
	var parent := z.get_parent()
	var dog := z is Dog
	var spine := _bone(skel, BONE_DOG if dog else BONE_SPINE)
	if skel and spine >= 0:
		var arc_to := _arc_target(z)
		if arc_to:
			var arc := Arc.new()
			arc.setup(skel, spine, _skel(arc_to), _bone(_skel(arc_to), BONE_DOG if arc_to is Dog else BONE_SPINE),
				fx_mat(BOLT_TEX[0]), ARC_TIME, ARC_WIDTH)
			parent.add_child(arc)
	if dog:
		if skel and spine >= 0:
			_on_bone(skel, spine, fx_model(GLOW, GLOW_TEX))
		_timed(parent, fx_model(STRIPS, STRIPS_TEX), z.global_transform, DOG_STRIPS_TIME)
		return
	var b2 := _bone(skel, BONE_SPINE2)
	if b2 >= 0:
		_on_bone(skel, b2, fx_model(GLOW, GLOW_TEX))
	var bn := _bone(skel, BONE_NECK)
	if bn >= 0:
		_on_bone(skel, bn, fx_model(GLOW_NECK, GLOW_TEX))
	_timed(parent, fx_model(SHEET, SHEET_TEX), z.global_transform, SHEET_TIME)
	_timed(parent, fx_model(STRIPS, STRIPS_TEX), z.global_transform, STRIPS_TIME)


# the nearest other zombie / dog within 25 m (RadialArc init)
static func _arc_target(z: Zombie) -> Zombie:
	var best: Zombie = null
	var bd := ARC_RANGE
	for n in z.get_tree().get_nodes_in_group("zombies"):
		var o := n as Zombie
		if o == null or o == z or not is_instance_valid(o):
			continue
		var d := o.global_position.distance_to(z.global_position)
		if d < bd and _skel(o) != null:
			bd = d
			best = o
	return best


# CRenderableEffectRadialArc: one quad between two bones, spread along each bone's x axis
# (whole texture, white, no jitter); freed after its life or when either body is gone
class Arc extends MeshInstance3D:
	var a_skel: Skeleton3D
	var a_bone := -1
	var b_skel: Skeleton3D
	var b_bone := -1
	var life := 0.4
	var half := 0.25

	func setup(sa: Skeleton3D, ba: int, sb: Skeleton3D, bb: int, mat: Material, time: float, width: float) -> void:
		a_skel = sa
		a_bone = ba
		b_skel = sb
		b_bone = bb
		life = time
		half = width * 0.5
		name = "WunderArc"
		top_level = true
		mesh = ImmediateMesh.new()
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		material_override = mat

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0 or not is_instance_valid(a_skel) or not is_instance_valid(b_skel) or a_bone < 0 or b_bone < 0:
			queue_free()
			return
		global_transform = Transform3D.IDENTITY
		var ta := a_skel.global_transform * a_skel.get_bone_global_pose(a_bone)
		var tb := b_skel.global_transform * b_skel.get_bone_global_pose(b_bone)
		var sa := ta.basis.x.normalized() * half
		var sb := tb.basis.x.normalized() * half
		var a := ta.origin
		var b := tb.origin
		var im := mesh as ImmediateMesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in [[a - sa, Vector2(0, 1)], [a + sa, Vector2(0, 0)], [b + sb, Vector2(1, 0)],
				[a - sa, Vector2(0, 1)], [b + sb, Vector2(1, 0)], [b - sb, Vector2(1, 1)]]:
			im.surface_set_color(Color.WHITE)
			im.surface_set_uv(v[1])
			im.surface_add_vertex(v[0])
		im.surface_end()
