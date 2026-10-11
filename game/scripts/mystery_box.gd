# Mystery box (CMysteryBoxSpec entity). The box logic lived in the engine, not in
# Lua, so it follows World at War: 950 points, the lid opens, weapons cycle above
# the box for ~4 s, the result floats for 12 s and sinks back if not taken.
class_name MysteryBox
extends Node3D

const COST := 950
const MODEL := "ecee0a62"
const ANIM_OPEN := "d8283c46"
const ANIM_CLOSE := "dc54990a"
const ANIM_IDLE_OPEN := "ef143ac4"
const ANIM_IDLE_CLOSED := "b4bcad2c"
const CYCLE_TIME := 4.2
const OFFER_TIME := 12.0
# weapons the box can give (models and stats exist for all of them)
const POOL := ["raygun", "mg42", "browning", "bar", "ptrs", "stg44", "ppsh", "mp40", "type100", "thompson",
	"garand", "g43", "trenchgun", "shotgun", "sawnoff", "springfield", "flamethrower", "fg42", "arisaka"]

enum State { CLOSED, CYCLING, OFFERED, CLOSING }

var state := State.CLOSED
var offered := ""
var _anim: AnimationPlayer
var _weapon: Node3D
var _timer := 0.0
var _swap := 0.0
var _buyer: Player
var _cache := {}


func setup(level: Level, entity: String) -> void:
	var e: Dictionary = level.entities[entity]
	global_transform = level.entity_transform(entity, true)
	var path := "res://assets/characters/levels/%s/dynamics/%s.glb" % [level.level_name, MODEL]
	if ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate()
		add_child(model)
		_anim = model.find_children("*", "AnimationPlayer")[0]
		_pose(ANIM_IDLE_CLOSED)
	# solid box from the entity collider (world aligned, like the debris)
	var body := StaticBody3D.new()
	add_child(body)
	for c in e.get("colliders", []):
		var lo := Vector3(c["min"][0], c["min"][1], c["min"][2]) * Level.UNITS
		var hi := Vector3(c["max"][0], c["max"][1], c["max"][2]) * Level.UNITS
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (hi - lo).max(Vector3(0.2, 0.2, 0.2))
		shape.shape = box
		body.add_child(shape)
		shape.global_transform = Transform3D(Basis(), level.entity_transform(entity).origin + (lo + hi) / 2)


func _pose(a: String) -> void:
	if _anim and _anim.has_animation(a):
		_anim.play(a)
		_anim.seek(0.0, true)
		_anim.pause()


func prompt(player: Player) -> String:
	match state:
		State.CLOSED:
			return "Premi E per la Mystery Box [%d]" % COST
		State.OFFERED:
			if player == _buyer:
				return "Premi E per prendere %s" % Weapons.display(offered)
	return ""


func interact(player: Player) -> void:
	match state:
		State.CLOSED:
			if player.points < COST:
				return
			player.add_points(-COST)
			_buyer = player
			_open()
		State.OFFERED:
			if player == _buyer:
				player.give_weapon(offered)
				_close()


func _open() -> void:
	state = State.CYCLING
	_timer = CYCLE_TIME
	if _anim:
		_anim.play(ANIM_OPEN)
	_show_weapon(POOL.pick_random())


func _close() -> void:
	state = State.CLOSING
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	if _anim:
		_anim.play(ANIM_CLOSE)
	var t := _anim.get_animation(ANIM_CLOSE).length if _anim else 0.5
	get_tree().create_timer(t + 0.3).timeout.connect(func():
		state = State.CLOSED
		_pose(ANIM_IDLE_CLOSED))


func _process(delta: float) -> void:
	match state:
		State.CYCLING:
			_timer -= delta
			_swap -= delta
			var p := 1.0 - _timer / CYCLE_TIME
			if _weapon:
				_weapon.position = Vector3(0, 0.25 + 0.45 * p, 0)
			if _timer <= 0.0:
				offered = _pick()
				_show_weapon(offered)
				state = State.OFFERED
				_timer = OFFER_TIME
			elif _swap <= 0.0:
				_swap = lerpf(0.08, 0.35, p)  # slows down like the original
				_show_weapon(POOL.pick_random())
		State.OFFERED:
			_timer -= delta
			if _weapon:
				# floats, then sinks back into the box in the last seconds
				var sink := clampf((3.0 - _timer) / 3.0, 0.0, 1.0)
				_weapon.position = Vector3(0, 0.7 - 0.45 * sink + sin(_timer * 3.0) * 0.02, 0)
			if _timer <= 0.0:
				_close()


func _pick() -> String:
	var owned := _buyer.weapons.map(func(w): return w["name"]) if _buyer else []
	var choices := POOL.filter(func(w): return not w in owned)
	return choices.pick_random() if not choices.is_empty() else POOL.pick_random()


func _show_weapon(name: String) -> void:
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	# same model as held in first person (tools/pair_arms.py picks it per weapon)
	var path := ""
	var info: Dictionary = Viewmodel.pairs()["weapons"].get(name, {})
	if info.has("model"):
		path = "res://assets/characters/ingame/player/%s.glb" % info["model"]
	if path == "" or not ResourceLoader.exists(path):
		return
	if not _cache.has(path):
		_cache[path] = load(path)
	# holder floats; the model inside is centred on its bounds (origins vary per model)
	_weapon = Node3D.new()
	add_child(_weapon)
	var model: Node3D = (_cache[path] as PackedScene).instantiate()
	_weapon.add_child(model)
	model.rotation.y = PI / 2  # lie along the box
	var bounds := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# static display: unbind the skin so the mesh shows as modelled, matching its bounds
		mi.skin = null
		mi.skeleton = NodePath("")
		var a: AABB = mi.get_aabb()
		bounds = a if first else bounds.merge(a)
		first = false
	model.position = -(model.basis * bounds.get_center())
