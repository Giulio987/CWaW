# HUD (round counter, points, ammo, prompts) and touch controls for iPhone.
class_name Hud
extends CanvasLayer

var game: Game
var _round: RoundCounter   # WaW tally marks / digits (round_counter.gd)
var _points: Label
var _ammo: Label
var _prompt: Label
var _msg: Label
var _hurt: ColorRect
var _perks: HBoxContainer
var _shown_perks := []
var _touch := false
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _look_id := -1
var _stick_knob: Control
var _stick_base: Control
var _pause: PauseMenu      # pause_menu.gd
var _shown_points := -1    # for the +/- points popups
var _over := false


func bind(g: Game) -> void:
	game = g
	_touch = DisplayServer.is_touchscreen_available()
	_hurt = ColorRect.new()
	_hurt.color = Color(0.6, 0, 0, 0)
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt)
	_round = RoundCounter.new()
	_round.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_round.position += Vector2(28, -28)
	add_child(_round)
	# perk icons in a row above the round number
	_perks = HBoxContainer.new()
	_perks.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_perks.position += Vector2(24, -150)
	_perks.add_theme_constant_override("separation", 6)
	_perks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_perks)
	_points = _label(46, UiArt.POINTS, Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -158))
	_points.add_theme_font_override("font", UiArt.font())
	_points.add_theme_constant_override("outline_size", 0)
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
	if _shown_points >= 0 and p.points != _shown_points:
		PointsPopup.spawn(self, p.points - _shown_points, _points.position)
	_shown_points = p.points
	var w := p.weapon()
	_ammo.text = "%s   %d / %d" % [Weapons.display_of(w), w["mag"], w["reserve"]]
	_hurt.color.a = clamp((1.0 - p.health / p.max_health) * 0.6, 0.0, 0.6)
	if p.perks != _shown_perks:
		_show_perks(p.perks)


func _show_perks(perks: Array) -> void:
	_shown_perks = perks.duplicate()
	for c in _perks.get_children():
		c.queue_free()
	for k in perks:
		var tex := Perks.icon(k)
		if tex:
			var r := TextureRect.new()
			r.texture = tex
			r.custom_minimum_size = Vector2(44, 45)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_perks.add_child(r)
		else:
			var l := Label.new()
			l.text = Perks.display(k)
			l.add_theme_font_size_override("font_size", 16)
			l.add_theme_color_override("font_color", Perks.INFO[k]["color"])
			_perks.add_child(l)


func _process(_d: float) -> void:
	if game and game.player:
		_prompt.text = game.player.prompt


func round_changed(n: int) -> void:
	_round.set_round(n)


func message(t: String) -> void:
	_msg.text = t


func game_over(rounds: int) -> void:
	_over = true
	_msg.text = "GAME OVER\nHai resistito %d round" % rounds
	var b := Button.new()
	b.text = "Menu principale"
	b.add_theme_font_size_override("font_size", 28)
	b.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	b.offset_top = 60
	b.offset_bottom = 120
	b.offset_left = -140
	b.offset_right = 140
	b.pressed.connect(func(): get_tree().reload_current_scene())
	add_child(b)


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
	# frag grenade: hold to cook, release to throw (grenade_belt.gd)
	_button("💣", Vector2(-450, -420), Vector2(90, 90), func(down):
		var belt := GrenadeBelt.of(game.player)
		if belt:
			belt.set_held(down))
	# pause button (original HUD atlas icon), top right
	var pb := TextureButton.new()
	pb.texture_normal = UiArt.region(UiArt.PAUSE_ICON)
	pb.ignore_texture_size = true
	pb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	pb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pb.position += Vector2(-90, 20)
	pb.size = Vector2(64, 64)
	pb.modulate = Color(1, 1, 1, 0.8)
	pb.pressed.connect(open_pause)
	add_child(pb)


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


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		open_pause()


# Pause menu (Esc / touch pause button); it closes itself (Riprendi or Esc).
func open_pause() -> void:
	if _over or get_tree().paused:
		return
	if _pause == null:
		_pause = PauseMenu.new()
		_pause.game = game
		add_child(_pause)
	_pause.open()


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
			game.player.look(event.relative * 0.005 * Settings.touch_sens())
