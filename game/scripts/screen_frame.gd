# "Dimensione schermo" (Settings "screen_scale", not in the original): the whole game picture
# - 3D, HUD, touch buttons, menus - shrunk around the screen centre with black borders, so on
# modern iPhones nothing ends up under the Dynamic Island / notch or the rounded corners.
#
# How: the root viewport keeps its logical size (get_visible_rect, layouts, anchors unchanged);
# - 2D: root.global_canvas_transform scales every canvas layer around the centre. Godot maps
#   input through the same transform (Viewport._make_input_local uses stretch * global canvas
#   transform), so mouse / touch positions, the HUD stick and the GUI buttons follow the
#   shrunk picture, and get_mouse_position / unproject_position stay consistent;
# - 3D: the root stops drawing 3D (disable_3d); a SubViewport sharing the root's World3D draws
#   it with a mirror camera that copies the root's current camera before every frame, at the
#   shrunk size in physical pixels (1:1, not resampled); its texture is shown on the lowest
#   canvas layer over the whole logical screen, so the global transform shrinks it with the 2D.
# At 100 % (the default on the Mac) nothing of this exists: the root is left untouched.
# Screenshots of get_viewport().get_texture() (the root) show the picture with its borders.
class_name ScreenFrame
extends Node

const MIN := 0.8
const ROOT_PROPS := ["scaling_3d_mode", "scaling_3d_scale", "fsr_sharpness", "texture_mipmap_bias",
	"anisotropic_filtering_level", "mesh_lod_threshold", "msaa_3d", "screen_space_aa", "use_taa",
	"use_debanding", "use_occlusion_culling", "positional_shadow_atlas_size",
	"positional_shadow_atlas_16_bits", "positional_shadow_atlas_quad_0",
	"positional_shadow_atlas_quad_1", "positional_shadow_atlas_quad_2", "positional_shadow_atlas_quad_3"]
const CAM_PROPS := ["projection", "fov", "size", "near", "far", "keep_aspect", "cull_mask",
	"environment", "attributes", "compositor", "h_offset", "v_offset", "frustum_offset"]

static var _inst: ScreenFrame
static var scale := 1.0

var _vp: SubViewport
var _cam: Camera3D
var _tex: TextureRect
var _borders: CanvasLayer


# Initial value where the device reports a safe area (iOS / Android): the largest centred
# picture that keeps clear of the side insets (Dynamic Island / notch, rounded corners) and
# the top one. The bottom inset (home indicator, a thin bar drawn over apps) is not counted.
# Elsewhere (Mac) 1.0: the safe area there is the usable rect (menu bar, Dock), not a cut-out.
static func auto_scale() -> float:
	if not (OS.has_feature("ios") or OS.has_feature("android")):
		return 1.0
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.x <= 0.0 or screen.y <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return 1.0
	var side := maxf(safe.position.x, screen.x - safe.end.x)
	var top := safe.position.y
	var s := minf(1.0 - 2.0 * side / screen.x, 1.0 - 2.0 * top / screen.y)
	if s <= 0.0 or s > 1.0:
		return 1.0
	return clampf(floorf(s * 100.0) / 100.0, MIN, 1.0)


# Debug: "--screen-scale 0.8" overrides the setting for this run (not saved).
static func cmdline_scale() -> float:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--screen-scale")
	return float(args[i + 1]) if i >= 0 and i + 1 < args.size() else -1.0


static func apply(s: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var cl := cmdline_scale()
	if cl > 0.0:
		s = cl
	scale = clampf(s, MIN, 1.0) if s < 0.999 else 1.0
	if scale >= 1.0:
		if _inst and is_instance_valid(_inst):
			_inst.queue_free()
		_inst = null
		tree.root.global_canvas_transform = Transform2D()
		tree.root.disable_3d = false
		return
	if _inst == null or not is_instance_valid(_inst):
		_inst = ScreenFrame.new()
		_inst.name = "ScreenFrame"
		tree.root.add_child.call_deferred(_inst)   # the root may be busy setting up children
	else:
		_inst._layout()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -128   # under every other layer (the HUD, menus...)
	add_child(layer)
	# the borders, over everything: art placed past the screen edges (menu smears, splats) and
	# the root's grey clear colour stay hidden, as on a full screen
	_borders = CanvasLayer.new()
	_borders.layer = 128
	add_child(_borders)
	for i in 4:
		var black := ColorRect.new()
		black.color = Color.BLACK
		black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_borders.add_child(black)
	_vp = SubViewport.new()
	_vp.name = "World3D"
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.disable_3d = false
	_vp.audio_listener_enable_3d = false   # the root's camera stays the listener
	add_child(_vp)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.current = true
	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_tex)
	get_tree().root.size_changed.connect(_layout)
	RenderingServer.frame_pre_draw.connect(_sync)
	_layout()
	get_tree().root.disable_3d = true


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)
	var root := get_tree().root
	if root.size_changed.is_connected(_layout):
		root.size_changed.disconnect(_layout)
	if _inst == self or _inst == null:
		root.global_canvas_transform = Transform2D()
		root.disable_3d = false


# Shrunk picture in physical pixels (whole, centred), and the canvas transform that maps the
# logical screen onto it: stretch (logical -> physical, k) * global (offset + scale).
func _layout() -> void:
	if not is_inside_tree() or _vp == null:   # apply() again before _ready: _ready lays out
		return
	var root := get_tree().root
	var logical := root.get_visible_rect().size
	var phys := Vector2(root.size)
	if logical.x <= 0.0 or phys.x <= 0.0:
		return
	var k := phys / logical
	var shrunk := (phys * scale).round()
	var off := ((phys - shrunk) * 0.5).floor()
	root.global_canvas_transform = Transform2D(0.0, shrunk / phys, 0.0, off / k)
	_vp.size = Vector2i(shrunk)
	_tex.position = Vector2.ZERO
	_tex.size = logical
	var big := 20000.0
	var rects := [Rect2(-big, -big, 2.0 * big + logical.x, big), Rect2(-big, logical.y, 2.0 * big + logical.x, big),
		Rect2(-big, 0.0, big, logical.y), Rect2(logical.x, 0.0, big, logical.y)]
	for i in 4:
		var r := _borders.get_child(i) as ColorRect
		r.position = rects[i].position
		r.size = rects[i].size


func _sync() -> void:
	var root := get_tree().root
	for p in ROOT_PROPS:
		var v = root.get(p)
		if _vp.get(p) != v:
			_vp.set(p, v)
	var src := root.get_camera_3d()
	if src == null:
		return
	for p in CAM_PROPS:
		var v = src.get(p)
		if _cam.get(p) != v:
			_cam.set(p, v)
	_cam.global_transform = src.global_transform
