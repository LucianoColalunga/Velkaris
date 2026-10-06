extends Node
## Prueba de humo de extremo a extremo: un bot se autentica, camina desde su santuario hasta
## el Portón Norte (prediccion + colisiones del servidor), lo golpea y usa el chat.
##
## Uso (dos consolas, desde la carpeta del proyecto):
##   godot --headless --path . -- --server --port=7790 --password=prueba
##   godot --headless --path . res://tests/smoke_bot.tscn -- --port=7790 --password=prueba
## Sin --headless (con ventana) y con --shots=C:/carpeta guarda capturas de pantalla.
## Termina con código 0 si todo funcionó y 1 si algo falló.

var client: GameClient
var t := 0.0
var phase := 0
var start_pos := Vector2.ZERO
var gate_hp_start := 0
var hits := 0
var shots_dir := ""
var _done := false


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = str(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if DisplayServer.get_name() != "headless":
		shots_dir = str(args.get("shots", ""))
	InputSetup.ensure_actions()
	client = GameClient.new()
	add_child(client)
	Net.client = client
	client.left_game.connect(func(reason: String) -> void: _finish(false, "left_game: " + reason))
	var err := client.connect_to_server({"name": "BotPrueba", "ip": "127.0.0.1",
		"port": int(args.get("port", "7777")), "password": str(args.get("password", "")),
		"realm": 0, "cls": 0, "shadows": false})
	if err != OK:
		_finish(false, "connect_to_server error %d" % err)


func _process(delta: float) -> void:
	if _done:
		return
	t += delta
	if t > 40.0:
		_finish(false, "timeout en la fase %d" % phase)
		return
	match phase:
		0:
			if client.in_world:
				start_pos = client.pred_pos
				print("[BOT] En el mundo. Posición inicial: ", start_pos)
				_shot("1_santuario")
				Input.action_press("move_forward")  # La cámara aparece mirando hacia el Bastión.
				phase = 1
				t = 0.0
		1:
			# Se re-pulsa cada frame: Godot suelta las teclas si la ventana pierde el foco.
			Input.action_press("move_forward")
			if t > 13.0:
				Input.action_release("move_forward")
				print("[BOT] Tras caminar: ", client.pred_pos, " (distancia al centro %.2f)" % client.pred_pos.length())
				_shot("2_porton")
				gate_hp_start = int(client.gate_hp[0])
				phase = 2
				t = 0.0
		2:
			if hits < 3 and t > 1.4 * (hits + 1):
				client.use_ability(0)
				hits += 1
			if t > 6.0:
				print("[BOT] Portón Norte: %d -> %d" % [gate_hp_start, int(client.gate_hp[0])])
				client.send_chat("hola [url=x]prueba[/url]")
				_shot("3_asedio")
				phase = 3
				t = 0.0
		3:
			if t > 1.0:
				var moved := client.pred_pos.distance_to(start_pos) > 30.0
				var wall_outer := GameData.WALL_RADIUS + GameData.WALL_HALF_THICKNESS + GameData.PLAYER_RADIUS
				var stopped_by_wall := absf(client.pred_pos.length() - wall_outer) < 0.3
				var damaged := int(client.gate_hp[0]) < gate_hp_start
				_finish(moved and stopped_by_wall and damaged,
					"movió=%s muralla=%s portón_dañado=%s" % [moved, stopped_by_wall, damaged])


func _shot(label: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join("%s.png" % label))


func _finish(ok: bool, msg: String) -> void:
	if _done:
		return
	_done = true
	print("[BOT] RESULTADO: %s (%s)" % ["OK" if ok else "FALLO", msg])
	get_tree().quit(0 if ok else 1)
