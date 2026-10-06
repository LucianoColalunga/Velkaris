extends Node
## Superficie RPC única del juego. Autoload "Net" => ruta /root/Net en cliente y servidor.
## (Godot exige que ambos lados declaren los mismos métodos @rpc en el mismo NodePath.)
##
## Reglas de seguridad de esta capa:
##  * Cliente -> servidor usa "any_peer". El servidor identifica al emisor SIEMPRE con
##    multiplayer.get_remote_sender_id(), nunca con un dato del paquete.
##  * Servidor -> cliente usa "authority": Godot descarta la llamada si no la hace el
##    servidor (peer 1). Con server_relay = false, un cliente no puede hablarle a otro.
##  * Los parámetros van sin tipo A PROPÓSITO: el servidor comprueba typeof() por sí mismo,
##    cuenta infracciones y expulsa a quien envía basura.

var server = null  ## GameServer (sólo existe en el proceso servidor)
var client = null  ## GameClient (sólo existe en el proceso cliente)


func _ready() -> void:
	var smp := multiplayer as SceneMultiplayer
	smp.peer_authenticating.connect(_on_peer_authenticating)
	smp.peer_authentication_failed.connect(_on_peer_authentication_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Cierra la conexión actual y deja el multijugador en modo offline.
func reset_peer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var smp := multiplayer as SceneMultiplayer
	smp.auth_callback = Callable()


# --- Señales de conexión (se enrutan al rol activo) ---------------------------------

func _on_peer_authenticating(id: int) -> void:
	if server:
		server.on_peer_authenticating(id)


func _on_peer_authentication_failed(id: int) -> void:
	if server:
		server.on_peer_authentication_failed(id)


func _on_peer_connected(id: int) -> void:
	if server:
		server.on_peer_connected(id)


func _on_peer_disconnected(id: int) -> void:
	if server:
		server.on_peer_disconnected(id)


func _on_connected_to_server() -> void:
	if client:
		client.on_connected_to_server()


func _on_connection_failed() -> void:
	if client:
		client.on_connection_failed()


func _on_server_disconnected() -> void:
	if client:
		client.on_server_disconnected()


# --- Cliente -> Servidor ------------------------------------------------------------

## Handshake de 3 fases: tras autenticarse, el cliente avisa que cargó y está listo.
@rpc("any_peer", "call_remote", "reliable")
func c2s_ready() -> void:
	if server and multiplayer.is_server():
		server.on_ready(multiplayer.get_remote_sender_id())


## Intenciones de movimiento: [[seq, Vector2 dirección, yaw], ...]. Nunca posiciones.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func c2s_input(cmds) -> void:
	if server and multiplayer.is_server():
		server.on_input(multiplayer.get_remote_sender_id(), cmds)


## "Quiero usar la habilidad <slot> sobre <target_id>". El servidor decide si ocurre.
@rpc("any_peer", "call_remote", "reliable")
func c2s_ability(slot, target_id, yaw) -> void:
	if server and multiplayer.is_server():
		server.on_ability(multiplayer.get_remote_sender_id(), slot, target_id, yaw)


@rpc("any_peer", "call_remote", "reliable")
func c2s_chat(text) -> void:
	if server and multiplayer.is_server():
		server.on_chat(multiplayer.get_remote_sender_id(), text)


# --- Servidor -> Cliente ------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func s2c_welcome(data) -> void:
	if client:
		client.on_welcome(data)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func s2c_snapshot(snap) -> void:
	if client:
		client.on_snapshot(snap)


@rpc("authority", "call_remote", "reliable")
func s2c_event(type, data) -> void:
	if client:
		client.on_event(type, data)
