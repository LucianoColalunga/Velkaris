class_name RateLimiter
extends RefCounted
## Cubeta de fichas (token bucket): permite ráfagas cortas pero limita el ritmo sostenido.

var capacity: float
var refill_per_sec: float
var tokens: float
var _last_ms: int


func _init(cap: float, per_sec: float) -> void:
	capacity = cap
	refill_per_sec = per_sec
	tokens = cap
	_last_ms = Time.get_ticks_msec()


func consume(cost: float = 1.0) -> bool:
	var now_ms := Time.get_ticks_msec()
	tokens = minf(capacity, tokens + (now_ms - _last_ms) / 1000.0 * refill_per_sec)
	_last_ms = now_ms
	if tokens < cost:
		return false
	tokens -= cost
	return true
