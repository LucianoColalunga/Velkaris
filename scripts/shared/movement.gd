class_name Movement
extends RefCounted
## Paso de movimiento determinista sobre el plano XZ.
## El SERVIDOR lo ejecuta como autoridad; el CLIENTE ejecuta el mismo código para predecir
## su propio movimiento. Mismo código en ambos lados = predicción precisa, sin tirones.
## No usa el motor de físicas: el servidor headless no necesita nodos ni colisionadores.

const SPEED := 6.0  ## m/s


static func step(pos: Vector2, move: Vector2, dt: float, speed_mult: float, gates_open: Array) -> Vector2:
	var dir := move
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	return resolve(pos + dir * (SPEED * speed_mult * dt), gates_open)


## Empuja la posición fuera de los obstáculos estáticos del mapa.
static func resolve(p: Vector2, gates_open: Array) -> Vector2:
	var r := GameData.PLAYER_RADIUS
	# 1) Límite del mapa (círculo).
	var limit := GameData.MAP_RADIUS - r
	if p.length() > limit:
		p = p.normalized() * limit
	# 2) Muralla del Bastión: un anillo con huecos en los portones abiertos.
	var d := p.length()
	var inner := GameData.WALL_RADIUS - GameData.WALL_HALF_THICKNESS - r
	var outer := GameData.WALL_RADIUS + GameData.WALL_HALF_THICKNESS + r
	if d > inner and d < outer and not in_open_gate(p, gates_open):
		var n := p / d
		p = n * (inner if (d - inner) < (outer - d) else outer)
	# 3) Pilares de las atalayas.
	var min_d := GameData.TOWER_PILLAR_RADIUS + r
	for i in GameData.TOWER_ANGLES.size():
		var c := GameData.tower_pos(i)
		var diff := p - c
		var dl := diff.length()
		if dl < min_d:
			p = c + (diff / dl if dl > 0.0001 else Vector2.RIGHT) * min_d
	return p


## true si el punto está dentro del hueco de algún portón abierto.
static func in_open_gate(p: Vector2, gates_open: Array) -> bool:
	var a := atan2(p.y, p.x)
	var margin := GameData.PLAYER_RADIUS / GameData.WALL_RADIUS
	for i in gates_open.size():
		if not gates_open[i]:
			continue
		var gate_angle: float = GameData.GATE_ANGLES[i]
		if absf(wrapf(a - gate_angle, -PI, PI)) < GameData.GATE_HALF_ANGLE - margin:
			return true
	return false
