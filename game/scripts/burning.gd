# A zombie on fire (M2 Flamethrower): flames from the original flame sprite sheet
# on its body, damage over time while in the jet and for a few seconds after.
class_name Burning
extends Node3D

const TICK := 0.5

var zombie: Zombie
var by: Player
var dps := 150.0
var _left := 0.0
var _tick := 0.0
var _fx: CPUParticles3D
var _light: OmniLight3D
var _dying := false


static func ignite(z: Zombie, player: Player, damage_per_s: float, afterburn: float) -> Burning:
	var b := z.get_node_or_null("Burning") as Burning
	if b == null:
		b = Burning.new()
		b.name = "Burning"
		b.zombie = z
		z.add_child(b)
		b._tick = 0.15   # first damage almost at once
	b.by = player
	b.dps = maxf(b.dps if b._left > 0.0 else 0.0, damage_per_s)
	b._left = maxf(b._left, afterburn)
	return b


func _ready() -> void:
	_fx = WeaponFx.particles("0f74ae25", {"amount": 18, "lifetime": 0.7, "size": 0.55, "grow": 1.3,
		"speed": 0.6, "dir": Vector3.UP, "spread": 20.0, "gravity": Vector3(0, 1.2, 0), "one_shot": false,
		"frames": Vector2i(8, 4), "box": Vector3(0.22, 0.5, 0.22), "rotate": false, "local": false})
	add_child(_fx)
	_fx.position = Vector3.UP * (0.3 if zombie.crawler else 0.9)
	_fx.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 1.5
	_light.omni_range = 3.5
	_light.position = Vector3.UP * 1.0
	add_child(_light)


func _process(delta: float) -> void:
	if zombie == null or not is_instance_valid(zombie):
		queue_free()
		return
	_light.light_energy = 1.2 + randf() * 0.8
	_fx.position.y = 0.3 if zombie.crawler or zombie.state == Zombie.State.DEAD else 0.9
	if zombie.state == Zombie.State.DEAD:
		if not _dying:
			# the corpse keeps burning a little
			_dying = true
			var tw := create_tween()
			tw.tween_interval(1.5)
			tw.tween_callback(func(): _fx.emitting = false)
			tw.tween_property(_light, "light_energy", 0.0, 0.7)
			tw.tween_callback(queue_free)
		return
	_left -= delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		if by != null and is_instance_valid(by):
			zombie.take_damage(dps * TICK, false, by)
	if _left <= 0.0 and zombie.state != Zombie.State.DEAD:
		_fx.emitting = false
		set_process(false)
		name = "BurntOut"   # a new ignite() makes a fresh one
		get_tree().create_timer(0.8, false).timeout.connect(queue_free)
