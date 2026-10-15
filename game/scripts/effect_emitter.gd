# CRenderableEffectEmitter: the sprite emitter of the effects-group spec lists
# (CRenderableEffectEmitterSpec, not CIwGFXEmitterSpec: see iw_emitter.gd for that one).
# Decoded from kiwi: spec Serialise 0x26629c (base 0x18c6f4: cull volume, ...; params
# 0x1afa14), emitter init 0x265aac, particle update 0x264050, draw 0x2757dc, random vector
# 0x231fe8. Raw spec values (units, ms, 4096 = 1.0, angles 4096 = one turn):
#   space      1 = particles in the entity's frame (2 = the spawn point is offset by the owner)
#   interval   [min, max] ms between spawns (re-rolled at every try)
#   life       [min, max] ms
#   size       [min, max] half-width of the sprite (units); aspect (4096 = square)
#   scale_rate [min, max]: the size factor (starts at 1.0) loses rate*dt/4096 per ms;
#              scale_life true = it reaches 0 at the end of the particle's life
#   col_rate   same for the colour/alpha factor (col_life true = linear over the life)
#   angle      [min, max] start angle, spin [min, max] per ms (x 1/4096 turn)
#   pos        box [min, max] (vector type 1; 2 = sphere, 3 = cylinder: not used here)
#   vel        box [min, max]: position += vel*dt/4096 per ms (vel*1000/4096 units/s)
#   accel      vel += accel*dt/4096 per ms
#   duration   ms of emission (<= 0: until stopped); the slot count is
#              min(duration, life max) / interval min, one spawn per free slot per frame
#   material   additive sprite (all three teleporter materials have byte 3 = 2, white)
# When the emission is over and the last particle is dead the owner is told
# (vfunc 0x6c): the effect entity dies and its CDeathActionSpawnSpec spawns the next one.
class_name EffectEmitter
extends Node3D

signal finished

const U := 1.0 / 400.0   # units -> metres

var spec := {}
var _slots := []         # [life, size, scale, scale_rate, col, col_rate, angle, spin, pos, vel]
var _acc := 0.0          # ms accumulated towards the next spawn
var _left := 0.0         # emission time left (ms)
var _timed := false
var _done := false
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D


static func spawn(parent: Node, xf: Transform3D, s: Dictionary) -> EffectEmitter:
	var e := EffectEmitter.new()
	e.spec = s
	parent.add_child(e)
	e.global_transform = xf
	return e


static func _rnd(r: Array) -> float:
	# rand() % (max - min) + min, as the original (a reversed range stays on the min side)
	var lo := int(r[0])
	var span := int(r[1]) - lo
	if span == 0:
		return float(lo)
	return float(lo + (randi() & 0x7fffffff) % span)


func _ready() -> void:
	var life: Array = spec.get("life", [1000, 1000])
	var iv: Array = spec.get("interval", [100, 100])
	var dur := float(spec.get("duration", 0))
	_timed = dur > 0.0
	_left = dur
	var lmax := maxf(float(life[0]), float(life[1]))
	var imin := minf(float(iv[0]), float(iv[1]))
	var n := 0
	if imin > 0.0:
		n = int((minf(dur, lmax) if _timed else lmax) / imin)
	for i in n:
		_slots.append([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Vector3.ZERO, Vector3.ZERO])
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true   # INSTANCE_CUSTOM.x = angle (BILLBOARD_PARTICLES)
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)   # size is the half-width
	q.material = WeaponFx.sprite_mat(spec.get("tex", ""), spec.get("additive", true), true)
	_mm.mesh = q
	_mm.instance_count = maxi(n, 1)
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 16.0
	add_child(_mmi)


func stop() -> void:
	_timed = true
	_left = 0.0


func _process(delta: float) -> void:
	if _done:
		return
	var dt := delta * 1000.0
	var ended := _timed and _left <= 0.0
	if _timed:
		_left = maxf(_left - dt, 0.0)
		_acc += minf(dt, _left) if _left < dt else dt
	else:
		_acc += dt
	var alive := 0
	for p: Array in _slots:
		p[0] -= dt
		if p[0] > 0.0:
			p[2] = maxf(p[2] - p[3] * dt / 4096.0, 0.0)
			p[4] = maxf(p[4] - p[5] * dt / 4096.0, 0.0)
			p[6] += p[7] * dt / 4096.0
			p[9] += (spec.get("accel", Vector3.ZERO) as Vector3) * dt / 4096.0
			p[8] += p[9] * dt / 4096.0
			alive += 1
			continue
		p[0] = 0.0
		if ended:
			continue
		var iv := _rnd(spec.get("interval", [100, 100]))
		if _acc < iv:
			continue
		_acc -= iv
		_spawn(p)
		alive += 1
	_draw_parts()
	if ended and alive == 0:
		_done = true
		finished.emit()
		queue_free()


func _spawn(p: Array) -> void:
	var life := _rnd(spec.get("life", [1000, 1000]))
	p[0] = life
	p[1] = _rnd(spec.get("size", [100, 100]))
	p[2] = 1.0
	p[3] = 4096.0 / life if spec.get("scale_life", false) else _rnd(spec.get("scale_rate", [0, 0])) / 4096.0
	p[4] = 1.0
	p[5] = 4096.0 / life if spec.get("col_life", false) else _rnd(spec.get("col_rate", [0, 0])) / 4096.0
	p[6] = _rnd(spec.get("angle", [0, 0]))
	p[7] = _rnd(spec.get("spin", [0, 0]))
	var pos: Array = spec.get("pos", [Vector3.ZERO, Vector3.ZERO])
	var vel: Array = spec.get("vel", [Vector3.ZERO, Vector3.ZERO])
	p[8] = Vector3(_rnd([pos[0].x, pos[1].x]), _rnd([pos[0].y, pos[1].y]), _rnd([pos[0].z, pos[1].z]))
	p[9] = Vector3(_rnd([vel[0].x, vel[1].x]), _rnd([vel[0].y, vel[1].y]), _rnd([vel[0].z, vel[1].z]))


func _draw_parts() -> void:
	var k := 0
	for p: Array in _slots:
		if p[0] <= 0.0:
			continue
		var s := maxf(float(p[1]) * float(p[2]) * U, 0.0001)
		_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * s), (p[8] as Vector3) * U))
		# draw 0x2757dc: additive materials scale the colour, blended ones the alpha
		var c := float(p[4])
		_mm.set_instance_color(k, Color(c, c, c, 1.0) if spec.get("additive", true) else Color(1, 1, 1, c))
		_mm.set_instance_custom_data(k, Color(float(p[6]) / 4096.0 * TAU, 0.0, 0.0, 0.0))
		k += 1
	_mm.visible_instance_count = k
