# Nacht der Untoten explosive barrels.
#
# nacht.lua Begin (line 63): Script.SetUpBarrels("BarrelExplosive", 25); SetUpBarrels
# (ingame.lua 1037-1054) spawns the entity spec "explosive_barrel" as "Barrel<i>" at each
# marker BarrelExplosive1..25 (25 = how many markers; the engine pool is ScriptMaxBarrels 32
# in console.bin). Only Nacht calls it (no other level script or entities.json has them).
# Resume does not call it again: the engine save keeps the barrels (CBarrel save/restore,
# kiwi 0x2020ac, also keeps the burn timer).
#
# CIwEntSpec "explosive_barrel" (aed776db, nacht dynamics group):
#   CIwColliderSpec cylinder radius 150, height 500 units; CIwRenderableModelSpec model 551533c3;
#   CHealthSpec 10; CLifeTimeSpec 3000 ms, not started at spawn (flag 0);
#   CDeathActionSpawnSpec: 3aa5fb63 (splash), 76b0fb36 and cd49c3e1 (particle emitters);
#   CBarrelSpec: [df8f83fb] (CBarrelSpec::Serialise kiwi 0x10ea70: an array of entity specs).
# CBarrel::HandleEvent (kiwi 0x201fe8): on the damage event (0x8002) that takes the health to
#   0 it starts the life timer (kiwi 0x222bb0: 3000 ms) and spawns the CBarrelSpec entities on
#   the barrel (df8f83fb: the fire model on top, 500 units up, material 53f7e924: additive,
#   texture 0f74ae25, 32 cels 8 per row, celPeriod 1, the same 30 Hz tick as the level flames),
#   and remembers who did it. CHealth (kiwi 0x2023c8) ignores damage once at 0, so it burns
#   only once. When the timer ends the barrel dies (no destroyed model, it is gone) and the
#   death action spawns the splash 3aa5fb63: CSplashEffectSpec 300 damage, type 2
#   (explosive: legs off), target mask 0x10000 like the frag grenade (not the player),
#   sound 7ba2387d "barrel_explosion", stat "barrelkill"; radius = its CIwVolumeSphere 1400
#   units = 3.5 m, los_free 0. Achievement 31 "Blow Me Away": 20 x nacht.totalzombiebarrelkill.
# Not decoded: which damage the barrel's CHealth accepts. Here bullets, the knife and every
# blast (grenade, monkey, Ray Gun splash, other barrels: chain reaction 3 s apart) set it off.
class_name ExplosiveBarrels
extends Node3D

const PREFIX := "BarrelExplosive"
const COUNT := 25
const MODEL := "551533c3"
const RADIUS := 150.0 * Level.UNITS          # collider cylinder
const HEIGHT := 500.0 * Level.UNITS
const HEALTH := 10.0                          # CHealthSpec
const FUSE := 3.0                             # CLifeTimeSpec 3000 ms
const FIRE_TEX := "0f74ae25"                  # fire model df8f83fb, material 53f7e924
const FIRE_Y := 500.0 * Level.UNITS
const FIRE_SIZE := Vector2(0.72, 1.2075)      # model 0f74ae25: x -0.36..0.36, y -0.32..0.8875
const FIRE_CELS := 32                         # 53f7e924: 32 cels, 8 per row, celPeriod 1
const SOUND := "barrel_explosion"             # 7ba2387d
const SPLASH := {
	"radius": 3.5, "max_damage": 300.0, "min_damage": 300.0, "kill_radius": 0.0, "los_free": 0.0,
	"crawl_chance": 1.0, "gib_chance": 0.0, "head_chance": 0.0,
	"player_radius": 0.0, "player_damage": 0.0, "shake": 1.0, "shake_radius": 14.0,
}

var game: Node3D
var level: Level
var barrels := {}            # name -> Barrel (intact or burning)
var destroyed := []          # names of the barrels that went off (save_game.gd)
var last_result := {}        # last explosion's Explosion.blast result (tests)
var log := []                # [time, name, event] (tests)
var _clock := 0.0
var _rebake := false


static func create(game_: Node3D, level_: Level) -> ExplosiveBarrels:
	if not level_.has_entity(PREFIX + "1"):
		return null
	var x := ExplosiveBarrels.new()
	x.name = "ExplosiveBarrels"
	x.game = game_
	x.level = level_
	x.add_to_group("explosive_barrels")
	x.add_to_group(SaveGame.PROVIDER_GROUP)
	level_.nav_region.add_child(x)   # solid: the navmesh goes around them
	for i in range(1, COUNT + 1):
		var n := PREFIX + str(i)
		if level_.has_entity(n):
			x._spawn(n)
	return x


static func of(node: Node) -> ExplosiveBarrels:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("explosive_barrels") as ExplosiveBarrels


func _spawn(n: String) -> void:
	var b := Barrel.new()
	b.name = "Barrel_" + n
	b.entity = n
	b.owner_set = self
	add_child(b)
	b.global_transform = Level.flag_transform(level.entity(n)["transform"])
	var model := level.dynamics_model(MODEL)
	if model:
		b.add_child(model)
		b.model = model
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = HEIGHT
	cs.shape = cyl
	cs.position = Vector3.UP * HEIGHT * 0.5
	b.add_child(cs)
	barrels[n] = b


# ------------------------------------------------------------------ damage

func damage(b: Barrel, amount: float, by: Player) -> void:
	if b.state != Barrel.INTACT:
		return
	b.health -= amount
	if b.health <= 0.0:
		ignite(b, by)


func ignite(b: Barrel, by: Player, fuse := FUSE) -> void:
	if b.state != Barrel.INTACT:
		return
	b.state = Barrel.BURNING
	b.by = by
	b.left = fuse
	b.add_fire()
	_log(b.entity, "ignite")


func _explode(b: Barrel) -> void:
	b.state = Barrel.GONE
	var pos := b.global_position + Vector3.UP * 0.1
	var xf := Transform3D(b.global_basis.orthonormalized(), b.global_position)
	var by: Player = b.by if is_instance_valid(b.by) else null
	barrels.erase(b.entity)
	destroyed.append(b.entity)
	b.collision_layer = 0   # out of the blast's line-of-sight rays
	b.visible = false
	_log(b.entity, "explode")
	Sfx.instance.play_at(SOUND, pos + Vector3.UP * 0.5)
	effect(game, xf)
	last_result = Explosion.blast(game, pos, by, SPLASH)
	Achievements.event(level.level_name + ".totalbarrelkill")
	if int(last_result.get("killed", 0)) > 0:
		Achievements.event(level.level_name + ".totalzombiebarrelkill", int(last_result["killed"]))
	b.queue_free()
	_queue_rebake()


# Any blast (Explosion.blast) sets off the barrels inside its radius.
func splash(pos: Vector3, radius: float, by: Player) -> void:
	for n in barrels.keys():
		var b: Barrel = barrels[n]
		if b.state != Barrel.INTACT:
			continue
		var c := Geometry3D.get_closest_point_to_segment(pos, b.global_position, b.global_position + Vector3.UP * HEIGHT)
		if pos.distance_to(c) <= radius + RADIUS:
			damage(b, 1e6, by)


# Knife (player.gd melee) when no zombie is in reach: the barrel in front.
func knife(p: Player, reach: float) -> bool:
	var facing := -p.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var best: Barrel = null
	var best_d := INF
	for b in barrels.values():
		if b.state != Barrel.INTACT:
			continue
		var to: Vector3 = b.global_position - p.global_position
		if absf(to.y) > 2.0:
			continue
		to.y = 0.0
		var d := maxf(to.length() - RADIUS, 0.0)
		if d > reach or (to.length() > 0.3 and facing.angle_to(to.normalized()) > deg_to_rad(60)):
			continue
		if d < best_d:
			best_d = d
			best = b
	if best:
		damage(best, Player.KNIFE_DAMAGE, p)
		return true
	return false


func _queue_rebake() -> void:
	if _rebake or not level.nav_ready:
		return
	_rebake = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	_rebake = false
	level.bake_navigation()


func _process(delta: float) -> void:
	_clock += delta
	for b in barrels.values():
		if b.state == Barrel.BURNING:
			b.left -= delta
			if b.left <= 0.0:
				_explode(b)


func _log(n: String, what: String) -> void:
	log.append([_clock, n, what])
	if OS.get_cmdline_user_args().has("--barrel-log"):
		print("[barrel] %.2f %s %s" % [_clock, n, what])


# Explosion look: the original emitters (CIwGFXEmitterSpec, iw_emitter.gd) spawned on the
# barrel's transform: the splash entity's fireball and the two death-spawn emitters. No
# flash light and no extra sprite: the original has neither.
const FX_FIREBALL := ["a6ce831f", true, 250.0, [10.0, 15.0], [500.0, 750.0],   # splash 3aa5fb63, mat b5a4bcab
	[Vector3(-25, 25, -25), Vector3(25, 75, 25)], [Vector3(-3500, 7500, -3500), Vector3(3500, 15000, 3500)],
	[400.0, 600.0], 500.0, [-440.0, 440.0]]
const FX_SPARKS := ["1d980a04", true, 400.0, [10.0, 17.0], [1250.0, 2000.0],   # 76b0fb36, mat 88d7daba
	[Vector3(-100, 50, -100), Vector3(100, 100, 100)], [Vector3(-10000, 3500, -10000), Vector3(10000, 5000, 10000)],
	[50.0, 150.0], -500.0, [-264.0, 264.0]]
const FX_SMOKE := ["81d92923", false, 1000.0, [100.0, 300.0], [1500.0, 3000.0],  # cd49c3e1, mat b690c2e5 (blend)
	[Vector3(-80, 400, 40), Vector3(80, 550, 80)], [Vector3(-3000, 5000, 100), Vector3(3000, 7500, 3000)],
	[1000.0, 1300.0], 500.0, [-176.0, 176.0]]
const SMOKE_COLOR := Color(0.5, 0.5, 0.5)     # b690c2e5 diffuse 0x80


static func effect(parent: Node, xf: Transform3D) -> void:
	for f in [FX_FIREBALL, FX_SPARKS, FX_SMOKE]:
		var c := IwEmitter.from_spec(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9],
			SMOKE_COLOR if f == FX_SMOKE else Color.WHITE)
		IwEmitter.burst(parent, xf, c)


# ------------------------------------------------------------------ save provider (save_game.gd)

func save_key() -> String:
	return "barrels"


# destroyed: gone for good; burning: [name, seconds left] (the original saves the timer too)
func save_state() -> Dictionary:
	var burning := []
	for b in barrels.values():
		if b.state == Barrel.BURNING:
			burning.append([b.entity, b.left])
	return {"destroyed": destroyed.duplicate(), "burning": burning}


func load_state(d: Dictionary) -> void:
	for n in d.get("destroyed", []):
		remove_silently(String(n))
	for e in d.get("burning", []):
		if e is Array and e.size() >= 2 and barrels.has(String(e[0])):
			ignite(barrels[String(e[0])], null, maxf(float(e[1]), 0.1))


# Names of the barrels that have exploded (for save_game.gd / tests).
func destroyed_barrels() -> Array:
	return destroyed.duplicate()


func remove_silently(n: String) -> void:
	if not barrels.has(n):
		return
	var b: Barrel = barrels[n]
	barrels.erase(n)
	if not n in destroyed:
		destroyed.append(n)
	b.collision_layer = 0
	b.queue_free()
	_queue_rebake()


# A barrel: solid for everything, and on the damage-trigger layer so the player's bullets
# find it (RadioEggs.bullet calls trigger_damage).
class Barrel extends StaticBody3D:
	enum { INTACT, BURNING, GONE }
	var entity := ""
	var owner_set: ExplosiveBarrels
	var model: Node3D
	var state := INTACT
	var health := ExplosiveBarrels.HEALTH
	var by: Player
	var left := 0.0
	var _fire: MeshInstance3D
	var _fire_mat: StandardMaterial3D
	var _light: OmniLight3D

	func _ready() -> void:
		collision_layer = 1 | RadioEggs.TRIGGER_LAYER
		collision_mask = 0

	func trigger_damage(by_: Player) -> void:
		# every gun's bullet does more than the barrel's 10 health (weapon_stats.json)
		owner_set.damage(self, ExplosiveBarrels.HEALTH, by_)

	func add_fire() -> void:
		_fire = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = ExplosiveBarrels.FIRE_SIZE
		q.center_offset = Vector3(0, (0.8875 - 0.32) * 0.5, 0)
		_fire_mat = StandardMaterial3D.new()
		_fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fire_mat.albedo_texture = WeaponFx.tex(ExplosiveBarrels.FIRE_TEX)
		_fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_fire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_fire_mat.uv1_scale = Vector3(1.0 / 8.0, 1.0 / 4.0, 1.0)
		q.material = _fire_mat
		_fire.mesh = q
		_fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_fire)
		_fire.position = Vector3.UP * ExplosiveBarrels.FIRE_Y
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.55, 0.2)
		_light.omni_range = 4.0
		add_child(_light)
		_light.position = Vector3.UP * (ExplosiveBarrels.FIRE_Y + 0.3)

	func _process(_delta: float) -> void:
		if _fire == null or state != BURNING:
			return
		# same tick as the level's cel animations (Level._animate_cels): one cel per 30 Hz tick
		var f := int(Time.get_ticks_msec() * Level.CEL_TICKS / 1000.0) % ExplosiveBarrels.FIRE_CELS
		_fire_mat.uv1_offset = Vector3(float(f % 8) / 8.0, float(f / 8) / 4.0, 0.0)
		_light.light_energy = 1.4 + randf() * 0.8
