# The hellhounds' lightning strike, as in the original: Script.SpawnDog (ingame.lua 780-794)
# spawns the entity "normal_dogSpawn" (bc3f1df0) or "flame_dogSpawn" (edf8a34c) of the
# effects group at the dog spawn. Both are the CIwSpecList 6be7f502 plus a
# CDeathActionSpawnSpec that spawns the dog ("cold" 5a2670c7 / "hot" 37e42ca3, dog group)
# when the effect dies. 6be7f502 (tools/ent_fx.py -> assets/effect_specs.json):
#   CLifeTimeSpec 1500 ms (random 0; third value 1000, read here as the fade-out time as
#   in wunderwaffe.gd: an estimate)
#   eeb35e5c  scorched ground rings (5.6 m, bolt strips 7fef4319 cycling 8 cels + glow)
#   30e42e21  the bolt from the sky (0.9 x 8.3 m, 6e9f714c scrolling), turns about the up axis
#   219c28ff  glow disc 3.5 m (41a63f86), faces the camera
#   0543b4db..df five spark sprites (e175d317 / e175d318, 4 cels) 2-2.5 m around, facing the camera
# No light and no other parts (the remake used to draw a line and an omni light).
extends Node3D

const SPEC := "6be7f502"

var life := 1.5
var fade := 1.0
var _t := 0.0
var _parts: Array[IwFx] = []


# the lightning at a dog spawn; returns its lifetime (the dog appears when it ends)
static func spawn(parent: Node, at: Vector3) -> float:
	var fx = load("res://scripts/dog_spawn_fx.gd").new()
	fx.name = "DogSpawnFx"
	parent.add_child(fx)
	fx.global_position = at
	fx._build()
	return fx.life


func _build() -> void:
	var spec: Dictionary = IwFx.spec_lists().get(SPEC, {})
	var lt = spec.get("lifetime")
	if lt is Array:
		life = float(lt[0]) / 1000.0
		fade = minf(float(lt[2]) / 1000.0, life)
	for e in spec.get("ents", []):
		if String(e.get("model", "")) == "":
			continue
		var part := IwFx.make(e["model"], int(e.get("flags", 0) if e.get("flags") != null else 0))
		add_child(part)
		if e.has("transform"):
			part.transform = Level.flag_transform(e["transform"])
		_parts.append(part)


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	var a := clampf((life - _t) / fade, 0.0, 1.0) if fade > 0.0 else 1.0
	for p in _parts:
		p.alpha = a
