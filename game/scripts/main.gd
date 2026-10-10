# Entry point. Command line: -- [level] [--autotest seconds]
extends Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level := "nacht"
	for a in args:
		if not a.begins_with("--") and not a.is_valid_float():
			level = a
	var game := Game.new()
	add_child(game)
	game.start(level)
	var i := args.find("--autotest")
	if i >= 0:
		var t := AutoTest.new()
		t.duration = float(args[i + 1]) if args.size() > i + 1 else 60.0
		t.game = game
		add_child(t)
