class_name GameServer
extends Node
## Servidor autoritativo de Velkaris.
##
## El servidor es la ÚNICA fuente de verdad: posiciones, vida, enfriamientos, capturas y
## puntuación se calculan aquí. Los clientes sólo envían INTENCIONES ("me muevo hacia
## allá", "uso la habilidad 2 sobre X") y reciben snapshots con el resultado.
##
## Flujo de conexión (handshake de 3 fases):
##   1. ENet conecta -> el servidor envía un desafío (nonce) por el canal de auth.
##   2. El cliente responde {versión, nombre, reino, clase, prueba de contraseña}.
##      Hasta completar la auth, Godot no entrega ningún RPC de ese peer.
##   3. El cliente envía c2s_ready -> el servidor crea su personaje y le da la bienvenida.

class SPlayer:
	var id: int
	var name: String
	var realm: int
	var cls: int
	var ip: String
	var pos := Vector2.ZERO
	var yaw := 0.0
	var hp := 1
	var max_hp := 1
	var alive := true
	var respawn_at := 0.0
	var cmd_queue: Array = []
	var last_recv_seq := 0
	var last_proc_seq := 0
	var move_tokens := 0.0
	var cooldowns: Array = [0.0, 0.0, 0.0]
	var gcd_until := 0.0
	var bulwark_until := 0.0
	var stealth_until := 0.0
	var resonance_until := 0.0
	var dash_until := 0.0
	var dash_dir := Vector2.ZERO
	var dash_speed := 0.0
	var violations := 0.0
	var kicked := false
	var cmds_in_window := 0
	var input_rl := RateLimiter.new(90.0, 60.0)  ## Paquetes de input (el cliente manda 30/s).
	var action_rl := RateLimiter.new(8.0, 5.0)   ## Habilidades.
	var chat_rl := RateLimiter.new(3.0, 0.5)     ## Chat: ráfaga de 3, luego 1 cada 2 s.

var cfg: ServerConfig
var players: Dictionary = {}    ## peer_id -> SPlayer (sólo quienes ya están en el mundo)
var _authing: Dictionary = {}   ## peer_id -> {nonce, ip}   desafío enviado, esperando respuesta
var _authed: Dictionary = {}    ## peer_id -> {name, realm, cls, ip}   esperando c2s_ready
var _fail_log: Dictionary = {}  ## ip -> Array de marcas de tiempo (ms) de fallos de auth
var _bans: Dictionary = {}      ## ip -> ms hasta el que está bloqueada
var tick := 0
var now := 0.0                  ## Tiempo de simulación (s). Todo enfriamiento usa este reloj.
var towers: Array = []          ## [{owner, capturer, progress, contested}, ...]
var gates: Array = []           ## Vida de cada portón.
var fortress: Dictionary = {}
var scores: Array = [0, 0, 0]
var charges: Array = []         ## Cargas de zapa pendientes de detonar.
var _score_timer := 0.0
var _window_timer := 0.0
var _spawn_salt := 0
var _crypto := Crypto.new()


func start(config: ServerConfig) -> Error:
	cfg = config
	Engine.physics_ticks_per_second = Protocol.TICK_RATE
	Engine.max_fps = 60  # Headless: evita quemar un núcleo entero sin necesidad.
	var peer := ENetMultiplayerPeer.new()
	if cfg.bind_ip != "*":
		peer.set_bind_ip(cfg.bind_ip)
	var err := peer.create_server(cfg.port, cfg.max_players)
	if err != OK:
		return err
	var smp := multiplayer as SceneMultiplayer
	smp.server_relay = false           # Un cliente jamás puede enviar RPCs a otro cliente.
	smp.allow_object_decoding = false  # Nunca deserializar objetos (evita ejecución remota de código).
	smp.auth_callback = _on_auth_data
	smp.auth_timeout = 6.0
	multiplayer.multiplayer_peer = peer
	_reset_objectives()
	_log("Servidor '%s' escuchando en UDP %d (máx. %d jugadores)%s." % [
		cfg.server_name, cfg.port, cfg.max_players, ", con contraseña" if cfg.password != "" else ", SIN contraseña"])
	if cfg.source_file != "":
		_log("Configuración leída de %s" % cfg.source_file)
	return OK


# =====================================================================================
#  Conexión y autenticación
# =====================================================================================

func on_peer_authenticating(id: int) -> void:
	var ip := _peer_ip(id)
	if _bans.has(ip) and Time.get_ticks_msec() < int(_bans[ip]):
		_log("Conexión rechazada de %s: IP bloqueada temporalmente." % ip)
		_drop(id)
		return
	if _count_ip(ip) >= cfg.max_conn_per_ip:
		_log("Conexión rechazada de %s: demasiadas conexiones desde esa IP." % ip)
		_drop(id)
		return
	var nonce := _crypto.generate_random_bytes(16).hex_encode()
	_authing[id] = {"nonce": nonce, "ip": ip}
	_send_auth(id, {"t": "challenge", "nonce": nonce, "v": Protocol.VERSION,
		"pw": cfg.password != "", "name": cfg.server_name})


func _on_auth_data(id: int, data: PackedByteArray) -> void:
	if not _authing.has(id):
		_drop(id)  # Mensaje de auth inesperado o repetido.
		return
	var pending: Dictionary = _authing[id]
	_authing.erase(id)
	var ip: String = pending["ip"]
	var msg: Variant = Protocol.parse_json_bytes(data, Protocol.MAX_AUTH_BYTES)
	if typeof(msg) != TYPE_DICTIONARY:
		_reject(id, ip, "Paquete de autenticación inválido.")
		return
	var d: Dictionary = msg
	if not Protocol.is_int_value(d.get("v"), Protocol.VERSION, Protocol.VERSION):
		_reject(id, ip, "Versión incompatible: el servidor usa el protocolo v%d. Actualiza el juego." % Protocol.VERSION, false)
		return
	var pname := Protocol.sanitize_name(d.get("name"))
	if pname == "":
		_reject(id, ip, "Nombre inválido: 3 a 16 caracteres (letras, números o _).")
		return
	if not Protocol.is_int_value(d.get("realm"), 0, GameData.REALM_COUNT - 1) \
			or not Protocol.is_int_value(d.get("cls"), 0, GameData.CLASS_COUNT - 1):
		_reject(id, ip, "Reino o clase inválidos.")
		return
	if cfg.password != "":
		var proof: Variant = d.get("proof")
		var expected := Protocol.password_proof(str(pending["nonce"]), cfg.password)
		if typeof(proof) != TYPE_STRING or not Protocol.constant_time_equals(proof, expected):
			_reject(id, ip, "Contraseña incorrecta.")
			return
	if _name_taken(pname):
		_reject(id, ip, "Ese nombre ya está en uso en este servidor.", false)
		return
	var realm := int(d["realm"])
	if not _realm_has_room(realm):
		_reject(id, ip, "%s tiene demasiados jugadores. Elige otro reino para equilibrar la guerra." % GameData.REALM_SHORT[realm], false)
		return
	_authed[id] = {"name": pname, "realm": realm, "cls": int(d["cls"]), "ip": ip}
	_send_auth(id, {"t": "ok", "id": id})
	(multiplayer as SceneMultiplayer).complete_auth(id)


func on_peer_authentication_failed(id: int) -> void:
	_authing.erase(id)
	_authed.erase(id)


func on_peer_connected(id: int) -> void:
	if not _authed.has(id):
		_drop(id)  # Defensa en profundidad: nunca debería pasar sin auth completa.
		return
	get_tree().create_timer(10.0).timeout.connect(_ready_timeout.bind(id))


func _ready_timeout(id: int) -> void:
	if _authed.has(id):
		_log("Peer %d no envió 'ready' a tiempo; desconectado." % id)
		_authed.erase(id)
		_drop(id)


func on_ready(id: int) -> void:
	if players.has(id) or not _authed.has(id):
		return
	var a: Dictionary = _authed[id]
	_authed.erase(id)
	var p := SPlayer.new()
	p.id = id
	p.name = a["name"]
	p.realm = a["realm"]
	p.cls = a["cls"]
	p.ip = a["ip"]
	p.max_hp = GameData.CLASS_MAX_HP[p.cls]
	players[id] = p
	_respawn(p)
	Net.s2c_welcome.rpc_id(id, {"id": id, "server": cfg.server_name, "realm": p.realm,
		"cls": p.cls, "roster": _roster(), "pos": [p.pos.x, p.pos.y], "yaw": p.yaw})
	_broadcast_event(Protocol.Ev.ROSTER, [[p.id, p.name, p.realm, p.cls]], id)
	_broadcast_system("%s se une a %s como %s." % [p.name, GameData.REALM_SHORT[p.realm], GameData.CLASS_NAMES[p.cls]])
	_log("  (id %d, IP %s, %d jugadores en línea)" % [id, p.ip, players.size()])


func on_peer_disconnected(id: int) -> void:
	_authing.erase(id)
	_authed.erase(id)
	if not players.has(id):
		return
	var p: SPlayer = players[id]
	players.erase(id)
	_broadcast_event(Protocol.Ev.LEAVE, [id])
	_broadcast_system("%s abandona la Frontera." % p.name)


# =====================================================================================
#  Mensajes del cliente (todo se valida: tipo, rango, ritmo y estado del juego)
# =====================================================================================

func on_input(id: int, cmds: Variant) -> void:
	var p := _player(id)
	if p == null:
		return
	if not p.input_rl.consume():
		_violation(p, 0.5, "flood de paquetes de movimiento")
		return
	if typeof(cmds) != TYPE_ARRAY:
		_violation(p, 2.0, "paquete de movimiento malformado")
		return
	var list: Array = cmds
	if list.is_empty() or list.size() > Protocol.MAX_CMDS_PER_PACKET:
		_violation(p, 2.0, "paquete de movimiento con tamaño inválido")
		return
	var prev_seq := -1
	for c in list:
		if typeof(c) != TYPE_ARRAY or c.size() != 3:
			_violation(p, 2.0, "comando malformado")
			return
		var seq: Variant = c[0]
		var mv: Variant = c[1]
		var yaw: Variant = c[2]
		if typeof(seq) != TYPE_INT or typeof(mv) != TYPE_VECTOR2 or typeof(yaw) != TYPE_FLOAT:
			_violation(p, 2.0, "tipos inválidos en comando")
			return
		var move: Vector2 = mv
		var fyaw: float = yaw
		var iseq: int = seq
		if not move.is_finite() or not is_finite(fyaw):
			_violation(p, 3.0, "NaN/Inf en comando")
			return
		if iseq <= prev_seq:
			_violation(p, 1.0, "secuencia desordenada")
			return
		prev_seq = iseq
		if iseq <= p.last_recv_seq:
			continue  # Duplicado por la redundancia del cliente: normal.
		if iseq > p.last_recv_seq + Protocol.MAX_SEQ_JUMP:
			_violation(p, 1.0, "salto de secuencia sospechoso")
			return
		if move.length_squared() > 1.0001:
			# Un cliente legítimo nunca pide moverse "más rápido" que 1.0. Se recorta y se anota.
			_violation(p, 1.0, "vector de movimiento > 1 (speedhack)")
			move = move.normalized()
		p.last_recv_seq = iseq
		p.cmds_in_window += 1
		if p.cmd_queue.size() >= Protocol.MAX_CMD_QUEUE:
			p.cmd_queue.pop_front()
			_violation(p, 0.25, "cola de comandos desbordada (cliente acelerado)")
		p.cmd_queue.append([iseq, move, wrapf(fyaw, -PI, PI)])


func on_ability(id: int, slot: Variant, target_id: Variant, yaw: Variant) -> void:
	var p := _player(id)
	if p == null:
		return
	if not p.action_rl.consume():
		_violation(p, 0.5, "flood de habilidades")
		return
	if typeof(slot) != TYPE_INT or typeof(target_id) != TYPE_INT or typeof(yaw) != TYPE_FLOAT:
		_violation(p, 2.0, "paquete de habilidad malformado")
		return
	var s: int = slot
	var tid: int = target_id
	var fyaw: float = yaw
	if s < 0 or s > 2 or not is_finite(fyaw):
		_violation(p, 2.0, "habilidad fuera de rango")
		return
	if not p.alive:
		return
	if now < p.gcd_until or now < float(p.cooldowns[s]):
		return  # Puede ocurrir legítimamente por latencia: se ignora sin sancionar.
	var ab: Dictionary = GameData.ABILITIES[p.cls][s]
	var kind: int = ab["kind"]
	fyaw = wrapf(fyaw, -PI, PI)
	var ok := false
	if kind == GameData.Kind.MELEE or kind == GameData.Kind.RANGED:
		ok = _ability_attack(p, ab, tid)
	elif kind == GameData.Kind.SELF_BUFF:
		p.bulwark_until = now + float(ab["duration"])
		ok = true
	elif kind == GameData.Kind.AOE_HEAL:
		ok = _ability_heal(p, ab)
	elif kind == GameData.Kind.DASH:
		p.yaw = fyaw
		p.dash_dir = GameData.yaw_to_dir(fyaw)
		p.dash_until = now + float(ab["duration"])
		p.dash_speed = float(ab["speed"])
		ok = true
	elif kind == GameData.Kind.STEALTH:
		p.stealth_until = now + float(ab["duration"])
		ok = true
	elif kind == GameData.Kind.SAPPER:
		ok = _ability_sapper(p, ab, tid)
	elif kind == GameData.Kind.RESONANCE:
		p.resonance_until = now + float(ab["duration"])
		ok = true
	if not ok:
		return
	p.cooldowns[s] = now + float(ab["cd"])
	p.gcd_until = now + GameData.GCD
	if kind == GameData.Kind.MELEE or kind == GameData.Kind.RANGED or kind == GameData.Kind.SAPPER:
		p.stealth_until = 0.0  # Atacar rompe el sigilo.
	_broadcast_fx(p, kind, tid)


func on_chat(id: int, text: Variant) -> void:
	var p := _player(id)
	if p == null:
		return
	if not p.chat_rl.consume():
		_notice(p, "Estás enviando mensajes demasiado rápido.")
		_violation(p, 0.5, "flood de chat")
		return
	var clean := Protocol.sanitize_chat(text)
	if clean == "":
		if typeof(text) != TYPE_STRING:
			_violation(p, 2.0, "chat malformado")
		return
	# Chat de reino: los enemigos no "entienden" tu idioma (y no pueden espiar tus planes).
	for o in players.values():
		if o.realm == p.realm and not o.kicked:
			_send_event(o.id, Protocol.Ev.CHAT, [p.id, clean])


# =====================================================================================
#  Simulación (30 ticks por segundo)
# =====================================================================================

func _physics_process(_delta: float) -> void:
	if cfg == null:
		return
	tick += 1
	now = tick * Protocol.TICK_DT
	var dt := Protocol.TICK_DT
	for p in players.values():
		_simulate(p, dt)
	_update_charges()
	_update_objectives(dt)
	_update_score(dt)
	_update_anticheat(dt)
	if tick % Protocol.SNAPSHOT_EVERY == 0:
		_send_snapshots()


func _simulate(p: SPlayer, dt: float) -> void:
	if p.kicked:
		return
	if not p.alive:
		# Muerto: se descartan las intenciones pero se confirman, para que el cliente no
		# las vuelva a simular.
		if not p.cmd_queue.is_empty():
			p.last_proc_seq = p.cmd_queue.back()[0]
			p.cmd_queue.clear()
		if now >= p.respawn_at:
			_respawn(p)
		return
	var gates_open := GameData.gates_open_for(p.realm, gates, fortress["owner"])
	# ANTI-SPEEDHACK: cada tick concede 1 "ficha" de movimiento (máx. MAX_MOVE_TOKENS) y
	# cada comando procesado gasta una. Enviar comandos más rápido NO mueve más rápido:
	# como máximo se avanza a la velocidad del reloj del servidor (+ un pequeño colchón).
	p.move_tokens = minf(p.move_tokens + 1.0, Protocol.MAX_MOVE_TOKENS)
	var processed := 0
	while not p.cmd_queue.is_empty() and p.move_tokens >= 1.0 and processed < Protocol.MAX_CMDS_PER_TICK:
		var c: Array = p.cmd_queue.pop_front()
		p.move_tokens -= 1.0
		processed += 1
		p.last_proc_seq = c[0]
		p.yaw = c[2]
		p.pos = Movement.step(p.pos, c[1], dt, 1.0, gates_open)
	if now < p.dash_until:
		p.pos = Movement.step(p.pos, p.dash_dir, dt, p.dash_speed / Movement.SPEED, gates_open)
	# Guardia del santuario: un intruso en la base enemiga recibe daño continuo.
	for r in GameData.REALM_COUNT:
		if r != p.realm and p.pos.distance_to(GameData.base_pos(r)) < GameData.BASE_RADIUS:
			_damage_player(p, GameData.BASE_GUARD_DPS * dt, null)


func _respawn(p: SPlayer) -> void:
	_spawn_salt += 1
	p.pos = GameData.spawn_pos(p.realm, _spawn_salt)
	p.yaw = GameData.dir_to_yaw(-p.pos.normalized())
	p.hp = p.max_hp
	p.alive = true
	p.cmd_queue.clear()
	p.move_tokens = 0.0
	p.dash_until = 0.0
	p.stealth_until = 0.0
	p.bulwark_until = 0.0
	p.resonance_until = 0.0


func _damage_player(t: SPlayer, amount: float, src: SPlayer) -> void:
	if not t.alive or _in_own_sanctuary(t):
		return
	if now < t.bulwark_until:
		amount *= 0.5
	var dmg := maxi(1, roundi(amount))
	t.hp -= dmg
	t.stealth_until = 0.0
	if src != null:
		var ev := [t.id, dmg, src.id, false]
		_send_event(t.id, Protocol.Ev.DAMAGE, ev)
		if src.id != t.id:
			_send_event(src.id, Protocol.Ev.DAMAGE, ev)
	if t.hp <= 0:
		_kill(t, src)


func _kill(t: SPlayer, src: SPlayer) -> void:
	t.hp = 0
	t.alive = false
	t.respawn_at = now + GameData.RESPAWN_TIME
	t.cmd_queue.clear()
	t.dash_until = 0.0
	if src != null and src.realm != t.realm:
		scores[src.realm] += GameData.KILL_SCORE
	_broadcast_event(Protocol.Ev.DEATH, [t.id, src.id if src != null else 0])
	_check_win()


# --- Habilidades -------------------------------------------------------------------

func _ability_attack(p: SPlayer, ab: Dictionary, target_id: int) -> bool:
	var rng: float = ab["range"]
	if target_id > 0:
		var t := _player(target_id)
		if t == null or not t.alive or t.realm == p.realm or not _visible_to(p, t):
			_notice(p, "Objetivo no válido.")
			return false
		if p.pos.distance_to(t.pos) > rng + GameData.RANGE_TOLERANCE:
			_notice(p, "Fuera de alcance.")
			return false
		if not _line_of_sight(p.pos, t.pos):
			_notice(p, "Sin línea de visión.")
			return false
		var dmg: float = ab["dmg"]
		if ab.has("backstab_mult") and _is_behind(p, t):
			dmg *= float(ab["backstab_mult"])
		_damage_player(t, dmg, p)
		return true
	if target_id < 0:
		var gi := -target_id - 1
		if not _gate_attackable(p, gi):
			_notice(p, "Ese portón no se puede atacar.")
			return false
		if p.pos.distance_to(GameData.gate_pos(gi)) > rng + GameData.GATE_REACH:
			_notice(p, "Fuera de alcance del portón.")
			return false
		_damage_gate(gi, float(ab["dmg"]) * float(ab.get("struct_mult", 1.0)), p)
		return true
	_notice(p, "Necesitas un objetivo (Tab).")
	return false


func _ability_heal(p: SPlayer, ab: Dictionary) -> bool:
	var radius: float = ab["radius"]
	var heal: int = ab["heal"]
	for o in players.values():
		if o.realm != p.realm or not o.alive or o.kicked or o.pos.distance_to(p.pos) > radius:
			continue
		var amount := mini(heal, o.max_hp - o.hp)
		if amount <= 0:
			continue
		o.hp += amount
		var ev := [o.id, amount, p.id, true]
		_send_event(o.id, Protocol.Ev.DAMAGE, ev)
		if o.id != p.id:
			_send_event(p.id, Protocol.Ev.DAMAGE, ev)
	return true


func _ability_sapper(p: SPlayer, ab: Dictionary, target_id: int) -> bool:
	var gi := -target_id - 1 if target_id < 0 else _nearest_gate(p.pos)
	if not _gate_attackable(p, gi):
		_notice(p, "No hay un portón enemigo que volar.")
		return false
	if p.pos.distance_to(GameData.gate_pos(gi)) > float(ab["range"]) + GameData.GATE_REACH:
		_notice(p, "Acércate más al portón.")
		return false
	charges.append({"gate": gi, "at": now + float(ab["delay"]), "dmg": float(ab["dmg"]), "owner": p.id})
	_notice(p, "Carga colocada en el %s: detona en %d s." % [GameData.GATE_NAMES[gi], int(ab["delay"])])
	return true


func _update_charges() -> void:
	if charges.is_empty():
		return
	var remaining := []
	for c in charges:
		if now >= float(c["at"]):
			_damage_gate(int(c["gate"]), float(c["dmg"]), _player(int(c["owner"])))
		else:
			remaining.append(c)
	charges = remaining


func _damage_gate(gi: int, amount: float, src: SPlayer) -> void:
	if gi < 0 or gi >= gates.size() or int(gates[gi]) <= 0:
		return
	if src != null and int(fortress["owner"]) == src.realm:
		return
	var dmg := maxi(1, roundi(amount))
	gates[gi] = maxi(0, int(gates[gi]) - dmg)
	if src != null:
		_send_event(src.id, Protocol.Ev.DAMAGE, [-(gi + 1), dmg, src.id, false])
	if int(gates[gi]) == 0:
		var by := (" por %s" % GameData.REALM_SHORT[src.realm]) if src != null else ""
		_broadcast_system("¡El %s ha caído%s!" % [GameData.GATE_NAMES[gi], by])


func _broadcast_fx(p: SPlayer, kind: int, target_id: int) -> void:
	var data := [p.id, kind, target_id]
	for o in players.values():
		if o.kicked or o.pos.distance_to(p.pos) > GameData.AOI_RADIUS:
			continue
		# Activar el sigilo no se anuncia a los enemigos (no revelar la posición).
		if kind == GameData.Kind.STEALTH and o.realm != p.realm:
			continue
		_send_event(o.id, Protocol.Ev.FX, data)


# --- Reglas espaciales ---------------------------------------------------------------

func _visible_to(viewer: SPlayer, target: SPlayer) -> bool:
	if viewer.realm == target.realm:
		return true
	if now < target.stealth_until and viewer.pos.distance_to(target.pos) > GameData.STEALTH_REVEAL_RADIUS:
		return false
	return true


func _in_own_sanctuary(p: SPlayer) -> bool:
	return p.pos.distance_to(GameData.base_pos(p.realm)) < GameData.BASE_RADIUS


func _is_behind(attacker: SPlayer, target: SPlayer) -> bool:
	var facing := GameData.yaw_to_dir(target.yaw)
	var to_attacker := (attacker.pos - target.pos).normalized()
	return facing.dot(to_attacker) < -0.3


## La muralla bloquea ataques a distancia salvo a través del hueco de un portón destruido.
func _line_of_sight(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var qa := d.dot(d)
	if qa < 0.0001:
		return true
	var qb := 2.0 * a.dot(d)
	var qc := a.dot(a) - GameData.WALL_RADIUS * GameData.WALL_RADIUS
	var disc := qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return true
	var sq := sqrt(disc)
	var broken := []
	for hp in gates:
		broken.append(int(hp) <= 0)
	var t1 := (-qb - sq) / (2.0 * qa)
	var t2 := (-qb + sq) / (2.0 * qa)
	if t1 > 0.0 and t1 < 1.0 and not Movement.in_open_gate(a + d * t1, broken):
		return false
	if t2 > 0.0 and t2 < 1.0 and not Movement.in_open_gate(a + d * t2, broken):
		return false
	return true


func _gate_attackable(p: SPlayer, gi: int) -> bool:
	return gi >= 0 and gi < gates.size() and int(gates[gi]) > 0 and int(fortress["owner"]) != p.realm


func _nearest_gate(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in gates.size():
		var dist := pos.distance_to(GameData.gate_pos(i))
		if dist < best_d:
			best_d = dist
			best = i
	return best


# --- Objetivos de asedio -------------------------------------------------------------

func _new_point() -> Dictionary:
	return {"owner": -1, "capturer": -1, "progress": 0.0, "contested": false}


func _reset_objectives() -> void:
	towers.clear()
	for i in GameData.TOWER_ANGLES.size():
		towers.append(_new_point())
	gates.clear()
	for i in GameData.GATE_ANGLES.size():
		gates.append(GameData.GATE_MAX_HP)
	fortress = _new_point()
	charges.clear()


func _update_objectives(dt: float) -> void:
	for i in towers.size():
		_update_point(towers[i], GameData.tower_pos(i), GameData.TOWER_CAPTURE_RADIUS, dt, "la " + str(GameData.TOWER_NAMES[i]))
	if _update_point(fortress, Vector2.ZERO, GameData.FORTRESS_CAPTURE_RADIUS, dt, "el " + GameData.FORTRESS_NAME):
		# El nuevo dueño reconstruye los portones: los demás deberán volver a derribarlos.
		for g in gates.size():
			gates[g] = GameData.GATE_MAX_HP
		charges.clear()
		_broadcast_system("Los portones del Bastión se reconstruyen.")


## Actualiza un punto de captura. Devuelve true si un reino acaba de conquistarlo.
func _update_point(pt: Dictionary, center: Vector2, radius: float, dt: float, label: String) -> bool:
	var weight := [0.0, 0.0, 0.0]
	for p in players.values():
		if p.alive and not p.kicked and p.pos.distance_to(center) <= radius:
			weight[p.realm] += 2.0 if now < p.resonance_until else 1.0
	var present := []
	for realm in GameData.REALM_COUNT:
		if weight[realm] > 0.0:
			present.append(realm)
	pt["contested"] = present.size() > 1
	if present.size() != 1:
		return false  # Vacío o disputado: el progreso se congela.
	var r: int = present[0]
	var rate := GameData.CAPTURE_RATE * minf(weight[r], GameData.MAX_CAPTURE_WEIGHT) * dt
	var cur_owner: int = pt["owner"]
	var progress: float = pt["progress"]
	if cur_owner == r:
		pt["progress"] = minf(1.0, progress + rate)
		return false
	if cur_owner >= 0:
		progress -= rate
		if progress <= 0.0:
			pt["owner"] = -1
			pt["capturer"] = r
			pt["progress"] = 0.0
			_broadcast_system("%s neutraliza %s." % [GameData.REALM_SHORT[r], label])
		else:
			pt["progress"] = progress
		return false
	if int(pt["capturer"]) != r and progress > 0.0:
		pt["progress"] = maxf(0.0, progress - rate)  # Primero deshace el avance rival.
		return false
	pt["capturer"] = r
	progress += rate
	if progress >= 1.0:
		pt["owner"] = r
		pt["capturer"] = -1
		pt["progress"] = 1.0
		_broadcast_system("¡%s conquista %s!" % [GameData.REALM_NAMES[r], label])
		return true
	pt["progress"] = progress
	return false


func _update_score(dt: float) -> void:
	_score_timer += dt
	if _score_timer < GameData.SCORE_INTERVAL:
		return
	_score_timer -= GameData.SCORE_INTERVAL
	for t in towers:
		if int(t["owner"]) >= 0:
			scores[int(t["owner"])] += GameData.TOWER_SCORE
	if int(fortress["owner"]) >= 0:
		scores[int(fortress["owner"])] += GameData.FORTRESS_SCORE
	_check_win()


func _check_win() -> void:
	for r in GameData.REALM_COUNT:
		if int(scores[r]) >= GameData.WIN_SCORE:
			_broadcast_event(Protocol.Ev.WIN, [r])
			_broadcast_system("¡%s gana la campaña! Comienza una nueva guerra." % GameData.REALM_NAMES[r])
			scores = [0, 0, 0]
			_reset_objectives()
			for p in players.values():
				_respawn(p)
			return


# --- Anti-trampas ------------------------------------------------------------------

func _update_anticheat(dt: float) -> void:
	for p in players.values():
		p.violations = maxf(0.0, p.violations - Protocol.VIOLATION_DECAY_PER_SEC * dt)
	_window_timer += dt
	if _window_timer < 5.0:
		return
	# Detección estadística de speedhack: ¿el cliente genera más comandos de los que su
	# reloj debería permitir? (El token bucket ya lo neutraliza; esto lo detecta y registra.)
	var expected := _window_timer * Protocol.TICK_RATE
	_window_timer = 0.0
	for p in players.values():
		if p.cmds_in_window > expected * 1.3:
			_violation(p, 3.0, "ritmo de comandos %d%% por encima del real (speedhack)" % int(100.0 * p.cmds_in_window / expected - 100.0))
		p.cmds_in_window = 0


func _violation(p: SPlayer, amount: float, reason: String) -> void:
	if p.kicked:
		return
	p.violations += amount
	_log("[ANTICHEAT] %s (id %d, %s): %s. Nivel %.1f/%.0f" % [p.name, p.id, p.ip, reason, p.violations, Protocol.VIOLATION_KICK_THRESHOLD])
	if p.violations >= Protocol.VIOLATION_KICK_THRESHOLD:
		_kick(p, "Expulsado: el servidor detectó un cliente modificado o paquetes anómalos.")


func _kick(p: SPlayer, reason: String) -> void:
	p.kicked = true
	_send_event(p.id, Protocol.Ev.KICK, [reason])
	_register_failure(p.ip)
	_log("[KICK] %s (id %d, %s): %s" % [p.name, p.id, p.ip, reason])
	_drop_later(p.id)


func _register_failure(ip: String) -> void:
	var now_ms := Time.get_ticks_msec()
	var log_arr: Array = _fail_log.get(ip, [])
	var recent := []
	for t in log_arr:
		if now_ms - int(t) < 60000:
			recent.append(t)
	recent.append(now_ms)
	_fail_log[ip] = recent
	if recent.size() >= 5:
		_bans[ip] = now_ms + 300000
		_fail_log.erase(ip)
		_log("[SEGURIDAD] IP %s bloqueada 5 minutos por fallos repetidos." % ip)


# =====================================================================================
#  Envío de estado
# =====================================================================================

func _send_snapshots() -> void:
	var tw := []
	for t in towers:
		tw.append([t["owner"], t["capturer"], t["progress"], t["contested"]])
	var obj := [tw, gates.duplicate(), [fortress["owner"], fortress["capturer"], fortress["progress"], fortress["contested"]]]
	for p in players.values():
		if p.kicked:
			continue
		# Área de interés + sigilo: lo que el servidor no envía, un wallhack no lo puede ver.
		var ents := []
		for o in players.values():
			if o.id == p.id or o.kicked:
				continue
			if p.pos.distance_to(o.pos) > GameData.AOI_RADIUS or not _visible_to(p, o):
				continue
			ents.append([o.id, o.pos.x, o.pos.y, o.yaw, o.hp, _flags(o)])
		var cds := []
		for c in p.cooldowns:
			cds.append(maxf(0.0, float(c) - now))
		var respawn_in := 0.0 if p.alive else maxf(0.0, p.respawn_at - now)
		var me := [p.pos.x, p.pos.y, p.yaw, p.hp, _flags(p), cds, respawn_in, maxf(0.0, p.gcd_until - now)]
		Net.s2c_snapshot.rpc_id(p.id, [tick, p.last_proc_seq, me, ents, obj, scores])


func _flags(p: SPlayer) -> int:
	var f := 0
	if now < p.stealth_until:
		f |= Protocol.F_STEALTH
	if now < p.bulwark_until:
		f |= Protocol.F_BULWARK
	if now < p.resonance_until:
		f |= Protocol.F_RESONANCE
	if not p.alive:
		f |= Protocol.F_DEAD
	if now < p.dash_until:
		f |= Protocol.F_DASH
	return f


func _roster() -> Array:
	var out := []
	for p in players.values():
		out.append([p.id, p.name, p.realm, p.cls])
	return out


func _send_event(id: int, type: int, data: Array) -> void:
	Net.s2c_event.rpc_id(id, type, data)


func _broadcast_event(type: int, data: Array, except_id: int = 0) -> void:
	for p in players.values():
		if p.id != except_id and not p.kicked:
			_send_event(p.id, type, data)


func _broadcast_system(text: String) -> void:
	_broadcast_event(Protocol.Ev.SYSTEM, [text])
	_log(text)


func _notice(p: SPlayer, text: String) -> void:
	_send_event(p.id, Protocol.Ev.NOTICE, [text])


# =====================================================================================
#  Utilidades
# =====================================================================================

func _player(id: int) -> SPlayer:
	var p: SPlayer = players.get(id)
	if p == null or p.kicked:
		return null
	return p


func _send_auth(id: int, payload: Dictionary) -> void:
	(multiplayer as SceneMultiplayer).send_auth(id, JSON.stringify(payload).to_utf8_buffer())


func _reject(id: int, ip: String, reason: String, count_failure: bool = true) -> void:
	_log("Auth rechazada (id %d, %s): %s" % [id, ip, reason])
	if count_failure:
		_register_failure(ip)
	_send_auth(id, {"t": "error", "reason": reason})
	_drop_later(id)


func _drop(id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null:
		peer.disconnect_peer(id)


## Desconecta con un pequeño retraso para que el mensaje de motivo llegue antes.
func _drop_later(id: int) -> void:
	get_tree().create_timer(0.3).timeout.connect(_drop.bind(id))


func _peer_ip(id: int) -> String:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return "?"
	var pp := peer.get_peer(id)
	return pp.get_remote_address() if pp != null else "?"


func _count_ip(ip: String) -> int:
	var n := 0
	for v in _authing.values():
		if v["ip"] == ip:
			n += 1
	for v in _authed.values():
		if v["ip"] == ip:
			n += 1
	for p in players.values():
		if p.ip == ip:
			n += 1
	return n


func _name_taken(pname: String) -> bool:
	var low := pname.to_lower()
	for p in players.values():
		if p.name.to_lower() == low:
			return true
	for v in _authed.values():
		if str(v["name"]).to_lower() == low:
			return true
	return false


func _realm_has_room(realm: int) -> bool:
	if cfg.realm_balance_margin <= 0:
		return true
	var counts := [0, 0, 0]
	for p in players.values():
		counts[p.realm] += 1
	for v in _authed.values():
		counts[int(v["realm"])] += 1
	return int(counts[realm]) - int(counts.min()) < cfg.realm_balance_margin


func _log(msg: String) -> void:
	print("[%s] %s" % [Time.get_time_string_from_system(), msg])
