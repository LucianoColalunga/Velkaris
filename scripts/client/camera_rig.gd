class_name CameraRig
extends Node3D
## Cámara en tercera persona estilo MMO: clic derecho (o izquierdo) + arrastrar para girar,
## rueda para acercar/alejar, Q/E para girar con teclado.

var yaw := 0.0
var pitch := -0.5
var distance := 10.0
var _cam: Camera3D
var _rotating := false


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.1
	_cam.far = 260.0
	add_child(_cam)
	_cam.current = true


func follow(target: Vector3) -> void:
	position = target + Vector3(0.0, 1.6, 0.0)
	_cam.position = Vector3(0.0, 0.0, distance).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	_cam.look_at(global_position, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
			_rotating = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = maxf(3.5, distance - 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = minf(24.0, distance + 1.0)
	elif event is InputEventMouseMotion and _rotating:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.005
		pitch = clampf(pitch - mm.relative.y * 0.005, -1.35, 0.1)


func _notification(what: int) -> void:
	# Al perder el foco de la ventana, liberar el ratón.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _rotating:
		_rotating = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
