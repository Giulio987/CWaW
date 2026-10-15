# Main menu: the original frontend background (a04fbb00) under the original pages
# (title, main menu, single player, level select, extras, options: frontend_menu.gd).
class_name Menu
extends CanvasLayer

signal play(level: String)

const TEX := "res://assets/textures/frontend/"
const MAPS := [
	{"id": "nacht", "name": "Nacht der Untoten", "preview": "0ffc6b53", "note": ""},
	{"id": "verruckt", "name": "Verrückt", "preview": "d3023ebb", "note": ""},
	{"id": "shinonuma", "name": "Shi No Numa", "preview": "dc131b97", "note": ""},
	{"id": "derriese", "name": "Der Riese", "preview": "365abbd8", "note": ""},
]
const RED := Color(0.62, 0.04, 0.03)

var _selected := 0
var _achievements: AchievementsScreen
var extras: FrontendMenu   # the pages, music, map description, options/help/leaderboards/credits/about


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiSound.install()   # menu_press on the buttons (ui_sound.gd)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	FrontendArt.background(root)
	extras = FrontendMenu.attach(self)   # frontend_menu.gd
	_select(0)


# Original textures are padded to powers of two: show only the used part.
static func cropped(path: String) -> Texture2D:
	var tex: Texture2D = load(path)
	var rect := tex.get_image().get_used_rect()
	if rect.size == Vector2i.ZERO or rect.size == Vector2i(tex.get_size()):
		return tex
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = Rect2(rect)
	return a


func _select(i: int) -> void:
	_selected = i
	if extras:
		extras.selected(MAPS[i]["id"])


# Options -> Language: the pages built again in the new language, on `page` (no title page;
# the menu music goes on where it was: the old pages' player is freed with them).
func relocalize(page := "options") -> void:
	var old := extras
	var music := old.get_node_or_null("MenuMusic") as AudioStreamPlayer if old else null
	var at := music.get_playback_position() if music and music.playing else -1.0
	extras = FrontendMenu.attach(self)
	var fresh := extras.get_node_or_null("MenuMusic") as AudioStreamPlayer
	if fresh and at >= 0.0:
		fresh.play(at)
	if old:
		old.queue_free()
	extras.show_page(page)
	_select(_selected)


# achievement list over the menu (achievements_screen.gd)
func show_achievements() -> AchievementsScreen:
	if _achievements == null:
		_achievements = AchievementsScreen.new()
		add_child(_achievements)
		_achievements.closed.connect(func(): _achievements = null)
	return _achievements
