# First-person weapon model with procedural bob, recoil and reload motion.
# Weapon models come from the original player group: "<name>" is the
# first-person model, "<name>_lod1" the world model (used when the former
# has a different name). The original first-person animations (keyframe
# type 2) are not decoded yet, so arms are not shown.
class_name Viewmodel
extends Node3D

const BASE := Vector3(0.16, -0.17, -0.38)

var _model: Node3D
var _recoil := 0.0
var _reload := 0.0
var _bob := 0.0


static func iw_hash(s: String) -> int:
	var h := 5381
	for c in s.to_lower().to_ascii_buffer():
		h = (h * 33 + c) & 0xFFFFFFFF
	return h


func set_weapon(name: String) -> void:
	if _model:
		_model.queue_free()
		_model = null
	for n in [name, name + "_lod1"]:
		var path := "res://assets/characters/ingame/player/%08x.glb" % iw_hash(n)
		if ResourceLoader.exists(path):
			_model = (load(path) as PackedScene).instantiate()
			break
	if _model == null:
		return
	add_child(_model)
	# models point down +Z; the camera looks down -Z
	_model.rotation.y = PI
	for mi in _model.find_children("*", "MeshInstance3D"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# hold the grip near the bottom right of the screen whatever the model's origin
	var aabb := AABB()
	var first := true
	for mi in _model.find_children("*", "MeshInstance3D"):
		var a: AABB = mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	# centre it sideways/vertically and put the stock end just in front of BASE,
	# so long rifles extend forward instead of behind the camera
	var c := Basis(Vector3.UP, PI) * aabb.get_center()
	var near_end := -aabb.position.z  # model +Z is forward, so its min z ends up closest to the camera
	_model.position = Vector3(-c.x, -c.y, -near_end + 0.12)


func kick() -> void:
	_recoil = 1.0


func reload(duration: float) -> void:
	_reload = duration


func _process(delta: float) -> void:
	var player := get_parent().get_parent() as CharacterBody3D
	var moving := player != null and Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	_bob += delta * (9.0 if moving else 2.0)
	var amp := 0.012 if moving else 0.003
	_recoil = move_toward(_recoil, 0.0, delta * 8.0)
	_reload = max(_reload - delta, 0.0)
	var dip := 0.0
	if _reload > 0.0:
		dip = sin(min(_reload, 1.0) * PI) * 0.25
	position = BASE + Vector3(sin(_bob) * amp, abs(cos(_bob)) * amp - dip, _recoil * 0.06)
	rotation = Vector3(_recoil * 0.12 - dip * 1.5, 0, dip * 0.8)
