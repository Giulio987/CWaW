# Special weapons and shared visual helpers (World at War behaviour):
#  - Ray Gun: a fast green bolt (RaygunBolt) that explodes on impact with splash
#    damage that also hurts the player when very close;
#  - M2 Flamethrower: short-range cone that sets zombies on fire (Burning), with a
#    flame jet from the muzzle (FlameJet);
#  - sprite particles built from the original effect textures
#    (assets/textures/ingame/effects, identified by eye from a contact sheet):
#      0f74ae25 flame animation (8x4 frames)   c03be099 / a42e102d / bce537be fireballs
#      81d92923 smoke   623a30c5 sparks/embers  a03e6a9a debris chunk
#      b81905e3 green star burst   a85c021b teal cloud   aca98856 small green glow
# Player._fire() calls WeaponFx.fire() first; when it returns true the normal
# hitscan is skipped.
class_name WeaponFx

const TEX := "res://assets/textures/ingame/effects/%s.png"

const FLAME_CONE := 18.0       # degrees, half angle
const FLAME_DPS_MUL := 5.0     # burn damage per second = weapon damage x this
const FLAME_AFTERBURN := 3.0   # seconds a zombie keeps burning out of the jet

static var _mats := {}


static func fire(player: Player, w: Dictionary, s: Dictionary, cam: Camera3D) -> bool:
	match String(w["name"]):
		"raygun":
			_fire_raygun(player, w, s, cam)
			return true
		"flamethrower":
			_fire_flamethrower(player, w, s, cam)
			return true
	return false


# ------------------------------------------------------------------ ray gun

static func _fire_raygun(player: Player, w: Dictionary, s: Dictionary, cam: Camera3D) -> void:
	var dir := -cam.global_basis.z
	var muzzle := cam.global_position + cam.global_basis * Vector3(0.12, -0.1, -0.5)
	var bolt := RaygunBolt.new()
	bolt.player = player
	bolt.damage = float(s["damage"])
	bolt.head_mul = float(s.get("head", 1.0))
	bolt.upgraded = bool(w.get("upgraded", false))
	bolt.max_range = float(s["range"])
	player.game.add_child(bolt)
	bolt.launch(cam.global_position, muzzle, dir)


# ------------------------------------------------------------------ flamethrower

static func _fire_flamethrower(player: Player, w: Dictionary, s: Dictionary, cam: Camera3D) -> void:
	var jet := cam.get_node_or_null("FlameJet") as FlameJet
	if jet == null:
		jet = FlameJet.new()
		jet.name = "FlameJet"
		cam.add_child(jet)
	jet.pulse(bool(w.get("upgraded", false)))
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	var reach := float(s["range"])
	var dps := float(s["damage"]) * FLAME_DPS_MUL
	var space := player.get_world_3d().direct_space_state
	for n in player.get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z.state == Zombie.State.DEAD:
			continue
		var target := z.global_position + Vector3.UP * (0.3 if z.crawler else 1.0)
		var to := target - origin
		var d := to.length()
		if d > reach or d < 0.01:
			continue
		var ang := rad_to_deg(fwd.angle_to(to / d))
		if ang > (50.0 if d < 1.5 else FLAME_CONE):
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, target, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		Burning.ignite(z, player, dps, FLAME_AFTERBURN)


# ------------------------------------------------------------------ visuals

static func tex(h: String) -> Texture2D:
	return load(TEX % h) as Texture2D


# Unshaded sprite material from an effect texture. billboard: MeshInstance quads
# face the camera; particles: per-particle billboards with sheet animation.
static func sprite_mat(h: String, additive := true, particles := true, frames := Vector2i(1, 1)) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [h, additive, particles, frames]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex(h)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	if particles:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true   # else the per-particle scale is ignored
		m.particles_anim_h_frames = frames.x
		m.particles_anim_v_frames = frames.y
		m.particles_anim_loop = false
	else:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	_mats[key] = m
	return m


# CPU sprite particles. cfg: amount, lifetime, size (start, metres), grow (end size / start size),
# speed, spread (deg), dir, gravity, color, additive, frames, one_shot,
# explosiveness, box (emission half extents), damping, local (local coords)
static func particles(h: String, cfg: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	var frames: Vector2i = cfg.get("frames", Vector2i(1, 1))
	quad.material = sprite_mat(h, cfg.get("additive", true), true, frames)
	p.mesh = quad
	p.amount = int(cfg.get("amount", 8))
	p.lifetime = float(cfg.get("lifetime", 1.0))
	p.one_shot = bool(cfg.get("one_shot", true))
	p.explosiveness = float(cfg.get("explosiveness", 0.95 if p.one_shot else 0.0))
	p.randomness = 0.3
	p.local_coords = bool(cfg.get("local", false))
	p.direction = cfg.get("dir", Vector3.UP)
	p.spread = float(cfg.get("spread", 180.0))
	var speed := float(cfg.get("speed", 1.0))
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.gravity = cfg.get("gravity", Vector3.ZERO)
	p.damping_min = float(cfg.get("damping", 0.0))
	p.damping_max = float(cfg.get("damping", 0.0))
	p.angle_min = -180.0 if cfg.get("rotate", true) else 0.0
	p.angle_max = 180.0 if cfg.get("rotate", true) else 0.0
	var size := float(cfg.get("size", 1.0))
	var grow := float(cfg.get("grow", 1.0))
	p.scale_amount_min = size * maxf(grow, 1.0) * 0.8
	p.scale_amount_max = size * maxf(grow, 1.0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, minf(1.0, 1.0 / grow) if grow > 0.0 else 1.0))
	curve.add_point(Vector2(1, minf(1.0, grow) if grow < 1.0 else 1.0))
	p.scale_amount_curve = curve
	var c: Color = cfg.get("color", Color.WHITE)
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	if cfg.has("fade_in"):
		g.add_point(float(cfg["fade_in"]), c)
		g.set_color(0, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = g
	if frames != Vector2i(1, 1):
		p.anim_speed_min = 1.0
		p.anim_speed_max = 1.0
	if cfg.has("box"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = cfg["box"]
	elif cfg.has("sphere"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = float(cfg["sphere"])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


# One-shot burst at a world position, freed when done.
static func burst(parent: Node, pos: Vector3, h: String, cfg: Dictionary) -> CPUParticles3D:
	var p := particles(h, cfg)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.5, false).timeout.connect(p.queue_free)
	return p


# Light that fades out.
static func flash(parent: Node, pos: Vector3, color: Color, energy: float, light_range: float, time: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)


# Billboard quad (not a particle) that grows and fades.
static func pop(parent: Node, pos: Vector3, h: String, size: float, grow: float, time: float, color := Color.WHITE) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = sprite_mat(h, true, false)
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	var mat := (sprite_mat(h, true, false).duplicate()) as StandardMaterial3D
	mat.albedo_color = color
	mi.material_override = mat
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * grow, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


# Camera shake (h/v offsets, so it never fights the look rotation).
static func shake(node: Node, strength: float, time := 0.45) -> void:
	if strength <= 0.01 or node == null or not node.is_inside_tree():
		return
	var cam := node.get_viewport().get_camera_3d()
	if cam == null:
		return
	var sh := cam.get_node_or_null("Shake") as Shaker
	if sh == null:
		sh = Shaker.new()
		sh.name = "Shake"
		cam.add_child(sh)
	sh.add(strength, time)


class Shaker extends Node:
	var _strength := 0.0
	var _time := 0.0
	var _left := 0.0

	func add(strength: float, time: float) -> void:
		_strength = maxf(_strength * (_left / maxf(_time, 0.001)), strength)
		_time = time
		_left = time

	func _process(delta: float) -> void:
		var cam := get_parent() as Camera3D
		if cam == null:
			return
		if _left <= 0.0:
			cam.h_offset = 0.0
			cam.v_offset = 0.0
			return
		_left -= delta
		var k := _strength * maxf(_left / _time, 0.0)
		cam.h_offset = randf_range(-1.0, 1.0) * k * 0.08
		cam.v_offset = randf_range(-1.0, 1.0) * k * 0.08
