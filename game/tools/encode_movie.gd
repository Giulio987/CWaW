# Re-encode a decoded video (PNG frames + WAV) through Godot's movie writer, so that an
# Ogg Theora file comes out without a Theora encoder in ffmpeg (tools/intro_video.sh):
#   godot --path game --write-movie out.ogv --fixed-fps <fps> \
#         -s res://tools/encode_movie.gd -- <frames dir> <audio.wav> <fps>
# One movie frame per input frame; the audio starts with the first frame. Godot records
# at the project's window size (1280x720); the picture keeps its aspect, centred.
extends SceneTree

var _frames: PackedStringArray
var _dir := ""
var _i := 0
var _count := 0
var _rect: TextureRect


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0]
	for f in DirAccess.get_files_at(_dir):
		if f.ends_with(".png"):
			_frames.append(f)
	_frames.sort()
	# Godot 4.7's OGV writer runs away when it is closed on some frame counts (the 414
	# frames of the intro: gigabytes of output, never "Done"; 400 or 420 are fine): pad
	# with the last frame to whole seconds (<fps> = 3rd argument)
	var fps := int(args[2]) if args.size() > 2 else 1
	_count = ceili(_frames.size() / float(fps)) * fps
	_rect = TextureRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	RenderingServer.set_default_clear_color(Color.BLACK)
	get_root().add_child(_rect)
	if args.size() > 1 and FileAccess.file_exists(args[1]):
		var p := AudioStreamPlayer.new()
		p.stream = AudioStreamWAV.load_from_file(args[1])
		p.autoplay = true   # starts once the node is in the tree (with the first frame)
		get_root().add_child(p)
	_show(0)
	print("[encode_movie] %d frames, %d written" % [_frames.size(), _count])


func _show(i: int) -> void:
	var img := Image.load_from_file(_dir.path_join(_frames[mini(i, _frames.size() - 1)]))
	_rect.texture = ImageTexture.create_from_image(img)


func _process(_delta: float) -> bool:
	_i += 1
	if _i >= _count:
		return true   # quit: the movie writer closes the file
	_show(_i)
	return false
