class_name GameData
extends RefCounted
## Datos de diseño compartidos: reinos, clases, habilidades y mapa.
## Cliente y servidor leen EXACTAMENTE la misma tabla. El cliente la usa para mostrar y
## predecir; el servidor, para decidir. Cambiar un valor aquí cambia ambos lados.

enum Kind { MELEE, RANGED, SELF_BUFF, AOE_HEAL, DASH, STEALTH, SAPPER, RESONANCE }

# --- Reinos ---------------------------------------------------------------------
const REALM_COUNT := 3
const REALM_NAMES := ["Hegemonía de Brasalta", "Concilio de Umbravel", "Clanes de Céfira"]
const REALM_SHORT := ["Brasalta", "Umbravel", "Céfira"]
const REALM_COLORS := [Color(0.95, 0.42, 0.16), Color(0.30, 0.80, 0.62), Color(0.55, 0.72, 1.0)]
const REALM_BLURB := [
	"Forjadores del desierto volcánico. Templan obsidiana con el Ascua Primordial y construyen murallas de vidrio negro.",
	"Alquimistas de los manglares de bruma. La Raíz Abisal les da hongos que curan, envenenan y ocultan.",
	"Nómadas de las islas flotantes. Encadenan tormentas dentro de esquirlas lunares y cantan para dirigirlas.",
]

# --- Clases ---------------------------------------------------------------------
const CLASS_COUNT := 3
const CLASS_NAMES := ["Quebrantamuros", "Cantor de Esquirlas", "Zapador de Bruma"]
const CLASS_ROLES := ["Tanque de asedio", "Soporte / daño a distancia", "Infiltrador / saboteador"]
const CLASS_MAX_HP := [1400, 900, 1000]
const CLASS_BLURB := [
	"Primera línea. Su martillo resonante parte portones y su Baluarte aguanta la respuesta.",
	"Canaliza esquirlas lunares: daña a distancia, cura al grupo y acelera las capturas.",
	"Se mueve oculto en la bruma, apuñala por la espalda y vuela portones con cargas de zapa.",
]

const GCD := 0.8               ## Enfriamiento global entre habilidades (s).
const RANGE_TOLERANCE := 1.0   ## Margen de alcance que concede el servidor por latencia (m).

## 3 habilidades por clase (teclas 1, 2, 3). "struct_mult" multiplica el daño a portones.
const ABILITIES := [
	[
		{"name": "Golpe Sísmico", "kind": Kind.MELEE, "cd": 1.2, "range": 3.5, "dmg": 110, "struct_mult": 4.0,
			"desc": "Golpe cuerpo a cuerpo. Hace x4 de daño a los portones."},
		{"name": "Baluarte", "kind": Kind.SELF_BUFF, "cd": 16.0, "duration": 4.0,
			"desc": "Reduce a la mitad el daño recibido durante 4 s."},
		{"name": "Embestida", "kind": Kind.DASH, "cd": 10.0, "duration": 0.3, "speed": 30.0,
			"desc": "Carga 9 m en la dirección en la que miras."},
	],
	[
		{"name": "Rayo de Esquirla", "kind": Kind.RANGED, "cd": 1.5, "range": 28.0, "dmg": 95, "struct_mult": 0.5,
			"desc": "Proyectil de luz lunar a 28 m. Requiere línea de visión."},
		{"name": "Pulso Restaurador", "kind": Kind.AOE_HEAL, "cd": 8.0, "radius": 9.0, "heal": 220,
			"desc": "Cura 220 puntos a ti y a los aliados en 9 m."},
		{"name": "Sello de Resonancia", "kind": Kind.RESONANCE, "cd": 20.0, "duration": 8.0,
			"desc": "Durante 8 s cuentas doble al capturar atalayas y el Bastión."},
	],
	[
		{"name": "Cuchilla Doble", "kind": Kind.MELEE, "cd": 1.0, "range": 3.0, "dmg": 90, "struct_mult": 1.0, "backstab_mult": 2.0,
			"desc": "Ataque rápido. Daño x2 si golpeas por la espalda."},
		{"name": "Velo de Bruma", "kind": Kind.STEALTH, "cd": 18.0, "duration": 7.0,
			"desc": "7 s invisible para el enemigo (salvo a 4 m). Atacar lo rompe."},
		{"name": "Carga de Zapa", "kind": Kind.SAPPER, "cd": 14.0, "range": 4.0, "delay": 3.0, "dmg": 700,
			"desc": "Coloca un explosivo en un portón: 700 de daño tras 3 s."},
	],
]

# --- Mapa: la Frontera Rota -------------------------------------------------------
# Plano XZ en metros, centro (0, 0). Las posiciones 2D son Vector2(x, z).
const MAP_RADIUS := 100.0
const PLAYER_RADIUS := 0.5

const BASE_RING := 85.0
const BASE_RADIUS := 12.0            ## Santuario: invulnerable para los propios, letal para intrusos.
const BASE_ANGLES := [-PI / 2.0, PI * 5.0 / 6.0, PI / 6.0]
const BASE_GUARD_DPS := 60.0

const TOWER_RING := 55.0
const TOWER_ANGLES := [-PI * 5.0 / 6.0, -PI / 6.0, PI / 2.0]
const TOWER_NAMES := ["Atalaya del Ocaso", "Atalaya del Alba", "Atalaya del Abismo"]
const TOWER_PILLAR_RADIUS := 1.6
const TOWER_CAPTURE_RADIUS := 9.0

const FORTRESS_NAME := "Bastión de Ilun"
const FORTRESS_CAPTURE_RADIUS := 6.0
const WALL_RADIUS := 18.0
const WALL_HALF_THICKNESS := 1.0
const WALL_HEIGHT := 6.0
const GATE_ANGLES := BASE_ANGLES     ## Cada portón mira hacia un santuario.
const GATE_HALF_ANGLE := 0.17        ## ≈ 6 m de hueco.
const GATE_REACH := 3.5              ## Distancia extra para golpear un portón desde fuera.
const GATE_MAX_HP := 4000
const GATE_NAMES := ["Portón Norte", "Portón Suroeste", "Portón Sureste"]

# --- Reglas de la campaña -----------------------------------------------------------
const CAPTURE_RATE := 0.08           ## Progreso de captura por segundo y por jugador.
const MAX_CAPTURE_WEIGHT := 4.0
const SCORE_INTERVAL := 5.0
const TOWER_SCORE := 1
const FORTRESS_SCORE := 3
const KILL_SCORE := 2
const WIN_SCORE := 300
const RESPAWN_TIME := 6.0
const AOI_RADIUS := 75.0             ## Área de interés: más lejos no se envía (ahorra red y evita ESP).
const STEALTH_REVEAL_RADIUS := 4.0


static func ring_point(angle: float, radius: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * radius


static func base_pos(realm: int) -> Vector2:
	return ring_point(BASE_ANGLES[realm], BASE_RING)


static func tower_pos(i: int) -> Vector2:
	return ring_point(TOWER_ANGLES[i], TOWER_RING)


static func gate_pos(i: int) -> Vector2:
	return ring_point(GATE_ANGLES[i], WALL_RADIUS)


## Punto de aparición dentro del santuario, repartido para que no se solapen.
static func spawn_pos(realm: int, salt: int) -> Vector2:
	var a := float(salt % 8) * TAU / 8.0
	return base_pos(realm) + Vector2(cos(a), sin(a)) * 4.0


## Portones transitables para un reino: los destruidos, o todos si ese reino controla el
## Bastión (sus defensores entran y salen por sus propias puertas).
static func gates_open_for(realm: int, gate_hp: Array, fortress_owner: int) -> Array:
	var open := []
	for i in GATE_ANGLES.size():
		open.append(int(gate_hp[i]) <= 0 or fortress_owner == realm)
	return open


## Convención de orientación de Godot: con yaw = 0 se mira hacia -Z.
static func yaw_to_dir(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


static func dir_to_yaw(d: Vector2) -> float:
	return atan2(-d.x, -d.y)
