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
	_camera.fov = 70
	_camera.near = 0.05
	_camera.far = 400
	add_child(_camera)
	_camera.make_current()
	_viewmodel = Viewmodel.new()
	_camera.add_child(_viewmodel)
	changed.connect(_sync_viewmodel)
	give_weapon("colt45")


func give_weapon(name: String) -> void:
	for i in weapons.size():
		if weapons[i]["name"] == name:
			var s := Weapons.stats(name)
			weapons[i]["mag"] = s["mag"]
			weapons[i]["reserve"] = s["reserve"]
			current = i
			changed.emit()
			return
	var st := Weapons.stats(name)
	var w := {"name": name, "mag": st["mag"], "reserve": st["reserve"] - st["mag"]}
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
	if n != _shown_weapon:
		_shown_weapon = n
		_viewmodel.set_weapon(n)


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative * MOUSE_SENS)
	elif event.is_action_pressed("switch_weapon"):
		switch_weapon()
	elif event.is_action_pressed("reload"):
		reload()
	elif event.is_action_pressed("melee"):
		melee()


func look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	_camera.rotation.x = clamp(_camera.rotation.x - delta.y, -1.45, 1.45)


const KNIFE_DAMAGE := 150.0
const KNIFE_RANGE := 1.8
var _melee_cooldown := 0.0


# Knife: short-range hit available with any weapon, as in the original.
func melee() -> void:
	if dead or _melee_cooldown > 0.0:
		return
	_melee_cooldown = 0.9
	_viewmodel.melee()
	Sfx.instance.play("knife_slash", -3.0)
	# a sphere in front of the camera: hits a zombie even when it is right on top
	# of the player or hunched below the line of sight
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	q.shape = sphere
	var fwd := -_camera.global_basis.z
	fwd.y = clampf(fwd.y, -0.5, 0.5)
	q.transform = Transform3D(Basis(), _camera.global_position + fwd.normalized() * 0.9 + Vector3.DOWN * 0.3)
	q.collision_mask = 2  # zombies
	q.exclude = [get_rid()]
	var best: Zombie = null
	for hit in space.intersect_shape(q, 8):
		var z = hit["collider"]
		if z is Zombie and z.state != Zombie.State.DEAD:
			if best == null or z.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
				best = z
	if best:
		best.take_damage(KNIFE_DAMAGE, false, self, true)


func switch_weapon() -> void:
	if weapons.size() > 1:
		current = (current + 1) % weapons.size()
		_reloading = 0.0
		changed.emit()


func reload() -> void:
	var w := weapon()
	var s := Weapons.stats(w["name"])
	if _reloading > 0.0 or w["mag"] >= s["mag"] or w["reserve"] <= 0:
		return
	_reloading = s["reload"]
	_viewmodel.reload(s["reload"])
	Sfx.instance.sequence(w["name"] + "_reload")


func _physics_process(delta: float) -> void:
	if dead:
		return
	_cooldown -= delta
	_repair_cooldown -= delta
	_melee_cooldown -= delta
	_since_hit += delta
	if _since_hit > REGEN_DELAY and health < MAX_HEALTH:
		health = min(MAX_HEALTH, health + 40.0 * delta)
		changed.emit()
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			_finish_reload()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + move_input
	input = input.limit_length(1.0)
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	var speed := SPRINT if Input.is_action_pressed("sprint") else SPEED
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

	var w := weapon()
	var s := Weapons.stats(w["name"])
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


func _fire(w: Dictionary, s: Dictionary) -> void:
	if w["mag"] <= 0:
		reload()
		return
	w["mag"] -= 1
	_cooldown = s["rate"]
	_viewmodel.kick()
	Sfx.instance.weapon_fire(w["name"])
	_camera.rotation.x = min(_camera.rotation.x + 0.012, 1.45)
	var space := get_world_3d().direct_space_state
	for p in s["pellets"]:
		var spread := Vector3.ZERO
		if s["pellets"] > 1:
			spread = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.06
		var from := _camera.global_position
		var dir := (-_camera.global_basis.z + _camera.global_basis * spread).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * s["range"], 1 | 2)  # bullets ignore window blockers
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var target: Object = hit["collider"]
		if target is Zombie:
			var head: bool = (hit["position"] as Vector3).y > target.global_position.y + 1.45
			var dmg: float = s["damage"] * (2.0 if head else 1.0)
			target.take_damage(dmg, head, self)
		else:
			game.spawn_impact(hit["position"], hit["normal"])
	game.muzzle_flash(_camera)
	if w["mag"] == 0:
		reload()
	changed.emit()


func _finish_reload() -> void:
	var w := weapon()
	var s := Weapons.stats(w["name"])
	var take: int = min(s["mag"] - w["mag"], w["reserve"])
	w["mag"] += take
	w["reserve"] -= take
	changed.emit()


func add_points(n: int) -> void:
	if n < 0:
		print("[points] spent %d at %s" % [-n, global_position])
	points += n
	changed.emit()


func take_hit(damage: float) -> void:
	if dead:
		return
	health -= damage
	_since_hit = 0.0
	Sfx.instance.play("zombie_hit", -2.0)
	Sfx.instance.play("player_pain", -4.0)
	changed.emit()
	if health <= 0.0:
		dead = true
		died.emit()


# ------------------------------------------------------------------ interaction

func _update_prompt() -> void:
	prompt = ""
	var t = _interaction_target()
	if t == null:
		return
	if t is MysteryBox:
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
	for d in game.level.debris:
		if is_instance_valid(d) and d.global_position.distance_to(p) < INTERACT_RANGE + 1.0:
			return d
	for b in game.wall_buys:
		if (b["position"] as Vector3).distance_to(p) < INTERACT_RANGE:
			return b
	return null


func interact() -> void:
	var t = _interaction_target()
	if t == null:
		return
	if t is Barricade:
		if _repair_cooldown <= 0.0 and t.repair_board():
			_repair_cooldown = 1.0
			add_points(10)
			Sfx.instance.play_at("window_repair", t.global_position)
	elif not Input.is_action_just_pressed("interact"):
		return
	elif t is MysteryBox:
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
