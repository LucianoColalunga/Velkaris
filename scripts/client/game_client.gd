class_name GameClient
extends Node3D
## Cliente de juego.
##  * Envía INTENCIONES al servidor (dirección de movimiento a 30 Hz, uso de habilidades).
##  * Predice su propio movimiento con el mismo código que el servidor (Movement.step) y se
##    reconcilia con cada snapshot: si el servidor dice otra cosa, gana el servidor.
##  * Muestra a los demás jugadores interpolados ~120 ms en el pasado (movimiento suave).

signal entered_world
signal left_game(reason: String)

const INTERP_DELAY := 0.12
const TARGET_RANGE := 45.0

var params: Dictionary = {}
var my_id := 0
var my_realm := 0
var my_cls := 0
var my_name := ""
var server_name := ""
var in_world := false

var roster: Dictionary = {}     ## id -> {"name", "realm", "cls"}
var remotes: Dictionary = {}    ## id -> {"node": PlayerAvatar, "buf": Array, "hp": int, "flags": int}

# Estado propio (predicho + confirmado por el servidor)
var seq := 0
var pending: Array = []         ## Comandos aún no confirmados: [seq, move, yaw]
var pred_pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var render_offset := Vector2.ZERO
var my_yaw := 0.0
var my_hp := 1
var my_max_hp := 1
var my_flags := 0
var my_alive := true
var respawn_in := 0.0
var cooldowns: Array = [0.0, 0.0, 0.0]
var gcd_left := 0.0
var target_id := 0

# Estado del mundo (sólo lectura: llega en los snapshots)
var towers: Array = []
var gate_hp: Array = []
var fortress: Array = [-1, -1, 0.0, false]
var scores: Array = [0, 0, 0]
var last_snapshot_tick := -1

var world: WorldView
var hud: Hud
var camera_rig: CameraRig
var me_avatar: PlayerAvatar

var _left := false
var _kick_reason := ""


func _init() -> void:
	for i in GameData.TOWER_ANGLES.size():
		towers.append([-1, -1, 0.0, false])
	for i in GameData.GATE_ANGLES.size():
		gate_hp.append(GameData.GATE_MAX_HP)


# =====================================================================================
#  Conexión
# =====================================================================================

func connect_to_server(p: Dictionary) -> Error:
	params = p
	my_name = p["name"]
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(str(p["ip"]), int(p["port"]))
	if err != OK:
		return err
	var smp := multiplayer as SceneMultiplayer
	smp.auth_callback = _on_auth_data
	smp.auth_timeout = 10.0
	multiplayer.multiplayer_peer = peer
	return OK


## Respuestas del servidor en el canal de autenticación.
func _on_auth_data(id: int, data: PackedByteArray) -> void:
	if id != 1:
		return
	var msg: Variant = Protocol.parse_json_bytes(data, 1024)
	if typeof(msg) != TYPE_DICTIONARY:
		_leave("Respuesta del servidor ilegible.")
		return
	var d: Dictionary = msg
	var smp := multiplayer as SceneMultiplayer
	match str(d.get("t", "")):
		"challenge":
			if not Protocol.is_int_value(d.get("v"), Protocol.VERSION, Protocol.VERSION):
				_leave("Versión incompatible con el servidor. Descarga la misma versión que el anfitrión.")
				return
			server_name = str(d.get("name", ""))
			var hello := {"v": Protocol.VERSION, "name": params["name"], "realm": params["realm"], "cls": params["cls"]}
			if d.get("pw", false):
				hello["proof"] = Protocol.password_proof(str(d.get("nonce", "")), str(params.get("password", "")))
			smp.send_auth(1, JSON.stringify(hello).to_utf8_buffer())
		"ok":
			smp.complete_auth(1)
		"error":
			_leave(str(d.get("reason", "Conexión rechazada por el servidor.")))
		_:
			_leave("Respuesta del servidor desconocida.")


func on_connected_to_server() -> void:
	Net.c2s_ready.rpc_id(1)


func on_connection_failed() -> void:
	_leave("No se pudo conectar con %s:%d.\n¿IP y puerto correctos? ¿El servidor está encendido? ¿Firewall / reenvío de puertos?" % [params.get("ip", "?"), int(params.get("port", 0))])


func on_server_disconnected() -> void:
	_leave(_kick_reason if _kick_reason != "" else "Se perdió la conexión con el servidor.")


func disconnect_from_server() -> void:
	_leave("Has salido de la partida.")


func _leave(reason: String) -> void:
	if _left:
		return
	_left = true
	in_world = false
	left_game.emit(reason)


# =====================================================================================
#  Mensajes del servidor
# =====================================================================================

func on_welcome(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY or in_world:
		return
	var d: Dictionary = data
	my_id = int(d.get("id", 0))
	my_realm = clampi(int(d.get("realm", 0)), 0, GameData.REALM_COUNT - 1)
	my_cls = clampi(int(d.get("cls", 0)), 0, GameData.CLASS_COUNT - 1)
	my_max_hp = GameData.CLASS_MAX_HP[my_cls]
	my_hp = my_max_hp
	server_name = str(d.get("server", server_name))
	var r: Variant = d.get("roster", [])
	if typeof(r) == TYPE_ARRAY:
		_apply_roster(r)
	_build_world()
	in_world = true
	hud.add_system("Bienvenido a %s. Defiende a %s." % [server_name, GameData.REALM_NAMES[my_realm]])
	hud.add_system("WASD mover · clic derecho girar cámara · 1-3 habilidades · Tab objetivo · Enter chat · F1 ayuda")
	entered_world.emit()


func on_snapshot(snap: Variant) -> void:
	if not in_world or typeof(snap) != TYPE_ARRAY or snap.size() != 6:
		return
	var stick: int = snap[0]
	if stick <= last_snapshot_tick:
		return
	last_snapshot_tick = stick
	var ack: int = snap[1]
	var me: Array = snap[2]
	var obj: Array = snap[4]
	towers = obj[0]
	gate_hp = obj[1]
	fortress = obj[2]
	scores = snap[5]
	world.update_objectives(towers, gate_hp, fortress)

	var was_alive := my_alive
	my_hp = me[3]
	my_flags = me[4]
	my_alive = (my_flags & Protocol.F_DEAD) == 0
	var cds: Array = me[5]
	for i in 3:
		cooldowns[i] = float(cds[i])
	respawn_in = me[6]
	gcd_left = me[7]
	me_avatar.set_status(my_hp, my_flags)

	# --- Reconciliación: posición del servidor + re-simular lo que aún no confirmó ---
	var server_pos := Vector2(me[0], me[1])
	while not pending.is_empty() and int(pending[0][0]) <= ack:
		pending.pop_front()
	if not my_alive:
		pending.clear()
		pred_pos = server_pos
		prev_pos = server_pos
		render_offset = Vector2.ZERO
	else:
		var p := server_pos
		var gopen := _gates_open()
		for c in pending:
			p = Movement.step(p, c[1], Protocol.TICK_DT, 1.0, gopen)
		var err := p - pred_pos
		if not was_alive or err.length() > 4.0:
			# Reaparición o corrección grande: salto directo.
			render_offset = Vector2.ZERO
			prev_pos = p
			my_yaw = float(me[2])
		elif err.length_squared() > 0.0001:
			# Corrección pequeña: se absorbe visualmente para que no se note el tirón.
			render_offset -= err
			prev_pos += err
		pred_pos = p

	# --- Entidades remotas ---
	var ents: Array = snap[3]
	var t := Time.get_ticks_msec() / 1000.0
	var seen := {}
	for e in ents:
		if typeof(e) != TYPE_ARRAY or e.size() != 6:
			continue
		var id: int = e[0]
		if not roster.has(id):
			continue
		seen[id] = true
		if not remotes.has(id):
			_spawn_remote(id)
		var rem: Dictionary = remotes[id]
		var buf: Array = rem["buf"]
		buf.append([t, Vector2(e[1], e[2]), float(e[3])])
		if buf.size() > 20:
			buf.pop_front()
		rem["hp"] = int(e[4])
		rem["flags"] = int(e[5])
		(rem["node"] as PlayerAvatar).set_status(rem["hp"], rem["flags"])
	for id in remotes.keys():
		if not seen.has(id):
			_despawn_remote(id)
	if target_id > 0 and not remotes.has(target_id):
		target_id = 0


func on_event(type: Variant, data: Variant) -> void:
	if typeof(type) != TYPE_INT or typeof(data) != TYPE_ARRAY:
		return
	var d: Array = data
	if d.is_empty():
		return
	if type == Protocol.Ev.KICK:
		_kick_reason = str(d[0])
		return
	if hud == null:
		return
	if type == Protocol.Ev.ROSTER:
		_apply_roster(d)
	elif type == Protocol.Ev.LEAVE:
		var id := int(d[0])
		_despawn_remote(id)
		roster.erase(id)
	elif type == Protocol.Ev.CHAT and d.size() == 2:
		var id := int(d[0])
		hud.add_chat(name_of(id), realm_of(id), str(d[1]))
	elif type == Protocol.Ev.SYSTEM:
		hud.add_system(str(d[0]))
	elif type == Protocol.Ev.NOTICE:
		hud.notice(str(d[0]))
	elif type == Protocol.Ev.DAMAGE and d.size() == 4:
		_on_damage(int(d[0]), int(d[1]), int(d[2]), bool(d[3]))
	elif type == Protocol.Ev.DEATH and d.size() == 2:
		var victim := int(d[0])
		var killer := int(d[1])
		if killer > 0:
			hud.add_kill(name_of(killer), realm_of(killer), name_of(victim), realm_of(victim))
		if victim == target_id:
			target_id = 0
	elif type == Protocol.Ev.FX and d.size() == 3:
		_on_fx(int(d[0]), int(d[1]), int(d[2]))
	elif type == Protocol.Ev.WIN:
		var r := clampi(int(d[0]), 0, GameData.REALM_COUNT - 1)
		hud.show_banner("¡%s gana la campaña!" % GameData.REALM_NAMES[r], GameData.REALM_COLORS[r])


# =====================================================================================
#  Bucle de juego
# =====================================================================================

func _physics_process(_delta: float) -> void:
	if not in_world:
		return
	var dt := Protocol.TICK_DT
	gcd_left = maxf(0.0, gcd_left - dt)
	for i in 3:
		cooldowns[i] = maxf(0.0, float(cooldowns[i]) - dt)
	respawn_in = maxf(0.0, respawn_in - dt)
	if not my_alive:
		return
	var move := Vector2.ZERO
	if not hud.is_typing():
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var cam_yaw := camera_rig.yaw
		var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
		move = right * input.x + GameData.yaw_to_dir(cam_yaw) * (-input.y)
		if move.length_squared() > 1.0:
			move = move.normalized()
	if move.length_squared() > 0.01:
		my_yaw = GameData.dir_to_yaw(move)
	seq += 1
	pending.append([seq, move, my_yaw])
	if pending.size() > 90:
		pending.pop_front()
	# Redundancia: cada paquete lleva los últimos 3 comandos (tolera pérdida de paquetes).
	Net.c2s_input.rpc_id(1, pending.slice(maxi(0, pending.size() - 3)))
	prev_pos = pred_pos
	pred_pos = Movement.step(pred_pos, move, dt, 1.0, _gates_open())


func _process(delta: float) -> void:
	if not in_world:
		return
	if not hud.is_typing():
		var turn := Input.get_axis("turn_right", "turn_left")
		if turn != 0.0:
			camera_rig.yaw += turn * 2.2 * delta
	render_offset = render_offset.lerp(Vector2.ZERO, clampf(delta * 10.0, 0.0, 1.0))
	var frac := Engine.get_physics_interpolation_fraction()
	var p2 := prev_pos.lerp(pred_pos, frac) + render_offset
	me_avatar.position = Vector3(p2.x, 0.0, p2.y)
	me_avatar.rotation.y = lerp_angle(me_avatar.rotation.y, my_yaw, clampf(delta * 15.0, 0.0, 1.0))
	camera_rig.follow(me_avatar.position)
	_update_remotes()
	world.set_target_marker(target_world_pos(), target_id != 0)
	hud.refresh(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not in_world or hud.is_typing():
		return
	if event.is_action_pressed("ability_1"):
		use_ability(0)
	elif event.is_action_pressed("ability_2"):
		use_ability(1)
	elif event.is_action_pressed("ability_3"):
		use_ability(2)
	elif event.is_action_pressed("target_next"):
		_cycle_target()
	elif event.is_action_pressed("chat"):
		hud.focus_chat()
	elif event.is_action_pressed("help"):
		hud.toggle_help()
	elif event.is_action_pressed("ui_cancel"):
		if target_id != 0:
			target_id = 0
		else:
			hud.toggle_pause_menu()
	else:
		return
	get_viewport().set_input_as_handled()


# =====================================================================================
#  Acciones del jugador
# =====================================================================================

func use_ability(slot: int) -> void:
	if not my_alive:
		return
	if float(cooldowns[slot]) > 0.05 or gcd_left > 0.05:
		hud.notice("En enfriamiento.")
		return
	var ab: Dictionary = GameData.ABILITIES[my_cls][slot]
	var kind: int = ab["kind"]
	var tid := target_id
	if kind == GameData.Kind.MELEE or kind == GameData.Kind.RANGED or kind == GameData.Kind.SAPPER:
		if tid == 0 or not _target_valid(tid):
			tid = _auto_target(float(ab.get("range", 4.0)))
			target_id = tid
		if tid == 0 and kind != GameData.Kind.SAPPER:
			hud.notice("Sin objetivo a tu alcance (Tab para elegir).")
			return
		if tid != 0:
			var tp := target_world_pos()
			var to_target := Vector2(tp.x, tp.z) - pred_pos
			if to_target.length_squared() > 0.01:
				my_yaw = GameData.dir_to_yaw(to_target)
	# El cliente sólo PIDE. Enfriamiento, alcance, daño y visibilidad los decide el servidor.
	Net.c2s_ability.rpc_id(1, slot, tid, my_yaw)
	gcd_left = GameData.GCD


func send_chat(text: String) -> void:
	var clean := Protocol.sanitize_chat(text)
	if clean != "":
		Net.c2s_chat.rpc_id(1, clean)


func _cycle_target() -> void:
	var cands := []
	for id in remotes:
		if _target_valid(id) and _remote_pos(id).distance_to(pred_pos) <= TARGET_RANGE:
			cands.append([_remote_pos(id).distance_to(pred_pos), id])
	for gi in gate_hp.size():
		var gid := -(gi + 1)
		if _target_valid(gid) and GameData.gate_pos(gi).distance_to(pred_pos) <= TARGET_RANGE:
			cands.append([GameData.gate_pos(gi).distance_to(pred_pos) + 1000.0, gid])  # Portones al final.
	if cands.is_empty():
		target_id = 0
		hud.notice("No hay enemigos cerca.")
		return
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var idx := 0
	for i in cands.size():
		if cands[i][1] == target_id:
			idx = (i + 1) % cands.size()
			break
	target_id = cands[idx][1]


func _auto_target(rng: float) -> int:
	var best := 0
	var best_d := INF
	for id in remotes:
		if not _target_valid(id):
			continue
		var dist := _remote_pos(id).distance_to(pred_pos)
		if dist <= rng + 1.0 and dist < best_d:
			best_d = dist
			best = id
	if best != 0:
		return best
	for gi in gate_hp.size():
		var gid := -(gi + 1)
		var dist := GameData.gate_pos(gi).distance_to(pred_pos)
		if _target_valid(gid) and dist <= rng + GameData.GATE_REACH and dist < best_d:
			best_d = dist
			best = gid
	return best


func _target_valid(tid: int) -> bool:
	if tid > 0:
		return remotes.has(tid) and realm_of(tid) != my_realm \
			and (int(remotes[tid]["flags"]) & Protocol.F_DEAD) == 0
	if tid < 0:
		var gi := -tid - 1
		return gi < gate_hp.size() and int(gate_hp[gi]) > 0 and int(fortress[0]) != my_realm
	return false


func target_world_pos() -> Vector3:
	if target_id > 0 and remotes.has(target_id):
		return (remotes[target_id]["node"] as Node3D).position
	if target_id < 0:
		var g := GameData.gate_pos(-target_id - 1)
		return Vector3(g.x, 0.0, g.y)
	return Vector3.ZERO


func target_info() -> Dictionary:
	if target_id > 0 and remotes.has(target_id):
		var cls := int(roster[target_id]["cls"])
		return {"name": name_of(target_id), "realm": realm_of(target_id), "hp": remotes[target_id]["hp"],
			"max": GameData.CLASS_MAX_HP[cls], "sub": GameData.CLASS_NAMES[cls]}
	if target_id < 0:
		var gi := -target_id - 1
		return {"name": GameData.GATE_NAMES[gi], "realm": -1, "hp": int(gate_hp[gi]), "max": GameData.GATE_MAX_HP,
			"sub": GameData.FORTRESS_NAME}
	return {}


# =====================================================================================
#  Internos
# =====================================================================================

func _build_world() -> void:
	world = WorldView.new()
	add_child(world)
	world.build(bool(params.get("shadows", false)))
	me_avatar = PlayerAvatar.new()
	add_child(me_avatar)
	me_avatar.setup(my_name, my_realm, my_cls, true)
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.setup(self)
	hud.disconnect_requested.connect(disconnect_from_server)


func _apply_roster(list: Array) -> void:
	for entry in list:
		if typeof(entry) != TYPE_ARRAY or entry.size() != 4:
			continue
		var id := int(entry[0])
		roster[id] = {"name": str(entry[1]), "realm": clampi(int(entry[2]), 0, GameData.REALM_COUNT - 1),
			"cls": clampi(int(entry[3]), 0, GameData.CLASS_COUNT - 1)}


func _spawn_remote(id: int) -> void:
	var av := PlayerAvatar.new()
	add_child(av)
	av.setup(name_of(id), realm_of(id), int(roster[id]["cls"]), false)
	remotes[id] = {"node": av, "buf": [], "hp": 1, "flags": 0}


func _despawn_remote(id: int) -> void:
	if remotes.has(id):
		(remotes[id]["node"] as Node).queue_free()
		remotes.erase(id)


func _update_remotes() -> void:
	var render_t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	for id in remotes:
		var rem: Dictionary = remotes[id]
		var buf: Array = rem["buf"]
		if buf.is_empty():
			continue
		var last: Array = buf[buf.size() - 1]
		var pos: Vector2 = last[1]
		var yaw: float = last[2]
		var first: Array = buf[0]
		if render_t <= float(first[0]):
			pos = first[1]
			yaw = first[2]
		else:
			for i in buf.size() - 1:
				var s0: Array = buf[i]
				var s1: Array = buf[i + 1]
				var t0: float = s0[0]
				var t1: float = s1[0]
				if render_t >= t0 and render_t <= t1:
					var w := (render_t - t0) / (t1 - t0) if t1 > t0 else 1.0
					var p0: Vector2 = s0[1]
					var p1: Vector2 = s1[1]
					pos = p0.lerp(p1, w)
					yaw = lerp_angle(float(s0[2]), float(s1[2]), w)
					break
		var node: Node3D = rem["node"]
		node.position = Vector3(pos.x, 0.0, pos.y)
		node.rotation.y = yaw


func _remote_pos(id: int) -> Vector2:
	var n: Node3D = remotes[id]["node"]
	return Vector2(n.position.x, n.position.z)


func _gates_open() -> Array:
	return GameData.gates_open_for(my_realm, gate_hp, int(fortress[0]))


func _on_damage(target: int, amount: int, source: int, is_heal: bool) -> void:
	var at := Vector3.ZERO
	if target == my_id:
		at = me_avatar.position
	elif target > 0 and remotes.has(target):
		at = (remotes[target]["node"] as Node3D).position
	elif target < 0:
		var g := GameData.gate_pos(-target - 1)
		at = Vector3(g.x, 3.0, g.y)
	else:
		return
	var color := Color(0.4, 1.0, 0.45) if is_heal else (Color(1.0, 0.3, 0.25) if target == my_id else Color(1.0, 0.85, 0.3))
	world.spawn_floating_text(at + Vector3(0, 2.8, 0), ("+%d" if is_heal else "%d") % amount, color)
	if source == my_id and target != my_id and not is_heal:
		hud.flash_hit()


func _on_fx(caster: int, kind: int, tid: int) -> void:
	var from := Vector3.ZERO
	if caster == my_id:
		from = me_avatar.position
	elif remotes.has(caster):
		from = (remotes[caster]["node"] as Node3D).position
	else:
		return
	var color: Color = GameData.REALM_COLORS[realm_of(caster)]
	var to := from
	if tid > 0 and (tid == my_id or remotes.has(tid)):
		to = me_avatar.position if tid == my_id else (remotes[tid]["node"] as Node3D).position
	elif tid < 0 and -tid - 1 < gate_hp.size():
		var g := GameData.gate_pos(-tid - 1)
		to = Vector3(g.x, 0.0, g.y)
	if kind == GameData.Kind.RANGED:
		world.spawn_beam(from + Vector3(0, 1.4, 0), to + Vector3(0, 1.2, 0), color)
	elif kind == GameData.Kind.MELEE:
		world.spawn_burst(to + Vector3(0, 1.0, 0), color, 1.2)
	elif kind == GameData.Kind.AOE_HEAL:
		world.spawn_burst(from + Vector3(0, 0.3, 0), Color(0.4, 1.0, 0.5), 9.0)
	elif kind == GameData.Kind.SAPPER:
		world.spawn_burst(to + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.1), 3.0)
	else:
		world.spawn_burst(from + Vector3(0, 1.0, 0), color, 2.0)


func name_of(id: int) -> String:
	return str(roster[id]["name"]) if roster.has(id) else "?"


func realm_of(id: int) -> int:
	if id == my_id:
		return my_realm
	return int(roster[id]["realm"]) if roster.has(id) else 0
