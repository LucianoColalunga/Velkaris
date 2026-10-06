class_name ServerConfig
extends RefCounted
## Configuración del servidor. Orden de prioridad (de menor a mayor):
##   valores por defecto < server.cfg < argumentos de línea de comandos (--port=7777 ...)
## server.cfg se busca junto al ejecutable y, si no está, en user://.

var port: int = Protocol.DEFAULT_PORT
var max_players: int = Protocol.DEFAULT_MAX_PLAYERS
var bind_ip: String = "*"
var password: String = ""
var server_name: String = "Servidor de Velkaris"
var realm_balance_margin: int = 3   ## 0 = sin límite de equilibrio entre reinos.
var max_conn_per_ip: int = 4
var source_file: String = ""


static func load_default() -> ServerConfig:
	var cfg := ServerConfig.new()
	var candidates := PackedStringArray()
	candidates.append(OS.get_executable_path().get_base_dir().path_join("server.cfg"))
	if OS.has_feature("editor"):
		candidates.append(ProjectSettings.globalize_path("res://server.cfg"))
	candidates.append("user://server.cfg")
	for path in candidates:
		if FileAccess.file_exists(path):
			cfg.load_file(path)
			break
	return cfg


func load_file(path: String) -> void:
	var f := ConfigFile.new()
	if f.load(path) != OK:
		push_warning("No se pudo leer %s; se usan valores por defecto." % path)
		return
	port = clampi(int(f.get_value("server", "port", port)), 1024, 65535)
	max_players = clampi(int(f.get_value("server", "max_players", max_players)), 1, 128)
	bind_ip = str(f.get_value("server", "bind_ip", bind_ip))
	password = str(f.get_value("server", "password", password))
	server_name = str(f.get_value("server", "name", server_name)).substr(0, 40)
	realm_balance_margin = maxi(0, int(f.get_value("server", "realm_balance_margin", realm_balance_margin)))
	max_conn_per_ip = clampi(int(f.get_value("security", "max_conn_per_ip", max_conn_per_ip)), 1, 64)
	source_file = path


func apply_args(args: Dictionary) -> void:
	if args.has("port"):
		port = clampi(int(args["port"]), 1024, 65535)
	if args.has("max-players"):
		max_players = clampi(int(args["max-players"]), 1, 128)
	if args.has("password"):
		password = str(args["password"])
	if args.has("name"):
		server_name = str(args["name"]).substr(0, 40)
	if args.has("bind"):
		bind_ip = str(args["bind"])
