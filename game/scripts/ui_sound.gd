# Front-end sounds: the menu music mx_frontend (frontend.group.bin 47a34869, 44 s; its
# CIwSoundSpec has loop count 0 = endless, like gameover_loop/perkhumloop, while the
# one-shots have 1; kiwi 0x196e28 starts it in the frontend states if it is not already
# playing) and menu_press (fixed.group.bin 7bb288e6, CGuiTouchButtonMenuItem MenuPressSound)
# on every menu button. Sound paths come from assets/sounds/index.json.
class_name UiSound
extends RefCounted

static var _paths := {}
static var _installed := false
static var _press: AudioStream


static func _path(name: String) -> String:
	if _paths.is_empty():
		var idx = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sounds/index.json"))
		if idx is Dictionary:
			for n in ["menu_press", "mx_frontend"]:
				var h = idx["names"].get(n, "")
				_paths[n] = idx["sounds"].get(h, "") if h is String else ""
	return _paths.get(name, "")


static func _load(name: String) -> AudioStream:
	var p := _path(name)
	return load(p) if p != "" and ResourceLoader.exists(p) else null


# Every BaseButton added from now on, except the HUD's touch buttons, plays menu_press.
static func install() -> void:
	if _installed:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_installed = true
	tree.node_added.connect(_on_node_added)


static func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var cb := _pressed.bind(n)
		if not (n as BaseButton).pressed.is_connected(cb):   # a reparented button is added again
			(n as BaseButton).pressed.connect(cb)


static func _pressed(b: BaseButton) -> void:
	var p := b.get_parent()
	while p:
		if p is PauseMenu or p is GameOverScreen:
			break   # menus inside the HUD
		if p is Hud:
			return  # touch controls
		p = p.get_parent()
	press()


static func press() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if _press == null:
		_press = _load("menu_press")
	if _press == null:
		return
	var a := AudioStreamPlayer.new()
	a.name = "MenuPress"
	a.stream = _press
	a.bus = Settings.BUS_EFFECTS
	a.process_mode = Node.PROCESS_MODE_ALWAYS   # also in the pause menu
	tree.root.add_child(a)
	a.finished.connect(a.queue_free)
	a.play()


# Looping menu music under `parent` (freed with it).
static func music(parent: Node) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.name = "MenuMusic"
	a.stream = _load("mx_frontend")
	a.bus = Settings.BUS_MUSIC
	a.process_mode = Node.PROCESS_MODE_ALWAYS   # keeps playing under the options screen
	parent.add_child(a)
	if a.stream:
		a.finished.connect(a.play)   # loop count 0: endless
		a.play()
	return a
