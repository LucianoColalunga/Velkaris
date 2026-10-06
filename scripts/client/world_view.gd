class_name WorldView
extends Node3D
## Construye la Frontera Rota con primitivas y refleja el estado de los objetivos.
##
## Presupuesto de gama baja (8 GB RAM / GPU 2 GB):
##  * Cero texturas: sólo colores planos => VRAM mínima.
##  * Materiales compartidos (caché) => menos cambios de estado en la GPU.
##  * MultiMesh para murallas, almenas, árboles y rocas => ~4 draw calls para cientos de objetos.
##  * Sin luces dinámicas extra; sombras desactivadas por defecto; niebla para recortar lo lejano.

const NEUTRAL := Color(0.75, 0.75, 0.78)
const STONE := Color(0.42, 0.40, 0.40)

var _mats: Dictionary = {}
var _tower_crystals: Array = []
var _tower_rings: Array = []
var _gate_nodes: Array = []
var _gate_labels: Array = []
var _rubble_nodes: Array = []
var _fortress_crystal: MeshInstance3D
var _fortress_ring: MeshInstance3D
var _target_marker: MeshInstance3D
var _fx: Array = []  ## [{node, ttl, life, kind, vel, mat}]
var _spin := 0.0


func build(shadows: bool) -> void:
	_build_environment(shadows)
	_build_ground()
	_build_bases()
	_build_towers()
	_build_fortress()
	_build_scenery()
	var marker := TorusMesh.new()
	marker.inner_radius = 0.9
	marker.outer_radius = 1.15
	marker.rings = 24
	marker.ring_segments = 4
	_target_marker = _add_mesh(marker, Vector3.ZERO, mat(Color(1.0, 0.2, 0.2), true))
	_target_marker.visible = false


func mat(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + ("u" if unshaded else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


# --- Construcción ---------------------------------------------------------------------

func _build_environment(shadows: bool) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.24, 0.40)
	sky_mat.sky_horizon_color = Color(0.66, 0.56, 0.55)
	sky_mat.ground_horizon_color = Color(0.36, 0.30, 0.32)
	sky_mat.ground_bottom_color = Color(0.10, 0.08, 0.12)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32  # Mínimo posible: ahorra VRAM.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.58, 0.52, 0.55)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)


func _build_ground() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = GameData.MAP_RADIUS + 2.0
	disc.bottom_radius = GameData.MAP_RADIUS - 6.0
	disc.height = 6.0
	disc.radial_segments = 64
	disc.rings = 1
	_add_mesh(disc, Vector3(0.0, -3.0, 0.0), mat(Color(0.33, 0.37, 0.25)))
	# La Fractura: el vacío que rodea la Frontera.
	var abyss := PlaneMesh.new()
	abyss.size = Vector2(700.0, 700.0)
	_add_mesh(abyss, Vector3(0.0, -25.0, 0.0), mat(Color(0.16, 0.10, 0.22), true))
	# Calzadas desde cada santuario hasta su portón.
	for r in GameData.REALM_COUNT:
		var a: Vector2 = GameData.base_pos(r)
		var b: Vector2 = GameData.gate_pos(r)
		var road := BoxMesh.new()
		road.size = Vector3(a.distance_to(b), 0.04, 5.0)
		var mid := (a + b) * 0.5
		var mi := _add_mesh(road, Vector3(mid.x, 0.01, mid.y), mat(Color(0.47, 0.42, 0.34)))
		mi.basis = _basis_along((b - a).normalized())
	# Explanada interior del Bastión.
	var yard := CylinderMesh.new()
	yard.top_radius = GameData.WALL_RADIUS
	yard.bottom_radius = GameData.WALL_RADIUS
	yard.height = 0.04
	yard.radial_segments = 48
	_add_mesh(yard, Vector3(0.0, 0.01, 0.0), mat(Color(0.45, 0.43, 0.40)))


func _build_bases() -> void:
	for r in GameData.REALM_COUNT:
		var c: Color = GameData.REALM_COLORS[r]
		var bp := GameData.base_pos(r)
		var pad := CylinderMesh.new()
		pad.top_radius = GameData.BASE_RADIUS
		pad.bottom_radius = GameData.BASE_RADIUS
		pad.height = 0.06
		pad.radial_segments = 48
		_add_mesh(pad, Vector3(bp.x, 0.02, bp.y), mat(c.darkened(0.45)))
		var obelisk := CylinderMesh.new()
		obelisk.top_radius = 0.35
		obelisk.bottom_radius = 1.3
		obelisk.height = 9.0
		obelisk.radial_segments = 6
		_add_mesh(obelisk, Vector3(bp.x, 4.5, bp.y), mat(Color(0.18, 0.17, 0.2)))
		var flame := SphereMesh.new()
		flame.radius = 0.9
		flame.height = 1.8
		flame.radial_segments = 8
		flame.rings = 4
		_add_mesh(flame, Vector3(bp.x, 9.6, bp.y), mat(c.lightened(0.2), true))
		_add_label(GameData.REALM_NAMES[r], Vector3(bp.x, 12.0, bp.y), c.lightened(0.3), 72)


func _build_towers() -> void:
	for i in GameData.TOWER_ANGLES.size():
		var tp := GameData.tower_pos(i)
		var pillar := CylinderMesh.new()
		pillar.top_radius = 1.1
		pillar.bottom_radius = GameData.TOWER_PILLAR_RADIUS
		pillar.height = 8.0
		pillar.radial_segments = 10
		_add_mesh(pillar, Vector3(tp.x, 4.0, tp.y), mat(STONE))
		_tower_crystals.append(_add_mesh(_crystal_mesh(0.9), Vector3(tp.x, 9.6, tp.y), mat(NEUTRAL, true)))
		_tower_rings.append(_add_mesh(_ring_mesh(GameData.TOWER_CAPTURE_RADIUS), Vector3(tp.x, 0.05, tp.y), mat(NEUTRAL, true)))
		_add_label(GameData.TOWER_NAMES[i], Vector3(tp.x, 12.0, tp.y), Color(0.95, 0.92, 0.85), 56)


func _build_fortress() -> void:
	var angles: Array = GameData.GATE_ANGLES.duplicate()
	angles.sort()
	var seg_target := 4.0
	var span: float = angles[1] - angles[0] - 2.0 * GameData.GATE_HALF_ANGLE  # Los 3 arcos son iguales.
	var n := ceili(span * GameData.WALL_RADIUS / seg_target)
	var step := span / n
	var chord := 2.0 * GameData.WALL_RADIUS * sin(step / 2.0) + 0.25
	var walls: Array = []
	var merlons: Array = []
	for gi in angles.size():
		var a0: float = angles[gi] + GameData.GATE_HALF_ANGLE
		for k in n:
			var a := a0 + step * (k + 0.5)
			var p := GameData.ring_point(a, GameData.WALL_RADIUS)
			var bas := _basis_along(Vector2(-sin(a), cos(a)))
			walls.append(Transform3D(bas, Vector3(p.x, GameData.WALL_HEIGHT / 2.0, p.y)))
			for side in [-0.25, 0.25]:
				var off: Vector2 = Vector2(-sin(a), cos(a)) * chord * float(side)
				merlons.append(Transform3D(bas, Vector3(p.x + off.x, GameData.WALL_HEIGHT + 0.4, p.y + off.y)))
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(chord, GameData.WALL_HEIGHT, GameData.WALL_HALF_THICKNESS * 2.0)
	wall_box.material = mat(STONE)
	_add_multimesh(wall_box, walls)
	var merlon_box := BoxMesh.new()
	merlon_box.size = Vector3(chord * 0.3, 0.8, GameData.WALL_HALF_THICKNESS * 2.0)
	merlon_box.material = mat(STONE.darkened(0.15))
	_add_multimesh(merlon_box, merlons)

	var gate_w := 2.0 * GameData.WALL_RADIUS * sin(GameData.GATE_HALF_ANGLE)
	for gi in GameData.GATE_ANGLES.size():
		var a: float = GameData.GATE_ANGLES[gi]
		var p := GameData.gate_pos(gi)
		var bas := _basis_along(Vector2(-sin(a), cos(a)))
		var gate := BoxMesh.new()
		gate.size = Vector3(gate_w, GameData.WALL_HEIGHT - 1.0, 1.2)
		var gn := _add_mesh(gate, Vector3(p.x, (GameData.WALL_HEIGHT - 1.0) / 2.0, p.y), mat(Color(0.40, 0.26, 0.15)))
		gn.basis = bas
		_gate_nodes.append(gn)
		var rubble := BoxMesh.new()
		rubble.size = Vector3(gate_w, 0.5, 2.2)
		var rn := _add_mesh(rubble, Vector3(p.x, 0.25, p.y), mat(Color(0.30, 0.22, 0.15)))
		rn.basis = bas
		rn.visible = false
		_rubble_nodes.append(rn)
		# Torreones a ambos lados del portón.
		for side in [-1.0, 1.0]:
			var tp := GameData.ring_point(a + float(side) * (GameData.GATE_HALF_ANGLE + 0.04), GameData.WALL_RADIUS)
			var turret := CylinderMesh.new()
			turret.top_radius = 1.5
			turret.bottom_radius = 1.6
			turret.height = GameData.WALL_HEIGHT + 2.5
			turret.radial_segments = 8
			_add_mesh(turret, Vector3(tp.x, (GameData.WALL_HEIGHT + 2.5) / 2.0, tp.y), mat(STONE.darkened(0.1)))
		var out := GameData.ring_point(a, GameData.WALL_RADIUS + 3.0)
		_gate_labels.append(_add_label(GameData.GATE_NAMES[gi], Vector3(out.x, GameData.WALL_HEIGHT + 3.0, out.y), Color.WHITE, 44))

	_fortress_crystal = _add_mesh(_crystal_mesh(1.8), Vector3(0.0, 6.0, 0.0), mat(NEUTRAL, true))
	_fortress_ring = _add_mesh(_ring_mesh(GameData.FORTRESS_CAPTURE_RADIUS), Vector3(0.0, 0.06, 0.0), mat(NEUTRAL, true))
	_add_label(GameData.FORTRESS_NAME, Vector3(0.0, 10.5, 0.0), Color(1.0, 0.95, 0.8), 72)


func _build_scenery() -> void:
	# Semilla fija: todos los clientes ven el mismo bosque.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var trees: Array = []
	var rocks: Array = []
	for _i in 900:
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf_range(0.06, 0.96)) * GameData.MAP_RADIUS
		var p := Vector2(cos(ang), sin(ang)) * rad
		if not _is_clear_spot(p):
			continue
		var s := rng.randf_range(0.7, 1.4)
		if rng.randf() < 0.72:
			var t := Transform3D(Basis.from_scale(Vector3(s, s * rng.randf_range(0.9, 1.4), s)), Vector3(p.x, 2.5 * s, p.y))
			trees.append(t)
		else:
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.4, s * 0.8, s))
			rocks.append(Transform3D(b, Vector3(p.x, 0.3 * s, p.y)))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.5
	cone.height = 5.0
	cone.radial_segments = 7
	cone.rings = 1
	cone.material = mat(Color(0.16, 0.30, 0.20))
	_add_multimesh(cone, trees)
	var rock := BoxMesh.new()
	rock.size = Vector3(1.6, 1.2, 1.4)
	rock.material = mat(Color(0.38, 0.36, 0.38))
	_add_multimesh(rock, rocks)


## Evita poner decoración sobre caminos, santuarios, atalayas o el Bastión.
func _is_clear_spot(p: Vector2) -> bool:
	if p.length() < GameData.WALL_RADIUS + 6.0:
		return false
	for r in GameData.REALM_COUNT:
		if p.distance_to(GameData.base_pos(r)) < GameData.BASE_RADIUS + 6.0:
			return false
		var closest := Geometry2D.get_closest_point_to_segment(p, GameData.base_pos(r), GameData.gate_pos(r))
		if p.distance_to(closest) < 6.0:
			return false
	for i in GameData.TOWER_ANGLES.size():
		if p.distance_to(GameData.tower_pos(i)) < GameData.TOWER_CAPTURE_RADIUS + 4.0:
			return false
	return true


# --- Estado de los objetivos ------------------------------------------------------------

func update_objectives(towers: Array, gates: Array, fortress: Array) -> void:
	for i in mini(towers.size(), _tower_crystals.size()):
		var col := _point_color(towers[i])
		var crystal: MeshInstance3D = _tower_crystals[i]
		var ring: MeshInstance3D = _tower_rings[i]
		crystal.material_override = mat(col, true)
		ring.material_override = mat(_ring_color(towers[i], col), true)
	for gi in mini(gates.size(), _gate_nodes.size()):
		var hp := int(gates[gi])
		var alive := hp > 0
		var gn: MeshInstance3D = _gate_nodes[gi]
		var rubble: MeshInstance3D = _rubble_nodes[gi]
		gn.visible = alive
		rubble.visible = not alive
		var ratio := clampf(float(hp) / GameData.GATE_MAX_HP, 0.0, 1.0)
		var tint := Color(0.75, 0.15, 0.1).lerp(Color(0.40, 0.26, 0.15), snappedf(ratio, 0.1))
		gn.material_override = mat(tint)
		var lbl: Label3D = _gate_labels[gi]
		lbl.text = "%s\n%d%%" % [GameData.GATE_NAMES[gi], roundi(ratio * 100.0)] if alive else "%s\n(DERRIBADO)" % GameData.GATE_NAMES[gi]
	var fcol := _point_color(fortress)
	_fortress_crystal.material_override = mat(fcol, true)
	_fortress_ring.material_override = mat(_ring_color(fortress, fcol), true)


func _point_color(pt: Array) -> Color:
	var own := int(pt[0])
	var capturer := int(pt[1])
	var progress := snappedf(clampf(float(pt[2]), 0.0, 1.0), 0.1)
	if own >= 0:
		return NEUTRAL.lerp(GameData.REALM_COLORS[own], 0.4 + 0.6 * progress)
	if capturer >= 0:
		return NEUTRAL.lerp(GameData.REALM_COLORS[capturer], progress * 0.6)
	return NEUTRAL


func _ring_color(pt: Array, base: Color) -> Color:
	return Color(1.0, 1.0, 1.0) if bool(pt[3]) else base  # Blanco = disputado.


func set_target_marker(pos: Vector3, shown: bool) -> void:
	_target_marker.visible = shown
	if shown:
		_target_marker.position = Vector3(pos.x, 0.06, pos.z)


# --- Efectos visuales (baratos y de vida corta) --------------------------------------------

func spawn_floating_text(at: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 48
	l.outline_size = 10
	l.pixel_size = 0.01
	l.position = at
	add_child(l)
	_fx.append({"node": l, "ttl": 1.0, "life": 1.0, "kind": "text"})


func spawn_beam(from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.2:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, length)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color.lightened(0.4)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var t := Transform3D(Basis.IDENTITY, (from + to) * 0.5)
	if absf((to - from).normalized().dot(Vector3.UP)) < 0.99:
		t = t.looking_at(to, Vector3.UP)
	mi.transform = t
	add_child(mi)
	_fx.append({"node": mi, "ttl": 0.25, "life": 0.25, "kind": "fade", "mat": m})


func spawn_burst(at: Vector3, color: Color, radius: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3.ONE * 0.2
	add_child(mi)
	_fx.append({"node": mi, "ttl": 0.4, "life": 0.4, "kind": "burst", "mat": m, "radius": radius})


func _process(delta: float) -> void:
	_spin += delta
	for c in _tower_crystals:
		var crystal: Node3D = c
		crystal.rotation.y = _spin * 0.8
	if _fortress_crystal:
		_fortress_crystal.rotation.y = -_spin * 0.5
		_fortress_crystal.position.y = 6.0 + sin(_spin * 1.5) * 0.3
	if _fx.is_empty():
		return
	var alive: Array = []
	for fx in _fx:
		fx["ttl"] = float(fx["ttl"]) - delta
		var node: Node3D = fx["node"]
		if float(fx["ttl"]) <= 0.0:
			node.queue_free()
			continue
		var k := float(fx["ttl"]) / float(fx["life"])
		var kind := str(fx["kind"])
		if kind == "text":
			var label := node as Label3D
			label.position.y += delta * 1.5
			label.modulate.a = k
		else:
			var m: StandardMaterial3D = fx["mat"]
			if kind == "burst":
				node.scale = Vector3.ONE * lerpf(float(fx["radius"]), 0.2, k)
				m.albedo_color.a = 0.5 * k
			else:
				m.albedo_color.a = k
		alive.append(fx)
	_fx = alive


# --- Utilidades -----------------------------------------------------------------------------

func _add_mesh(mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi


func _add_multimesh(mesh: Mesh, transforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _add_label(text: String, pos: Vector3, color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.outline_size = 12
	l.pixel_size = 0.02
	l.position = pos
	add_child(l)
	return l


func _crystal_mesh(size: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.8
	s.radial_segments = 6
	s.rings = 2
	return s


func _ring_mesh(radius: float) -> Mesh:
	var t := TorusMesh.new()
	t.inner_radius = radius - 0.3
	t.outer_radius = radius
	t.rings = 48
	t.ring_segments = 4
	return t


## Base cuyo eje X local apunta en la dirección dada del plano XZ.
func _basis_along(d: Vector2) -> Basis:
	return Basis(Vector3(d.x, 0.0, d.y), Vector3.UP, Vector3(-d.y, 0.0, d.x))
