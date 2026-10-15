# Hit effects of the original effects group (tools/hit_fx.py -> assets/effects/hit_fx.json):
#  - blood on zombies and dogs: their CHitTemplate "Hit" (zombiesbase c9872545, dogs
#    1d1ca339; CHitHandler kiwi va 0x110e58) spawns, for a hit with a position, the first
#    effect whose damage limit is above the damage: a8e710ae (< 40: chips and a puff),
#    b73b0896 (< 150), a8621840 (< 250), a03f2a9e (< 400 and above); every explosive hit
#    (damage type 2) spawns ef263f8b at the entity's origin (the legs come off there).
#    The hit effect sits at the hit point in a frame whose y is up and z the bullet's
#    direction (its mist is placed and thrown along -z, back towards the shooter); the
#    particles live in that frame (coordinate mode 1) and follow the zombie.
#  - bullet impacts on walls: the gun's CItemGun 0xe8 effect (249fa16c pistols / SMGs,
#    241aa8fe shotguns / MGs / magnum, aa05b114 rifles): a ring c8e5bf94 lying on the
#    surface and three dust plumes (child entities of a spec list, 0 / 60 / 120 deg),
#    in a frame whose z goes into the surface (impact routine kiwi va 0x20eadc).
#  - limbs: the CDismembermentSpec effect entities (3e08391d head, 34a75f56 / 888d60e9
#    arms): model a03e9fcc (blood running from the stump) on the limb's bone for 1.5 / 2.5 s.
#  - muzzle flashes (CItemGun body 131): flash_spec() for viewmodel.gd.
# The emitters (CRenderableEffectEmitterSpec) and the droplet splats
# (CRenderableEffectSplatSpec) follow the original update and draw code, documented in
# tools/hit_fx.py. Units: 400 per metre, times in ms.
class_name HitFx
extends Node3D

const DATA := "res://assets/effects/hit_fx.json"
const TEX := "res://assets/textures/ingame/effects/%s.png"
const U := 1.0 / 400.0
const F24 := 1.0 / 16777216.0     # rates: 4096ths per ms, x4096
const WORLD_GRAVITY := 4000.0     # splat gravity = world gravity x scale: WorldColliderGravity 4000 (estimate)
const LIMBS := {"head": ["7c9b1c06", 1.5], "left": ["f503c7dc", 2.5], "right": ["8f943e2f", 2.5]}
const LIMB_MODEL := "a03e9fcc"
const EXPLOSION := "ee72b935"   # betty / Mustang & Sally splash: smoke, fireball, sparks emitters

static var _data := {}
static var _mats := {}
static var _tex_size := {}
static var history := []  # [time, effect] for tests

var _parts := []          # Emitter / Splat
var _age := 0.0


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(DATA):
		_data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return _data


static func material(tex: String, additive: bool) -> StandardMaterial3D:
	var key := "%s|%s" % [tex, additive]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = load(TEX % tex) as Texture2D if ResourceLoader.exists(TEX % tex) else null
		_mats[key] = m
	return _mats[key]


static func tex_aspect(tex: String) -> float:   # width / height
	if not _tex_size.has(tex):
		var t := load(TEX % tex) as Texture2D if ResourceLoader.exists(TEX % tex) else null
		_tex_size[tex] = float(t.get_width()) / float(t.get_height()) if t else 1.0
	return _tex_size[tex]


# Plays effect entity `h` as a child of `parent` at the global transform `xf`.
static func play(parent: Node, xf: Transform3D, h: String) -> HitFx:
	var parts: Array = data().get("entities", {}).get(h, [])
	if parts.is_empty() or parent == null or not parent.is_inside_tree():
		return null
	var fx := HitFx.new()
	fx.name = "HitFx_" + h
	parent.add_child(fx)
	fx.global_transform = xf
	for p in parts:
		var q: Dictionary = p
		var local := Transform3D(_quat(q.get("rot_wxyz", [1, 0, 0, 0])), _v(q.get("pos", [0, 0, 0])) * U)
		match String(q["type"]):
			"emitter":
				fx._parts.append(Emitter.new(fx, q, local))
			"splat":
				fx._parts.append(Splat.new(fx, q, local))
	history.append([Time.get_ticks_msec() / 1000.0, h])
	return fx


static func _quat(r: Array) -> Basis:
	return Basis(Quaternion(float(r[1]), float(r[2]), float(r[3]), float(r[0])).normalized())


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _rand(r: Array, k := 1.0) -> float:
	return randf_range(float(r[0]), float(r[1])) * k


# ------------------------------------------------------------------ hooks

# A hit on a zombie or dog (Zombie.take_damage): the CHitTemplate effect for `amount` at
# the hit point. No effect without a hit position (splash damage, the knife: the melee
# code, kiwi file 0x20d490, passes none). Sound: CHitHandler (kiwi file 0x10f774) plays
# the template's first sound (zombie_hit f889c48a) for every hit but fire (type 5), the
# second (f889c48b) when the damage info's byte 0x21 is set, i.e. by a splash (file
# 0x1d9030): bullets and the knife here, explosions in on_splash_hit.
static func on_hit(z: Zombie, amount: float, hit_pos: Vector3, by: Node3D, knife := false) -> void:
	if z == null or not z.is_inside_tree():
		return
	if knife or hit_pos != Vector3.INF:
		hit_sound(z, false)
	if hit_pos == Vector3.INF:
		return
	var tpl: Dictionary = data().get("hit_dog" if z is Dog else "hit_zombie", {})
	var steps: Array = tpl.get("steps", [])
	if steps.is_empty():
		return
	var h := String(steps[-1][0])
	for s in steps:
		if float(s[1]) > amount:
			h = String(s[0])
			break
	var from := hit_pos - z.global_basis.z
	var cam := z.get_viewport().get_camera_3d() if by != null else null
	if cam:
		from = cam.global_position
	play(z, _frame(hit_pos, hit_pos - from), h)


# A splash hit (Explosion.blast): the template's second sound; explosive damage (type 2)
# also spawns its explosive effect at the entity's origin.
static func on_splash_hit(z: Zombie, explosive: bool) -> void:
	if z == null or not z.is_inside_tree():
		return
	hit_sound(z, true)
	if explosive:
		on_explosive_hit(z)


static func hit_sound(z: Zombie, splash: bool) -> void:
	var snd: Array = data().get("hit_dog" if z is Dog else "hit_zombie", {}).get("sounds", [])
	if snd.size() == 2 and Sfx.instance:
		Sfx.instance.play_at(String(snd[1 if splash else 0]), z.global_position + Vector3.UP, -2.0)
		history.append([Time.get_ticks_msec() / 1000.0, "snd_" + String(snd[1 if splash else 0])])


# Explosive damage (damage type 2): the template's explosive effect at the entity's origin.
static func on_explosive_hit(z: Zombie) -> void:
	if z == null or not z.is_inside_tree():
		return
	var h := String(data().get("hit_dog" if z is Dog else "hit_zombie", {}).get("explosive", ""))
	if h != "":
		play(z, z.global_transform.orthonormalized(), h)


# y up, z along `forward` (made horizontal; the original builds it from the entity's up axis).
static func _frame(origin: Vector3, forward: Vector3) -> Transform3D:
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length_squared() < 1e-6:
		f = Vector3.FORWARD
	f = f.normalized()
	return Transform3D(Basis(Vector3.UP.cross(f), Vector3.UP, f), origin)


# Bullet impact on the level (Game.spawn_impact): the gun's 0xe8 effect, z into the surface.
static func impact(parent: Node, pos: Vector3, normal: Vector3, shot_dir: Vector3, weapon: Dictionary) -> HitFx:
	var key := String(weapon.get("name", "colt45")) + ("_upgrade" if weapon.get("upgraded", false) else "")
	var gun: Dictionary = data().get("guns", {}).get(key, {})
	var h := String(gun.get("impact", "00000000"))
	if h == "00000000":
		return null
	var z := -normal.normalized()
	var up := Vector3.UP - z * Vector3.UP.dot(z)
	if up.length_squared() < 0.01:   # floor / ceiling: "up" from the shot
		up = shot_dir - z * shot_dir.dot(z)
		if up.length_squared() < 1e-6:
			up = Vector3.FORWARD
	up = up.normalized()
	return play(parent, Transform3D(Basis(up.cross(z), up, z), pos + normal * 0.01), h)


# Blood running from a stump: the dismemberment effect entity's model on the limb's bone.
static func limb(z: Zombie, which: String) -> void:
	if z == null or not z.is_inside_tree() or not LIMBS.has(which):
		return
	var skel := z._skeleton() if z.has_method("_skeleton") else null
	if skel == null:
		return
	var holder: Node3D = null
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).ends_with(String(LIMBS[which][0])):
			var att := BoneAttachment3D.new()
			att.bone_name = skel.get_bone_name(i)
			skel.add_child(att)
			holder = att
			break
	if holder == null:
		return
	var fx := IwFx.make(LIMB_MODEL, IwFx.FLAG_BILLBOARD_AXIS)
	holder.add_child(fx)
	history.append([Time.get_ticks_msec() / 1000.0, "limb_" + which])
	z.get_tree().create_timer(float(LIMBS[which][1]), false).timeout.connect(holder.queue_free)


# Muzzle flash of a gun (its CItemGun flash entity): {tex, additive, side [min, max] m,
# life s, grow /s, spin deg/s} for one sprite.
static func flash_spec(weapon: Dictionary) -> Dictionary:
	var key := String(weapon.get("name", "colt45")) + ("_upgrade" if weapon.get("upgraded", false) else "")
	var h := String(data().get("guns", {}).get(key, {}).get("flash", ""))
	var parts: Array = data().get("entities", {}).get(h, [])
	if parts.is_empty():
		return {}
	var p: Dictionary = parts[0]
	if p["type"] == "gfx":   # CIwGFXEmitterSpec: size centre to corner, one particle
		return {"tex": p["tex"], "additive": int(p["blend"]) == 2,
			"side": [float(p["size"][0]) * U * sqrt(2.0), float(p["size"][1]) * U * sqrt(2.0)],
			"life": float(p["life"][1]) / 1000.0, "grow": float(p["grow"]) * U * sqrt(2.0),
			"spin": [float(p["spin"][0]), float(p["spin"][1])], "offset": float(p["box"][1][1]) * U}
	return {"tex": p["tex"], "additive": int(p["blend"]) == 2,
		"side": [float(p["size"][0]) * 2.0 * U, float(p["size"][1]) * 2.0 * U],
		"life": float(p["life"][1]) / 1000.0, "grow": -float(p["size_decay"][0]) * F24 * 1000.0 * float(p["size"][1]) * 2.0 * U,
		"spin": [0.0, 0.0], "offset": float(p["box"][1][1]) * U}


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	_age += delta
	var dt := delta * 1000.0
	var live := false
	var cam := get_viewport().get_camera_3d()
	for p in _parts:
		if p.update(dt):
			live = true
		p.draw(global_transform, cam)
	if not live:
		queue_free()


# CRenderableEffectEmitter (kiwi va 0x265aac spawn setup, 0x264050 update, 0x2757dc draw).
class Emitter:
	var s: Dictionary
	var local: Transform3D
	var slots := []        # [life_left, life, size, scale, scale_rate, alpha, alpha_rate, angle, spin, pos, vel]
	var acc := 0.0
	var emit_left := INF
	var accel := Vector3.ZERO
	var color := Color.WHITE
	var additive := false
	var aspect := 1.0
	var pivot := Vector2.ZERO
	var mm: MultiMesh
	var mmi: MultiMeshInstance3D

	func _init(fx: Node3D, spec: Dictionary, xf: Transform3D) -> void:
		s = spec
		local = xf
		var every: Array = s["every"]
		var life: Array = s["life"]
		var emit := float(s["emit"])
		if emit > 0.0:
			emit_left = emit
		var span := minf(emit, float(life[1])) if emit > 0.0 else float(life[1])
		var n := int(span / maxf(float(every[0]), 1.0)) + 1
		for i in n:
			slots.append([0.0])
		accel = HitFx._v(s["accel"]) * HitFx.F24
		var c: Array = s["color"]
		color = Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, c[3] / 255.0)
		additive = int(s["blend"]) == 2
		aspect = float(s["aspect"]) / 4096.0 * HitFx.tex_aspect(s["tex"])
		pivot = Vector2(float(s["pivot"][0]), float(s["pivot"][1])) / 4096.0
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		q.material = HitFx.material(s["tex"], additive)
		mm.mesh = q
		mm.instance_count = slots.size()
		mm.visible_instance_count = 0
		mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.top_level = true
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fx.add_child(mmi)
		mmi.global_transform = Transform3D.IDENTITY

	static func sample(kind: int, r: Array) -> Vector3:
		var a := HitFx._v(r[0])
		var b := HitFx._v(r[1])
		var v := Vector3(randf_range(a.x, b.x), randf_range(a.y, b.y), randf_range(a.z, b.z))
		match kind:
			2:   # sphere: two angles (4096 = turn) and a radius
				var t := v.x / 4096.0 * TAU
				var p := v.y / 4096.0 * TAU
				return Vector3(cos(t) * sin(p), cos(p), sin(t) * sin(p)) * v.z
			3:   # cylinder: angle, height, radius
				var t := v.x / 4096.0 * TAU
				return Vector3(cos(t) * v.z, v.y, sin(t) * v.z)
		return v

	func spawn(slot: Array) -> void:
		var life := HitFx._rand(s["life"])
		var scale_rate := 1.0 / life if int(s["size_by_life"]) else HitFx._rand(s["size_decay"], HitFx.F24)
		var alpha_rate := 1.0 / life if int(s["alpha_by_life"]) else HitFx._rand(s["alpha_decay"], HitFx.F24)
		slot.resize(11)
		slot[0] = life
		slot[1] = life
		slot[2] = HitFx._rand(s["size"])
		slot[3] = 1.0
		slot[4] = scale_rate
		slot[5] = 1.0
		slot[6] = alpha_rate
		slot[7] = HitFx._rand(s["angle"]) / 4096.0 * TAU
		slot[8] = HitFx._rand(s["spin"], HitFx.F24) * TAU
		slot[9] = sample(int(s["box_type"]), s["box"])
		slot[10] = sample(int(s["vel_type"]), s["vel"]) / 4096.0

	# true while the emitter emits or has particles
	func update(dt: float) -> bool:
		var done := emit_left <= 0.0
		acc += minf(dt, maxf(emit_left, 0.0)) if emit_left != INF else dt
		emit_left -= dt
		var live := false
		for slot in slots:
			slot[0] -= dt
			if slot[0] > 0.0:
				slot[3] = maxf(slot[3] - slot[4] * dt, 0.0)
				slot[5] = maxf(slot[5] - slot[6] * dt, 0.0)
				slot[7] += slot[8] * dt
				slot[10] += accel * dt
				slot[9] += slot[10] * dt
				live = true
			elif not done:
				slot[0] = 0.0
				var gap := HitFx._rand(s["every"])
				if acc >= gap:
					acc -= gap
					spawn(slot)
					live = true
		return live or not done

	func draw(xf: Transform3D, cam: Camera3D) -> void:
		var w := xf * local
		var n := 0
		var camera_facing := int(s["frame"]) == 0
		for slot in slots:
			if slot[0] <= 0.0 or slot.size() < 11:
				continue
			var h: float = slot[2] * slot[3] * HitFx.U
			if h <= 0.0001:
				continue
			var ang: float = slot[7]
			var ax: Vector3
			var ay: Vector3
			if camera_facing and cam:
				ax = cam.global_basis.x
				ay = cam.global_basis.y
			else:
				ax = w.basis.x.normalized()
				ay = w.basis.y.normalized()
			# texture up = local +y turned by the angle + 180 deg (the images are stored
			# bottom up: the dust plumes, angle ~2048, stand on their pivot)
			var up := -(ay * cos(ang) - ax * sin(ang))
			var right := -(ax * cos(ang) + ay * sin(ang))
			var half_w := h * aspect
			var pos: Vector3 = w * (slot[9] * HitFx.U)
			pos += right * pivot.x * half_w + up * pivot.y * h
			var nrm := right.cross(up).normalized() * 0.001
			mm.set_instance_transform(n, Transform3D(Basis(right * half_w, up * h, nrm), pos))
			var a: float = slot[5]
			mm.set_instance_color(n, Color(color.r * a, color.g * a, color.b * a, color.a) if additive
				else Color(color.r, color.g, color.b, color.a * a))
			n += 1
		mm.visible_instance_count = n


# CRenderableEffectSplat (kiwi va 0x1cda44 spawn, 0x2657c4 update, 0x22aabc draw): droplets
# thrown in the frame's XY plane, drawn as kites stretched along their velocity.
class Splat:
	var s: Dictionary
	var local: Transform3D
	var drops := []       # [pos, vel, angle, stretch, grow, size]
	var left := 0.0
	var gravity := Vector3.ZERO
	var color := Color.WHITE
	var im: ImmediateMesh
	var mi: MeshInstance3D

	func _init(fx: Node3D, spec: Dictionary, xf: Transform3D) -> void:
		s = spec
		local = xf
		left = float(s["life"])
		var n := int(s["count"])
		var a := 0.0
		for i in n:
			a += HitFx._rand(s["step"]) / 4096.0 / float(n) * TAU
			var v := Vector3(sin(a) * HitFx._rand([s["speed"][0][0], s["speed"][1][0]]),
				cos(a) * HitFx._rand([s["speed"][0][1], s["speed"][1][1]]),
				HitFx._rand([s["speed"][0][2], s["speed"][1][2]])) / 4096.0
			drops.append([Vector3.ZERO, v, a, 0.0, 0.0, HitFx._rand(s["size"])])
		# world gravity in the frame, x the spec's scale (frames here are upright)
		gravity = Vector3(0, -HitFx.WORLD_GRAVITY * float(s["gravity"]) / 4096.0, 0) * HitFx.F24
		var c: Array = s["color"]
		color = Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, c[3] / 255.0)
		im = ImmediateMesh.new()
		mi = MeshInstance3D.new()
		mi.mesh = im
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = HitFx.material(s["tex"], int(s["blend"]) == 2)
		fx.add_child(mi)
		mi.global_transform = Transform3D.IDENTITY

	func update(dt: float) -> bool:
		left -= dt
		if left <= 0.0:
			return false
		var turn := float(s["turn"]) * HitFx.F24 * TAU * dt
		for d in drops:
			d[1] += gravity * dt
			d[0] += d[1] * dt
			var vel: Vector3 = d[1]
			var target := atan2(vel.x, vel.y)
			d[2] += clampf(wrapf(target - d[2], -PI, PI), -turn, turn)
			d[3] = clampf(d[3] + float(s["stretch"]) * HitFx.F24 * dt, 0.0, 10.0)
			d[4] = clampf(d[4] + float(s["grow"]) * HitFx.F24 * dt, 0.0, 1.0)
		return true

	func draw(xf: Transform3D, _cam: Camera3D) -> void:
		im.clear_surfaces()
		if left <= 0.0:
			return
		var w := xf * local
		var begun := false
		for d in drops:
			var size: float = d[5] * sin(d[4] * PI * 0.5) * HitFx.U
			if size <= 0.0001:
				continue
			var ang: float = d[2]
			var fwd := Vector3(sin(ang), cos(ang), 0.0)
			var side := Vector3(fwd.y, -fwd.x, 0.0)
			var c: Vector3 = d[0] * HitFx.U
			var stretch: float = d[3]
			var front: Vector3 = w * (c + fwd * size * (1.0 + stretch))
			var back: Vector3 = w * (c - fwd * size)
			var l: Vector3 = w * (c - side * size)
			var r: Vector3 = w * (c + side * size)
			if not begun:
				im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				begun = true
			for t in [[front, Vector2(0.5, 0.0), l, Vector2(0.0, 0.5), r, Vector2(1.0, 0.5)],
					[back, Vector2(0.5, 1.0), r, Vector2(1.0, 0.5), l, Vector2(0.0, 0.5)]]:
				for k in 3:
					im.surface_set_color(color)
					im.surface_set_uv(t[k * 2 + 1])
					im.surface_add_vertex(t[k * 2])
		if begun:
			im.surface_end()
