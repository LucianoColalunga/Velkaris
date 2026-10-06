extends Node
## Punto de entrada. Decide si este proceso es SERVIDOR (headless) o CLIENTE (menú + juego).
##
##   Velkaris.exe                                  -> cliente con menú
##   Velkaris.console.exe --headless -- --server   -> servidor dedicado (con consola de logs)
##   Opciones del servidor: --port=7777 --password=xxx --max-players=32 --name="Mi server"

const CLIENT_CFG := "user://client.cfg"

var _menu: MainMenu
var _client: GameClient
var _hosted_pid := -1


func _ready() -> void:
	_boot.call_deferred()


func _boot() -> void:
	var args := _parse_args()
	# "server" es la etiqueta de las exportaciones de servidor (ver export_presets.cfg).
	if args.has("server") or OS.has_feature("server") or OS.has_feature("dedicated_server") \
			or DisplayServer.get_name() == "headless":
		_run_dedicated_server(args)
	else:
		InputSetup.ensure_actions()
		_show_menu("")


func _exit_tree() -> void:
	_stop_hosted_server()


# --- Servidor ---------------------------------------------------------------------------------

func _run_dedicated_server(args: Dictionary) -> void:
	var cfg := ServerConfig.load_default()
	cfg.apply_args(args)
	var server := GameServer.new()
	server.name = "GameServer"
	Net.add_child(server)
	Net.server = server
	var err := server.start(cfg)
	if err != OK:
		printerr("No se pudo abrir el puerto UDP %d (error %d). ¿Hay otro servidor usando ese puerto?" % [cfg.port, err])
		get_tree().quit(1)


# --- Cliente ----------------------------------------------------------------------------------

func _show_menu(message: String) -> void:
	_menu = MainMenu.new()
	add_child(_menu)
	_menu.setup(_load_client_cfg(), message)
	_menu.join_requested.connect(_on_join_requested)
	_menu.host_requested.connect(_on_host_requested)


func _on_join_requested(p: Dictionary) -> void:
	_save_client_cfg(p)
	_client = GameClient.new()
	_client.name = "GameClient"
	add_child(_client)
	Net.client = _client
	_client.entered_world.connect(_on_entered_world)
	_client.left_game.connect(_on_left_game)
	var err := _client.connect_to_server(p)
	if err != OK:
		_on_left_game("No se pudo iniciar la conexión (error %d)." % err)


## "Hospedar y jugar": lanza un servidor headless en segundo plano (otro proceso, con su
## propia memoria) y se conecta a él. El anfitrión juega como un cliente más: no tiene
## ninguna ventaja ni acceso especial a la simulación.
func _on_host_requested(p: Dictionary) -> void:
	_save_client_cfg(p)
	_stop_hosted_server()
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]))
	args.append_array(PackedStringArray(["--headless", "--", "--server", "--port=%d" % int(p["port"])]))
	if str(p["password"]) != "":
		args.append("--password=%s" % p["password"])
	_hosted_pid = OS.create_process(OS.get_executable_path(), args)
	if _hosted_pid <= 0:
		_menu.set_busy(false)
		_menu.set_status("No se pudo lanzar el servidor local.", true)
		return
	await get_tree().create_timer(1.0).timeout
	var local := p.duplicate()
	local["ip"] = "127.0.0.1"
	_on_join_requested(local)


func _on_entered_world() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


func _on_left_game(reason: String) -> void:
	_finish_leave.call_deferred(reason)


func _finish_leave(reason: String) -> void:
	Net.client = null
	Net.reset_peer()
	if _client:
		_client.queue_free()
		_client = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_stop_hosted_server()
	if _menu == null:
		_show_menu(reason)
	else:
		_menu.set_busy(false)
		_menu.set_status(reason, true)


func _stop_hosted_server() -> void:
	if _hosted_pid > 0 and OS.is_process_running(_hosted_pid):
		OS.kill(_hosted_pid)
	_hosted_pid = -1


# --- Utilidades -------------------------------------------------------------------------------

func _parse_args() -> Dictionary:
	var out := {}
	var all := OS.get_cmdline_args()
	all.append_array(OS.get_cmdline_user_args())
	for a in all:
		var arg: String = a
		if arg.begins_with("--"):
			var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


func _load_client_cfg() -> Dictionary:
	var f := ConfigFile.new()
	var out := {}
	if f.load(CLIENT_CFG) == OK and f.has_section("client"):
		for key in f.get_section_keys("client"):
			out[key] = f.get_value("client", key)
	return out


## La contraseña NO se guarda en disco.
func _save_client_cfg(p: Dictionary) -> void:
	var f := ConfigFile.new()
	for key in ["name", "ip", "port", "realm", "cls", "shadows"]:
		f.set_value("client", key, p[key])
	f.save(CLIENT_CFG)
