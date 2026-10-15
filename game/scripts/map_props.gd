# Map entities that are only a model of the level's dynamics group, which the environment
# export (tools/export_gltf.py place_entities: environment models only) does not place.
#  - Mystery box stands: CIwRenderableModelSpec-only entities with model 7e489a07 (Verrückt,
#    5) or 7cf1b0c8 (Shi No Numa and Der Riese, 6): one at every box location, on the
#    same spot and with the same quarter turns as the box (Level.flag_transform; the box's child offset puts it on
#    the stand's origin). Crates under the box outline (Der Riese/Shi No Numa: 2.2 x 0.33 m,
#    same atlas 994f5dac as the box; Verrückt: a rubble heap 1a47bbc1) with a bloodied bear
#    (f44162d9) sitting on top, which would poke through the closed box (box 0.48 m high,
#    bear up to 0.71 m): an empty location. Each CMysteryBoxSpec names its stand (spec field
#    after the box data, e.g. MysteryBox_garage -> c1d55a8e): the stand is hidden while the
#    box is at that location (arriving, closed, open, flying off) and shown otherwise
#    (the toggle itself is not decoded in kiwi: estimated from the geometry).
#  - Der Riese tower clock (below).
class_name MapProps
extends Node

const STAND_MODELS := ["7e489a07", "7cf1b0c8"]
const POLL := 0.2

var level: Level
var stands := {}   # box location entity -> Node3D
var _t := 0.0


static func build(level_: Level) -> MapProps:
	var mp := MapProps.new()
	mp.name = "MapProps"
	mp.level = level_
	level_.add_child(mp)
	mp._build_stands()
	mp._build_panel()
	return mp


func _build_stands() -> void:
	var boxes := level.entities.keys().filter(func(n): return "CMysteryBoxSpec" in level.entities[n]["components"])
	if boxes.is_empty():
		return
	for n in level.entities:
		var e: Dictionary = level.entities[n]
		if e["components"] != ["CIwRenderableModelSpec"] or e["models"].is_empty() or not e["models"][0] in STAND_MODELS:
			continue
		var m := level.dynamics_model(e["models"][0])
		if m == null:
			continue
		m.name = "Stand_" + n
		level.add_child(m)
		m.global_transform = Level.flag_transform(e["transform"])
		# its box location: the CMysteryBoxSpec at the same spot (0.4-1.1 m from the box root)
		var at := m.global_position
		var best := ""
		for b in boxes:
			if best == "" or level.entity_transform(b).origin.distance_to(at) < level.entity_transform(best).origin.distance_to(at):
				best = b
		stands[best] = m
	_refresh()


func _process(delta: float) -> void:
	if panel_anim:
		_panel_t -= delta
		if _panel_t <= 0.0:
			var tick := not _panel_ticking
			_panel_ticking = tick
			_panel_t += PANEL_TICK_TIME if tick else PANEL_REST
			panel_anim.play(PANEL_TICK if tick else PANEL_STATIC)
			panel_anim.seek(0.0, true)
			if tick:
				panel_ticks += 1
				Sfx.instance.play_at(PANEL_SOUND, panel.global_position)
			else:
				panel_anim.pause()
	_t -= delta
	if _t > 0.0 or stands.is_empty():
		return
	_t = POLL
	_refresh()


func _refresh() -> void:
	var here := {}
	for b in level.boxes:
		if is_instance_valid(b) and b.state != MysteryBox.State.GONE:
			here[b.entity] = true
	for loc in stands:
		(stands[loc] as Node3D).visible = not here.has(loc)


# ------------------------------------------------------------------ Der Riese tower clock
# Link_oLC_L_Trigger1 (1aec757f: CTriggerInteractableASMSpec + model 0f3b9851, rigged, Der Riese
# dynamics; not used by the Lua scripts despite its name) is the clock face on the tower of
# the power courtyard, 8.4 m up: a 3.6 m dial (atlas 994f5dac) and its hand (bone01). Its
# ASM 0f3b9851 (2 states, one input "Always"):
#   S0 "static" (b51d4772, 1500 ms; setIsButtonEnabled 0, setGoodieMessage 0) -Always-> S1
#   S1 7c9e7750 (b52363bf, 291 ms: the hand jerks -6.7 deg; playsound 2024f29b, 1.75 s;
#      setIsButtonEnabled 0, setGoodieMessage 0) -Always-> S0 (the hand drops back)
# so the hand twitches with a clank every 1.79 s, forever; the trigger is never usable
# and shows no message.
const PANEL := "Link_oLC_L_Trigger1"
const PANEL_MODEL := "0f3b9851"
const PANEL_STATIC := "b51d4772"
const PANEL_TICK := "b52363bf"
const PANEL_SOUND := "2024f29b"
const PANEL_REST := 1.5
const PANEL_TICK_TIME := 0.291
var panel: Node3D
var panel_anim: AnimationPlayer
var panel_ticks := 0
var _panel_t := PANEL_REST
var _panel_ticking := false


func _build_panel() -> void:
	if not level.has_entity(PANEL):
		return
	panel = level.dynamics_model(PANEL_MODEL)
	if panel == null:
		return
	panel.name = "Panel_" + PANEL
	level.add_child(panel)
	panel.global_transform = level.entity_transform(PANEL, true)
	var aps := panel.find_children("*", "AnimationPlayer")
	panel_anim = aps[0] if aps.size() > 0 else null
	if panel_anim and panel_anim.has_animation(PANEL_STATIC):
		panel_anim.play(PANEL_STATIC)
		panel_anim.seek(0.0, true)
		panel_anim.pause()
