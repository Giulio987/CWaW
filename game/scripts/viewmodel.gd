# First-person arms + weapon from the original player group.
# The weapon hangs from the arms' tag bone; each weapon animation is paired with
# an arms animation (see tools/pair_arms.py -> arms_pairs.json). Both models
# face +Z, the camera looks down -Z, hence the half turn.
class_name Viewmodel
extends Node3D

const DIR := "res://assets/characters/ingame/player/"

static var _pairs: Dictionary

var _arms: Node3D
var _arms_anim: AnimationPlayer
var _weapon: Node3D
var _weapon_anim: AnimationPlayer
var _attach: BoneAttachment3D
var _anims := {}   # action -> [weapon anim, arms anim]
var _bob := 0.0
var _kick := 0.0


static func iw_hash(s: String) -> int:
	var h := 5381
	for c in s.to_lower().to_ascii_buffer():
		h = (h * 33 + c) & 0xFFFFFFFF
	return h


static func pairs() -> Dictionary:
	if _pairs.is_empty():
		_pairs = JSON.parse_string(FileAccess.get_file_as_string(DIR + "arms_pairs.json"))
	return _pairs


func _ready() -> void:
	pairs()
	rotation.y = PI
	_arms = (load(DIR + _pairs["arms_model"] + ".glb") as PackedScene).instantiate()
	add_child(_arms)
	_arms_anim = _arms.find_children("*", "AnimationPlayer")[0]
	var skel: Skeleton3D = _arms.find_children("*", "Skeleton3D")[0]
	_skel = skel
	_attach = BoneAttachment3D.new()
	skel.add_child(_attach)
	_attach.bone_idx = int(_pairs["tag_weapon"])
	_no_shadows(_arms)


func set_weapon(name: String) -> void:
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	var info: Dictionary = _pairs["weapons"].get(name, {})
	var model: String = info.get("model", "%08x" % iw_hash(name))
	if not ResourceLoader.exists(DIR + model + ".glb"):
		return
	_weapon = (load(DIR + model + ".glb") as PackedScene).instantiate()
	_attach.add_child(_weapon)
	_no_shadows(_weapon)
	var wap := _weapon.find_children("*", "AnimationPlayer")
	_weapon_anim = wap[0] if wap.size() > 0 else null
	_anims = info.get("anims", {})
	_play("idle", true)


func _no_shadows(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _play(action: String, loop := false) -> float:
	if not _anims.has(action):
		return 0.0
	var pair: Array = _anims[action]
	var length := 0.0
	for p in [[_weapon_anim, pair[0]], [_arms_anim, pair[1]]]:
		var ap: AnimationPlayer = p[0]
		if ap and ap.has_animation(p[1]):
			var a := ap.get_animation(p[1])
			a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			ap.stop()
			ap.play(p[1])
			length = max(length, a.length)
	if not loop and length > 0.0:
		get_tree().create_timer(length).timeout.connect(_back_to_idle.bind(action))
	return length


func _back_to_idle(action: String) -> void:
	if _arms_anim.current_animation == "" or _arms_anim.current_animation == _anims.get(action, ["", ""])[1]:
		_play("idle", true)


# Knife slash: none of the original arms animations matches the iOS knife, so it is
# procedural. The knife is a rigid child of the right hand, set at the start of the
# slash so its tip points to the left of the screen; the arms then sweep left -> right.
const KNIFE_MODEL := "78d2d941"   # knife_lod1 in the player group
const GRIP_BONE := 6              # right hand (chain 3-4-5-6, fingers 7-12; 15 is the left hand)
const PALM := Vector3(0.0, 0.0, 0.062)  # palm centre measured from the skin (raised into the fist)
const KNIFE_GRIP := 0.06          # metres from the model origin (pommel end) to mid-handle
const SLASH_TIME := 0.42
var _knife: Node3D
var _hand: BoneAttachment3D
var _skel: Skeleton3D
var _slash := -1.0                # 0..1 while slashing
var _knife_set := false


func melee() -> void:
	if _slash >= 0.0:
		return
	if _knife == null:
		_hand = BoneAttachment3D.new()
		_skel.add_child(_hand)
		_hand.bone_idx = GRIP_BONE
		var models: Node = (load("res://assets/models/ingame/player.glb") as PackedScene).instantiate()
		_knife = models.find_child(KNIFE_MODEL, true, false)
		if _knife:
			_knife.get_parent().remove_child(_knife)
			_hand.add_child(_knife)
			if _knife is GeometryInstance3D:
				_knife.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		models.queue_free()
	if _weapon:
		_weapon.visible = false
	if _knife:
		_knife.visible = false  # shown once oriented on the first slash frame
	_play("idle", true)
	_slash = 0.0
	_knife_set = false


func _end_melee() -> void:
	_slash = -1.0
	if _knife:
		_knife.visible = false
	if _weapon:
		_weapon.visible = true


# Arms offset in camera space: wind-up on the left, quick sweep to the right.
func _slash_offset() -> Transform3D:
	var t := _slash
	var sweep := smoothstep(0.1, 0.7, t)
	var arc := sin(clampf(t / 0.85, 0.0, 1.0) * PI)
	var pos := Vector3(lerpf(-0.40, 0.06, sweep), 0.15 + 0.03 * arc, -0.10 * arc)
	var yaw := lerpf(0.4, -0.3, sweep)
	return Transform3D(Basis.from_euler(Vector3(0.0, yaw, -0.2 * arc)), pos)


func _orient_knife() -> void:
	if _knife == null or _hand == null:
		return
	var cam := get_viewport().get_camera_3d()
	var palm := _hand.global_transform * PALM
	# model blade runs along +X: point it to the camera's left, edge slightly forward
	var b := cam.global_basis * Basis(Vector3.UP, PI - 0.3) * Basis(Vector3.RIGHT, 0.25)
	_knife.global_transform = Transform3D(b, palm - b.x * KNIFE_GRIP)
	_knife.visible = true
	_knife_set = true


func kick() -> void:
	_kick = 1.0
	_play("shoot")


func reload(duration: float) -> void:
	if _play("reload") == 0.0:
		_kick = -duration  # no reload animation for this weapon: dip instead


func _process(delta: float) -> void:
	var player := get_parent().get_parent() as CharacterBody3D
	var moving := player != null and Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	_bob += delta * (9.0 if moving else 2.0)
	var amp := 0.008 if moving else 0.002
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	var dip: float = clamp(-_kick, 0.0, 1.0) * 0.25
	var base := Transform3D(Basis(Vector3.UP, PI), Vector3(sin(_bob) * amp, abs(cos(_bob)) * amp - dip, max(_kick, 0.0) * 0.02))
	if _slash >= 0.0:
		_slash += delta / SLASH_TIME
		if _slash >= 1.0:
			_end_melee()
		else:
			base = _slash_offset() * base
	transform = base
	if _slash >= 0.0 and not _knife_set:
		_orient_knife()
