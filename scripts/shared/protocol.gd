class_name Protocol
extends RefCounted
## Constantes y utilidades de red compartidas por cliente y servidor.
## Regla de oro: todo lo que llega por la red es NO confiable hasta pasar por aquí.

const VERSION := 1
const DEFAULT_PORT := 7777
const DEFAULT_MAX_PLAYERS := 32

## Simulación a tasa fija. Debe coincidir con physics/common/physics_ticks_per_second.
const TICK_RATE := 30
const TICK_DT := 1.0 / TICK_RATE
## El servidor envía un snapshot cada N ticks (30 / 2 = 15 snapshots por segundo).
const SNAPSHOT_EVERY := 2

# --- Límites anti-abuso ---------------------------------------------------------
const MAX_AUTH_BYTES := 512
const MIN_NAME_LEN := 3
const MAX_NAME_LEN := 16
const MAX_CHAT_LEN := 120
const MAX_CMDS_PER_PACKET := 4     ## El cliente reenvía sus últimos 3 comandos (redundancia).
const MAX_SEQ_JUMP := 60           ## Salto máximo de secuencia aceptado (2 s de comandos).
const MAX_CMD_QUEUE := 10          ## Comandos en cola por jugador.
const MAX_MOVE_TOKENS := 6.0       ## "Crédito" de pasos de movimiento (absorbe jitter de red).
const MAX_CMDS_PER_TICK := 3
const VIOLATION_KICK_THRESHOLD := 12.0
const VIOLATION_DECAY_PER_SEC := 0.5

## Tipos de evento servidor -> cliente.
enum Ev { ROSTER, LEAVE, CHAT, SYSTEM, DAMAGE, DEATH, FX, KICK, WIN, NOTICE }

## Bits de estado de una entidad dentro de un snapshot.
const F_STEALTH := 1
const F_BULWARK := 2
const F_RESONANCE := 4
const F_DEAD := 8
const F_DASH := 16

static var _name_re: RegEx = null


## Devuelve el nombre saneado, o "" si no es válido.
static func sanitize_name(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var s: String = raw
	s = s.strip_edges()
	if s.length() < MIN_NAME_LEN or s.length() > MAX_NAME_LEN:
		return ""
	if _name_re == null:
		_name_re = RegEx.create_from_string("^[A-Za-z0-9_ÁÉÍÓÚÜÑáéíóúüñ]+$")
	if _name_re.search(s) == null:
		return ""
	return s


## Limpia texto de chat: tipo, longitud, caracteres de control, zero-width y overrides
## bidireccionales (evita suplantación visual). El cliente además lo muestra con
## RichTextLabel.add_text(), que nunca interpreta BBCode.
static func sanitize_chat(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var src: String = raw
	if src.length() > MAX_CHAT_LEN * 4:
		return ""
	var out := ""
	for i in src.length():
		var c := src.unicode_at(i)
		if c < 32 or c == 127 or c == 0xFEFF:
			continue
		if (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069):
			continue
		out += char(c)
	out = out.strip_edges()
	if out.length() > MAX_CHAT_LEN:
		out = out.substr(0, MAX_CHAT_LEN)
	return out


## true si v es un entero en [lo, hi]. Acepta float sin decimales porque JSON
## entrega todos los números como float.
static func is_int_value(v: Variant, lo: int, hi: int) -> bool:
	if typeof(v) == TYPE_INT:
		var i: int = v
		return i >= lo and i <= hi
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_finite(f) and f == floorf(f) and f >= lo and f <= hi
	return false


## Comparación en tiempo constante: no filtra por temporización cuántos caracteres coinciden.
static func constant_time_equals(a: String, b: String) -> bool:
	var ba := a.to_utf8_buffer()
	var bb := b.to_utf8_buffer()
	if ba.size() != bb.size():
		return false
	var diff := 0
	for i in ba.size():
		diff |= ba[i] ^ bb[i]
	return diff == 0


## Prueba de contraseña con desafío (nonce): la contraseña nunca viaja por la red y una
## respuesta capturada no sirve para otra conexión.
static func password_proof(nonce: String, password: String) -> String:
	return (nonce + ":" + password.sha256_text()).sha256_text()


## Decodifica JSON con límite de tamaño. Devuelve null si es inválido.
static func parse_json_bytes(data: PackedByteArray, max_bytes: int) -> Variant:
	if data.is_empty() or data.size() > max_bytes:
		return null
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK:
		return null
	return json.data
