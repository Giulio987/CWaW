# Pack-a-Punch (Der Riese, CPackAPunchSpec "packapunch", cost 5000). As in
# derriese.lua it is off ("PaP_Static" model) until the power is on and works once
# all three teleporters are linked to the mainframe (UpdatePackAPunch: third link
# opens the mainframe door and enables the "packAPunch" trigger). Using it: pay,
# the gun goes in, ticks (pack_tick) for a few seconds, then must be taken back
# within a time limit; the taken gun is the "_upgrade" version (Weapons.UPGRADES).
class_name PackAPunch
extends Node3D

const STATIC_MODEL := "6f6f4191"
const ANIMATED_MODEL := "654a0eb5"
const WORK_TIME := 3.5
const TAKE_TIME := 12.0
const USE_RANGE := 2.3

enum State { IDLE, WORKING, READY }

var level: Level
var entity := ""
var cost := 5000
var state := State.IDLE
var _timer := 0.0
var _tick := 0.0
var _weapon: Dictionary = {}     # the held weapon dictionary being upgraded
var _centre := Vector3.ZERO
var _model_off: Node3D
var _model_on: Node3D
var _light: OmniLight3D


func setup(level_: Level, entity_: String) -> void:
	level = level_
	entity = entity_
	var e: Dictionary = level.entities[entity]
	cost = int(e.get("params", {}).get("cost", 5000))
	var root := level.entity_transform(entity)
	var cols: Array = e.get("colliders", [])
	_centre = root * Trap._box_centre(cols[0]) if not cols.is_empty() else root.origin
	var at := level.entity_transform("PaP_Static") if level.has_entity("PaP_Static") else root
	global_transform = at
	_model_off = level.dynamics_model(STATIC_MODEL)
	_model_on = level.dynamics_model(ANIMATED_MODEL)
	var aabb := AABB()
	for m in [_model_off, _model_on]:
		if m:
			add_child(m)
			for mi in m.find_children("*", "MeshInstance3D", true, false) + ([m] if m is MeshInstance3D else []):
				aabb = mi.get_aabb() if aabb.size == Vector3.ZERO else aabb.merge(mi.get_aabb())
	# the use zone of the entity overlaps the machine: stand in front of it, on the
	# side facing the mainframe door the player comes through
	if level.has_entity("mainframe_door"):
		var door := level.entity_transform("mainframe_door").origin
		var out := Vector3(door.x - at.origin.x, 0, door.z - at.origin.z).normalized()
		_centre = at.origin + out * (maxf(aabb.size.z, aabb.size.x) * 0.5 + 0.7)
	if aabb.size != Vector3.ZERO:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size
		cs.shape = box
		cs.position = aabb.get_center()
		body.add_child(cs)
		add_child(body)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.4, 0.8, 1.0)
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.8, 0)
	add_child(_light)
	level.power_changed.connect(func(_on): _refresh())
	_refresh()


func enabled() -> bool:
	return level.power_on and (level.teleporters == null or level.teleporters.linked_count() >= 3)


func _refresh() -> void:
	var on := enabled()
	if _model_off:
		_model_off.visible = not level.power_on or _model_on == null
	if _model_on:
		_model_on.visible = level.power_on
	_light.light_energy = 1.2 if on else 0.0


func usable_from(p: Vector3) -> bool:
	return Vector2(p.x - _centre.x, p.z - _centre.z).length() < USE_RANGE and absf(p.y - _centre.y) < 2.0


func prompt(player: Player) -> String:
	if not level.power_on:
		return "Serve la corrente"
	if not enabled():
		return "Collega i teletrasporti al mainframe"
	match state:
		State.WORKING:
			return ""
		State.READY:
			return "Premi E per prendere %s" % Weapons.UPGRADES[_weapon["name"]]["name"]
	var w := player.weapon()
	if w.get("upgraded", false):
		return "Arma già potenziata"
	if not Weapons.can_upgrade(w["name"]):
		return ""
	return "Premi E per potenziare l'arma [%d]" % cost


func interact(player: Player) -> void:
	if not enabled():
		return
	if state == State.READY:
		_give(player)
		return
	if state != State.IDLE:
		return
	var w := player.weapon()
	if w.get("upgraded", false) or not Weapons.can_upgrade(w["name"]):
		return
	if player.points < cost:
		Sfx.instance.play("buy_fail")
		return
	player.add_points(-cost)
	Sfx.instance.play_at(Sfx.iw_hash("pack_buy"), global_position + Vector3.UP)
	_weapon = w
	state = State.WORKING
	_timer = WORK_TIME
	_tick = 0.0


func _give(player: Player) -> void:
	var w := _weapon
	var idx := player.weapons.find(w)
	if idx < 0:
		# swapped away meanwhile: it comes back in place of the gun in hand
		w = {"name": _weapon["name"]}
		if player.weapons.size() >= 2:
			player.weapons[player.current] = w
		else:
			player.weapons.append(w)
		idx = player.weapons.find(w)
	w["upgraded"] = true
	var s := Weapons.stats_of(w)
	w["mag"] = s["mag"]
	w["reserve"] = s["reserve"]
	player.current = idx
	state = State.IDLE
	_weapon = {}
	Sfx.instance.play("buy_success")
	player.changed.emit()


func _process(delta: float) -> void:
	if state == State.IDLE:
		return
	_timer -= delta
	_tick -= delta
	if state == State.WORKING:
		_light.light_energy = 1.2 + sin(_timer * 20.0)
		if _tick <= 0.0:
			_tick = 0.5
			Sfx.instance.play_at(Sfx.iw_hash("pack_tick"), global_position + Vector3.UP)
		if _timer <= 0.0:
			state = State.READY
			_timer = TAKE_TIME
			_light.light_energy = 2.5
	elif state == State.READY and _timer <= 0.0:
		state = State.IDLE   # not taken in time: the gun is gone, as in the original
		var game := level.get_parent() as Game
		if game and game.player:
			var p := game.player
			var idx := p.weapons.find(_weapon)
			if idx >= 0 and p.weapons.size() > 1:
				p.weapons.remove_at(idx)
				p.current = 0
				p.changed.emit()
		_weapon = {}
		_refresh()


# Upgraded look, from the player group: every first-person weapon model's own
# materials are two-texture ones (flags 0x2d: the gun texture, then the "packapunch"
# camo texture 91f20da3 on the model's second UV set, combined as BLEND_MODULATE_2X).
# A normal CItemGun overrides them with its CIsMaterialSets (single-texture materials),
# a "<weapon>_upgrade" CItemGun has none, so the upgraded gun shows the camo.
const CAMO := "res://assets/textures/ingame/player/91f20da3.png"   # iw_hash("packapunch")
static var _shine: StandardMaterial3D


static func decorate(vm: Node) -> void:
	var wpn = vm.get("_weapon")
	if not wpn is Node:
		return
	var camo := load(CAMO) as Texture2D
	var found := false
	for mi: MeshInstance3D in (wpn as Node).find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null or camo == null:
				continue
			var lm := str(mat.get_meta("extras", {}).get("lightmap", ""))
			if not lm.ends_with(CAMO.get_file()):
				continue
			var m := mat.duplicate() as StandardMaterial3D
			m.detail_enabled = true
			m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
			# The trench gun model (02b0744d, also ppsh bed7ac37) has no CIwModelBlockGLUVs2
			# stream: like IwGx, sample the camo with the first UV set instead of a missing
			# second one (Godot would read (0, 0) and tint the whole gun one flat colour).
			if not (mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV2):
				m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
			m.detail_albedo = camo
			m.detail_mask = null
			m.albedo_color = Color(2.0, 2.0, 2.0)   # modulate x2
			mi.set_surface_override_material(s, m)
			found = true
	if found:
		return
	# no camo material (should not happen): a blue-purple sheen instead
	if _shine == null:
		_shine = StandardMaterial3D.new()
		_shine.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shine.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shine.albedo_color = Color(0.25, 0.12, 0.45, 0.35)
	for mi in (wpn as Node).find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _shine
