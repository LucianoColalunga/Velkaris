class_name MainMenu
extends Control
## Menú principal: datos del personaje, dirección del servidor y opciones gráficas.

signal join_requested(params: Dictionary)
signal host_requested(params: Dictionary)

var _name: LineEdit
var _ip: LineEdit
var _port: SpinBox
var _pass: LineEdit
var _realm: OptionButton
var _cls: OptionButton
var _shadows: CheckBox
var _realm_info: Label
var _cls_info: Label
var _status: Label
var _buttons: Array = []


func setup(saved: Dictionary, message: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_name.text = str(saved.get("name", ""))
	_ip.text = str(saved.get("ip", "127.0.0.1"))
	_port.value = int(saved.get("port", Protocol.DEFAULT_PORT))
	_realm.select(clampi(int(saved.get("realm", 0)), 0, GameData.REALM_COUNT - 1))
	_cls.select(clampi(int(saved.get("cls", 0)), 0, GameData.CLASS_COUNT - 1))
	_shadows.button_pressed = bool(saved.get("shadows", false))
	_update_info()
	if message != "":
		set_status(message, true)


func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if is_error else Color(0.85, 0.85, 0.9))


func set_busy(busy: bool) -> void:
	for b in _buttons:
		var btn: Button = b
		btn.disabled = busy


func _collect() -> Dictionary:
	return {
		"name": _name.text.strip_edges(),
		"ip": _ip.text.strip_edges(),
		"port": int(_port.value),
		"password": _pass.text,
		"realm": _realm.get_selected_id(),
		"cls": _cls.get_selected_id(),
		"shadows": _shadows.button_pressed,
	}


func _validate(p: Dictionary, need_ip: bool) -> bool:
	if Protocol.sanitize_name(p["name"]) == "":
		set_status("El nombre debe tener entre 3 y 16 caracteres: letras, números o _.", true)
		return false
	if need_ip and str(p["ip"]) == "":
		set_status("Escribe la IP (o dominio) del servidor.", true)
		return false
	return true


func _on_join() -> void:
	var p := _collect()
	if not _validate(p, true):
		return
	set_busy(true)
	set_status("Conectando a %s:%d..." % [p["ip"], p["port"]])
	join_requested.emit(p)


func _on_host() -> void:
	var p := _collect()
	if not _validate(p, false):
		return
	set_busy(true)
	set_status("Iniciando servidor local en el puerto %d..." % p["port"])
	host_requested.emit(p)


func _update_info(_idx: int = 0) -> void:
	var r := _realm.get_selected_id()
	var c := _cls.get_selected_id()
	var color: Color = GameData.REALM_COLORS[r]
	_realm_info.text = GameData.REALM_BLURB[r]
	_realm_info.add_theme_color_override("font_color", color.lightened(0.3))
	_cls_info.text = "%s — %s" % [GameData.CLASS_ROLES[c], GameData.CLASS_BLURB[c]]


# --- Construcción --------------------------------------------------------------------------

func _build() -> void:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.10, 0.06, 0.14), Color(0.04, 0.03, 0.06)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	center.add_child(vb)

	var title := Label.new()
	title.text = "VELKARIS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	vb.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "La Guerra de los Tres Reinos"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(subtitle)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.10, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	vb.add_child(panel)

	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	form.custom_minimum_size = Vector2(500, 0)
	panel.add_child(form)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	form.add_child(grid)

	_name = LineEdit.new()
	_name.max_length = Protocol.MAX_NAME_LEN
	_name.placeholder_text = "Tu nombre de héroe"
	_add_row(grid, "Nombre", _name)

	_realm = OptionButton.new()
	for r in GameData.REALM_COUNT:
		_realm.add_item(GameData.REALM_NAMES[r], r)
	_realm.item_selected.connect(_update_info)
	_add_row(grid, "Reino", _realm)

	_cls = OptionButton.new()
	for c in GameData.CLASS_COUNT:
		_cls.add_item(GameData.CLASS_NAMES[c], c)
	_cls.item_selected.connect(_update_info)
	_add_row(grid, "Clase", _cls)

	_ip = LineEdit.new()
	_ip.placeholder_text = "127.0.0.1, IP del anfitrión o dominio"
	_add_row(grid, "Servidor", _ip)

	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.step = 1
	_add_row(grid, "Puerto (UDP)", _port)

	_pass = LineEdit.new()
	_pass.secret = true
	_pass.placeholder_text = "Vacío si el servidor no tiene"
	_add_row(grid, "Contraseña", _pass)

	_shadows = CheckBox.new()
	_shadows.text = "Sombras (desactívalo en GPU de 2 GB)"
	_add_row(grid, "Gráficos", _shadows)

	_realm_info = _info_label()
	form.add_child(_realm_info)
	_cls_info = _info_label()
	form.add_child(_cls_info)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	form.add_child(buttons)
	_add_button(buttons, "Unirse al servidor", _on_join)
	_add_button(buttons, "Hospedar y jugar", _on_host)
	_add_button(buttons, "Salir", func() -> void: get_tree().quit())

	_status = _info_label()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(_status)

	var footer := Label.new()
	footer.text = "v%s · protocolo %d · github.com/LucianoColalunga" % [ProjectSettings.get_setting("application/config/version", "0.1.0"), Protocol.VERSION]
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.modulate = Color(1, 1, 1, 0.4)
	vb.add_child(footer)


func _add_row(grid: GridContainer, label: String, field: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(field)


func _add_button(parent: Container, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	_buttons.append(b)


func _info_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	l.modulate = Color(1, 1, 1, 0.85)
	return l
