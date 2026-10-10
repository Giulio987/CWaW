# HUD (round counter, points, ammo, prompts) and touch controls for iPhone.
class_name Hud
extends CanvasLayer

var game: Game
var _round: Label
var _points: Label
var _ammo: Label
var _prompt: Label
var _msg: Label
var _hurt: ColorRect
var _touch := false
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _look_id := -1
var _stick_knob: Control
var _stick_base: Control


func bind(g: Game) -> void:
	game = g
	_touch = DisplayServer.is_touchscreen_available()
	_hurt = ColorRect.new()
	_hurt.color = Color(0.6, 0, 0, 0)
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt)
	_round = _label(64, Color(0.65, 0.05, 0.03), Control.PRESET_BOTTOM_LEFT, Vector2(24, -96))
	_points = _label(28, Color(1, 0.9, 0.5), Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -150))
	_ammo = _label(22, Color.WHITE, Control.PRESET_BOTTOM_RIGHT, Vector2(-320, -80))
	_prompt = _label(22, Color.WHITE, Control.PRESET_CENTER_BOTTOM, Vector2(-260, -200))
	_msg = _label(30, Color.WHITE, Control.PRESET_CENTER, Vector2(-200, -100))
	var cross := _label(26, Color(1, 1, 1, 0.7), Control.PRESET_CENTER, Vector2(-7, -18))
	cross.text = "+"
	if _touch:
		_build_touch()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	g.player.changed.connect(_refresh)
	_refresh()


func _label(size: int, color: Color, preset: int, offset: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.set_anchors_preset(preset)
	l.position += offset
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _refresh() -> void:
	var p := game.player
	_points.text = str(p.points)
	var w := p.weapon()
	_ammo.text = "%s   %d / %d" % [Weapons.display(w["name"]), w["mag"], w["reserve"]]
	_hurt.color.a = clamp((1.0 - p.health / Player.MAX_HEALTH) * 0.6, 0.0, 0.6)


func _process(_d: float) -> void:
	if game and game.player:
		_prompt.text = game.player.prompt


func round_changed(n: int) -> void:
	_round.text = _roman(n) if n <= 5 else str(n)


func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IIII", "V"][n]


func message(t: String) -> void:
	_msg.text = t


func game_over(rounds: int) -> void:
	_msg.text = "GAME OVER\nHai resistito %d round" % rounds


# ------------------------------------------------------------------ touch

func _build_touch() -> void:
	_stick_base = Panel.new()
	_stick_base.size = Vector2(180, 180)
	_stick_base.modulate = Color(1, 1, 1, 0.25)
	_stick_base.visible = false
	add_child(_stick_base)
	_stick_knob = Panel.new()
	_stick_knob.size = Vector2(70, 70)
	_stick_knob.modulate = Color(1, 1, 1, 0.5)
	_stick_knob.visible = false
	add_child(_stick_knob)
	_button("FUOCO", Vector2(-200, -260), Vector2(170, 170), func(down): game.player.fire_held = down)
	_button("E", Vector2(-330, -150), Vector2(100, 100), func(down):
		if down:
			Input.action_press("interact")
		else:
			Input.action_release("interact"))
	_button("R", Vector2(-120, -420), Vector2(90, 90), func(down):
		if down:
			game.player.reload())
	_button("⇄", Vector2(-230, -420), Vector2(90, 90), func(down):
		if down:
			game.player.switch_weapon())
	_button("🔪", Vector2(-340, -420), Vector2(90, 90), func(down):
		if down:
			game.player.melee())


func _button(text: String, offset: Vector2, size: Vector2, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size = size
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position += offset
	b.modulate = Color(1, 1, 1, 0.6)
	b.button_down.connect(func(): cb.call(true))
	b.button_up.connect(func(): cb.call(false))
	add_child(b)


func _input(event: InputEvent) -> void:
	if not _touch or game == null or game.player == null:
		return
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and _stick_id == -1:
				_stick_id = event.index
				_stick_origin = event.position
				_stick_base.position = event.position - _stick_base.size / 2
				_stick_base.visible = true
				_stick_knob.visible = true
				_stick_knob.position = event.position - _stick_knob.size / 2
			elif event.position.x >= half and _look_id == -1:
				_look_id = event.index
		else:
			if event.index == _stick_id:
				_stick_id = -1
				game.player.move_input = Vector2.ZERO
				_stick_base.visible = false
				_stick_knob.visible = false
			elif event.index == _look_id:
				_look_id = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			var v: Vector2 = (event.position - _stick_origin).limit_length(90.0)
			_stick_knob.position = _stick_origin + v - _stick_knob.size / 2
			game.player.move_input = v / 90.0
		elif event.index == _look_id:
			game.player.look(event.relative * 0.005)
