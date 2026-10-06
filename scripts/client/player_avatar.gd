class_name PlayerAvatar
extends Node3D
## Representación visual de un jugador hecha con primitivas (cero texturas => poca VRAM).
## La silueta del "casco" identifica la clase a distancia; el color, el reino.

var max_hp := 1
var _name := ""
var _body: MeshInstance3D
var _label: Label3D
var _mat: StandardMaterial3D
var _last_status := ""


func setup(pname: String, realm: int, cls: int, is_local: bool) -> void:
	_name = pname
	max_hp = GameData.CLASS_MAX_HP[cls]
	var color: Color = GameData.REALM_COLORS[realm]

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.roughness = 0.8

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	capsule.radial_segments = 12
	capsule.rings = 4
	_body = MeshInstance3D.new()
	_body.mesh = capsule
	_body.material_override = _mat
	_body.position.y = 0.9
	add_child(_body)

	var head := MeshInstance3D.new()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = color.darkened(0.55)
	match cls:
		0:  # Quebrantamuros: yelmo de asedio cuadrado
			var box := BoxMesh.new()
			box.size = Vector3(0.75, 0.35, 0.75)
			head.mesh = box
			head.position.y = 0.95
			head.material_override = dark
		1:  # Cantor: orbe de esquirla flotante
			var orb := SphereMesh.new()
			orb.radius = 0.22
			orb.height = 0.44
			orb.radial_segments = 8
			orb.rings = 4
			head.mesh = orb
			head.position.y = 1.35
			var glow := StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.albedo_color = color.lightened(0.5)
			head.material_override = glow
		_:  # Zapador: capucha puntiaguda
			var hood := CylinderMesh.new()
			hood.top_radius = 0.0
			hood.bottom_radius = 0.42
			hood.height = 0.6
			hood.radial_segments = 8
			head.mesh = hood
			head.position.y = 1.05
			head.material_override = dark
	_body.add_child(head)

	# "Nariz": indica hacia dónde mira el personaje (-Z).
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.18, 0.18, 0.4)
	nose.mesh = nose_mesh
	nose.material_override = dark
	nose.position = Vector3(0.0, 0.45, -0.45)
	_body.add_child(nose)

	if is_local:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.75
		torus.outer_radius = 0.9
		torus.rings = 24
		torus.ring_segments = 4
		ring.mesh = torus
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(1, 1, 1, 0.8)
		ring.material_override = ring_mat
		ring.position.y = 0.05
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.55
	_label.font_size = 36
	_label.pixel_size = 0.01
	_label.outline_size = 10
	_label.modulate = Color.WHITE if is_local else color.lightened(0.35)
	add_child(_label)
	set_status(max_hp, 0)


func set_status(hp: int, flags: int) -> void:
	var dead := (flags & Protocol.F_DEAD) != 0
	var pct := clampi(roundi(100.0 * hp / maxf(1.0, max_hp)), 0, 100)
	var filled := int(pct / 10.0)
	var text := "%s\n[%s%s] %d%%" % [_name, "|".repeat(filled), ".".repeat(10 - filled), pct]
	if dead:
		text = "%s\n(caído)" % _name
	if text != _last_status:
		_last_status = text
		_label.text = text
	_body.rotation_degrees.x = 90.0 if dead else 0.0
	_body.position.y = 0.45 if dead else 0.9
	var stealth := (flags & Protocol.F_STEALTH) != 0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if stealth else BaseMaterial3D.TRANSPARENCY_DISABLED
	_mat.albedo_color.a = 0.35 if stealth else 1.0
	_mat.emission_enabled = (flags & (Protocol.F_BULWARK | Protocol.F_RESONANCE)) != 0
	_mat.emission = Color(1.0, 0.9, 0.5) * 0.4
