# HUD (round counter, points, ammo, prompts) and touch controls for iPhone.
class_name Hud
extends CanvasLayer

var game: Game
var _round: RoundCounter   # WaW tally marks / digits (round_counter.gd)
var _points: Label
var _weapon_hud: WeaponHud           # hud_guns icon + ammos_container (weapon_hud.gd)
var _prompt: Label
var _msg: Label
var _hurt: ColorRect
var _perks: HBoxContainer
var _shown_perks := []
var _touch := false
var touch_ui: TouchControls         # original touch buttons (touch_controls.gd)
var _pause: PauseMenu      # pause_menu.gd
var _shown_points := -1    # for the +/- points popups
var _over := false
var _damage: DamageOverlay          # DamageBitmapTop/Bottom (damage_overlay.gd)
var _powerups: PowerupFrame         # CGuiFramePowerup + pickup message (powerup_frame.gd)
var _msg_t := 0.0                   # show_message timer
var _last_health := -1.0
var _reticle: AimingReticle         # CGuiFrameAimingReticle (aiming_reticle.gd)
var _hold_bar: ProgressBar          # InteractTime hold progress
const UI_SCALE := 2.0               # original 480x320 HUD pixels -> screen (as WeaponHud)
const MESSAGE_Y := 0x6b8 / 4096.0   # MessageLabel y (fraction of the screen height)


func bind(g: Game) -> void:
	game = g
	# --touch-ui: the touch controls on a Mac too (tests, screenshots)
	_touch = DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch-ui")
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
	# Layout of the original HUD (ui.group.bin, 480x320, here x UI_SCALE from the top
	# left; units: 1 = pixels, 2 = parent size + value, 8 = fraction of the parent):
	# "wave_indicator" 100x50 centred at 55,65 (tally images at 1:1 -> bottom at 90)
	_round = RoundCounter.new()
	_round.position = Vector2(5, 90) * UI_SCALE
	add_child(_round)
	# CGuiFramePerkDisplay (17daefa2): at 122,0, 86x34, 34x34 icons 17 px apart, overlapping
	_perks = HBoxContainer.new()
	_perks.position = Vector2(122, 0) * UI_SCALE
	_perks.add_theme_constant_override("separation", int(-17 * UI_SCALE))
	_perks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_perks)
	# "points_container" 120x50 at 0,0: a 100x50 red smear (atlas 192,61-292,101) and
	# "points_count" at 30 % (36), 0, 96x40, HUD font, left / top aligned
	var smear := TextureRect.new()
	smear.texture = UiArt.region(Rect2(192, 61, 100, 40))
	smear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	smear.size = Vector2(100, 50) * UI_SCALE
	smear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(smear)
	_points = _label(int(22 * UI_SCALE), UiArt.POINTS, Control.PRESET_TOP_LEFT, Vector2(36, 0) * UI_SCALE)
	_points.add_theme_font_override("font", UiArt.font())
	_points.add_theme_constant_override("outline_size", 0)
	# CGuiLabelInteractMessage of the control frames: top, full width, 65 px high, centred
	_prompt = _label(22, Color.WHITE, Control.PRESET_TOP_WIDE, Vector2.ZERO)
	_prompt.custom_minimum_size.y = 65 * UI_SCALE
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# "MessageLabel" ("Round 1"...): centred on x 50 %, y 0x6b8 / 4096 (42 %), HUD font
	_msg = _label(int(22 * UI_SCALE), Color.WHITE, Control.PRESET_TOP_WIDE, Vector2.ZERO)
	_msg.add_theme_font_override("font", UiArt.font())
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle = AimingReticle.new()
	_reticle.player = g.player
	add_child(_reticle)
	_weapon_hud = WeaponHud.new()   # top right, as hud_guns / ammos_container
	_weapon_hud.player = g.player
	add_child(_weapon_hud)
	# InteractTime hold progress (player.gd interact_progress), under the prompt
	_hold_bar = ProgressBar.new()
	_hold_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hold_bar.position += Vector2(-110, 65 * UI_SCALE)
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
		# the counter is top left as in the original: popups go to its right / below
		# (CGuiInGameHud's own animation, startPtAnim 40,40 towards -200,-200 over
		# pointAnimationTime 500 ms, would leave the screen at once: not reproduced)
		var pp := PointsPopup.spawn(self, p.points - _shown_points, _points.position)
		var w := _points.get_minimum_size().x
		if p.points > _shown_points:
			pp.position = _points.position + Vector2(w + 20 + randf() * 30, randf_range(0, 40))
			pp._vel = Vector2(randf_range(60, 110), randf_range(-30, 50))
		else:
			pp.position = _points.position + Vector2(w * 0.3, 50)
			pp._vel = Vector2(10, 22)
	_shown_points = p.points
	var frac: float = p.health / p.max_health
	_hurt.color.a = clamp((1.0 - frac) * 0.15, 0.0, 0.15)
	_damage.set_health(frac, _last_health >= 0.0 and p.health < _last_health)
	_last_health = p.health
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
			r.custom_minimum_size = Vector2(34, 34) * UI_SCALE
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
	_msg.position.y = get_viewport().get_visible_rect().size.y * MESSAGE_Y - _msg.size.y / 2.0
	if game and game.player:
		_prompt.text = game.player.prompt
		var hp: float = game.player.interact_progress()
		_hold_bar.visible = hp >= 0.0
		_hold_bar.value = maxf(hp, 0.0)
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
	if touch_ui:
		touch_ui.release_all()
		touch_ui.visible = false
	_msg.text = ""
	_msg_t = 0.0
	var screen := GameOverScreen.new()   # game_over_screen.gd (ig_gameover + local leaderboard)
	screen.game = game
	add_child(screen)


# ------------------------------------------------------------------ touch

func _build_touch() -> void:
	# the original buttons (touch_controls.gd), under the weapon icon so that it gets
	# its touches first; full rect of this layer: laid out on the visible area
	touch_ui = TouchControls.new()
	touch_ui.game = game
	add_child(touch_ui)
	move_child(touch_ui, _weapon_hud.get_index())


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
