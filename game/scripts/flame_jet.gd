# Flamethrower jet: flame sprites (original 8x4 flame sheet + fireball) streaming
# from the muzzle while the trigger is held, a flickering light and the fire loop.
# Child of the player's camera; WeaponFx._fire_flamethrower() pulses it every shot.
class_name FlameJet
extends Node3D

const MUZZLE := Vector3(0.14, -0.13, -0.75)
const HOLD := 0.12      # keeps emitting this long after the last pulse
const SOUND_EVERY := 1.1

var _flames: CPUParticles3D
var _core: CPUParticles3D
var _light: OmniLight3D
var _since := 99.0
var _sound := 0.0


func _ready() -> void:
	position = MUZZLE
	_flames = WeaponFx.particles("0f74ae25", {"amount": 80, "lifetime": 0.5, "size": 0.7, "grow": 5.0,
		"speed": 13.0, "dir": Vector3.FORWARD, "spread": 5.0, "gravity": Vector3(0, 1.5, 0), "damping": 6.0,
		"one_shot": false, "frames": Vector2i(8, 4), "local": false})
	add_child(_flames)
	_core = WeaponFx.particles("f7bd0a62", {"amount": 40, "lifetime": 0.35, "size": 0.15, "grow": 6.0,
		"speed": 12.0, "dir": Vector3.FORWARD, "spread": 3.0, "damping": 4.0, "one_shot": false, "local": false,
		"color": Color(1.0, 0.85, 0.6, 0.8)})
	add_child(_core)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0, -1.5)
	add_child(_light)
	_set_on(false)


func pulse(upgraded: bool) -> void:
	_since = 0.0
	var c := Color(0.75, 0.85, 1.0) if upgraded else Color.WHITE   # Dante's Inferno burns hotter
	_flames.color = c
	if not _flames.emitting:
		_set_on(true)
	if _sound <= 0.0:
		_sound = SOUND_EVERY
		Sfx.instance.play("flamethrower_fire", -6.0, randf_range(0.97, 1.03))


func is_on() -> bool:
	return _flames.emitting


func _set_on(on: bool) -> void:
	_flames.emitting = on
	_core.emitting = on
	if not on:
		_light.light_energy = 0.0


func _process(delta: float) -> void:
	_since += delta
	_sound -= delta
	if _flames.emitting:
		_light.light_energy = 2.0 + randf() * 1.5
		if _since > HOLD:
			_set_on(false)
			_sound = 0.0
