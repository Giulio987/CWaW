# User settings (pause menu "Impostazioni"), saved in user://settings.cfg.
# Static class: Settings.mouse_sens etc. are read where the values are used
# (player.gd look/fov, hud.gd touch look). Audio uses three buses: Master,
# "Effects" and "Music"; players created on the Master bus are moved to
# "Effects" automatically (set bus = "Music" explicitly for music).
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"
const BUS_EFFECTS := "Effects"
const BUS_MUSIC := "Music"
const DEFAULTS := {
	"mouse_sens": 1.0,    # multiplier of Player.MOUSE_SENS
	"touch_sens": 1.0,    # multiplier of the touch look factor
	"invert_y": false,
	"fov": 70.0,
	"master_volume": 1.0,  # linear 0..1
	"effects_volume": 1.0,
	"music_volume": 0.8,
}

static var values := {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in DEFAULTS:
			values[k] = cfg.get_value("settings", k, DEFAULTS[k])
	apply_audio()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.node_added.connect(_on_node_added)
		_retag(tree.root)


static func get_value(key: String) -> Variant:
	ensure_loaded()
	return values[key]


static func set_value(key: String, v: Variant) -> void:
	ensure_loaded()
	values[key] = v
	if key.ends_with("_volume"):
		apply_audio()
	elif key == "fov":
		var tree := Engine.get_main_loop() as SceneTree
		var cam := tree.root.get_viewport().get_camera_3d() if tree else null
		if cam:
			cam.fov = v


static func save() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)


# --- shortcuts used by gameplay code
static func mouse_sens() -> float:
	return float(get_value("mouse_sens"))


static func touch_sens() -> float:
	return float(get_value("touch_sens"))


static func invert_y() -> bool:
	return bool(get_value("invert_y"))


static func fov() -> float:
	return float(get_value("fov"))


# --- audio buses
static func _bus(name: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	return i


static func apply_audio() -> void:
	for pair in [["Master", "master_volume"], [BUS_EFFECTS, "effects_volume"], [BUS_MUSIC, "music_volume"]]:
		var i := _bus(pair[0])
		var v: float = values.get(pair[1], 1.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


static func _on_node_added(n: Node) -> void:
	if (n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D) and n.bus == &"Master":
		n.bus = BUS_MUSIC if "music" in String(n.name).to_lower() else BUS_EFFECTS


static func _retag(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_retag(c)
