# Shi No Numa mystery box map boards (shinonuma.lua).
#  - entities MysteryBoxMapDownstairsRoom1/2, Storage, Fishing, Doctors, Comm:
#    CIsAnimatorASMSpec + model cd366b65 (rig of the Shi No Numa dynamics group), ASM 0b888f83.
#  - UpdateMysteryMaps (779-787) sends the same ASM trigger to all six boards;
#    WarpMysteryBox (around 765-776) sends the new box's entry of MysteryBoxMapTriggers, and
#    RefreshMysteryMaps (789-815, called by Resume, line 372) the current box's one.
#  - MysteryBoxes / MysteryBoxMapTriggers (184-201) pair by index.
#  - ASM 0b888f83 (shi_dynamics group, 650 bytes): 6 states, each one a pose; triggers list
#    [movedToFishing, movedToWarning, movedToStorage, movedToDoctors, movedToComm, movedToMain, f208adf6];
#    each state has 5 transitions (target state, trigger number n); n counts that list from
#    the end (n = 6 - index, as Der Riese's list also runs backwards):
#    state 0 f023ea20 <- movedToMain, 1 f7c296cf <- movedToComm, 2 ce42afc1 <- movedToDoctors,
#    3 e0e7816b <- movedToFishing, 4 d4e36438 <- movedToStorage, 5 fc211279 <- movedToWarning.
#    Checked on the boards (barrel_tests.gd --maps-test --maps-all): each pose lights the box
#    icon of that place (Fishing Hut, Comm Room, Doctor's Quarters, Storage Hut; main building:
#    downstairsRoom1 upper right, downstairsRoom2 centre left, as the box positions).
# Same approach as the Der Riese boards (derriese_extras.gd): follow the box's moved signal.
class_name ShinonumaMysteryMaps
extends Node3D

const MODEL := "cd366b65"
const BOARDS := ["MysteryBoxMapDownstairsRoom1", "MysteryBoxMapDownstairsRoom2", "MysteryBoxMapStorage",
	"MysteryBoxMapFishing", "MysteryBoxMapDoctors", "MysteryBoxMapComm"]
const BOX_ANIMS := {
	"MysteryBox_downstairsRoom1": "f023ea20",   # movedToMain
	"MysteryBox_downstairsRoom2": "fc211279",   # movedToWarning
	"MysteryBox_fishing": "e0e7816b",           # movedToFishing
	"MysteryBox_storage": "d4e36438",           # movedToStorage
	"MysteryBox_doctors": "ce42afc1",           # movedToDoctors
	"MysteryBox_commRoom": "f7c296cf",          # movedToComm
}

var level: Level
var boards := []          # AnimationPlayer per board
var pose := ""            # current pose (tests)


static func create(level_: Level) -> ShinonumaMysteryMaps:
	if level_.level_name != "shinonuma":
		return null
	var x := ShinonumaMysteryMaps.new()
	x.name = "MysteryMaps"
	x.level = level_
	level_.add_child(x)
	for n in BOARDS:
		var ap := x._board(n)
		if ap:
			x.boards.append(ap)
	for b in level_.boxes:
		b.moved.connect(x.update)
	if not level_.boxes.is_empty():
		x.update(level_.boxes[0].entity)
	return x


func _board(entity: String) -> AnimationPlayer:
	if not level.has_entity(entity):
		return null
	var model := level.dynamics_model(MODEL)
	if model == null:
		return null
	model.name = "Board_" + entity
	add_child(model)
	model.global_transform = Level.flag_transform(level.entity(entity)["transform"])
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aps := model.find_children("*", "AnimationPlayer")
	return aps[0] if not aps.is_empty() else null


func update(box_entity: String) -> void:
	for n in BOX_ANIMS:
		if n.to_lower() == box_entity.to_lower():
			pose = BOX_ANIMS[n]
	for ap in boards:
		DerrieseExtras._pose(ap, pose)
