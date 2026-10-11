# Power-up drop (World at War): spins above the floor, picked up by walking into
# it, blinks and disappears after 30 s. Models are the original pickup entities
# in the ingame dynamics group.
class_name Powerup
extends Node3D

const KINDS := {
	"maxammo":      {"model": "7c941e6f", "voice": "maxammo",      "label": "MAX AMMO"},
	"instakill":    {"model": "105caeb0", "voice": "instakill",    "label": "INSTA-KILL"},
	"doublepoints": {"model": "005979ef", "voice": "doublepoints", "label": "DOPPI PUNTI"},
	"nuke":         {"model": "7c94b345", "voice": "nuke",         "label": "NUKE"},
	"carpenter":    {"model": "0190717f", "voice": "carpenter",    "label": "CARPENTER"},
}
const LIFETIME := 30.0
const PICK_RADIUS := 1.2

var kind := ""
var game: Game
var _age := 0.0
var _model: Node3D
static var _models: Node


func setup(g: Game, k: String, at: Vector3) -> void:
	game = g
	kind = k
	position = at + Vector3.UP * 0.6


func _ready() -> void:
	if _models == null:
		_models = (load("res://assets/models/ingame/dynamics.glb") as PackedScene).instantiate()
	var src := _models.find_child(KINDS[kind]["model"], true, false) as Node3D
	if src:
		_model = src.duplicate() as Node3D
		_model.transform = Transform3D.IDENTITY
		add_child(_model)
		for mi in _model.find_children("*", "MeshInstance3D") + ([_model] if _model is MeshInstance3D else []):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# green glow like the original pickups
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.3)
	light.light_energy = 1.5
	light.omni_range = 3.0
	add_child(light)


func _process(delta: float) -> void:
	_age += delta
	rotation.y += delta * 2.0
	if _model:
		_model.position.y = sin(_age * 3.0) * 0.08
		# blink during the last 6 seconds
		_model.visible = _age < LIFETIME - 6.0 or fmod(_age, 0.4) < 0.25
	if _age >= LIFETIME:
		queue_free()
		return
	var p := game.player
	if p and not p.dead and p.global_position.distance_to(global_position) < PICK_RADIUS + 0.6:
		game.apply_powerup(kind)
		queue_free()
