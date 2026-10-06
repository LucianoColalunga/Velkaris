extends Node
## Bot de QA multijugador. Se lanzan varios procesos a la vez contra un servidor real:
##   --role=atacante  (Brasalta, Quebrantamuros): captura la Atalaya del Ocaso y pelea.
##   --role=defensor  (Umbravel, Cantor): llega tarde, disputa la atalaya, ataca y se cura.
##   --role=tramposo  (Céfira, Zapador): speedhack por ritmo de comandos y paquetes con NaN.
## Uso:
##   godot --headless --path . res://tests/qa_bot.tscn -- --port=7790 --role=atacante
## Imprime líneas "[QA:<rol>]" y termina con código 0 (OK) o 1 (FALLO).

const TOWER := 0  # Atalaya del Ocaso, entre Brasalta y Umbravel.

var role := ""
var client: GameClient
var t := 0.0
var phase := 0
var _done := false
var _log := PackedStringArray()

# Atacante / defensor
var captured_at := -1.0
var enemy_seen_dead := false
var died := false
var respawned_ok := false
var first_hit_logged := false

# Tramposo
var cheat_seq := 0
var cheat_start := Vector2.ZERO
var cheat_speed := -1.0
var nan_sent := 0


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = str(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	role = str(args.get("role", "atacante"))
	var realm := int({"atacante": 0, "defensor": 1, "tramposo": 2}.get(role, 0))
	var cls := realm
	InputSetup.ensure_actions()
	client = GameClient.new()
	add_child(client)
	Net.client = client
	client.left_game.connect(_on_left)
	client.connect_to_server({"name": "QA_" + role, "ip": "127.0.0.1", "port": int(args.get("port", "7777")),
		"password": str(args.get("password", "")), "realm": realm, "cls": cls, "shadows": false})


func _on_left(reason: String) -> void:
	if role == "tramposo":
		_say("Desconectado por el servidor: " + reason)
		var kicked := reason.contains("Expulsado")
		_finish(kicked and cheat_speed >= 0.0 and cheat_speed <= 7.5,
			"velocidad_con_speedhack=%.2f m/s expulsado=%s" % [cheat_speed, kicked])
	else:
		_finish(false, "desconectado: " + reason)


func _process(delta: float) -> void:
	if _done:
		return
	t += delta
	if t > 95.0:
		_finish(false, "timeout en fase %d" % phase)
		return
	if phase == 0:
		if client.in_world:
			_say("En el mundo en %s" % client.pred_pos)
			if role == "tramposo":
				# El tramposo ignora el cliente normal y envía sus propios paquetes.
				client.set_physics_process(false)
				cheat_seq = client.seq
				cheat_start = client.pred_pos
			phase = 1
			t = 0.0
		return
	match role:
		"atacante":
			_attacker()
		"defensor":
			_defender()


func _physics_process(_delta: float) -> void:
	if role != "tramposo" or _done or not client.in_world:
		return
	# Prueba A (0-1.5 s): speedhack por ritmo, 2 comandos por tick con dirección válida.
	if phase == 1:
		if t < 1.5:
			for i in 2:
				cheat_seq += 1
				Net.c2s_input.rpc_id(1, [[cheat_seq, Vector2(0, 1), 0.0]])
		elif t > 2.2 and cheat_speed < 0.0:
			# Tras recibir snapshots, pred_pos = posición autoritativa del servidor.
			cheat_speed = client.pred_pos.distance_to(cheat_start) / 1.5
			_say("Speedhack x2 durante 1.5 s: el servidor me movió %.2f m (%.2f m/s; legal = 6)" % [
				client.pred_pos.distance_to(cheat_start), cheat_speed])
		elif t > 5.0:
			phase = 2
	# Prueba B: paquetes con yaw = NaN (deberían acabar en expulsión).
	elif phase == 2 and nan_sent < 8 and Engine.get_physics_frames() % 10 == 0:
		cheat_seq += 1
		nan_sent += 1
		Net.c2s_input.rpc_id(1, [[cheat_seq, Vector2.ZERO, NAN]])


func _attacker() -> void:
	var stop := GameData.tower_pos(TOWER) + Vector2(0, -5)
	match phase:
		1:
			if _walk_to(stop, 0.6) or t > 18.0:
				_release()
				_say("Llegué a la atalaya (%.1f s)" % t)
				phase = 2
				t = 0.0
		2:
			var tw: Array = client.towers[TOWER]
			if captured_at < 0.0 and int(tw[0]) == 0:
				captured_at = t
				_say("Atalaya capturada por Brasalta en %.1f s (esperado ~12.5 s)" % t)
			if captured_at >= 0.0 and _enemy() != 0:
				_say("Llega un enemigo; combate. Puntos: %s" % str(client.scores))
				phase = 3
				t = 0.0
			elif t > 45.0:
				_finish(false, "nunca apareció el defensor")
		3:
			var e := _enemy()
			if e != 0:
				var ep: Vector2 = client._remote_pos(e)
				if ep.distance_to(client.pred_pos) > 2.5:
					_walk_to(ep, 2.5)
				else:
					_release()
					client.target_id = e
					client.use_ability(0)
					if client.my_hp < client.my_max_hp * 0.6:
						client.use_ability(1)  # Baluarte
				var ehp := int(client.remotes[e]["hp"])
				if not first_hit_logged and ehp < 900:
					first_hit_logged = true
					_say("Primer golpe confirmado por el servidor: vida enemiga %d/900" % ehp)
			for id in client.remotes:
				if (int(client.remotes[id]["flags"]) & Protocol.F_DEAD) != 0 and not enemy_seen_dead:
					enemy_seen_dead = true
					_say("Enemigo abatido en %.1f s. Mi vida: %d/%d" % [t, client.my_hp, client.my_max_hp])
			if enemy_seen_dead and t > 0.0 and phase == 3:
				phase = 4
				t = 0.0
			elif t > 40.0:
				_finish(false, "no logré abatir al enemigo")
		4:
			_release()
			if t > 12.0:
				var tw: Array = client.towers[TOWER]
				_finish(captured_at >= 0.0 and enemy_seen_dead,
					"captura=%s abatido=%s dueño_atalaya=%d puntos=%s" % [
						captured_at >= 0.0, enemy_seen_dead, int(tw[0]), str(client.scores)])


func _defender() -> void:
	var stop := GameData.tower_pos(TOWER) + Vector2(-4, -3)
	match phase:
		1:
			if t > 20.0:
				phase = 2
				t = 0.0
		2:
			if _walk_to(stop, 0.6) or t > 20.0:
				_release()
				var tw: Array = client.towers[TOWER]
				_say("Llegué a la atalaya. Estado: dueño=%d disputada=%s" % [int(tw[0]), str(tw[3])])
				phase = 3
				t = 0.0
		3:
			if client.my_alive:
				client.use_ability(0)  # Rayo (autoobjetivo)
				if client.my_hp < client.my_max_hp * 0.5:
					client.use_ability(1)  # Pulso restaurador
				var tw: Array = client.towers[TOWER]
				if t > 1.0 and not first_hit_logged:
					first_hit_logged = true
					_say("Con los dos reinos dentro: disputada=%s" % str(tw[3]))
			elif not died:
				died = true
				_say("He caído (%.1f s de combate). Reaparición en %.1f s" % [t, client.respawn_in])
				phase = 4
				t = 0.0
			if t > 45.0:
				_finish(false, "nunca morí (¿el atacante no pega?)")
		4:
			if client.my_alive and not respawned_ok:
				var base := GameData.base_pos(1)
				respawned_ok = client.pred_pos.distance_to(base) < GameData.BASE_RADIUS and client.my_hp == client.my_max_hp
				_say("Reaparecí a los %.1f s en %s (santuario: %s, vida llena: %s)" % [
					t, client.pred_pos, client.pred_pos.distance_to(base) < GameData.BASE_RADIUS, client.my_hp == client.my_max_hp])
				_finish(respawned_ok and t > 5.0 and t < 8.0, "muerte+reaparición correctas=%s" % respawned_ok)
			elif t > 15.0:
				_finish(false, "no reaparecí")


func _enemy() -> int:
	var best := 0
	var best_d := INF
	for id in client.remotes:
		if client.realm_of(id) == client.my_realm:
			continue
		if (int(client.remotes[id]["flags"]) & Protocol.F_DEAD) != 0:
			continue
		var d := client._remote_pos(id).distance_to(client.pred_pos)
		if d < 30.0 and d < best_d:
			best_d = d
			best = id
	return best


func _walk_to(p: Vector2, tolerance: float) -> bool:
	var to := p - client.pred_pos
	if to.length() <= tolerance:
		_release()
		return true
	client.camera_rig.yaw = GameData.dir_to_yaw(to.normalized())
	Input.action_press("move_forward")
	return false


func _release() -> void:
	Input.action_release("move_forward")


func _say(msg: String) -> void:
	print("[QA:%s] %s" % [role, msg])


func _finish(ok: bool, msg: String) -> void:
	if _done:
		return
	_done = true
	_release()
	_say("RESULTADO: %s (%s)" % ["OK" if ok else "FALLO", msg])
	get_tree().quit(0 if ok else 1)
