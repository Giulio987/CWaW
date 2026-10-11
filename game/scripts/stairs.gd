# Step climbing for CharacterBody3D: Godot does not climb steps by itself.
# If the horizontal move is blocked, try lifting the body by up to STEP_HEIGHT,
# carrying it over the step edge and putting it down on a flat tread.
class_name Stairs

const STEP_HEIGHT := 0.45
const REACH := 0.35  # past the capsule radius, so the body ends up over the tread


static func step_up(body: CharacterBody3D, delta: float) -> void:
	var move := Vector3(body.velocity.x, 0, body.velocity.z) * delta
	if move.length() < 0.001:
		return
	var xf := body.global_transform
	if not body.test_move(xf, move):
		return  # nothing in the way
	var up := Vector3.UP * STEP_HEIGHT
	if body.test_move(xf, up):
		return  # no head room
	var raised := xf.translated(up)
	var reach := move.normalized() * REACH
	if body.test_move(raised, reach):
		return  # a wall, not a step
	var col := KinematicCollision3D.new()
	if not body.test_move(raised.translated(reach), -up, col):
		return  # nothing to stand on
	var rise := STEP_HEIGHT - col.get_travel().length()
	if rise < 0.05 or rise > STEP_HEIGHT - 0.01 or col.get_normal().y < 0.7:
		return  # not a flat tread at step height
	# only lift and nudge forward by this frame's move; the next frames walk onto the tread
	body.global_position += Vector3.UP * (rise + 0.01) + move
	body.velocity.y = 0.0
