# First-person player: movement, shooting, buying, repairing barricades.
class_name Player
extends CharacterBody3D

signal died
signal changed  # points/ammo/weapon/health changed (HUD refresh)

const SPEED := 4.2
const SPRINT := 6.0
const JUMP := 4.0
const GRAVITY := 12.0
const MOUSE_SENS := 0.0025
const MAX_HEALTH := 100.0
const REGEN_DELAY := 4.0
const INTERACT_RANGE := 1.8

var game: Node  # Game
var points := 500
var health := MAX_HEALTH
var max_health := MAX_HEALTH   # raised by Juggernog
var perks := []                # owned perks (Perks.ORDER keys), lost when going down
var dead := false
var weapons := []          # [{name, mag, reserve}]
var current := 0
var prompt := ""           # interaction hint for the HUD
var move_input := Vector2.ZERO   # set by touch controls (mobile)
var fire_held := false           # set by touch controls (mobile)

var _camera: Camera3D
var _viewmodel: Viewmodel
var _cooldown := 0.0
var _reloading := 0.0
var _since_hit := 99.0
var _kick := 0.0
var _repair_cooldown := 0.0


func _ready() -> void:
	collision_mask = 1 | 2 | 4  # world, zombies, window blockers
	floor_snap_length = 0.5   # stick to stairs when walking down
	floor_max_angle = deg_to_rad(50)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	shape.shape = cap
	shape.position.y = 0.875
	add_child(shape)
	_camera = Camera3D.new()
	_camera.position.y = 1.6
	_camera.fov = Settings.fov()  # user setting (pause menu)
	_camera.near = 0.05
	_camera.far = 400
	add_child(_camera)
	_camera.make_current()
	_viewmodel = Viewmodel.new()
	_camera.add_child(_viewmodel)
	changed.connect(_sync_viewmodel)
	add_child(GrenadeBelt.new())   # frag grenades (grenade_belt.gd)
	give_weapon("colt45")


func give_weapon(name: String) -> void:
	for i in weapons.size():
		if weapons[i]["name"] == name:
			var s := Weapons.stats_of(weapons[i])   # a Pack-a-Punched gun refills to its upgraded size
			weapons[i]["mag"] = s["mag"]
			weapons[i]["reserve"] = s["reserve"]
			current = i
			changed.emit()
			return
	var st := Weapons.stats(name)
	# reserve = spare ammo besides the magazine (original CItemGun); the start pistol
	# gets Weapons.START_RESERVE like the original Lua (AddPlayerWeapon("colt45", 32))
	var w := {"name": name, "mag": st["mag"], "reserve": Weapons.START_RESERVE if weapons.is_empty() and name == "colt45" else st["reserve"]}
	if weapons.size() >= 2:
		weapons[current] = w  # two-weapon limit: replace the one in hand
	else:
		weapons.append(w)
		current = weapons.size() - 1
	changed.emit()


func weapon() -> Dictionary:
	return weapons[current]


var _shown_weapon := ""


func _sync_viewmodel() -> void:
	var n: String = weapon()["name"]
	var key := n + ("+" if weapon().get("upgraded", false) else "")
	if key != _shown_weapon:
		_shown_weapon = key
		_viewmodel.set_weapon(n)
		if weapon().get("upgraded", false):
			PackAPunch.decorate(_viewmodel)


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative * MOUSE_SENS * Settings.mouse_sens())
	elif event.is_action_pressed("switch_weapon"):
		switch_weapon()
	elif event.is_action_pressed("reload"):
		reload()
	elif event.is_action_pressed("melee"):
		melee()


func look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	_camera.rotation.x = clamp(_camera.rotation.x - delta.y * (-1.0 if Settings.invert_y() else 1.0), -1.45, 1.45)


const KNIFE_DAMAGE := 150.0
const KNIFE_RANGE := 1.8  # metres, horizontal
var _melee_cooldown := 0.0


# Knife: short-range hit available with any weapon, as in the original.
func melee() -> void:
	if dead or _melee_cooldown > 0.0 or _viewmodel.throwing():
		return
	_melee_cooldown = 0.9
	_viewmodel.melee()
	Sfx.instance.play("knife_slash", -3.0)
	# like the original, the knife hits the zombie in front of the player whatever the
	# vertical aim (crawlers at your feet, zombies slightly to the side)
	var facing := -global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var best: Zombie = null
	var best_d := INF
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z is Zombie or z.state == Zombie.State.DEAD:
			continue
		var to: Vector3 = z.global_position - global_position
		if absf(to.y) > 2.0:
			continue
		to.y = 0.0
		var d := to.length()
		if d > KNIFE_RANGE or (d > 0.3 and facing.angle_to(to / d) > deg_to_rad(60)):
			continue
		# nothing solid in between (no stabbing through walls or window boards)
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, z.global_position + Vector3.UP * (0.4 if z.crawler else 1.0), 1)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		# a crawler lies at your feet: you have to aim down at it
		if z.crawler:
			var aim := -_camera.global_basis.z
			var body: Vector3 = (z.global_position + Vector3.UP * 0.3 - _camera.global_position).normalized()
			if aim.angle_to(body) > deg_to_rad(35):
				continue
		if d < best_d:
			best_d = d
			best = z
	if best:
		best.take_damage(knife_damage(best), false, self, true)


# World at War knife: always 150 damage (one stab at round 1, two at round 2...)
func knife_damage(_z: Zombie) -> float:
	return KNIFE_DAMAGE


func switch_weapon() -> void:
	if weapons.size() > 1:
		current = (current + 1) % weapons.size()
		_reloading = 0.0
		changed.emit()


func reload() -> void:
	var w := weapon()
	var s := Weapons.stats_of(w)
	if _reloading > 0.0 or w["mag"] >= s["mag"] or w["reserve"] <= 0:
		return
	_reloading = s["reload"] * (Perks.SPEED_RELOAD if has_perk("speed") else 1.0)
	_viewmodel.reload(_reloading)
	Sfx.instance.sequence(w["name"] + "_reload")


func _physics_process(delta: float) -> void:
	if dead:
		return
	_cooldown -= delta
	_repair_cooldown -= delta
	_melee_cooldown -= delta
	_since_hit += delta
	if _since_hit > REGEN_DELAY and health < max_health:
		health = min(max_health, health + 40.0 * delta)
		changed.emit()
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			_finish_reload()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + move_input
	input = input.limit_length(1.0)
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	var speed := SPRINT if Input.is_action_pressed("sprint") else SPEED
	if game and game.level and game.level.in_water(global_position):
		speed *= Level.WATER_MOVE_SPEED   # wading in the swamp (level.gd)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * delta
	if is_on_floor():
		Stairs.step_up(self, delta)
	move_and_slide()
	_footsteps(delta)

	var w := weapon()
	var s := Weapons.stats_of(w)
	var wants_fire := fire_held
	if s["auto"]:
		wants_fire = wants_fire or Input.is_action_pressed("fire")
	else:
		wants_fire = wants_fire or Input.is_action_just_pressed("fire")
	if wants_fire and _cooldown <= 0.0 and _reloading <= 0.0:
		_fire(w, s)
		if not s["auto"]:
			fire_held = false
	_kick = move_toward(_kick, 0.0, delta * 0.3)
	_camera.rotation.z = 0.0
	_update_prompt()
	if Input.is_action_pressed("interact"):
		interact()


# Footsteps, as the original player update does them (CPlayer, kiwi 0x1a1f88):
# when the step timer has run out and the player moves, the next sound of
# WalkingFootstepSounds (console.bin: player_footstep_walk3,player_footstep_walk4)
# plays, or of WalkingFootstepWaterSounds (water_walk1,water_walk2) when the floor
# is water (collision material flag 2 there; the swamp water of level.gd here), in
# turn with one shared index; then the timer restarts at
# FootstepSpeedMultiplier / (|vx| + |vz|) of the velocity in the player's frame: the
# faster (and the more diagonal the stick: it is the Manhattan length) the player
# moves, the closer the steps; wading at half speed
# (WaterMoveSpeedModifier) doubles the interval. FootstepSpeedMultiplier (fixed 14/4096
# per world unit/frame of the original) is set here as metres of |vx|+|vz| per step,
# calibrated by ear (0.42 s at walking speed). Sound specs: volume 0x599/4096
# (-9 dB), pitch 0x0c00/4096 (0.75). The original has no zombie footsteps.
const FOOTSTEPS := ["player_footstep_walk3", "player_footstep_walk4"]
const FOOTSTEPS_WATER := ["water_walk1", "water_walk2"]
const FOOTSTEP_STRIDE := 1.75
const FOOTSTEP_DB := -9.1
const FOOTSTEP_PITCH := 0.75
var _step_t := 0.0
var _step_i := 0
var footsteps_log := []   # [time, sound] (tests)


func _footsteps(delta: float) -> void:
	_step_t -= delta
	if _step_t > 0.0 or not is_on_floor():
		return
	var v := global_basis.inverse() * get_real_velocity()   # in the player's frame, as the original's
	var hv := absf(v.x) + absf(v.z)
	if hv < 0.05:
		return
	var water: bool = game != null and game.level != null and game.level.in_water(global_position)
	var list: Array = FOOTSTEPS_WATER if water else FOOTSTEPS
	if _step_i >= list.size():
		_step_i = 0
	if Sfx.instance:
		Sfx.instance.play(list[_step_i], FOOTSTEP_DB, FOOTSTEP_PITCH)
	if footsteps_log.size() < 200:
		footsteps_log.append([Time.get_ticks_msec() / 1000.0, list[_step_i]])
	_step_i += 1
	_step_t = FOOTSTEP_STRIDE / hv


func _fire(w: Dictionary, s: Dictionary) -> void:
	if w["mag"] <= 0:
		reload()
		return
	w["mag"] -= 1
	Achievements.fired(w["name"])
	_cooldown = s["rate"] * (Perks.DBTAP_RATE if has_perk("dbtap") else 1.0)
	_viewmodel.kick()
	if w["name"] != "flamethrower":   # FlameJet plays its own fire loop
		Sfx.instance.weapon_fire(w["name"])
	_camera.rotation.x = min(_camera.rotation.x + 0.012, 1.45)
	var space := get_world_3d().direct_space_state
	# Ray Gun bolt / flamethrower cone (weapon_fx.gd) replace the hitscan
	if not WeaponFx.fire(self, w, s, _camera):
		_fire_bullet(s, space)
	game.muzzle_flash(_camera)
	if w["mag"] == 0:
		reload()
	changed.emit()


# One shot as in the original (weapons.gd): the bullet goes through up to s.hits
# zombies (each one passed lowers the damage) and stops at the first wall; shotguns
# hit every zombie inside their cone once (no pellets). Damage from Weapons.hit_damage.
func _fire_bullet(s: Dictionary, space: PhysicsDirectSpaceState3D) -> void:
	var from := _camera.global_position
	var dir := -_camera.global_basis.z
	var reach := float(s.get("range", Weapons.RANGE))
	var exclude: Array[RID] = [get_rid()]
	var targets := []   # [distance, zombie, hit position, head]
	var first := Vector3.INF
	var cone := float(s.get("cone", 0.0))
	while targets.size() < int(s.get("hits", 1)):
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1 | 2)  # bullets ignore window blockers
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var pos: Vector3 = hit["position"]
		if first == Vector3.INF:
			first = pos
		var target: Object = hit["collider"]
		if not target is Zombie:
			game.spawn_impact(pos, hit["normal"])
			reach = from.distance_to(pos)
			break
		var z := target as Zombie
		exclude.append(z.get_rid())
		targets.append([from.distance_to(pos), z, pos, pos.y > z.global_position.y + 1.45])
	RadioEggs.bullet(self, from, first + dir * 0.5 if first != Vector3.INF else from + dir * reach)   # easter-egg triggers
	if cone > 0.0:
		targets = _cone_targets(s, space, from, dir, cone)
	for i in targets.size():
		var t: Array = targets[i]
		var z: Zombie = t[1]
		if not is_instance_valid(z):
			continue
		var pos: Vector3 = t[2]
		var lateral := (pos - from - dir * dir.dot(pos - from)).length() if cone > 0.0 else 0.0
		var loc := -1 if cone > 0.0 else Weapons.location(z, pos, t[3])
		z.take_damage(Weapons.hit_damage(s, t[0], i, loc, lateral), t[3], self, false, pos)


# Zombies inside the shotgun cone (full angle `cone` degrees, up to s.hits, nearest
# first) with a clear line from the muzzle: [distance, zombie, aim point, false].
func _cone_targets(s: Dictionary, space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, cone: float) -> Array:
	var tan_half := tan(deg_to_rad(cone * 0.5))
	var reach := float(s.get("range", Weapons.RANGE))
	var out := []
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z.state == Zombie.State.DEAD:
			continue
		var c := z.global_position + Vector3.UP * (0.35 if z.crawler or z is Dog else 1.1)
		var along := dir.dot(c - from)
		if along <= 0.05 or along > reach:
			continue
		var off := (c - from - dir * along).length()
		if off > along * tan_half + 0.3:   # cone vs the zombie's ~0.3 m body
			continue
		var aim := from + dir * along + (c - from - dir * along).limit_length(maxf(off - 0.3, 0.0))
		var q := PhysicsRayQueryParameters3D.create(from, aim, 1)   # walls only
		if not space.intersect_ray(q).is_empty():
			continue
		out.append([along, z, aim, false])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out.slice(0, int(s.get("hits", 1)))


func _finish_reload() -> void:
	var w := weapon()
	var s := Weapons.stats_of(w)
	var take: int = min(s["mag"] - w["mag"], w["reserve"])
	w["mag"] += take
	w["reserve"] -= take
	changed.emit()


func add_points(n: int) -> void:
	if n < 0:
		print("[points] spent %d at %s" % [-n, global_position])
	points += n
	Achievements.points(n)
	changed.emit()


func take_hit(damage: float) -> void:
	if dead or _revive_grace > 0.0:
		return
	health -= damage
	_since_hit = 0.0
	Sfx.instance.play("zombie_hit", -2.0)
	Sfx.instance.play("player_pain", -4.0)
	changed.emit()
	if health <= 0.0:
		if has_perk("revive"):
			_self_revive()
			return
		dead = true
		perks.clear()
		died.emit()


# ------------------------------------------------------------------ perks

var _revive_grace := 0.0


func has_perk(kind: String) -> bool:
	return kind in perks


func give_perk(kind: String) -> void:
	if has_perk(kind):
		return
	perks.append(kind)
	if kind == "jugga":
		max_health = Perks.JUGG_HEALTH
		health = max_health
	changed.emit()


# Solo Quick Revive: instead of dying, get back up once; every perk is lost (WaW).
func _self_revive() -> void:
	perks.clear()
	max_health = MAX_HEALTH
	health = max_health
	_revive_grace = Perks.REVIVE_GRACE
	get_tree().create_timer(Perks.REVIVE_GRACE, false).timeout.connect(func(): _revive_grace = 0.0)
	Sfx.instance.play("player_heartbeat")
	changed.emit()


# ------------------------------------------------------------------ interaction

func _update_prompt() -> void:
	prompt = ""
	var t = _interaction_target()
	if t == null:
		return
	if t is MysteryBox or t is PerkMachine or (t is Object and t in game.level.interactables):
		prompt = t.prompt(self)
	elif t is Barricade:
		prompt = "Tieni premuto E per riparare la barricata"
	elif t is Debris:
		prompt = "Premi E per sgombrare [%d]" % t.cost
	elif t is Dictionary:
		var has := weapons.any(func(w): return w["name"] == t["weapon"])
		if has:
			prompt = "Premi E per le munizioni %s [%d]" % [Weapons.display(t["weapon"]), t["ammo_cost"]]
		else:
			prompt = "Premi E per comprare %s [%d]" % [Weapons.display(t["weapon"]), t["cost"]]


func _interaction_target():
	var p := global_position
	for w in game.level.windows:
		if w.inside.distance_to(p) < INTERACT_RANGE and w.boards < Barricade.MAX_BOARDS and w.occupied_by == null:
			return w
	for b in game.level.boxes:
		if b.global_position.distance_to(p) < INTERACT_RANGE + 0.6 and b.prompt(self) != "":
			return b
	for m in game.level.perk_machines:
		if m.usable_from(p) and m.prompt(self) != "":
			return m
	# doors, traps, teleporters, Pack-a-Punch and wall buys can be in reach together
	# (the Der Riese lab trap lever is next to a door): the one looked at wins
	var cands := []
	for d in game.level.debris:
		if is_instance_valid(d) and d.global_position.distance_to(p) < INTERACT_RANGE + 1.0:
			cands.append([d, d.global_position])
	for o in game.level.interactables:
		if o.usable_from(p) and o.prompt(self) != "":
			var at: Vector3 = (o as Node3D).global_position
			for k in ["use_point", "centre", "_centre"]:
				if k in o:
					at = o.get(k)
					break
			cands.append([o, at])
	for b in game.wall_buys:
		if (b["position"] as Vector3).distance_to(p) < INTERACT_RANGE:
			cands.append([b, b["position"]])
	var best = null
	var best_score := -INF
	var eye := _camera.global_position
	var fwd := -_camera.global_basis.z
	for c in cands:
		var to: Vector3 = c[1] - eye
		var score := fwd.dot(to.normalized()) - to.length() * 0.05
		if score > best_score:
			best_score = score
			best = c[0]
	return best


func interact() -> void:
	var t = _interaction_target()
	if t == null:
		return
	if t is Barricade:
		if _repair_cooldown <= 0.0 and t.repair_board():
			_repair_cooldown = 1.0
			add_points(10)
			Achievements.repaired(10)
			Sfx.instance.play_at("window_repair", t.global_position)
	elif not Input.is_action_just_pressed("interact"):
		return
	elif t is MysteryBox or t is PerkMachine or (t is Object and t in game.level.interactables):
		t.interact(self)
	elif t is Debris:
		if points >= t.cost:
			add_points(-t.cost)
			t.open()
			Sfx.instance.play("buy_success")
			Sfx.instance.play_at("dooropen", t.global_position)
		else:
			Sfx.instance.play("buy_fail")
	elif t is Dictionary:
		var has := weapons.any(func(w): return w["name"] == t["weapon"])
		var cost: int = t["ammo_cost"] if has else t["cost"]
		if points >= cost:
			add_points(-cost)
			give_weapon(t["weapon"])
			Sfx.instance.play("buy_success")
		else:
			Sfx.instance.play("buy_fail")
