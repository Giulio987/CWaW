# First-person player: movement, shooting, buying, repairing barricades.
class_name Player
extends CharacterBody3D

signal died
signal changed  # points/ammo/weapon/health changed (HUD refresh)

# Movement, from console.bin and the player movement code (kiwi 0x182c68 / ctor 0x182ea8):
# step = Max<State>MoveSpeed x WorldScale (4.0) x stick (iwfixed, after the
# analoguePadMovingResponse curve) x frame time in ms -> world units (400 per metre).
# The speeds are therefore centimetres per millisecond (= x10 m/s): MaxRunMoveSpeed /
# MaxWalkMoveSpeed / MaxRunStrafeSpeed 0.649 -> 6.49 m/s with the stick fully pushed
# (keyboard). Per-state caps replace it: MaxAimMoveSpeed 0.25 (2.5 m/s, aiming down the
# sights), MaxKnife/Grenade/Betty/Molotov/Monkey/DrinkPerkColaMoveSpeed 0.5 (5 m/s);
# BackpedalSpeedRatio 0.5 when the stick points backwards; WaterMoveSpeedModifier 0.5.
# (The Accel*Ramp* arrays are accelerometer tilt-steering curves, not acceleration.)
const MOVE_UNIT := 4.0 * 1000.0 / 400.0   # cm/ms x WorldScale -> m/s
const SPEED := 0.649 * MOVE_UNIT          # MaxRunMoveSpeed: 6.49 m/s
const AIM_SPEED := 0.25 * MOVE_UNIT       # MaxAimMoveSpeed
const ACTION_SPEED := 0.5 * MOVE_UNIT     # MaxKnife/Grenade/DrinkPerkCola/Monkey...MoveSpeed
const BACKPEDAL := 0.5                    # BackpedalSpeedRatio
const SPRINT := 8.0                       # remake extra (the original has no sprint)
const JUMP := 4.0                         # remake extra
const GRAVITY := 12.0
const MOUSE_SENS := 0.0025
# Health: CHealthSpec of the player entity (player group e8a50fda: max 20, regen 3000 ms)
# and console.bin PlayerHealth 20 / PerkedPlayerHealth 40 (Juggernog) / PlayerHealthRecruit
# 30 / PerkedPlayerHealthRecruit 60, scaled x5 to keep the remake's damage values
# (zombie / dog / trap / explosion hits are in these units).
const HEALTH_SCALE := 5.0
const MAX_HEALTH := 20.0 * HEALTH_SCALE
# CHealth (kiwi 0x19c6b4): REGEN_DELAY after the last hit, health jumps back to full
# (the delay restarts with every hit, kiwi 0x19c59c).
const REGEN_DELAY := 3.0
const INTERACT_RANGE := 1.8
# InteractTime 750 ms (console.bin; code default 1500): the use button is held this long
# to buy / open / use (barricade repair keeps its own per-board pace).
const INTERACT_TIME := 0.75

var game: Node  # Game
var points := 500
var health := MAX_HEALTH
var max_health := MAX_HEALTH   # raised by Juggernog, Recruit difficulty (base_health)
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
var _repair_cooldown := 0.0


func _ready() -> void:
	collision_mask = 1 | 2 | 4 | Level.SEE_THROUGH_LAYER  # world, zombies, window blockers, grids
	floor_snap_length = 0.5   # stick to stairs when walking down
	floor_max_angle = deg_to_rad(50)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.68   # eye at 1.6; 1.75 did not fit under the Doctor's hut porch roof (Shi No Numa)
	shape.shape = cap
	shape.position.y = 0.84
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
	add_child(BettyBelt.new())     # Bouncing Betties (betty_belt.gd)
	add_child(MolotovBelt.new())   # Molotov cocktails from the mystery box (molotov_belt.gd)
	add_child(BowieKnife.new())    # Bowie knife wall buy, Der Riese (bowie_knife.gd)
	give_weapon("colt45")
	max_health = base_health(false)
	health = max_health
	if not InputMap.has_action("aim"):   # aim down the sights: right mouse button
		InputMap.add_action("aim")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("aim", mb)


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
	elif event.is_action_pressed("aim"):
		aim_wanted = not aim_wanted if Settings.aim_toggle() else true
	elif event.is_action_released("aim") and not Settings.aim_toggle():
		aim_wanted = false


# Look input (mouse / touch drag), radians. Vertical speed is scaled like the original's
# default sensitivities (SensitivityYDefault 0.375 / SensitivityXDefault 0.5, settings.gd);
# aiming slows the turn rate: MaxAimTurnSpeed 0.5 / MaxRunTurnSpeed 1.0 and
# MaxAimVerticalAimSpeed 0.5 / MaxRunVerticalAimSpeed 0.7.
const AIM_TURN := 0.5
const AIM_VTURN := 0.5 / 0.7


func look(delta: Vector2) -> void:
	_look_amount += delta.length()
	delta.x *= lerpf(1.0, AIM_TURN, _aim_blend)
	delta.y *= lerpf(1.0, AIM_VTURN, _aim_blend) * Settings.look_y_ratio()
	rotate_y(-delta.x)
	_camera.rotation.x = clamp(_camera.rotation.x - delta.y * (-1.0 if Settings.invert_y() else 1.0), -1.45, 1.45)


const KNIFE_DAMAGE := 150.0
const KNIFE_RANGE := 1.8  # metres, horizontal (slash)
# Stab or slash (kiwi va 0x205e7c, on the knife button): the default is the slash (state 40);
# the stab (state 39) when the current target is closer than CItemKnife i_40 = 1000 units
# (2.5 m) and within i_44 = 136 (1/4096 turn, ~12 deg) of the view. The stab keeps that
# target (+0xdc) for its damage.
const STAB_RANGE := 2.5
const STAB_ANGLE := 136.0 / 4096.0 * TAU
const SLASH_ANGLE := PI / 3.0   # remake: zombies slightly to the side
# knifeDamage events of both states: 1 at 199 ms, 0 at 500 ms (stab) / 599 ms (slash): one
# hit per swing, at the start of the window
const KNIFE_HIT_TIME := 0.199
const STAB_TIME := 1.0    # state 39
const SLASH_TIME := 0.633 # state 40
var _melee_cooldown := 0.0
var _melee_id := 0


# Knife: short-range hit available with any weapon, as in the original.
func melee() -> void:
	if dead or _melee_cooldown > 0.0 or _viewmodel.throwing() or _viewmodel.drinking:
		return
	var target := _knife_target(STAB_RANGE, STAB_ANGLE)
	var stab := target != null
	var length := _viewmodel.melee(stab)
	if length <= 0.0:
		return
	_melee_cooldown = STAB_TIME if stab else SLASH_TIME
	Sfx.instance.play("knife_stab" if stab else "knife_slash", -3.0)
	_melee_id += 1
	var id := _melee_id
	get_tree().create_timer(KNIFE_HIT_TIME, false).timeout.connect(func():
		if id == _melee_id and not dead:
			_knife_hit(target))


func _knife_hit(target: Zombie) -> void:
	var best: Zombie = null
	if target and is_instance_valid(target) and _knife_reach(target, STAB_RANGE, STAB_ANGLE * 2.0) >= 0.0:
		best = target
	else:
		best = _knife_target(KNIFE_RANGE, SLASH_ANGLE)
	if best:
		best.take_damage(knife_damage(best), false, self, true)
	elif ExplosiveBarrels.of(self):
		ExplosiveBarrels.of(self).knife(self, KNIFE_RANGE)   # Nacht barrels (barrels.gd)


# like the original, the knife hits the zombie in front of the player whatever the
# vertical aim (zombies slightly to the side), except a crawler at your feet
func _knife_target(reach: float, max_angle: float) -> Zombie:
	var best: Zombie = null
	var best_d := INF
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z is Zombie:
			continue
		var d := _knife_reach(z, reach, max_angle)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = z
	return best


# horizontal distance to a zombie the knife can reach, -1 otherwise
func _knife_reach(z: Zombie, reach: float, max_angle: float) -> float:
	if z.state == Zombie.State.DEAD:
		return -1.0
	var facing := -global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var to: Vector3 = z.global_position - global_position
	if absf(to.y) > 2.0:
		return -1.0
	to.y = 0.0
	var d := to.length()
	if d > reach or (d > 0.3 and facing.angle_to(to / d) > max_angle):
		return -1.0
	# nothing solid in between (no stabbing through walls or window boards)
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, z.global_position + Vector3.UP * (0.4 if z.crawler else 1.0), 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return -1.0
	# a crawler lies at your feet: you have to aim down at it
	if z.crawler:
		var aim := -_camera.global_basis.z
		var body: Vector3 = (z.global_position + Vector3.UP * 0.3 - _camera.global_position).normalized()
		if aim.angle_to(body) > deg_to_rad(35):
			return -1.0
	return d


# World at War knife: always 150 damage (one stab at round 1, two at round 2...)
func knife_damage(_z: Zombie) -> float:
	var bowie := BowieKnife.damage_of(self)   # CItemKnife bowieKnife: 1000
	if bowie > 0.0:
		return bowie
	var shovel := float(get_meta("shovel_damage", 0.0))   # CItemKnife shovel: 400 (wunder_grave.gd)
	return shovel if shovel > 0.0 else KNIFE_DAMAGE


func switch_weapon() -> void:
	if weapons.size() > 1:
		current = (current + 1) % weapons.size()
		_reloading = 0.0
		changed.emit()


func reload() -> void:
	var w := weapon()
	var s := Weapons.stats_of(w)
	if _reloading > 0.0 or w["mag"] >= s["mag"] or w["reserve"] <= 0 or _viewmodel.slashing():
		return
	_reloading = s["reload"] * (Perks.SPEED_RELOAD if has_perk("speed") else 1.0)
	if aiming:   # the reload leaves the sights straight away (no lowering animation)
		aiming = false
		_viewmodel.aiming = false
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
		health = max_health   # CHealth: back to full at once
		changed.emit()
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			_finish_reload()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + stick_response(move_input)
	input = input.limit_length(1.0)
	_update_aim(delta, input)
	if input.y > 0.0:
		input.y *= BACKPEDAL   # BackpedalSpeedRatio: only the backwards part of the stick
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	var speed := move_speed(input)
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
	if wants_fire and _cooldown <= 0.0 and _reloading <= 0.0 and not _viewmodel.slashing():
		_fire(w, s)
		if not s["auto"]:
			fire_held = false
	_update_kick(delta)
	_auto_aim(delta)
	_update_prompt()
	if Input.is_action_pressed("interact"):
		_interact_hold += delta
		interact()
	else:
		_interact_hold = 0.0
		_interact_done = false


# Footsteps, as the original player update does them (CPlayer, kiwi 0x1a1f88):
# when the step timer has run out and the player moves, the next sound of
# WalkingFootstepSounds (console.bin: player_footstep_walk3,player_footstep_walk4)
# plays, or of WalkingFootstepWaterSounds (water_walk1,water_walk2) when the floor
# is water (collision material flag 2 there; the swamp water of level.gd here), in
# turn with one shared index; then the timer restarts at
# FootstepSpeedMultiplier / (|vx| + |vz|) of the velocity in the player's frame: the
# faster (and the more diagonal the stick: it is the Manhattan length) the player
# moves, the closer the steps; wading at half speed
# (WaterMoveSpeedModifier) doubles the interval. Exact formula (kiwi 0x1a211c-0x1a2150):
# timer_ms = IW_FIXED_DIV(FootstepSpeedMultiplier, |dx| + |dz|) = 14 * 4096 / s, where
# FootstepSpeedMultiplier is 14 (iwfixed, console.bin; built-in default "0.2") and s is
# the motor's displacement of THIS FRAME in world units (accumulated by the movement
# code, 0x182d70: speed x WorldScale x stick x frame ms). So the interval depends on the
# original's frame time: with s = |v| (m/s) x 400 x frame, interval = 0.14336 / (|v| x
# frame) s. FOOTSTEP_FRAME (estimated: the device frame time, ~30 fps; variableFPS only
# clamps it to 5..45 ms) turns it into metres of |vx|+|vz| per step: 4.3 m, i.e. 0.66 s
# running straight at 6.49 m/s, 0.47 s diagonally (at 20 fps it would be 2.87 m).
# Sound specs: volume 0x599/4096 (-9 dB), pitch 0x0c00/4096 (0.75). The original has no
# zombie footsteps.
const FOOTSTEPS := ["player_footstep_walk3", "player_footstep_walk4"]
const FOOTSTEPS_WATER := ["water_walk1", "water_walk2"]
const FOOTSTEP_MULT := 14.0 / 4096.0        # FootstepSpeedMultiplier (console.bin)
const FOOTSTEP_FRAME := 1.0 / 30.0          # estimated original frame time (s)
# timer ms = (14/4096 x 4096) x 4096 / s  ->  stride = 57.344 / (400 x frame) = 4.30 m
const FOOTSTEP_STRIDE := FOOTSTEP_MULT * 4096.0 * 4096.0 / 1000.0 / (400.0 * FOOTSTEP_FRAME)
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
	_recoil += RECOIL * (RECOIL_AIMED if aiming else 1.0)
	var space := get_world_3d().direct_space_state
	# Ray Gun bolt / flamethrower cone (weapon_fx.gd) replace the hitscan
	if not WeaponFx.fire(self, w, s, _camera):
		_fire_bullet(s, space)
	if not w["name"] in ["raygun", "flamethrower", "wunderwaffe"]:   # these have their own effects
		_viewmodel.muzzle_flash()
		game.muzzle_flash(_camera, _viewmodel.muzzle_position())
	_heat = minf(_heat + HEAT_PER_SHOT, 1.0)   # continuous fire widens the spread
	if w["mag"] == 0:
		reload()
	changed.emit()


# One shot as in the original (weapons.gd): the bullet goes through up to s.hits
# zombies (each one passed lowers the damage) and stops at the first wall; shotguns
# hit every zombie inside their cone once (no pellets). Damage from Weapons.hit_damage.
func _fire_bullet(s: Dictionary, space: PhysicsDirectSpaceState3D) -> void:
	var from := _camera.global_position
	var dir := _spread_dir(-_camera.global_basis.z, Weapons.spread(weapon(), aiming, _heat))
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
	# a shot that hits no head ends the headshot streak (kiwi 0x20cb80 -> 0x131868)
	if not targets.any(func(t): return t[3]):
		headshot_streak = 0


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


# ------------------------------------------------------------------ aiming, movement caps

# Aim down the sights (toggleAim): right mouse button (hold, or click with the
# "aim_toggle" option), touch button ToggleAimIcon (hud.gd: toggle_aim). The FOV goes to
# the gun's aim FOV (CItemGun 0xc4, Weapons.aim_fov; AimModeFOV "0" = use the gun's) in
# AimModeInterpolateTime 300 ms, movement is capped at MaxAimMoveSpeed, turning slowed
# (look), the arms play the aim states (viewmodel.gd set_aim), the spread drops to the
# gun's aimed values and the auto-aim "lockon" pulls the view (_auto_aim).
const AIM_TIME := 0.3          # AimModeInterpolateTime 300 ms
var aim_wanted := false        # button held / toggled on
var aiming := false            # actually aiming (not while reloading, sprinting, knifing...)
var _aim_blend := 0.0          # 0 hip .. 1 sights (FOV / turn speed)


func toggle_aim() -> void:
	aim_wanted = not aim_wanted


func _update_aim(delta: float, input: Vector2) -> void:
	var sprinting := Input.is_action_pressed("sprint") and input.length() > 0.1
	var on := aim_wanted and not dead and _reloading <= 0.0 and not sprinting \
		and not _viewmodel.drinking and not _viewmodel.throwing() and not _viewmodel.slashing()
	if on != aiming:
		aiming = on
		_viewmodel.set_aim(on)
		if on:
			_lock_t = LOCK_STICKY if Settings.auto_aim() else 0.0   # the "lockon" output of state 32
		changed.emit()
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, delta / AIM_TIME)
	# the gun's aim FOV is relative to the original ViewportFOV 50: scaled with the user's FOV
	var base := float(Settings.get_value("fov"))
	var aimed := Weapons.aim_fov(weapon()) * base / 50.0
	_camera.fov = Settings.vertical_fov(lerpf(base, aimed, smoothstep(0.0, 1.0, _aim_blend)))


# Ground speed for the current state (original per-state caps, see the constants).
func move_speed(input: Vector2) -> float:
	var speed := SPEED
	if Input.is_action_pressed("sprint") and not aiming and input.y <= 0.0:
		speed = SPRINT   # remake extra, forwards / sideways only
	if _viewmodel.slashing() or _viewmodel.throwing() or _viewmodel.drinking:
		speed = minf(speed, ACTION_SPEED)
	if aiming:
		speed = minf(speed, AIM_SPEED)
	return speed


# Touch stick deflection (0..1) through analoguePadMovingResponse
# {(0,0),(819,0),(820,2048),(4096,4096)}: 20 % dead zone, then from half to full speed.
static func stick_response(v: Vector2) -> Vector2:
	var m := v.length()
	if m < 0.2:
		return Vector2.ZERO
	return v / m * lerpf(0.5, 1.0, clampf((m - 0.2) / 0.8, 0.0, 1.0))


# Bullet spread: a random direction inside a cone of `spread_deg` (full angle).
static func _spread_dir(dir: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return dir
	var half := deg_to_rad(spread_deg) * 0.5 * sqrt(randf())
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
	side = side.rotated(dir, randf() * TAU)
	return dir.rotated(side, half).normalized()


# ------------------------------------------------------------------ camera kick

# Weapon recoil (remake addition: the original only plays the arms' fire animation):
# the view climbs a little per shot and settles back.
const RECOIL := 0.006            # rad per shot
const RECOIL_AIMED := 0.5
const RECOIL_RECOVERY := 10.0    # 1/s, exponential
const HEAT_PER_SHOT := 0.2       # spread from minimum to maximum in 5 quick shots
const HEAT_DECAY := 2.0          # per second
var _recoil := 0.0
var _heat := 0.0
# Being hit: CCameraProcessorKick with the CCameraKickConfig "player_damaged"
# (misc group: 800 ms, magnitude 227) shaped by CamKickCurve {(0,0),(300,3900),
# (450,4100),(700,3700),(1300,1500),(2600,400),(4096,0)} (time and value x4096,
# kiwi 0xa9120): the view rotates about the horizontal axis square to the hit direction
# (kiwi 0xa9080). 227 read as an iwangle (4096 = 360 deg): ~20 deg at the peak.
const DAMAGE_KICK_TIME := 0.8
const DAMAGE_KICK := 227.0 * TAU / 4096.0
const KICK_CURVE := [[0.0, 0.0], [300.0, 3900.0], [450.0, 4100.0], [700.0, 3700.0],
	[1300.0, 1500.0], [2600.0, 400.0], [4096.0, 0.0]]
var _hit_kick_t := -1.0
var _hit_kick_axis := Vector2.ZERO   # (pitch, roll) weights
var _applied_kick := Vector2.ZERO    # offset currently added to the camera (pitch, roll)


static func kick_curve(t: float) -> float:
	var x := clampf(t, 0.0, 1.0) * 4096.0
	for i in KICK_CURVE.size() - 1:
		var a: Array = KICK_CURVE[i]
		var b: Array = KICK_CURVE[i + 1]
		if x <= b[0]:
			return lerpf(a[1], b[1], (x - a[0]) / maxf(b[0] - a[0], 1.0)) / 4096.0
	return 0.0


func _start_hit_kick(from: Vector3) -> void:
	var d := from - global_position
	d.y = 0.0
	if d.length() < 0.01:
		d = -global_basis.z
	var l := global_basis.inverse() * d.normalized()
	_hit_kick_axis = Vector2(-l.z, -l.x)   # hit in front: the head goes back; from a side: rolls away
	_hit_kick_t = 0.0


func _update_kick(delta: float) -> void:
	_recoil *= exp(-RECOIL_RECOVERY * delta)
	_heat = move_toward(_heat, 0.0, delta * HEAT_DECAY)
	var k := Vector2(_recoil, 0.0)
	if _hit_kick_t >= 0.0:
		_hit_kick_t += delta
		if _hit_kick_t >= DAMAGE_KICK_TIME:
			_hit_kick_t = -1.0
		else:
			k += _hit_kick_axis * DAMAGE_KICK * kick_curve(_hit_kick_t / DAMAGE_KICK_TIME)
	# offsets are added on top of the look rotation (tests and photo mode set it directly)
	_camera.rotation.x += k.x - _applied_kick.x
	_camera.rotation.z += k.y - _applied_kick.y
	_applied_kick = k


# ------------------------------------------------------------------ auto-aim

# CAutoAim (kiwi 0x1ab49c): every frame the enemy (CAutoAimSpec flag mask 0x4000) with
# the lowest score = (AutoAimWeightAngle x angle^2 + AutoAimWeightRange x distance) >> 12
# (angle off the view in iwangle units, 4096 = 360 deg; distance in world units, 400 per
# metre; raw weights 490 and 3276 = AutoAimWeightAngleMax / RangeMax, the "Auto-Aim on"
# values) is taken if below AutoAimScoreAcquire 6500 and in sight; the current target is
# kept until its score passes AutoAimScoreRelease 7500, or a target better by
# AutoAimScoreDiffSwitch 500 replaces it. E.g. 5 m: within 18 deg, 10 m: 13 deg, none
# beyond 20 m. An aim point moves to the target at AutoAimSpeed 2.0 (x WorldScale: 8
# units/ms = 20 m/s), or back to 500 units (5 m) ahead at AutoAimCentreSpeed 1.0.
# The view is pulled to the aim point only while aiming down the sights: raising the
# sights (gun state 32) emits "lockon", which arms LockOnStickyTime 1500 ms; each frame
# the view turns by remaining/1500 of the angle to the aim point (kiwi 0x1a4e08), no
# target switching meanwhile. Remake: the pull also gives way to the player's own look
# input like the original's LockOnSpringConst 0.729 damping (dt / (dt + 0.729 x drag)).
# Option "Mira assistita" (toggleAutoaim); off = no assist (the original then switched
# to the much narrower Min weights: AutoAimWeightAngleMin 1.0, RangeMin 4.5).
const AA_WEIGHT_ANGLE := 490.0
const AA_WEIGHT_RANGE := 3276.0
const AA_ACQUIRE := 6500.0
const AA_RELEASE := 7500.0
const AA_SWITCH := 500.0
const AA_SPEED := 2.0 * MOVE_UNIT        # 20 m/s
const AA_CENTRE_SPEED := 1.0 * MOVE_UNIT
const AA_CENTRE := 5.0
const LOCK_STICKY := 1.5                 # LockOnStickyTime
const LOCK_SPRING := 0.729               # LockOnSpringConst
var auto_aim_target: Zombie = null
var _aim_point := Vector3.INF
var _lock_t := 0.0
var _look_amount := 0.0                  # look input this frame (rad), for the damping


func _aa_point(z: Zombie) -> Vector3:
	return z.global_position + Vector3.UP * (0.35 if z.crawler or z is Dog else 1.1)


func _aa_score(z: Zombie, eye: Vector3, fwd: Vector3) -> float:
	var to := _aa_point(z) - eye
	var a := fwd.angle_to(to) * 4096.0 / TAU
	return (AA_WEIGHT_ANGLE * a * a + AA_WEIGHT_RANGE * to.length() * 400.0) / 4096.0


func _aa_visible(z: Zombie, eye: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye, _aa_point(z), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _auto_aim(delta: float) -> void:
	var look := _look_amount
	_look_amount = 0.0
	if not Settings.auto_aim() or dead:
		auto_aim_target = null
		_aim_point = Vector3.INF
		_lock_t = 0.0
		return
	var eye := _camera.global_position
	var fwd := -_camera.global_basis.z
	var cur := auto_aim_target
	var cur_score := INF
	if cur != null and (not is_instance_valid(cur) or cur.state == Zombie.State.DEAD):
		cur = null
	if cur != null:
		cur_score = _aa_score(cur, eye, fwd)
		if cur_score > AA_RELEASE or not _aa_visible(cur, eye):
			cur = null
			cur_score = INF
	if not (aiming and _lock_t > 0.0 and cur != null):   # locked: no switching
		var best: Zombie = null
		var best_score := AA_ACQUIRE
		for n in get_tree().get_nodes_in_group("zombies"):
			var z := n as Zombie
			if z == null or z == cur or z.state == Zombie.State.DEAD:
				continue
			var sc := _aa_score(z, eye, fwd)
			if sc < best_score and _aa_visible(z, eye):
				best = z
				best_score = sc
		if best != null and (cur == null or best_score < cur_score - AA_SWITCH):
			cur = best
	auto_aim_target = cur
	var goal := _aa_point(cur) if cur else eye + fwd * AA_CENTRE
	if _aim_point == Vector3.INF:
		_aim_point = goal
	_aim_point = _aim_point.move_toward(goal, (AA_SPEED if cur else AA_CENTRE_SPEED) * delta)
	if not aiming:
		_lock_t = 0.0
		return
	if _lock_t <= 0.0 or cur == null:
		_lock_t = maxf(_lock_t - delta, 0.0)
		return
	var f := _lock_t / LOCK_STICKY
	_lock_t = maxf(_lock_t - delta, 0.0)
	var ms := delta * 1000.0
	f *= ms / (ms + LOCK_SPRING * look / MOUSE_SENS)   # the player's own look input wins
	var to := _aim_point - eye
	var yaw_err := wrapf(atan2(-to.x, -to.z) - rotation.y, -PI, PI)
	var pitch_err := atan2(to.y, Vector2(to.x, to.z).length()) - (_camera.rotation.x - _applied_kick.x)
	rotate_y(yaw_err * f)
	_camera.rotation.x = clampf(_camera.rotation.x + pitch_err * f, -1.45, 1.45)


# Max health for the difficulty: PlayerHealth / PerkedPlayerHealth, Recruit variants.
static func base_health(jugg: bool) -> float:
	var recruit := Game.recruit()
	return HEALTH_SCALE * (60.0 if jugg and recruit else 40.0 if jugg else 30.0 if recruit else 20.0)


func _finish_reload() -> void:
	var w := weapon()
	var s := Weapons.stats_of(w)
	var take: int = min(s["mag"] - w["mag"], w["reserve"])
	w["mag"] += take
	w["reserve"] -= take
	changed.emit()


# Consecutive heads taken off (kiwi 0x1315a0, score component +0x2c): it picks the
# headshot kill points (PlayerHeadShotPoints {100,100,110,110,120,120,130,130,140}, the
# streak before this head; the 9th and later 140) and at 3, 5, 7 (HeadshotAnnounceCount)
# the announcer line (kiwi 0x131874): with player vox (Game.SetUsingPlayerVox(true): Shi No
# Numa, Der Riese) the character's "killstreak1..3" (player%d_killstreak%d, player 1 in
# solo). Elsewhere it would play HeadshotAnnounceSounds, but console.bin only has it as
# "XHeadshotAnnounceSounds" (disabled): the code default "10" names no sound.
const HEADSHOT_POINTS := [100, 100, 110, 110, 120, 120, 130, 130, 140]
const HEADSHOT_ANNOUNCE := [3, 5, 7]
const PLAYER_VOX_LEVELS := ["shinonuma", "derriese"]
var headshot_streak := 0


func headshot_points() -> int:
	return HEADSHOT_POINTS[mini(headshot_streak, HEADSHOT_POINTS.size() - 1)]


func head_popped() -> void:
	headshot_streak += 1
	var i := HEADSHOT_ANNOUNCE.find(headshot_streak)
	if i >= 0 and game != null and String(game.get("level_name")) in PLAYER_VOX_LEVELS and Sfx.instance:
		Sfx.instance.play(Sfx.iw_hash("player1_killstreak%d" % (i + 1)))


func add_points(n: int) -> void:
	if n < 0:
		print("[points] spent %d at %s" % [-n, global_position])
	points += n
	Achievements.points(n)
	if game and game.has_method("points_earned"):
		game.points_earned(n)   # power-up drop threshold, game over score (game.gd)
	changed.emit()


# `from`: where the hit came from (camera kick direction); by default the nearest zombie.
func take_hit(damage: float, from := Vector3.INF) -> void:
	if dead or _revive_grace > 0.0:
		return
	health -= damage
	_since_hit = 0.0
	if from == Vector3.INF:
		var best := INF
		for z in get_tree().get_nodes_in_group("zombies"):
			var d: float = (z as Node3D).global_position.distance_to(global_position)
			if d < best:
				best = d
				from = (z as Node3D).global_position
	_start_hit_kick(from if from != Vector3.INF else global_position - global_basis.z)
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
		max_health = base_health(true)   # PerkedPlayerHealth 40 (Recruit 60) x HEALTH_SCALE
		health = max_health
	changed.emit()


# Solo Quick Revive: instead of dying, get back up once; every perk is lost (WaW).
# Remake addition: in the original the revive perk (index 1) only shortens reviving a
# co-op partner (kiwi 0xc9900: PerkedRevivingTimeMs 1000 instead of RevivingTimeMs) and
# counts totalplayerrevivedsoda (0xcb10c); in single player it has no effect.
func _self_revive() -> void:
	perks.clear()
	max_health = base_health(false)
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
		prompt = "Tieni premuto E per sgombrare [%d]" % t.cost
	elif t is Dictionary:
		var has := weapons.any(func(w): return w["name"] == t["weapon"])
		if has:
			prompt = "Tieni premuto E per le munizioni %s [%d]" % [Weapons.display(t["weapon"]), t["ammo_cost"]]
		else:
			prompt = "Tieni premuto E per comprare %s [%d]" % [Weapons.display(t["weapon"]), t["cost"]]


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
		if not is_instance_valid(d):
			continue
		if d.global_position.distance_to(p) < INTERACT_RANGE + 1.0:
			cands.append([d, d.global_position])
		else:
			var near: Vector3 = d.nearest_point(p)
			if near.distance_to(p) < INTERACT_RANGE:
				cands.append([d, near])
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
	elif _interact_done or _interact_hold < INTERACT_TIME:
		return   # InteractTime: held long enough, once per press
	elif _mark_interacted() and (t is MysteryBox or t is PerkMachine or (t is Object and t in game.level.interactables)):
		t.interact(self)
	elif t is Debris:
		if points >= t.cost:
			add_points(-t.cost)
			t.open()
			Sfx.instance.play("buy_success")
			Sfx.instance.play_at(t.open_sound, t.global_position)   # its ASM's sound (debris.gd)
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


# InteractTime hold (interact): progress 0..1 for the HUD, -1 when there is nothing to hold for.
var _interact_hold := 0.0
var _interact_done := false


func _mark_interacted() -> bool:
	_interact_done = true
	return true


func interact_progress() -> float:
	if _interact_hold <= 0.0 or _interact_done or prompt == "" or prompt.begins_with("Tieni premuto E per riparare"):
		return -1.0
	return clampf(_interact_hold / INTERACT_TIME, 0.0, 1.0)
