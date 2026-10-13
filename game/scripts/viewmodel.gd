# First-person arms + weapon from the original player group.
# The weapon hangs from the arms' tag bone; each weapon animation is paired with
# an arms animation (see tools/pair_arms.py -> arms_pairs.json). Both models
# face +Z, the camera looks down -Z, hence the half turn.
class_name Viewmodel
extends Node3D

const DIR := "res://assets/characters/ingame/player/"

static var _pairs: Dictionary
const ARM_DONOR := {"ppsh": "thompson", "type100": "thompson", "fg42": "bar", "raygun": "colt45",
	"flamethrower": "bar", "wunderwaffe": "mg42"}

var _arms: Node3D
var _arms_anim: AnimationPlayer
var _weapon: Node3D
var _weapon_anim: AnimationPlayer
var _attach: BoneAttachment3D
var _anims := {}   # action -> [weapon anim, arms anim]
var _bob := 0.0
const LAYER := 2   # render layer of the first-person models (Game.muzzle_flash skips it)
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
	_weapon.visible = not drinking and _item == null
	var wap := _weapon.find_children("*", "AnimationPlayer")
	_weapon_anim = wap[0] if wap.size() > 0 else null
	_anims = info.get("anims", {}).duplicate(true)
	# weapons whose arms animations could not be paired reliably borrow the arms of a
	# similar weapon (their own weapon animations are kept)
	var donor: String = ARM_DONOR.get(name, "")
	if donor != "":
		var d: Dictionary = pairs()["weapons"][donor]["anims"]
		for act in d:
			var own: String = _anims[act][0] if _anims.has(act) else ""
			_anims[act] = [own, d[act][1]]
	if not drinking and _item == null:
		_play("idle", true)


func _no_shadows(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = LAYER   # out of the muzzle light


func _play(action: String, loop := false) -> float:
	if drinking or _item != null:
		return 0.0
	# The idle arms poses were paired by timing alone and some are wrong (FG42, PPSh):
	# hold the first frame of the shoot animation instead, which always starts in the grip pose.
	if action == "idle" and _anims.has("shoot"):
		_hold_first_frame("shoot")
		return 0.0
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


func _hold_first_frame(action: String) -> void:
	var pair: Array = _anims[action]
	for p in [[_weapon_anim, pair[0]], [_arms_anim, pair[1]]]:
		var ap: AnimationPlayer = p[0]
		if ap and ap.has_animation(p[1]):
			ap.stop()
			ap.play(p[1])
			ap.seek(0.0, true)
			ap.pause()


func _back_to_idle(action: String) -> void:
	if drinking or _item != null:
		return
	if not _arms_anim.is_playing() or _arms_anim.current_animation == "" or _arms_anim.current_animation == _anims.get(action, ["", ""])[1]:
		_play("idle", true)


# Knife slash: none of the original arms animations matches the iOS knife, so it is
# procedural. The knife is a rigid child of the right hand, set at the start of the
# slash so its tip points to the left of the screen; the arms then sweep left -> right.
const KNIFE_MODEL := "78d2d941"   # knife_lod1 in the player group
const GRIP_BONE := 15             # left hand (chain 13-14-15, fingers 16-21); the knife uses the left arm only
const PALM := Vector3(0.011, -0.012, 0.004)  # inside the fist: palm centroid moved back towards the wrist and into the palm
const HIDE_BONE := 4              # right upper arm: collapsed while knifing
const KNIFE_GRIP := 0.05          # metres from the model origin (pommel end) to the middle of the handle
const SLASH_TIME := 0.42
var _knife: Node3D
var _hand: BoneAttachment3D
var _skel: Skeleton3D
var _slash := -1.0                # 0..1 while slashing
var _knife_set := false


func melee() -> void:
	if _slash >= 0.0 or drinking or _item != null:
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
	_skel.set_bone_pose_scale(HIDE_BONE, Vector3.ZERO)  # right arm out of view
	_slash = 0.0
	_knife_set = false


func _end_melee() -> void:
	_slash = -1.0
	_skel.set_bone_pose_scale(HIDE_BONE, Vector3.ONE)
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


# Perk-a-Cola: the weapon goes away, the arms drink from the bottle (the bottle
# model and both animations are from the player group: the weapon state machines'
# drinkPerkCola state plays them with the perk_drink sound sequence), then the
# weapon comes back. The bottle hangs from the weapon tag bone like a weapon; the
# original has one bottle model for every perk.
const BOTTLE_MODEL := "fbd2a17d"
const BOTTLE_ANIM := "a0ab314d"
const DRINK_ARMS := "a239daae"   # 2.54 s like the bottle animation (d926090d, same timing, lights the molotov)
var drinking := false
var _bottle: Node3D
var _bottle_anim: AnimationPlayer
var _drink_id := 0


func drink() -> float:
	if _bottle == null:
		if not ResourceLoader.exists(DIR + BOTTLE_MODEL + ".glb"):
			return 0.0
		_bottle = (load(DIR + BOTTLE_MODEL + ".glb") as PackedScene).instantiate()
		_attach.add_child(_bottle)
		_no_shadows(_bottle)
		var aps := _bottle.find_children("*", "AnimationPlayer")
		_bottle_anim = aps[0] if aps.size() > 0 else null
	_clear_item()
	_slash = -1.0
	if _skel:
		_skel.set_bone_pose_scale(HIDE_BONE, Vector3.ONE)
	if _knife:
		_knife.visible = false
	drinking = true
	if _weapon:
		_weapon.visible = false
	_bottle.visible = true
	var arms := DRINK_ARMS
	var ai := OS.get_cmdline_user_args().find("--drink-arms")
	if ai >= 0:
		arms = OS.get_cmdline_user_args()[ai + 1]
	var length := 2.5
	for p in [[_arms_anim, arms], [_bottle_anim, BOTTLE_ANIM]]:
		var ap: AnimationPlayer = p[0]
		if ap and ap.has_animation(p[1]):
			ap.get_animation(p[1]).loop_mode = Animation.LOOP_NONE
			ap.stop()
			ap.play(p[1])
			length = ap.get_animation(p[1]).length
	Sfx.instance.sequence("perk_drink")
	_drink_id += 1
	var id := _drink_id
	get_tree().create_timer(length, false).timeout.connect(func():
		if id == _drink_id:
			_end_drink())
	return length


func _end_drink() -> void:
	drinking = false
	if _bottle:
		_bottle.visible = false
	if _weapon:
		_weapon.visible = true
	_kick = -0.6  # weapon comes up from below
	_play("idle", true)


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


# Grenades and monkey bombs, from the arms state machine "base_arms" (CIsAnimStateMachine
# in the player group, state names recovered from their hashes):
#   Priminggrenade      arms fdec0a8f (0.17 s), primeGrenade call; the pose is held while
#                       the button is down (the grenade is cooking)
#   Throwinggrenade     arms fe14380f (0.21 s), throwGrenade call at 99 ms; at 0.17 s the
#                       tag bone jumps away (the grenade has left the hand)
#   Throwingmonkeybomb  arms 5b46984c + monkey bb6812ab ("monkeybomb_throw", 3.4 s): the
#                       monkey is brought up, wound (the key turns), then thrown at the end
# then the state machine switches back to the gun. The item hangs from the weapon tag
# bone like a weapon (grenade1 c53574cc is a static model, the monkey has its skeleton).
const GRENADE_PRIME := "fdec0a8f"
const GRENADE_THROW := "fe14380f"
const GRENADE_RELEASE := 0.099      # throwGrenade at 99 ms
const MONKEY_ARMS := "5b46984c"
const MONKEY_ANIM := "bb6812ab"     # monkeybomb_throw
const MONKEY_RELEASE := 3.3         # hand at the end of the forward swing
var _item: Node3D
var _item_id := 0


func throwing() -> bool:
	return _item != null


# where the thrown item leaves the hand (world space), null without an item in hand
func item_position() -> Variant:
	return _item.global_position if _item and _item.is_inside_tree() else null


# Shows `item` in hand and plays the arms animation (held on its last frame).
func hold_item(item: Node3D, arms_anim: String, item_anim := "") -> float:
	_clear_item()
	_slash = -1.0
	if _skel:
		_skel.set_bone_pose_scale(HIDE_BONE, Vector3.ONE)
	if _knife:
		_knife.visible = false
	if _weapon:
		_weapon.visible = false
	_item = item
	_attach.add_child(item)
	_no_shadows(item)
	_item_id += 1
	var length := _play_raw(_arms_anim, arms_anim)
	if item_anim != "":
		var aps := item.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			length = maxf(length, _play_raw(aps[0], item_anim))
	return length


# Plays the throw (or lets the held animation run when arms_anim is ""); the item is
# removed after `release` s, the weapon comes back at the end of the animation.
func throw_item(arms_anim: String, release: float) -> float:
	if _item == null:
		return 0.0
	var length := 0.0
	if arms_anim != "":
		length = _play_raw(_arms_anim, arms_anim, 0.05)
	elif _arms_anim.is_playing():
		length = _arms_anim.current_animation_length - _arms_anim.current_animation_position
	var id := _item_id
	get_tree().create_timer(release, false).timeout.connect(func():
		if id == _item_id and _item:
			_item.visible = false)
	get_tree().create_timer(maxf(length, release), false).timeout.connect(func():
		if id == _item_id:
			end_item())
	return length


# Back to the weapon (also when the grenade went off in hand or the player died).
func end_item() -> void:
	if _item == null:
		return
	_clear_item()
	if drinking:
		return
	if _weapon:
		_weapon.visible = true
	_kick = -0.6  # weapon comes up from below
	_play("idle", true)


func _clear_item() -> void:
	_item_id += 1
	if _item:
		_item.queue_free()
		_item = null


# blend: from the held pose (the original has no clip linking primed pose and throw)
func _play_raw(ap: AnimationPlayer, anim: String, blend := 0.0) -> float:
	if ap == null or not ap.has_animation(anim):
		return 0.0
	var a := ap.get_animation(anim)
	a.loop_mode = Animation.LOOP_NONE
	if blend <= 0.0:
		ap.stop()
	ap.play(anim, blend)
	return a.length
