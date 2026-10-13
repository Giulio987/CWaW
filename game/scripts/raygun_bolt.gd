# Ray Gun projectile (World at War): a fast glowing bolt; on impact the zombie hit
# takes the full damage and everything within ~2 m takes splash damage (the
# player too when very close). Green, red for the Pack-a-Punched Porter's X2.
class_name RaygunBolt
extends Node3D

const SPEED := 55.0

var player: Player
var damage := 1000.0
var head_mul := 1.0
var upgraded := false
var max_range := 100.0

var _dir := Vector3.FORWARD
var _from := Vector3.ZERO     # collision is traced from here (the camera on the first step)
var _travelled := 0.0
var _visual_offset := Vector3.ZERO
var _done := false


func launch(eye: Vector3, muzzle: Vector3, dir: Vector3) -> void:
	_dir = dir.normalized()
	_from = eye
	global_position = eye
	# the sprite starts at the muzzle and converges onto the aim line
	_visual_offset = muzzle - eye
	_build()
	_place_visual()


func _build() -> void:
	var col := Color(1.0, 0.3, 0.25) if upgraded else Color(0.4, 1.0, 0.35)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	var m := WeaponFx.sprite_mat("b81905e3", true, false).duplicate() as StandardMaterial3D
	m.albedo_color = col
	q.material = m
	glow.mesh = q
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	var core := MeshInstance3D.new()
	core.name = "Core"
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.16, 0.16)
	q2.material = WeaponFx.sprite_mat("aca98856", true, false)
	core.mesh = q2
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.add_child(core)
	var trail := WeaponFx.particles("aca98856", {"amount": 24, "lifetime": 0.14, "size": 0.2, "grow": 0.3,
		"speed": 0.2, "one_shot": false, "color": col, "rotate": false})
	trail.name = "Trail"
	glow.add_child(trail)
	trail.emitting = true
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.0
	l.omni_range = 3.0
	l.light_cull_mask = ~Viewmodel.LAYER   # leaves the muzzle inside the gun: it would paint it green
	glow.add_child(l)


func _place_visual() -> void:
	var glow := get_node_or_null("Glow") as Node3D
	if glow:
		var k := clampf(1.0 - _travelled / 6.0, 0.0, 1.0)
		glow.position = _visual_offset * k


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := SPEED * delta
	var to := global_position + _dir * step
	var q := PhysicsRayQueryParameters3D.create(_from, to, 1 | 2)
	if player and is_instance_valid(player):
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_impact(hit)
		return
	global_position = to
	_from = to
	_travelled += step
	_place_visual()
	if _travelled > max_range:
		queue_free()


func _impact(hit: Dictionary) -> void:
	_done = true
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var target: Object = hit["collider"]
	var game := get_parent() as Node3D
	var direct: Zombie = null
	if target is Zombie and player:
		direct = target as Zombie
		var head := pos.y > direct.global_position.y + 1.45 and not direct.crawler
		direct.take_damage(damage * (head_mul if head else 1.0), head, player)
	var at := pos + normal * 0.1
	Explosion.blast(game, at, player, Explosion.raygun_cfg(damage), direct)
	Explosion.raygun_effect(game, at, upgraded)
	Sfx.instance.play_at("raygun_%d" % randi_range(1, 3), at, -6.0)
	# let the trail fade before freeing
	var glow := get_node_or_null("Glow") as Node3D
	if glow:
		glow.visible = false
	get_tree().create_timer(0.3, false).timeout.connect(queue_free)
