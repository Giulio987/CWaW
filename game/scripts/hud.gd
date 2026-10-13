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
var _damage: DamageOverlay          # DamageBitmapTop/Bottom (damage_overlay.gd)
var _powerups: PowerupFrame         # CGuiFramePowerup + pickup message (powerup_frame.gd)
var _msg_t := 0.0                   # show_message timer
var _low_ammo := false              # LowClipPercentage / LowAmmoPercentage reached
var _blink_t := 0.0
var _last_health := -1.0
var _cross: Label                   # reticle, hidden while aiming down the sights
var _hold_bar: ProgressBar          # InteractTime hold progress
# console.bin: the clip blinks at LowClipPercentage 35 % of the magazine, the
# reserve at LowAmmoPercentage 20 % of the full reserve, every AmmoBlinkTime 500 ms
const LOW_CLIP := 0.35
const LOW_AMMO := 0.20
const AMMO_BLINK := 0.5


func bind(g: Game) -> void:
	game = g
	_touch = DisplayServer.is_touchscreen_available()
	_hurt = ColorRect.new()   # kept for a faint full-screen tint; the strips carry the damage
	_hurt.color = Color(0.6, 0, 0, 0)
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt)
	_damage = DamageOverlay.new()
	add_child(_damage)
	var prox := ProximityIndicator.new()   # proximity_indicator.gd
	prox.game = g
	add_child(prox)
	_powerups = PowerupFrame.new()
	_powerups.game = g
	add_child(_powerups)
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
	_cross = _label(26, Color(1, 1, 1, 0.7), Control.PRESET_CENTER, Vector2(-7, -18))
	_cross.text = "+"
	# InteractTime hold progress (player.gd interact_progress), under the prompt
	_hold_bar = ProgressBar.new()
	_hold_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hold_bar.position += Vector2(-110, -168)
	_hold_bar.size = Vector2(220, 12)
	_hold_bar.show_percentage = false
	_hold_bar.max_value = 1.0
	_hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_bar.visible = false
	add_child(_hold_bar)
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
	var frac: float = p.health / p.max_health
	_hurt.color.a = clamp((1.0 - frac) * 0.15, 0.0, 0.15)
	_damage.set_health(frac, _last_health >= 0.0 and p.health < _last_health)
	_last_health = p.health
	var st := Weapons.stats_of(w)
	_low_ammo = (st["mag"] > 0 and w["mag"] <= st["mag"] * LOW_CLIP) or (st["reserve"] > 0 and w["reserve"] <= st["reserve"] * LOW_AMMO)
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
		# the aim states switch the reticle off (gun state machine output "reticle")
		_cross.visible = not game.player.aiming
		var hp: float = game.player.interact_progress()
		_hold_bar.visible = hp >= 0.0
		_hold_bar.value = maxf(hp, 0.0)
	# low ammo: the ammo counter blinks red / white every AmmoBlinkTime
	_blink_t += _d
	var red := _low_ammo and fmod(_blink_t, AMMO_BLINK * 2.0) < AMMO_BLINK
	_ammo.add_theme_color_override("font_color", Color(1.0, 0.15, 0.1) if red else Color.WHITE)
	if _msg_t > 0.0:
		_msg_t -= _d
		if _msg_t <= 0.0:
			_msg.text = ""


func round_changed(n: int) -> void:
	_round.set_round(n)


func message(t: String) -> void:
	_msg.text = t
	_msg_t = 0.0


# a centre message for some seconds (Game.ShowStartGameMessage(4000): "Round 1")
func show_message(t: String, seconds: float) -> void:
	_msg.text = t
	_msg_t = seconds


# power-up pickup message (PickupMessageTimeMs)
func pickup_message(t: String) -> void:
	_powerups.message(t)


func game_over(rounds: int) -> void:
	_over = true
	_msg.text = ""
	_msg_t = 0.0
	var screen := GameOverScreen.new()   # game_over_screen.gd (ig_gameover + local leaderboard)
	screen.game = game
	add_child(screen)


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
	# aim down the sights: ToggleAimIcon (toggleAim) toggles
	_button("◎", Vector2(-450, -260), Vector2(110, 110), func(down):
		if down:
			game.player.toggle_aim())
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
