# Game over fly-through (CCameraControllerFlythrough "cam_flythrough", kiwi va 0x1e4fe4):
# 3 s after death (game_over_screen.gd) the camera leaves the player and travels the
# level's CCameraPath resources EndCamera1..5 (tools/camera_paths.py ->
# assets/levels/<map>/camera_paths.json) in resource order, each from its start at its
# own speed, looking at the point of its target line at the same fraction of the way; at
# the end of one the next starts (after the last, the first again). The last path used is
# remembered (the controller keeps it, va 0x1e4eec), so the next game over goes on from there.
class_name EndCamera
extends Camera3D

var paths: Array = []
var index := -1
var dist := 0.0
var _len := 0.0
var _tlen := 0.0

static var _last_index := {}   # map -> last path index


static func start(g: Game) -> EndCamera:
	var f := "res://assets/levels/%s/camera_paths.json" % g.level_name
	if not FileAccess.file_exists(f):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(f))
	if not data is Array or (data as Array).is_empty():
		return null
	var cam := EndCamera.new()
	cam.paths = data
	cam.index = _last_index.get(g.level_name, -1)
	var old := g.get_viewport().get_camera_3d()
	if old:
		cam.fov = old.fov
		cam.near = old.near
		cam.far = old.far
	cam.cull_mask &= ~Viewmodel.LAYER   # not the dead player's first-person models
	g.add_child(cam)
	cam._next()
	cam._place()
	cam.make_current()
	_last_index[g.level_name] = cam.index
	return cam


func _next() -> void:
	index = (index + 1) % paths.size()
	dist = 0.0
	_len = _length(paths[index]["pos"])
	_tlen = _length(paths[index]["target"])


static func _length(pts: Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += _v(pts[i - 1]).distance_to(_v(pts[i]))
	return l


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


# CIwPathLine: the point `d` along the polyline
static func sample(pts: Array, d: float) -> Vector3:
	if pts.size() == 1:
		return _v(pts[0])
	for i in range(1, pts.size()):
		var a := _v(pts[i - 1])
		var b := _v(pts[i])
		var s := a.distance_to(b)
		if d <= s or i == pts.size() - 1:
			return a.lerp(b, clampf(d / s, 0.0, 1.0) if s > 0.0 else 1.0)
		d -= s
	return _v(pts[-1])


func _place() -> void:
	var p: Dictionary = paths[index]
	var pos := sample(p["pos"], dist)
	var at := pos + Vector3.FORWARD
	if not (p["target"] as Array).is_empty():
		at = sample(p["target"], dist * _tlen / _len if _len > 0.0 else 0.0)
	global_position = pos
	if not pos.is_equal_approx(at):
		look_at(at, Vector3.UP if absf((at - pos).normalized().y) < 0.99 else Vector3.FORWARD)


func _process(delta: float) -> void:
	dist += float(paths[index]["speed"]) * delta
	if dist >= _len:
		_next()
		_last_index[get_parent().level_name] = index
	_place()
