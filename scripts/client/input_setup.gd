class_name InputSetup
extends RefCounted
## Registra las acciones de teclado por código (más legible que serializarlas en project.godot).
## Se usan teclas FÍSICAS: WASD funciona igual en teclados QWERTY, AZERTY, etc.

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"turn_left": [KEY_Q, KEY_LEFT],
	"turn_right": [KEY_E, KEY_RIGHT],
	"ability_1": [KEY_1],
	"ability_2": [KEY_2],
	"ability_3": [KEY_3],
	"target_next": [KEY_TAB],
	"chat": [KEY_ENTER, KEY_KP_ENTER],
	"help": [KEY_F1],
}


static func ensure_actions() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
