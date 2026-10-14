# Sprite particles that follow the original CIwGFXEmitterSpec (Serialise kiwi 0x11c358;
# decoded with the barrel and bridge-steam emitters):
#   0x20 flags (bit 3 = fade out), 0x28 emission time (fixed 1/4096 ms; negative = until
#   stopped), 0x2c spawn box, 0x44 velocity box (x 1000/4096 units/s), 0x60 lifetime min/max,
#   0x68 start size (centre to corner: the square's side is size * sqrt 2), 0x70 spin,
#   0x80 time between spawns min/max, 0x88 size growth. No gravity, no damping: particles
#   fly straight. Fade: colour and alpha = min(1, life left / lifetime min).
#   Blend from byte 3 of the material: 2 = additive, 4 = alpha blend.
# Spawn box and velocity are in the emitter's local frame; the particles live in the world.
# cfg (metres, seconds, degrees):
#   tex, additive, color, emit (s, < 0 loops until stop()), every [min, max] s,
#   life [min, max] s, box [Vector3 min, Vector3 max], vel [Vector3 min, Vector3 max] m/s,
#   size [min, max] m (centre to corner), grow m/s, spin [min, max] deg/s, fade
class_name IwEmitter
extends Node3D

var cfg := {}
var emitting := false
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _parts := []          # [pos, vel, age, life, size, angle, spin]
var _elapsed := 0.0
var _next := 0.0
var _one_shot := false


static func make(c: Dictionary) -> IwEmitter:
	var e := IwEmitter.new()
	e.cfg = c
	return e


# One-shot emitter at `xf` (world), freed when its last particle dies.
static func burst(parent: Node, xf: Transform3D, c: Dictionary) -> IwEmitter:
	var e := make(c)
	e._one_shot = true
	parent.add_child(e)
	e.global_transform = xf
	e.start()
	return e


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true   # INSTANCE_CUSTOM.x = spin angle (BILLBOARD_PARTICLES)
	var q := QuadMesh.new()
	q.size = Vector2.ONE * sqrt(2.0)   # size is centre to corner
	q.material = WeaponFx.sprite_mat(cfg.get("tex", ""), cfg.get("additive", true), true)
	_mm.mesh = q
	var every: Array = cfg.get("every", [0.1, 0.1])
	var life: Array = cfg.get("life", [1.0, 1.0])
	_mm.instance_count = int(ceil(float(life[1]) / maxf(float(every[0]), 0.001))) + 2
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.top_level = true
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_mmi.global_transform = Transform3D.IDENTITY


func start() -> void:
	emitting = true
	_elapsed = 0.0
	_next = 0.0


func stop() -> void:
	emitting = false


static func _rand(r: Array) -> float:
	return randf_range(float(r[0]), float(r[1]))


static func _rand3(r: Array) -> Vector3:
	var a: Vector3 = r[0]
	var b: Vector3 = r[1]
	return Vector3(randf_range(a.x, b.x), randf_range(a.y, b.y), randf_range(a.z, b.z))


func _spawn() -> void:
	var xf := global_transform.orthonormalized()
	var pos := xf * _rand3(cfg.get("box", [Vector3.ZERO, Vector3.ZERO]))
	var vel := xf.basis * _rand3(cfg.get("vel", [Vector3.ZERO, Vector3.ZERO]))
	_parts.append([pos, vel, 0.0, _rand(cfg.get("life", [1.0, 1.0])), _rand(cfg.get("size", [1.0, 1.0])),
		0.0, deg_to_rad(_rand(cfg.get("spin", [0.0, 0.0])))])


func _process(delta: float) -> void:
	if emitting:
		var emit := float(cfg.get("emit", -1.0))
		var t0 := _elapsed
		_elapsed += delta
		# CIwGFXEmitter: one particle, then the next after a random gap, while the emission lasts
		while _next <= _elapsed and (emit < 0.0 or _next < emit) and _parts.size() < _mm.instance_count:
			_spawn()
			var p: Array = _parts[-1]
			var late := _elapsed - maxf(_next, t0)   # born part-way through this frame
			p[0] += p[1] * late
			p[2] = late
			_next += _rand(cfg.get("every", [0.1, 0.1]))
		if emit >= 0.0 and _elapsed >= emit:
			emitting = false
	var grow := float(cfg.get("grow", 0.0))
	var fade := bool(cfg.get("fade", true))
	var life_min := float((cfg.get("life", [1.0, 1.0]) as Array)[0])
	var col: Color = cfg.get("color", Color.WHITE)
	var i := 0
	while i < _parts.size():
		var p: Array = _parts[i]
		p[2] += delta
		if p[2] >= p[3]:
			_parts.remove_at(i)
			continue
		p[0] += p[1] * delta
		p[5] += p[6] * delta
		i += 1
	_mm.visible_instance_count = _parts.size()
	for k in _parts.size():
		var p: Array = _parts[k]
		var s := maxf(float(p[4]) + grow * float(p[2]), 0.0)   # shrinking ones stop at 0
		_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * maxf(s, 0.0001)), p[0]))
		var f := minf(1.0, (float(p[3]) - float(p[2])) / life_min) if fade else 1.0
		_mm.set_instance_color(k, Color(col.r * f, col.g * f, col.b * f, col.a * f))
		_mm.set_instance_custom_data(k, Color(float(p[5]), 0.0, 0.0, 0.0))
	if _one_shot and not emitting and _parts.is_empty():
		queue_free()


# cfg from the spec's raw fields: times in ms, box and size in units, velocity and growth
# in the spec's fixed-point units/s (x 1000/4096 -> units/s), spin in degrees/s.
static func from_spec(tex: String, additive: bool, emit_ms: float, every_ms: Array, life_ms: Array,
		box: Array, vel: Array, size: Array, grow: float, spin: Array, color := Color.WHITE) -> Dictionary:
	const U := 1.0 / 400.0                 # Level.UNITS
	const V := 1000.0 / 4096.0 / 400.0     # velocity / growth field -> m/s
	return {"tex": tex, "additive": additive, "color": color, "fade": true,
		"emit": emit_ms / 1000.0 if emit_ms >= 0.0 else -1.0,
		"every": [every_ms[0] / 1000.0, every_ms[1] / 1000.0],
		"life": [life_ms[0] / 1000.0, life_ms[1] / 1000.0],
		"box": [box[0] * U, box[1] * U], "vel": [vel[0] * V, vel[1] * V],
		"size": [size[0] * U, size[1] * U], "grow": grow * V, "spin": spin}
