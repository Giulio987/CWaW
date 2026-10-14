# User settings (pause menu "Impostazioni"), saved in user://settings.cfg.
# Static class: Settings.mouse_sens etc. are read where the values are used
# (player.gd look/fov, hud.gd touch look). Audio uses three buses: Master,
# "Effects" and "Music"; players created on the Master bus are moved to
# "Effects" automatically (set bus = "Music" explicitly for music).
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"
const PATH_TEST := "user://settings_test.cfg"   # --frontend-test (frontend_tests.gd)
const BUS_EFFECTS := "Effects"
const BUS_MUSIC := "Music"
const DEFAULTS := {
	"mouse_sens": 1.0,    # multiplier of Player.MOUSE_SENS
	"touch_sens": 1.0,    # multiplier of the touch look factor
	"invert_y": false,
	# vertical look speed relative to horizontal: console.bin SensitivityYDefault 0.375 /
	# SensitivityXDefault 0.5 (the original's slider defaults)
	"look_y_ratio": 0.75,
	# ViewportFOV 50 (console.bin): the original's field of view, in degrees across the
	# average of the screen width and height (ViewportMode "AverageDimension", kiwi
	# 0xb4940/0xb4984: perspective multiplier = (w+h)/2 / (2 tan(fov/2))); see vertical_fov()
	"fov": 50.0,
	"fov_version": 2,      # settings saved before it had "fov" = Godot's vertical FOV (70): reset
	# aim down the sights: hold the right mouse button (false) or click to toggle (the
	# original's toggleAim / ToggleAimIcon is a toggle; the touch button always toggles)
	"aim_toggle": false,
	# toggleAutoaim ("Auto-Aim:" option): default on with a touch screen (see ensure_loaded)
	"auto_aim": false,
	"master_volume": 1.0,  # linear 0..1
	"effects_volume": 1.0,
	"music_volume": 0.8,
	"recruit": false,      # difficulty Recruit instead of Regular (Game.difficulty, from the next game)
	# se_performanceleveltoggle "High (slowest)" / "Medium" / "Low (fastest)": 0 / 1 / 2, see
	# apply_detail(); cl_autopausetoggle "Auto-Pause": pause when the app loses focus
	"detail_level": 0,
	"auto_pause": true,
}

static var values := {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path()) == OK:
		for k in DEFAULTS:
			values[k] = cfg.get_value("settings", k, DEFAULTS[k])
		if int(cfg.get_value("settings", "fov_version", 1)) < 2:
			values["fov"] = DEFAULTS["fov"]
			values["fov_version"] = DEFAULTS["fov_version"]
	if not cfg.has_section_key("settings", "auto_aim"):
		values["auto_aim"] = DisplayServer.is_touchscreen_available()
	apply_audio()
	apply_detail()
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
	elif key == "detail_level":
		apply_detail()
	elif key == "fov":
		var tree := Engine.get_main_loop() as SceneTree
		var cam := tree.root.get_viewport().get_camera_3d() if tree else null
		if cam:
			cam.fov = vertical_fov(v)


static func save() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(path())


static func path() -> String:
	return PATH_TEST if OS.get_cmdline_user_args().has("--frontend-test") else PATH


# "Default Settings" (restoretofactory, kiwi 0x180694: the settings back to their defaults,
# saved and applied); the difficulty is not a setting of that screen and stays.
static func restore_defaults() -> void:
	ensure_loaded()
	var keep: bool = values.get("recruit", false)
	values = DEFAULTS.duplicate()
	values["recruit"] = keep
	values["auto_aim"] = DisplayServer.is_touchscreen_available()   # as in ensure_loaded
	apply_audio()
	apply_detail()
	set_value("fov", values["fov"])
	save()


# Detail Level (the original's performance toggle) mapped to Godot: 3D render scale and mesh
# LOD threshold. High = full resolution (as before the option existed).
static func apply_detail() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var lvl := clampi(int(values.get("detail_level", 0)), 0, 2)
	tree.root.scaling_3d_scale = [1.0, 0.8, 0.6][lvl]
	tree.root.mesh_lod_threshold = [1.0, 2.0, 4.0][lvl]


# --- shortcuts used by gameplay code
static func mouse_sens() -> float:
	return float(get_value("mouse_sens"))


static func touch_sens() -> float:
	return float(get_value("touch_sens"))


static func invert_y() -> bool:
	return bool(get_value("invert_y"))


# Godot camera FOV (vertical) for the user's FOV setting (original ViewportFOV units).
static func fov() -> float:
	return vertical_fov(float(get_value("fov")))


# The original applies the FOV across the average screen dimension (ViewportMode
# "AverageDimension"); Godot's Camera3D.fov is vertical (keep height): convert with the
# current aspect. 50 -> 41 deg vertical on the 480x320 iPhone, 37 deg at 16:9.
static func vertical_fov(avg_fov: float) -> float:
	var size := Vector2(480, 320)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		size = tree.root.get_visible_rect().size
	var k := 2.0 * size.y / maxf(size.x + size.y, 1.0)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(avg_fov) * 0.5) * k))


static func look_y_ratio() -> float:
	return float(get_value("look_y_ratio"))


static func aim_toggle() -> bool:
	return bool(get_value("aim_toggle"))


static func auto_aim() -> bool:
	return bool(get_value("auto_aim"))


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
