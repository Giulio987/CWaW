# Start-up sequence before the main menu, as in the original: the splash screen, then the
# intro video, then the frontend (with its music, ui_sound.gd).
# - splash (main/splash/splash.group.bin): CIwGuiMultiFrame "splash" with three frames
#   over texture d102cdb4: Activision (1,170)-(343,255), Treyarch (4,58)-(346,166),
#   Ideaworks (397,5)-(508,232), stored sideways. The splash state (kiwi 0x1743a4) moves to
#   the next frame every SplashScreenMs = "3000" (default string at 0x281b64), on black.
# - intro (kiwi 0x160894): unless DisableVideo, plays IntroVideoPath (console.bin
#   "videos/intro.mp4", converted by tools/intro_video.sh); the "skip" event (a tap) stops it
#   (0x160984).
# Here a tap, click or key skips the current part (logo or video). Only when the game is
# started with no arguments (main.gd): tests and debug options never show it.
class_name IntroSequence
extends CanvasLayer

signal finished

const SPLASH := "res://assets/textures/splash/d102cdb4.png"
const VIDEO := "res://assets/videos/intro.ogv"
const SPLASH_MS := 3000
# frame order of the multi-frame; the third logo is turned upright
const LOGOS := [[Rect2(1, 170, 342, 85), 0.0], [Rect2(4, 58, 342, 108), 0.0], [Rect2(397, 5, 111, 227), 90.0]]

var _skip := false
var _done := false
var _logo: TextureRect
var _video: VideoStreamPlayer
var phase := ""   # "logos" / "video" / "" (for tests)


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_run()


func _run() -> void:
	phase = "logos"
	if ResourceLoader.exists(SPLASH):
		var tex: Texture2D = load(SPLASH)
		for l in LOGOS:
			_show_logo(tex, l[0], l[1])
			await _wait(SPLASH_MS / 1000.0)
		if _logo:
			_logo.queue_free()
			_logo = null
	phase = "video"
	if ResourceLoader.exists(VIDEO):
		_video = VideoStreamPlayer.new()
		_video.stream = load(VIDEO)
		_video.expand = true
		_video.bus = Settings.BUS_MUSIC
		_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_video)
		_fit_video()
		get_viewport().size_changed.connect(_fit_video)
		_video.play()
		_skip = false
		while _video.is_playing() and not _skip:
			await get_tree().process_frame
		_video.stop()
	phase = ""
	_done = true
	finished.emit()
	queue_free()


func _show_logo(tex: Texture2D, region: Rect2, angle: float) -> void:
	if _logo == null:
		_logo = TextureRect.new()
		_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_logo)
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = region
	_logo.texture = a
	# logos at the size they had on the 480x320 screen, scaled to the window height
	var k := get_viewport().get_visible_rect().size.y / 320.0
	var sz := region.size * k
	_logo.size = sz
	_logo.pivot_offset = sz * 0.5
	_logo.rotation_degrees = angle
	_logo.position = get_viewport().get_visible_rect().size * 0.5 - sz * 0.5


# 3:2 picture letterboxed in the 16:9 file: keep the file's aspect, centred
func _fit_video() -> void:
	if _video == null:
		return
	var view := get_viewport().get_visible_rect().size
	var aspect := 16.0 / 9.0
	var tex := _video.get_video_texture()
	if tex and tex.get_height() > 0:
		aspect = float(tex.get_width()) / tex.get_height()
	var sz := Vector2(view.y * aspect, view.y)
	if sz.x > view.x:
		sz = Vector2(view.x, view.x / aspect)
	_video.size = sz
	_video.position = (view - sz) * 0.5


func _wait(seconds: float) -> void:
	_skip = false
	var t := 0.0
	while t < seconds and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()


func skip() -> void:
	_skip = true


func _input(event: InputEvent) -> void:
	if _done:
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if tap:
		get_viewport().set_input_as_handled()
		skip()
