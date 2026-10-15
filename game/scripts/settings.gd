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
	# se_brightnessslider position 0..1 (apply_brightness); 0.32 -> IwGx ScreenBrightness 10,
	# the neutral value (estimate: the original's default is not in the data)
	"brightness": 0.32,
	# "Dimensione schermo" (not in the original, screen_frame.gd): the picture shrunk with black
	# borders, clear of the Dynamic Island / rounded corners; default from the safe area
	# (ScreenFrame.auto_scale, 1.0 on the Mac), see ensure_loaded / restore_defaults
	"screen_scale": 1.0,
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
	if not cfg.has_section_key("settings", "screen_scale"):
		values["screen_scale"] = ScreenFrame.auto_scale()
	apply_audio()
	apply_detail()
	apply_brightness()
	apply_screen_scale()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		if not tree.node_added.is_connected(_on_node_added):   # ensure_loaded again (tests)
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
	elif key == "brightness":
		apply_brightness()
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
	var args := OS.get_cmdline_user_args()
	return PATH_TEST if args.has("--frontend-test") or args.has("--frame-test") else PATH


# "Default Settings" (restoretofactory, kiwi 0x180694: the settings back to their defaults,
# saved and applied); the difficulty is not a setting of that screen and stays.
static func restore_defaults() -> void:
	ensure_loaded()
	var keep: bool = values.get("recruit", false)
	values = DEFAULTS.duplicate()
	values["recruit"] = keep
	values["auto_aim"] = DisplayServer.is_touchscreen_available()   # as in ensure_loaded
	values["screen_scale"] = ScreenFrame.auto_scale()
	apply_audio()
	apply_detail()
	apply_brightness()
	apply_screen_scale()
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


# Brightness (fe_settings/ig_settings se_brightnessslider, kiwi va 0x195f20): the slider
# position v (0..0x1000) becomes BrightnessSettingMinMax "{ 1, 15 }" lerped on 0x1000 - v
# (right = brighter), stored and passed to IwGx (0x96dcc). After each frame IwGx (0xa6a80)
# draws a full-screen quad unless the value is 10: above 8 black alpha-blended with alpha
# 3 * (b - 8) (15 -> 21/255, darker), up to 8 grey (8 - b) * 8 added (1 -> +56/255, brighter).
static func brightness_level(v: float) -> int:
	var x := clampi(int(clampf(v, 0.0, 1.0) * 4096.0), 0, 4096)
	return 1 + (14 * (4096 - x)) / 4096


static var _bright_layer: CanvasLayer


static func apply_brightness() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if _bright_layer == null or not is_instance_valid(_bright_layer):
		_bright_layer = CanvasLayer.new()
		_bright_layer.name = "Brightness"
		_bright_layer.layer = 128
		var r := ColorRect.new()
		r.name = "Quad"
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.material = CanvasItemMaterial.new()
		_bright_layer.add_child(r)
		tree.root.add_child.call_deferred(_bright_layer)
	var b := brightness_level(float(values.get("brightness", DEFAULTS["brightness"])))
	var quad := _bright_layer.get_node("Quad") as ColorRect
	var mat := quad.material as CanvasItemMaterial
	_bright_layer.visible = b != 10
	if b > 8:
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		quad.color = Color(0, 0, 0, 3.0 * (b - 8) / 255.0)
	else:
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		var g := (8 - b) * 8 / 255.0
		quad.color = Color(g, g, g, 1.0)


# "Dimensione schermo": set_value only stores it; the settings slider applies it when released
# (applied while dragging, the slider would move under the finger).
static func apply_screen_scale() -> void:
	ScreenFrame.apply(float(values.get("screen_scale", 1.0)))


# --- shortcuts used by gameplay code
# Both multiply an event's relative motion, which the root maps through the screen frame's
# canvas transform: with the picture shrunk (screen_frame.gd) it grows by 1 / scale, so the
# scale here keeps the turn per pixel moved as at 100 %.
static func mouse_sens() -> float:
	return float(get_value("mouse_sens")) * ScreenFrame.scale


static func touch_sens() -> float:
	return float(get_value("touch_sens")) * ScreenFrame.scale


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
	if OS.get_environment("CODZ_MUTE") == "1":  # tools/run_godot.sh: silent test runs, players still advance
		AudioServer.set_bus_mute(_bus("Master"), true)


static func _on_node_added(n: Node) -> void:
	if (n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D) and n.bus == &"Master":
		n.bus = BUS_MUSIC if "music" in String(n.name).to_lower() else BUS_EFFECTS


static func _retag(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_retag(c)
