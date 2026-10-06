class_name Hud
extends Control
## Interfaz en partida, construida por código (sin escenas que mantener).
## Seguridad: el chat se pinta con add_text(), que NUNCA interpreta BBCode; un jugador no
## puede inyectar [url], [img] ni colores falsos en la ventana de otro.

signal disconnect_requested

var client = null  ## GameClient (sin tipo para no crear dependencia cíclica)

var _score_labels: Array = []
var _objectives: RichTextLabel
var _info: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _ability_buttons: Array = []
var _cd_labels: Array = []
var _target_box: PanelContainer
var _target_name: Label
var _target_bar: ProgressBar
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _notice: Label
var _notice_t := 0.0
var _center: Label
var _banner: Label
var _banner_t := 0.0
var _help: PanelContainer
var _pause: PanelContainer
var _hit_flash: ColorRect
var _slow_t := 0.0


func setup(c) -> void:
	client = c
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_bottom()
	_build_chat()
	_build_overlays()


# --- API usada por GameClient ------------------------------------------------------------

func is_typing() -> bool:
	return _chat_input.has_focus()


func focus_chat() -> void:
	_chat_input.grab_focus()


func add_chat(sender: String, realm: int, text: String) -> void:
	_chat_log.push_color(GameData.REALM_COLORS[realm])
	_chat_log.add_text("[%s] " % sender)
	_chat_log.pop()
	_chat_log.add_text(text)
	_chat_log.newline()
	_trim_chat()


func add_system(text: String) -> void:
	_chat_log.push_color(Color(1.0, 0.85, 0.45))
	_chat_log.add_text("» " + text)
	_chat_log.pop()
	_chat_log.newline()
	_trim_chat()


func add_kill(killer: String, killer_realm: int, victim: String, victim_realm: int) -> void:
	_chat_log.push_color(GameData.REALM_COLORS[killer_realm])
	_chat_log.add_text(killer)
	_chat_log.pop()
	_chat_log.add_text(" ha abatido a ")
	_chat_log.push_color(GameData.REALM_COLORS[victim_realm])
	_chat_log.add_text(victim)
	_chat_log.pop()
	_chat_log.newline()
	_trim_chat()


func notice(text: String) -> void:
	_notice.text = text
	_notice.modulate.a = 1.0
	_notice_t = 2.0


func show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner_t = 6.0


func flash_hit() -> void:
	_hit_flash.color.a = 0.08


func toggle_help() -> void:
	_help.visible = not _help.visible


func toggle_pause_menu() -> void:
	_pause.visible = not _pause.visible


func refresh(delta: float) -> void:
	# Cada frame: enfriamientos y efectos que se desvanecen.
	for i in 3:
		var cd := maxf(float(client.cooldowns[i]), float(client.gcd_left))
		var lbl: Label = _cd_labels[i]
		var btn: Button = _ability_buttons[i]
		lbl.text = ("%.1f" % cd) if cd > 0.05 else ""
		btn.modulate = Color(0.55, 0.55, 0.6) if cd > 0.05 else Color.WHITE
	if _notice_t > 0.0:
		_notice_t -= delta
		_notice.modulate.a = clampf(_notice_t, 0.0, 1.0)
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.visible = _banner_t > 0.0
	_hit_flash.color.a = maxf(0.0, _hit_flash.color.a - delta * 0.4)

	# 10 veces por segundo: textos (evita re-maquetar la UI en cada frame).
	_slow_t -= delta
	if _slow_t > 0.0:
		return
	_slow_t = 0.1
	for r in GameData.REALM_COUNT:
		var sl: Label = _score_labels[r]
		sl.text = "%s  %d" % [GameData.REALM_SHORT[r], int(client.scores[r])]
	_hp_bar.max_value = client.my_max_hp
	_hp_bar.value = client.my_hp
	_hp_label.text = "%d / %d" % [client.my_hp, client.my_max_hp]
	if client.my_alive:
		_center.visible = false
	else:
		_center.visible = true
		_center.text = "Has caído.\nReapareces en tu santuario en %.0f s" % ceilf(client.respawn_in)
	var t: Dictionary = client.target_info()
	_target_box.visible = not t.is_empty()
	if not t.is_empty():
		_target_name.text = "%s — %s" % [t["name"], t["sub"]]
		var realm: int = t["realm"]
		_target_name.add_theme_color_override("font_color", GameData.REALM_COLORS[realm] if realm >= 0 else Color(0.9, 0.8, 0.6))
		_target_bar.max_value = t["max"]
		_target_bar.value = t["hp"]
	_objectives.text = _objectives_text()
	var ping := 0.0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null:
		var pp := enet.get_peer(1)
		if pp != null:
			ping = pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	_info.text = "%s · %d ms · %d FPS" % [client.server_name, int(ping), int(Engine.get_frames_per_second())]


# --- Construcción -----------------------------------------------------------------------

func _build_top() -> void:
	var scores_panel := _panel()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	scores_panel.add_child(hb)
	for r in GameData.REALM_COUNT:
		var l := Label.new()
		l.add_theme_color_override("font_color", GameData.REALM_COLORS[r])
		l.add_theme_font_size_override("font_size", 20)
		hb.add_child(l)
		_score_labels.append(l)
	var goal := Label.new()
	goal.text = "Meta: %d" % GameData.WIN_SCORE
	goal.modulate = Color(1, 1, 1, 0.6)
	hb.add_child(goal)
	_place(scores_panel, Control.PRESET_CENTER_TOP)

	var obj_panel := _panel()
	_objectives = RichTextLabel.new()
	_objectives.bbcode_enabled = true  # Sólo texto generado localmente (nombres fijos y números).
	_objectives.fit_content = true
	_objectives.scroll_active = false
	_objectives.custom_minimum_size = Vector2(270, 0)
	_objectives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_panel.add_child(_objectives)
	_place(obj_panel, Control.PRESET_TOP_LEFT)

	_info = Label.new()
	_info.modulate = Color(1, 1, 1, 0.75)
	var info_box := VBoxContainer.new()
	info_box.add_child(_info)
	var hint := Label.new()
	hint.text = "F1: ayuda · Esc: menú"
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_box.add_child(hint)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(info_box, Control.PRESET_TOP_RIGHT)


func _build_bottom() -> void:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 6)

	_target_box = _panel()
	var tvb := VBoxContainer.new()
	_target_name = Label.new()
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_bar = ProgressBar.new()
	_target_bar.custom_minimum_size = Vector2(300, 14)
	_target_bar.show_percentage = false
	tvb.add_child(_target_name)
	tvb.add_child(_target_bar)
	_target_box.add_child(tvb)
	_target_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_target_box.visible = false
	vb.add_child(_target_box)

	var bar_panel := _panel()
	var bvb := VBoxContainer.new()
	var hp_row := HBoxContainer.new()
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(300, 20)
	_hp_bar.show_percentage = false
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.18, 0.15)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	_hp_label = Label.new()
	hp_row.add_child(_hp_bar)
	hp_row.add_child(_hp_label)
	bvb.add_child(hp_row)
	var abilities := HBoxContainer.new()
	abilities.add_theme_constant_override("separation", 6)
	var my_abilities: Array = GameData.ABILITIES[client.my_cls]
	for i in 3:
		var ab: Dictionary = my_abilities[i]
		var b := Button.new()
		b.text = "%d · %s" % [i + 1, ab["name"]]
		b.tooltip_text = str(ab["desc"])
		b.custom_minimum_size = Vector2(150, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(Callable(client, "use_ability").bind(i))
		var cd := Label.new()
		cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd.add_theme_font_size_override("font_size", 22)
		cd.add_theme_color_override("font_outline_color", Color.BLACK)
		cd.add_theme_constant_override("outline_size", 6)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cd)
		abilities.add_child(b)
		_ability_buttons.append(b)
		_cd_labels.append(cd)
	bvb.add_child(abilities)
	bar_panel.add_child(bvb)
	bar_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(bar_panel)
	_place(vb, Control.PRESET_CENTER_BOTTOM)


func _build_chat() -> void:
	var panel := _panel()
	var vb := VBoxContainer.new()
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = false
	_chat_log.scroll_following = true
	_chat_log.custom_minimum_size = Vector2(390, 150)
	_chat_log.mouse_filter = Control.MOUSE_FILTER_PASS
	_chat_input = LineEdit.new()
	_chat_input.max_length = Protocol.MAX_CHAT_LEN
	_chat_input.placeholder_text = "Enter: escribir a tu reino"
	_chat_input.text_submitted.connect(_on_chat_submitted)
	vb.add_child(_chat_log)
	vb.add_child(_chat_input)
	panel.add_child(vb)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_place(panel, Control.PRESET_BOTTOM_LEFT)


func _build_overlays() -> void:
	_hit_flash = ColorRect.new()
	_hit_flash.color = Color(1.0, 0.9, 0.6, 0.0)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit_flash)
	_hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", 20)
	_notice.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_notice.add_theme_color_override("font_outline_color", Color.BLACK)
	_notice.add_theme_constant_override("outline_size", 6)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_notice, Control.PRESET_CENTER_TOP, 70)

	_center = Label.new()
	_center.add_theme_font_size_override("font_size", 30)
	_center.add_theme_color_override("font_outline_color", Color.BLACK)
	_center.add_theme_constant_override("outline_size", 8)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.visible = false
	_place(_center, Control.PRESET_CENTER)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 42)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_place(_banner, Control.PRESET_CENTER_TOP, 120)

	_help = _panel()
	var help_text := Label.new()
	help_text.text = "\n".join(PackedStringArray([
		"CONTROLES",
		"WASD / flechas — moverse",
		"Clic derecho o izquierdo + arrastrar — girar cámara · Q/E — girar",
		"Rueda — zoom",
		"1, 2, 3 — habilidades de tu clase",
		"Tab — siguiente objetivo (enemigos y portones) · Esc — soltar objetivo",
		"Enter — chat de reino",
		"",
		"OBJETIVOS",
		"Quédate dentro del círculo de una Atalaya para capturarla.",
		"Derriba un portón del Bastión de Ilun y captura su Esquirla central.",
		"Cada 5 s: +1 punto por atalaya, +3 por el Bastión. +2 por derribo.",
		"Gana el primer reino en llegar a %d puntos." % GameData.WIN_SCORE,
	]))
	_help.add_child(help_text)
	_help.visible = false
	_place(_help, Control.PRESET_CENTER)

	_pause = _panel()
	_pause.mouse_filter = Control.MOUSE_FILTER_STOP
	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Menú"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvb.add_child(title)
	var resume := Button.new()
	resume.text = "Volver al juego"
	resume.pressed.connect(toggle_pause_menu)
	pvb.add_child(resume)
	var leave := Button.new()
	leave.text = "Desconectar"
	leave.pressed.connect(func() -> void: disconnect_requested.emit())
	pvb.add_child(leave)
	var quit := Button.new()
	quit.text = "Salir del juego"
	quit.pressed.connect(func() -> void: get_tree().quit())
	pvb.add_child(quit)
	_pause.add_child(pvb)
	_pause.visible = false
	_place(_pause, Control.PRESET_CENTER)


func _objectives_text() -> String:
	var lines := PackedStringArray()
	lines.append("[b]Frontera Rota[/b]")
	for i in GameData.TOWER_ANGLES.size():
		lines.append(_point_line(GameData.TOWER_NAMES[i], client.towers[i]))
	lines.append(_point_line(GameData.FORTRESS_NAME, client.fortress))
	for gi in GameData.GATE_ANGLES.size():
		var hp := int(client.gate_hp[gi])
		var state := "[color=#ff6655]derribado[/color]" if hp <= 0 else "%d%%" % roundi(100.0 * hp / GameData.GATE_MAX_HP)
		lines.append("   %s: %s" % [GameData.GATE_NAMES[gi], state])
	return "\n".join(lines)


func _point_line(label: String, pt: Array) -> String:
	var own := int(pt[0])
	var capturer := int(pt[1])
	var progress := float(pt[2])
	var state := "neutral"
	if own >= 0:
		var c: Color = GameData.REALM_COLORS[own]
		state = "[color=#%s]%s[/color]" % [c.to_html(false), GameData.REALM_SHORT[own]]
	elif capturer >= 0:
		var c: Color = GameData.REALM_COLORS[capturer]
		state = "[color=#%s]%s %d%%[/color]" % [c.to_html(false), GameData.REALM_SHORT[capturer], roundi(progress * 100.0)]
	if bool(pt[3]):
		state += " [color=#ffffff](en disputa)[/color]"
	return "%s: %s" % [label, state]


func _on_chat_submitted(text: String) -> void:
	client.send_chat(text)
	_chat_input.clear()
	_chat_input.release_focus()


func _trim_chat() -> void:
	while _chat_log.get_paragraph_count() > 120:
		_chat_log.remove_paragraph(0)


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.72)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _place(c: Control, preset: Control.LayoutPreset, margin: int = 10) -> void:
	add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, margin)
