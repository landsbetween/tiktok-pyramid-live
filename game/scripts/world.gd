extends Node3D
## Procedural desert diorama: sand plateau, quarry with a block pile, path, sphinx, oasis, palms,
## clouds and a painted sky canvas. Three looks (day, sunset, night) cycle per pyramid.

var THEMES := [
	{"name": "Sunny Day", "top": Color(0.08, 0.7, 0.95), "hor": Color(0.62, 0.94, 0.98),
		"sun": Color(1, 0.95, 0.85), "sun_e": 1.15, "amb": Color(0.75, 0.82, 0.95), "amb_e": 0.5,
		"sand": Color(1, 1, 1), "disc": Color(1, 0.98, 0.75), "night": false, "cloud": Color(1, 1, 1)},
	{"name": "Golden Sunset", "top": Color(0.3, 0.26, 0.64), "hor": Color(1.0, 0.62, 0.36),
		"sun": Color(1, 0.74, 0.5), "sun_e": 1.1, "amb": Color(0.9, 0.62, 0.6), "amb_e": 0.45,
		"sand": Color(1, 0.9, 0.84), "disc": Color(1, 0.62, 0.3), "night": false, "cloud": Color(1, 0.8, 0.75)},
	{"name": "Starry Night", "top": Color(0.02, 0.03, 0.13), "hor": Color(0.14, 0.18, 0.42),
		"sun": Color(0.62, 0.72, 1.0), "sun_e": 0.6, "amb": Color(0.45, 0.52, 0.85), "amb_e": 0.42,
		"sand": Color(0.78, 0.8, 0.95), "disc": Color(0.93, 0.95, 1.0), "night": true, "cloud": Color(0.55, 0.6, 0.8)},
]

const GROUND_MIN := -11.0
const GROUND_MAX := 22.0

var game
var bg_grad: Gradient
var disc: TextureRect
var disc_grad: Gradient
var stars: Control
var sand_mat: StandardMaterial3D
var cliff_mat: StandardMaterial3D
var cloud_mat: StandardMaterial3D
var clouds: Array = []
var pile_mm: MultiMesh
var quarry_root: Node3D
var path_mi: MeshInstance3D


class Stars extends Control:
	var pts: Array = []
	var t := 0.0

	func _ready() -> void:
		for i in 140:
			pts.append(Vector3(randf() * 1080.0, randf() * 700.0, randf() * TAU))

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		for p in pts:
			var a := 0.45 + 0.55 * sin(t * 1.7 + p.z)
			draw_circle(Vector2(p.x, p.y), 2.0 + (1.2 if int(p.z * 10) % 5 == 0 else 0.0), Color(1, 1, 1, a))


func build(g) -> void:
	game = g
	_background()
	_ground()
	_quarry()
	_sphinx(Vector3(15.5, 0, 4.5), -40.0)
	_oasis(Vector3(18.0, 0, 15.0))
	for p in [Vector3(-11, 0, 10), Vector3(-12.5, 0, 12.5), Vector3(-10, 0, -3.5), Vector3(-3.5, 0, -10),
			Vector3(9.5, 0, -9.5), Vector3(3, 0, 19.5), Vector3(13.5, 0, -6.5)]:
		_palm(p, randf_range(2.6, 3.6))
	for i in 26:
		var x := randf_range(GROUND_MIN + 1, GROUND_MAX - 1)
		var z := randf_range(GROUND_MIN + 1, GROUND_MAX - 1)
		if absf(x) < 10.5 and absf(z) < 10.5:
			continue
		_rock(Vector3(x, 0, z))
	_clouds()


# ---------- sky ----------
func _background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	bg_grad = Gradient.new()
	var gt := GradientTexture2D.new()
	gt.gradient = bg_grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 0.55)
	gt.width = 8
	gt.height = 256
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	stars = Stars.new()
	stars.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(stars)
	disc_grad = Gradient.new()
	disc_grad.offsets = PackedFloat32Array([0.0, 0.34, 0.4, 1.0])
	disc_grad.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var dt := GradientTexture2D.new()
	dt.gradient = disc_grad
	dt.fill = GradientTexture2D.FILL_RADIAL
	dt.fill_from = Vector2(0.5, 0.5)
	dt.fill_to = Vector2(0.5, 0.0)
	dt.width = 256
	dt.height = 256
	disc = TextureRect.new()
	disc.texture = dt
	disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	disc.position = Vector2(700, 150)
	disc.size = Vector2(330, 330)
	layer.add_child(disc)


func apply_theme(i: int) -> Dictionary:
	var t: Dictionary = THEMES[i % THEMES.size()]
	bg_grad.offsets = PackedFloat32Array([0.0, 1.0])
	bg_grad.colors = PackedColorArray([t.top, t.hor])
	disc.modulate = t.disc
	stars.visible = t.night
	sand_mat.albedo_color = t.sand
	cliff_mat.albedo_color = Color(0.86, 0.55, 0.3) * t.sand
	cloud_mat.albedo_color = t.cloud
	return t


func _clouds() -> void:
	cloud_mat = StandardMaterial3D.new()
	cloud_mat.albedo_color = Color.WHITE
	cloud_mat.roughness = 1.0
	cloud_mat.rim_enabled = true
	cloud_mat.rim = 0.4
	for i in 6:
		var c := Node3D.new()
		var n := randi_range(4, 7)
		for k in n:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r := randf_range(0.9, 1.7)
			sm.radius = r
			sm.height = r * 1.7
			sm.radial_segments = 20
			sm.rings = 10
			s.mesh = sm
			s.material_override = cloud_mat
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.position = Vector3((k - n * 0.5) * 1.2, randf_range(0, 0.8) if k % 2 else 0.0, randf_range(-0.6, 0.6))
			c.add_child(s)
		add_child(c)
		clouds.append({"node": c, "sx": randf_range(-16, 16), "sy": randf_range(14.0, 21.0), "v": randf_range(0.25, 0.6)})
	_place_clouds(0.0)


func _place_clouds(delta: float) -> void:
	# clouds live in screen space (sx, sy of the iso camera) far behind the plateau
	for c in clouds:
		c.sx += c.v * delta
		if c.sx > 18.0:
			c.sx = -18.0
		var y := 3.0
		var sy: float = game.screen_top_sy() - (c.sy - 12.5)
		var sum: float = (0.816 * y - sy) / 0.408
		var diff: float = c.sx / 0.7071
		c.node.position = Vector3((sum + diff) * 0.5, y, (sum - diff) * 0.5)


func _process(delta: float) -> void:
	_place_clouds(delta)


# ---------- ground ----------
func _ground() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.015
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.92, 0.64, 0.33), Color(0.98, 0.77, 0.45)])
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.color_ramp = ramp
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	sand_mat = StandardMaterial3D.new()
	sand_mat.albedo_texture = nt
	sand_mat.uv1_triplanar = true
	sand_mat.uv1_world_triplanar = true
	sand_mat.uv1_scale = Vector3.ONE * 0.04
	sand_mat.roughness = 1.0
	var span := GROUND_MAX - GROUND_MIN
	var mid := (GROUND_MAX + GROUND_MIN) * 0.5
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(span, 0.6, span)
	top.mesh = tm
	top.material_override = sand_mat
	top.position = Vector3(mid, -0.3, mid)
	add_child(top)
	cliff_mat = StandardMaterial3D.new()
	cliff_mat.albedo_color = Color(0.86, 0.55, 0.3)
	cliff_mat.roughness = 1.0
	var strata := [[-1.6, 1.4, 1.0], [-3.3, 1.6, 0.9], [-5.3, 2.0, 0.8]]
	for s in strata:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(span - 0.1 + s[2] * 0.2, s[1], span - 0.1 + s[2] * 0.2)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.9, 0.58, 0.32) * s[2]
		m.roughness = 1.0
		mi.material_override = m
		mi.position = Vector3(mid, s[0], mid)
		add_child(mi)
	var base := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(span - 0.3, 10, span - 0.3)
	base.mesh = bb
	base.material_override = cliff_mat
	base.position = Vector3(mid, -6.3, mid)
	add_child(base)


func set_layout(quarry: Vector3, path_end: Vector3, animate: bool) -> void:
	if animate:
		create_tween().tween_property(quarry_root, "position", quarry, 1.2).set_trans(Tween.TRANS_SINE)
	else:
		quarry_root.position = quarry
	if path_mi == null:
		path_mi = MeshInstance3D.new()
		path_mi.mesh = PlaneMesh.new()
		path_mi.material_override = game.mat(Color(0.97, 0.8, 0.52))
		add_child(path_mi)
	var a := quarry + Vector3(-0.4, 0, -1.0)
	var d := path_end - a
	path_mi.mesh.size = Vector2(2.6, d.length())
	path_mi.position = (a + path_end) * 0.5 + Vector3(0, 0.015, 0)
	path_mi.rotation.y = atan2(d.x, d.z)


# ---------- quarry ----------
func _quarry() -> void:
	quarry_root = Node3D.new()
	add_child(quarry_root)
	var q := Vector3.ZERO
	var pit := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(5.5, 0.1, 4.2)
	pit.mesh = pm
	pit.material_override = game.mat(Color(0.8, 0.55, 0.3))
	pit.position = q + Vector3(0.5, 0.0, 1.8)
	quarry_root.add_child(pit)
	# static stacks of cut blocks around the pit
	var spots := [Vector3(3.8, 0, 0.6), Vector3(3.8, 0, 1.6), Vector3(3.8, 0, 2.6), Vector3(2.8, 0, 3.8),
		Vector3(-2.6, 0, 3.5), Vector3(-2.6, 0, 2.5), Vector3(-3.2, 0, 0.2)]
	for i in spots.size():
		var h := randi_range(1, 3)
		for k in h:
			var b := MeshInstance3D.new()
			b.mesh = game.block_mesh
			b.material_override = game.carry_mat
			b.scale = Vector3(1, 0.7, 1) * 0.9
			b.position = q + spots[i] + Vector3(0, 0.32 + k * 0.63, 0)
			b.rotation.y = randf_range(-0.1, 0.1)
			quarry_root.add_child(b)
	for i in 14:
		var r := MeshInstance3D.new()
		r.mesh = game.box_mesh(Vector3.ONE * randf_range(0.18, 0.4))
		r.material_override = game.mat(Color(0.85, 0.62, 0.36))
		r.position = q + Vector3(randf_range(-2.0, 3.0), 0.1, randf_range(0.8, 3.6))
		r.rotation = Vector3(randf(), randf(), randf())
		quarry_root.add_child(r)
	# pile of blocks waiting to be carried (grows with likes and gifts)
	pile_mm = MultiMesh.new()
	pile_mm.transform_format = MultiMesh.TRANSFORM_3D
	pile_mm.mesh = game.block_mesh
	pile_mm.instance_count = 60
	var idx := 0
	for lvl in 4:
		for r in 5 - lvl:
			for c in 4 - lvl:
				if idx >= 60:
					break
				var p := q + Vector3(-1.2 + c * 0.82 + lvl * 0.4, 0.34 + lvl * 0.66, 1.2 + r * 0.82 + lvl * 0.4)
				pile_mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3(0.82, 0.68, 0.82)), p))
				idx += 1
	pile_mm.visible_instance_count = 0
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = pile_mm
	pmi.material_override = game.carry_mat
	quarry_root.add_child(pmi)


func set_pile(n: int) -> void:
	pile_mm.visible_instance_count = clampi(n, 0, 50)


# ---------- props ----------
func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = game.box_mesh(size)
	mi.material_override = game.mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _sphinx(pos: Vector3, rot_deg: float) -> void:
	var s := Node3D.new()
	s.position = pos
	s.rotation_degrees.y = rot_deg
	s.scale = Vector3.ONE * 1.25
	add_child(s)
	var stone := Color(0.93, 0.7, 0.42)
	var dark := Color(0.8, 0.56, 0.32)
	var blue := Color(0.25, 0.45, 0.8)
	_box(s, Vector3(0, 0.2, 0), Vector3(2.8, 0.4, 5.4), dark)
	_box(s, Vector3(0, 0.95, -0.5), Vector3(1.6, 1.1, 3.0), stone)
	_box(s, Vector3(-0.5, 0.58, 1.55), Vector3(0.38, 0.36, 1.6), stone)
	_box(s, Vector3(0.5, 0.58, 1.55), Vector3(0.38, 0.36, 1.6), stone)
	_box(s, Vector3(0, 1.35, 0.85), Vector3(1.3, 1.3, 0.9), stone)
	_box(s, Vector3(0, 2.2, 0.85), Vector3(1.3, 1.1, 0.75), stone)   # nemes back
	for k in 3:
		_box(s, Vector3(0, 1.85 + k * 0.3, 0.84), Vector3(1.33, 0.08, 0.77), blue)
	_box(s, Vector3(-0.58, 1.6, 1.28), Vector3(0.28, 1.0, 0.2), stone)
	_box(s, Vector3(0.58, 1.6, 1.28), Vector3(0.28, 1.0, 0.2), stone)
	var head := _box(s, Vector3(0, 2.15, 1.3), Vector3(0.9, 0.95, 0.5), stone)
	_box(head, Vector3(-0.2, 0.1, 0.26), Vector3(0.16, 0.08, 0.02), Color(0.2, 0.12, 0.05))
	_box(head, Vector3(0.2, 0.1, 0.26), Vector3(0.16, 0.08, 0.02), Color(0.2, 0.12, 0.05))
	_box(head, Vector3(0, -0.08, 0.28), Vector3(0.13, 0.22, 0.08), dark)
	_box(head, Vector3(0, -0.3, 0.26), Vector3(0.28, 0.04, 0.02), Color(0.35, 0.2, 0.1))
	_box(s, Vector3(0, 1.75, 1.62), Vector3(0.14, 0.4, 0.14), dark)  # beard
	_box(s, Vector3(0.9, 0.55, -1.9), Vector3(0.2, 0.18, 1.2), stone)  # tail


func _palm(pos: Vector3, h: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = randf() * TAU
	add_child(root)
	var segs := 6
	var lean := randf_range(0.03, 0.08)
	var p := Vector3.ZERO
	for i in segs:
		var w := 0.36 - i * 0.025
		var c := Color(0.55, 0.36, 0.2) if i % 2 == 0 else Color(0.47, 0.3, 0.17)
		_box(root, p + Vector3(0, h / segs * 0.5, 0), Vector3(w, h / segs + 0.02, w), c)
		p += Vector3(lean * i, h / segs, 0)
	var greens := [Color(0.3, 0.72, 0.25), Color(0.22, 0.6, 0.2)]
	for k in 7:
		var piv := Node3D.new()
		piv.position = p
		piv.rotation = Vector3(0, k * TAU / 7.0 + randf() * 0.3, deg_to_rad(-28))
		root.add_child(piv)
		_box(piv, Vector3(0.95, 0, 0), Vector3(1.9, 0.08, 0.55), greens[k % 2])
		var tip := Node3D.new()
		tip.position = Vector3(1.85, 0, 0)
		tip.rotation.z = deg_to_rad(-30)
		piv.add_child(tip)
		_box(tip, Vector3(0.4, 0, 0), Vector3(0.8, 0.07, 0.42), greens[(k + 1) % 2])
	for k in 3:
		var co := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		co.mesh = sm
		co.material_override = game.mat(Color(0.4, 0.26, 0.12))
		co.position = p + Vector3(cos(k * 2.1) * 0.2, -0.15, sin(k * 2.1) * 0.2)
		root.add_child(co)


func _rock(pos: Vector3) -> void:
	var r := MeshInstance3D.new()
	r.mesh = game.box_mesh(Vector3(randf_range(0.5, 1.2), randf_range(0.3, 0.7), randf_range(0.5, 1.1)))
	r.material_override = game.mat(Color(0.82, 0.6, 0.38))
	r.position = pos + Vector3(0, 0.15, 0)
	r.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
	add_child(r)


func _oasis(pos: Vector3) -> void:
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 3.4
	rm.bottom_radius = 3.4
	rm.height = 0.06
	rm.radial_segments = 10
	rim.mesh = rm
	rim.material_override = game.mat(Color(0.55, 0.75, 0.3))
	rim.position = pos + Vector3(0, 0.02, 0)
	add_child(rim)
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 2.7
	wm.bottom_radius = 2.7
	wm.height = 0.08
	wm.radial_segments = 10
	water.mesh = wm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.7, 0.95)
	m.roughness = 0.08
	m.metallic_specular = 0.9
	water.material_override = m
	water.position = pos + Vector3(0, 0.05, 0)
	add_child(water)
	for k in 5:
		var a := k * TAU / 5.0 + 0.4
		_palm(pos + Vector3(cos(a), 0, sin(a)) * 3.3, randf_range(2.4, 3.4))
	for k in 10:
		var a := randf() * TAU
		var tuft := _box(self, pos + Vector3(cos(a), 0, sin(a)) * randf_range(3.6, 4.4) + Vector3(0, 0.12, 0),
			Vector3(0.1, 0.25, 0.1), Color(0.35, 0.7, 0.25))
		tuft.rotation.z = randf_range(-0.4, 0.4)
