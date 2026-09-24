extends Node3D
## Pyramid Live: the whole chat builds one pyramid.
## Likes and gifts add blocks to the quarry pile, workers carry and throw them onto the pyramid,
## followers and gifters get their own named worker, GG-style gifts shake the top off.
## When a pyramid is done: leaderboard, then a bigger pyramid in a new look.

const SERVER_URL := "ws://127.0.0.1:3001"
const FIRST_SIZE := 7
const MAX_SIZE := 15
const IDLE_BLOCK_EVERY := 3.0      # free block when nobody is donating
const NPC_WORKERS := 4
const MAX_WORKERS := 40
const LIKE_WORKER_TTL := 15.0       # a likes-only worker leaves after this long without likes
const RAIN_THRESHOLD := 40         # big backlog: blocks also drop from the sky
const QUARRY := Vector3(7.9, 0, 17.8)
const CAM_LOOK := Vector3(4.53, 0, 4.53)
const CAM_DIR := Vector3(1, 1, 1)
const SAND_BLOCK := Color(0.97, 0.76, 0.45)

var WorkerScript = preload("res://scripts/worker.gd")
var UiScript = preload("res://scripts/ui.gd")
var NetScript = preload("res://scripts/net.gd")
var FxScript = preload("res://scripts/fx.gd")
var WorldScript = preload("res://scripts/world.gd")

var args := {}
var quarry_pos := QUARRY
var cam_look := CAM_LOOK
var font: SystemFont
var tag_font: SystemFont
var tag_bg_mat: StandardMaterial3D
var user_likes := {}
var top_likers := {}   # uid -> {name, n}  whole stream
var top_donors := {}   # uid -> {name, n}  coins, whole stream
var top_builders := {} # uid -> {name, n}  blocks from likes + gifts + follows, whole stream
var tops_dirty := false
var viewer_stats := {}   # uid -> {likes, coins} whole stream: drives the level
const LIKES_PER_LEVEL := 500
const COINS_PER_LEVEL := 10
var aura_tex: GradientTexture2D
var beam_tex: GradientTexture2D
var fx_mat_cache := {}
var tops_t := 0.0
var ttl_t := 0.0
var likes_per_block := 5
var blocks_per_coin := 10
var pyramid_no := 1
var pyr_size := FIRST_SIZE
var theme_i := 0
var slots: Array = []
var slot_state := PackedByteArray()   # 0 empty, 1 reserved (block in the air), 2 placed
var next_slot := 0
var placed_count := 0
var pending := 0
var celebrating := false
var like_acc := 0
var idle_t := 0.0
var rain_t := 0.0
var shake := 0.0
var speed_mult := 1.0
var perf_t := 0.0
var demo_t := 0.0
var round_credit := {}
var pop_anim := {}

var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var mm: MultiMesh
var mmi: MultiMeshInstance3D
var capstone: MeshInstance3D
var block_mesh: BoxMesh
var block_mat: StandardMaterial3D
var carry_mat: StandardMaterial3D
var workers: Array = []
var by_user := {}
var ui
var net
var fx
var world
var mesh_cache := {}
var mat_cache := {}


func _ready() -> void:
	randomize()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("window"):
		var wh: PackedStringArray = str(args.window).split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	if args.has("borderless"):
		get_window().borderless = true
		get_window().position = Vector2i.ZERO
	Engine.max_fps = 60   # LIVE Studio takes 30 fps anyway; do not burn the GPU when vsync is off
	if args.has("ontop"):
		# Window capture on macOS freezes when the window is covered: keep it always on top,
		# as tall as the screen (sharper capture) and parked at the right edge.
		var win := get_window()
		var r := DisplayServer.screen_get_usable_rect(win.current_screen)
		var h := r.size.y
		var w := int(h * 9.0 / 16.0)
		win.size = Vector2i(w, h)
		win.position = Vector2i(r.position.x + r.size.x - w, r.position.y)
		win.borderless = true   # no title bar in the captured picture
		win.always_on_top = true
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Arial Rounded MT Bold", "Segoe UI Black", "Arial Black", "Arial"])
	font.font_weight = 800
	# Minecraft-like name tags: tiny un-antialiased mono font scaled up with nearest filtering
	tag_font = SystemFont.new()
	tag_font.font_names = PackedStringArray(["Menlo", "Consolas", "Courier New", "monospace"])
	tag_font.font_weight = 700
	tag_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	tag_font.hinting = TextServer.HINTING_NONE
	tag_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	tag_bg_mat = StandardMaterial3D.new()
	tag_bg_mat.albedo_color = Color(0, 0, 0, 0.42)
	tag_bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tag_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tag_bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	tag_bg_mat.no_depth_test = true
	tag_bg_mat.render_priority = 10
	if args.has("size"):
		pyr_size = clampi(int(args.size), 3, MAX_SIZE)
	_setup_render()
	_setup_blocks()
	world = WorldScript.new()
	add_child(world)
	world.build(self)
	fx = FxScript.new()
	add_child(fx)
	fx.setup(self)
	ui = UiScript.new()
	add_child(ui)
	ui.setup(self)
	ui.set_rules(likes_per_block, blocks_per_coin)
	net = NetScript.new()
	net.url = str(args.get("server", SERVER_URL))
	add_child(net)
	net.event.connect(_on_event)
	mmi = MultiMeshInstance3D.new()
	mmi.material_override = block_mat
	add_child(mmi)
	capstone = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.72
	cm.height = 1.0
	cm.radial_segments = 4
	cm.rings = 1
	capstone.mesh = cm
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.8, 0.25)
	gold.metallic = 0.85
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.7, 0.2)
	gold.emission_energy_multiplier = 0.6
	capstone.material_override = gold
	capstone.rotation.y = PI / 4.0
	capstone.visible = false
	add_child(capstone)
	_new_pyramid()
	for i in NPC_WORKERS:
		_spawn_worker("", "", false)
	if args.has("shot"):
		_take_shot()
	if args.has("reel"):
		AudioServer.set_bus_mute(0, true)   # the soundtrack is added afterwards
		get_window().size = Vector2i(1080, 1920)   # record at full TikTok resolution
	if args.has("skins"):   # debug: line up every skin in front of the camera
		var all := ["worker", "steve", "explorer", "bedouin", "mummy", "ninja", "spartan", "cleopatra", "pharaoh", "anubis", "gold_pharaoh"]
		for i in all.size():
			var w = _spawn_worker("skin%d" % i, all[i], false, all[i])
			w.position = quarry_pos + Vector3(-5.0 + i * 1.0, 0, 3.0)
			w.rotation.y = PI * 0.25
			w.process_mode = Node.PROCESS_MODE_DISABLED
		cam.size = 9.0
		_set_cam_look(quarry_pos + Vector3(0, 0, 3.0))


# ---------- helpers ----------
func _glowy(tex: Texture2D, c: Color, a: float, cull := BaseMaterial3D.CULL_BACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = cull
	m.no_depth_test = false
	m.albedo_color = Color(c.r, c.g, c.b, a)
	if tex:
		m.albedo_texture = tex
	return m


## soft glowing disc on the ground
func aura_mat(c: Color, a: float) -> StandardMaterial3D:
	var key := "a%s%.2f" % [c.to_html(), a]
	if not fx_mat_cache.has(key):
		if aura_tex == null:
			var g := Gradient.new()
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
			g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
			aura_tex = GradientTexture2D.new()
			aura_tex.gradient = g
			aura_tex.fill = GradientTexture2D.FILL_RADIAL
			aura_tex.fill_from = Vector2(0.5, 0.5)
			aura_tex.fill_to = Vector2(1.0, 0.5)
		fx_mat_cache[key] = _glowy(aura_tex, c, a)
	return fx_mat_cache[key]


## bright ring (HDR colour so the glow post-effect picks it up)
func glow_mat(c: Color) -> StandardMaterial3D:
	var key := "g%s" % c.to_html()
	if not fx_mat_cache.has(key):
		fx_mat_cache[key] = _glowy(null, c, 0.9)
	return fx_mat_cache[key]


## vertical light pillar for high levels
func beam_mat(c: Color) -> StandardMaterial3D:
	var key := "b%s" % c.to_html()
	if not fx_mat_cache.has(key):
		if beam_tex == null:
			var g := Gradient.new()
			g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55)])
			beam_tex = GradientTexture2D.new()
			beam_tex.gradient = g
			beam_tex.fill_from = Vector2(0.5, 0.0)
			beam_tex.fill_to = Vector2(0.5, 1.0)
		fx_mat_cache[key] = _glowy(beam_tex, c, 0.5, BaseMaterial3D.CULL_DISABLED)
	return fx_mat_cache[key]


func level_of(uid: String) -> int:
	var st: Dictionary = viewer_stats.get(uid, {})
	return 1 + int(st.get("likes", 0)) / LIKES_PER_LEVEL + int(st.get("coins", 0)) / COINS_PER_LEVEL


func _add_stat(u: Dictionary, key: String, n: int) -> void:
	var uid := str(u.get("id", ""))
	if uid == "" or uid == "anon" or n <= 0:
		return
	if not viewer_stats.has(uid):
		viewer_stats[uid] = {"likes": 0, "coins": 0}
	viewer_stats[uid][key] += n


func _sync_level(u: Dictionary) -> void:
	var uid := str(u.get("id", ""))
	var w = by_user.get(uid)
	if w == null or not is_instance_valid(w):
		return
	var l := level_of(uid)
	if l != w.level:
		w.set_level(l, true)
		if l > 1 and l % 5 == 0:
			ui.popup("%s  LV %d!" % [str(u.get("name", uid)).substr(0, 12), l], WorkerScript.tier_color(l))


func box_mesh(s: Vector3) -> BoxMesh:
	var key := "%.3f_%.3f_%.3f" % [s.x, s.y, s.z]
	if not mesh_cache.has(key):
		var b := BoxMesh.new()
		b.size = s
		mesh_cache[key] = b
	return mesh_cache[key]


func mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		mat_cache[key] = m
	return mat_cache[key]


func _set_cam_look(v: Vector3) -> void:
	cam_look = v
	cam.look_at_from_position(v + CAM_DIR.normalized() * 90.0, v, Vector3.UP)


func screen_top_sy() -> float:
	# iso screen "y" of the top edge; screen centre sits on CAM_LOOK
	return -0.816 * cam_look.x + cam.size * 0.5


func _setup_render() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 36.0
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)
	_set_cam_look(CAM_LOOK)
	cam.current = true
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	sun.shadow_bias = 0.03
	sun.shadow_blur = 1.5
	add_child(sun)
	sun.look_at_from_position(Vector3(3.0, 13.0, -8.5), Vector3.ZERO, Vector3.UP)
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_blocks() -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var e := float(mini(mini(x, n - 1 - x), mini(y, n - 1 - y))) / n
			var edge := clampf(e / 0.07, 0.0, 1.0)
			var shade := lerpf(0.58, 1.0, edge * edge * (3.0 - 2.0 * edge))
			if e > 0.07 and e < 0.12:
				shade += 0.07
			shade += noise.get_noise_2d(x, y) * 0.07
			img.set_pixel(x, y, Color(shade, shade, shade))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	block_mesh = BoxMesh.new()
	block_mesh.size = Vector3.ONE * 0.96
	block_mat = StandardMaterial3D.new()
	block_mat.albedo_texture = tex
	block_mat.vertex_color_use_as_albedo = true
	block_mat.vertex_color_is_srgb = true
	block_mat.uv1_triplanar = true
	block_mat.uv1_scale = Vector3.ONE / 0.96
	block_mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	block_mat.roughness = 0.9
	carry_mat = block_mat.duplicate()
	carry_mat.vertex_color_use_as_albedo = false
	carry_mat.albedo_color = SAND_BLOCK


# ---------- pyramid ----------
func _build_slots(n: int) -> Array:
	var out := []
	var layer := 0
	var w := n
	while w > 0:
		var off := (w - 1) * 0.5
		for j in w:
			for i in w:
				out.append(Vector3(i - off, layer + 0.5, j - off))
		w -= 2
		layer += 1
	return out


func _hidden(i: int) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ONE * 0.001), slots[i])


func _new_pyramid() -> void:
	slots = _build_slots(pyr_size)
	slot_state = PackedByteArray()
	slot_state.resize(slots.size())
	next_slot = 0
	placed_count = 0
	pop_anim.clear()
	round_credit.clear()
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = block_mesh
	mm.instance_count = slots.size()
	for i in slots.size():
		mm.set_instance_transform(i, _hidden(i))
		var h := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var v := 0.9 + h * 0.16
		mm.set_instance_color(i, Color(SAND_BLOCK.r * v, SAND_BLOCK.g * v * (0.97 + h * 0.05), SAND_BLOCK.b * v))
	mm.custom_aabb = AABB(Vector3(-8, 0, -8), Vector3(16, 10, 16))
	mmi.multimesh = mm
	mmi.position = Vector3.ZERO
	capstone.visible = false
	var t: Dictionary = world.apply_theme(theme_i)
	sun.light_color = t.sun
	sun.light_energy = t.sun_e
	env.ambient_light_color = t.amb
	env.ambient_light_energy = t.amb_e
	ui.set_progress(pyramid_no, 0, slots.size())
	# frame: pyramid + quarry fill the band between the HUD (top 22%) and TikTok chat (bottom 27%)
	var s := float(pyr_size)
	quarry_pos = Vector3(1.6 + 0.39 * s, 0, 3.3 + 0.84 * s)
	var cam_size := (s * 1.414 + 6.0) / 0.5625
	var top_sy := 0.816 * (s + 1.0) * 0.5
	var bottom_sy := -0.408 * (quarry_pos.x + quarry_pos.z) - 2.5
	var centre_sy := (top_sy + bottom_sy) * 0.5 - 0.025 * cam_size
	var look := Vector3(-centre_sy / 0.816, 0, -centre_sy / 0.816)
	var first := pyramid_no == 1
	world.set_layout(quarry_pos, Vector3(0, 0, s * 0.5 + 1.0), not first)
	if first:
		cam.size = cam_size
		_set_cam_look(look)
	else:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(cam, "size", cam_size, 1.5).set_trans(Tween.TRANS_SINE)
		tw.tween_method(_set_cam_look, cam_look, look, 1.5).set_trans(Tween.TRANS_SINE)


func _reserve() -> int:
	if next_slot >= slots.size():
		return -1
	var i := next_slot
	slot_state[i] = 1
	next_slot += 1
	return i


func _place(i: int) -> void:
	slot_state[i] = 2
	placed_count += 1
	mm.set_instance_transform(i, Transform3D(Basis(), slots[i]))
	pop_anim[i] = 0.0
	fx.dust(slots[i] + Vector3(0, -0.45, 0))
	fx.thud()
	ui.set_progress(pyramid_no, placed_count, slots.size())
	if placed_count >= slots.size():
		_complete()


## A viewer's own worker first carries the blocks that viewer earned with likes.
func take_blocks_for(w) -> int:
	var cap: int = 0 if w.npc else w.capacity()
	if w.own > 0 and not celebrating and next_slot < slots.size():
		var n: int = mini(w.own, maxi(cap, 1))
		w.own -= n
		return n
	return take_blocks(cap)


## cap 0 = NPC helper (small loads); viewers lift up to their level-based capacity
func take_blocks(cap := 0) -> int:
	if celebrating or pending <= 0 or next_slot >= slots.size():
		return 0
	var n := clampi(1 + pending / 25, 1, 4)
	if cap > 0:
		n = cap
	n = mini(n, pending)
	pending -= n
	return n


func drop_point() -> Vector3:
	var h := pyr_size * 0.5
	return Vector3(randf_range(-h + 0.6, h - 0.6), 0, h + 0.8 + randf() * 0.5)


func aim_point() -> Vector3:
	return slots[mini(next_slot, slots.size() - 1)]


func quarry_point() -> Vector3:
	return quarry_pos + Vector3(randf_range(-2.2, 1.6), 0, randf_range(-1.6, 0.4))


func throw_blocks(from: Vector3, n: int, _uid: String) -> void:
	for k in n:
		var idx := _reserve()
		if idx < 0:
			pending += n - k    # no room left: back to the pile
			return
		var b := MeshInstance3D.new()
		b.mesh = block_mesh
		b.material_override = carry_mat
		add_child(b)
		var start := from + Vector3(0, k * 0.62, 0)
		b.position = start
		var to: Vector3 = slots[idx]
		var dist := start.distance_to(to)
		var dur := 0.45 + dist * 0.035 + k * 0.07
		var tw := create_tween()
		tw.tween_method(_fly_step.bind(b, start, to, 1.2 + dist * 0.28), 0.0, 1.0, dur)
		tw.tween_callback(_land.bind(b, idx))


func _fly_step(t: float, b: Node3D, a: Vector3, c: Vector3, h: float) -> void:
	var p := a.lerp(c, t)
	p.y += sin(t * PI) * h
	b.position = p
	b.scale = Vector3.ONE * lerpf(0.62, 1.0, t)
	b.rotation = Vector3(t * TAU, t * PI, 0)


func _land(b: Node3D, idx: int) -> void:
	b.queue_free()
	if idx >= 0 and idx < slot_state.size() and slot_state[idx] == 1:
		_place(idx)
	else:
		var j := _reserve()   # its slot was knocked off by a quake: take the next one
		if j >= 0:
			_place(j)
		else:
			pending += 1


func _rain_block() -> void:
	var idx := _reserve()
	if idx < 0:
		return
	pending -= 1
	var b := MeshInstance3D.new()
	b.mesh = block_mesh
	b.material_override = carry_mat
	add_child(b)
	var to: Vector3 = slots[idx]
	var from := to + Vector3(randf_range(-1, 1), 16.0, randf_range(-1, 1))
	b.position = from
	var tw := create_tween()
	tw.tween_property(b, "position", to, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_land.bind(b, idx))


func quake(power: int) -> void:
	var k := clampi(power * 3, 4, 500)
	var removed := 0
	var idx := next_slot - 1
	var lowest := next_slot
	while idx >= 0 and removed < k:
		if slot_state[idx] == 2:
			placed_count -= 1
			mm.set_instance_transform(idx, _hidden(idx))
			pop_anim.erase(idx)
			if removed < 70:
				_debris(slots[idx])
		slot_state[idx] = 0
		lowest = idx
		removed += 1
		idx -= 1
	next_slot = lowest
	shake = 1.0
	fx.boom(Vector3(0, 1.0, 0))
	ui.set_progress(pyramid_no, placed_count, slots.size())


func _debris(pos: Vector3) -> void:
	var b := MeshInstance3D.new()
	b.mesh = block_mesh
	b.material_override = carry_mat
	add_child(b)
	b.position = pos
	var dir := Vector3(pos.x, 0, pos.z)
	if dir.length() < 0.3:
		dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var to := pos + dir.normalized() * randf_range(4.0, 9.0) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	to.y = 0.4
	var tw := create_tween()
	tw.tween_method(_debris_step.bind(b, pos, to), 0.0, 1.0, randf_range(0.8, 1.2))
	tw.tween_property(b, "scale", Vector3.ZERO, 0.35)
	tw.tween_callback(b.queue_free)


func _debris_step(t: float, b: Node3D, a: Vector3, c: Vector3) -> void:
	var p := a.lerp(c, t)
	p.y += sin(t * PI) * 3.0
	b.position = p
	b.rotation = Vector3(t * 7.0, t * 3.0, t * 5.0)


func _complete() -> void:
	celebrating = true
	var top: Vector3 = slots[slots.size() - 1]
	capstone.position = top + Vector3(0, 1.5, 0)
	capstone.scale = Vector3.ONE * 0.01
	capstone.visible = true
	var tw := create_tween()
	tw.tween_property(capstone, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(capstone, "position:y", top.y + 1.0, 0.6)
	fx.party(top + Vector3(0, 1.5, 0))
	for w in workers:
		w.jump()
	var list := round_credit.values()
	list.sort_custom(func(a, b): return a.blocks > b.blocks)
	var next_theme: Dictionary = world.THEMES[(theme_i + 1) % world.THEMES.size()]
	if args.has("reel"):
		ui.popup("COMPLETE!")
	else:
		ui.show_board(pyramid_no, list, str(next_theme.name))
	get_tree().create_timer(7.0).timeout.connect(_next_pyramid)


func _next_pyramid() -> void:
	ui.hide_board()
	var layers := float(slots[slots.size() - 1].y) + 2.0
	var tw := create_tween()
	tw.tween_property(mmi, "position:y", -layers, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(capstone, "position:y", capstone.position.y - layers, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_advance)
	shake = 0.6
	fx.boom(Vector3(0, 0.3, 0))


func _advance() -> void:
	pyr_size = mini(pyr_size + 2, MAX_SIZE)
	pyramid_no += 1
	theme_i = (theme_i + 1) % world.THEMES.size()
	_new_pyramid()
	celebrating = false


# ---------- workers ----------
func _spawn_worker(uid: String, uname: String, walk_in: bool, skin := ""):
	var w = WorkerScript.new()
	add_child(w)
	if skin == "":
		skin = "worker" if uid == "" else WorkerScript.COMMON.pick_random()
	w.setup(self, uid, uname, skin)
	if walk_in:
		w.position = quarry_pos + Vector3(6.0, 0, 3.0)
		w.target = quarry_point()
		w.state = WorkerScript.WANDER
		w.jump()
	else:
		w.position = quarry_point()
	workers.append(w)
	if uid != "":
		by_user[uid] = w
	return w


## kind: "like" (temporary worker), "gift" or "follow" (stays). coins picks a fancier skin for bigger gifts.
func _ensure_worker(u: Dictionary, kind := "gift", coins := 0):
	var uid := str(u.get("id", ""))
	if uid == "" or uid == "anon":
		return null
	var now := Time.get_ticks_msec() / 1000.0
	var w = by_user.get(uid)
	if w == null or not is_instance_valid(w) or w.state == WorkerScript.GONE:
		if workers.size() >= MAX_WORKERS:
			_evict_one()
		var skin := ""
		if kind != "like":
			skin = _gift_skin(coins)
		w = _spawn_worker(uid, str(u.get("name", uid)), true, skin)
		w.like_only = kind == "like"
		w.set_level(level_of(uid))
	else:
		w.jump()
		if kind != "like":
			w.like_only = false
			var better := _gift_skin(coins)
			if better != "" and not WorkerScript.ROYAL.has(w.skin) and w.skin != "gold_pharaoh":
				w.set_skin(better)
			elif coins >= 100 and w.skin != "gold_pharaoh":
				w.set_skin("gold_pharaoh")
	w.last_seen = now
	return w


func _gift_skin(coins: int) -> String:
	if coins >= 100:
		return "gold_pharaoh"
	if coins >= 10:
		return ["pharaoh", "anubis", "cleopatra"].pick_random()
	return WorkerScript.ROYAL.pick_random() if randf() < 0.5 else WorkerScript.COMMON.pick_random()


func _remove_worker(w) -> void:
	workers.erase(w)
	if by_user.get(w.user_id) == w:
		by_user.erase(w.user_id)
	w.vanish()


func _evict_one() -> void:
	var victim = null
	for w in workers:   # oldest idle likes-only worker first, then any named worker
		if not w.npc and w.like_only and (victim == null or w.last_seen < victim.last_seen):
			victim = w
	if victim == null:
		for w in workers:
			if not w.npc:
				victim = w
				break
	if victim != null:
		_remove_worker(victim)


func _credit(u: Dictionary, n: int) -> void:
	_tally(top_builders, u, n)
	var uid := str(u.get("id", "anon"))
	if not round_credit.has(uid):
		round_credit[uid] = {"name": str(u.get("name", uid)), "blocks": 0, "avatar": ""}
	round_credit[uid].blocks += n
	if u.get("avatar") != null and str(u.get("avatar")) != "":
		round_credit[uid].avatar = str(u.get("avatar"))


func _tally(board: Dictionary, u: Dictionary, n: int) -> void:
	var uid := str(u.get("id", ""))
	if uid == "" or uid == "anon" or n <= 0:
		return
	if not board.has(uid):
		board[uid] = {"name": str(u.get("name", uid)), "n": 0, "avatar": ""}
	board[uid].n += n
	board[uid].name = str(u.get("name", board[uid].name))
	if u.get("avatar") != null and str(u.get("avatar")) != "":
		board[uid].avatar = str(u.get("avatar"))
	tops_dirty = true


func _sorted_top(board: Dictionary) -> Array:
	var list := []
	for uid in board.keys():
		var e: Dictionary = board[uid].duplicate()
		e["level"] = level_of(uid)
		list.append(e)
	list.sort_custom(func(a, b): return a.n > b.n)
	return list.slice(0, 5)


# ---------- events ----------
func _on_event(d: Dictionary) -> void:
	var u: Dictionary = d.get("user", {}) if d.get("user") is Dictionary else {}
	match str(d.get("type", "")):
		"gift", "quake":
			_tally(top_donors, u, int(d.get("coins", d.get("blocks", 1))))
			_add_stat(u, "coins", int(d.get("coins", 1)))
		"like":
			_tally(top_likers, u, int(d.get("likes", 1)))
			_add_stat(u, "likes", int(d.get("likes", 1)))
	_handle_event(d, u)
	_sync_level(u)


func _handle_event(d: Dictionary, u: Dictionary) -> void:
	match str(d.get("type", "")):
		"snapshot":
			var c = d.get("config", {})
			if c is Dictionary and c.has("likesPerBlock"):
				likes_per_block = maxi(1, int(c.likesPerBlock))
			if c is Dictionary and c.has("blocksPerDiamond"):
				blocks_per_coin = maxi(1, int(c.blocksPerDiamond))
			ui.set_rules(likes_per_block, blocks_per_coin)
		"gift":
			var n := int(d.get("blocks", 1))
			pending += n
			_credit(u, n)
			_ensure_worker(u, "gift", int(d.get("coins", n)))
			var cnt := int(d.get("count", 1))
			var gname := str(d.get("giftName", "Gift"))
			ui.show_banner(u, "%s%s  +%d BLOCKS" % [gname, (" x%d" % cnt) if cnt > 1 else "", n])
			fx.gift_sound()
			if n >= 50:
				ui.popup("+%d BLOCKS!" % n)
		"quake":
			var power := int(d.get("power", 1))
			_ensure_worker(u, "gift", power)
			ui.show_banner(u, "%s  EARTHQUAKE!" % str(d.get("giftName", "GG")), Color(1, 0.45, 0.3))
			ui.popup("EARTHQUAKE!", Color(1, 0.45, 0.3))
			fx.gift_sound()
			quake(power)
		"follow":
			var n := int(d.get("blocks", 5))
			pending += n
			_credit(u, n)
			_ensure_worker(u, "follow", 10)
			ui.show_banner(u, "JOINED THE CREW!  +%d" % n, Color(0.45, 0.9, 1.0))
			fx.follow_sound()
		"like":
			# every viewer has their own like counter: each 5 likes spawn their worker and give it 1 block to place
			var uid := str(u.get("id", ""))
			var likes := int(d.get("likes", 1))
			if uid == "" or uid == "anon":
				like_acc += likes
				var g := like_acc / likes_per_block
				if g > 0:
					like_acc -= g * likes_per_block
					pending += g
				return
			var acc: int = int(user_likes.get(uid, 0)) + likes
			var got := acc / likes_per_block
			user_likes[uid] = acc - got * likes_per_block
			var w = by_user.get(uid)
			if got > 0:
				w = _ensure_worker(u, "like")
				w.own += got
				_credit(u, got)
			elif w != null and is_instance_valid(w):
				w.last_seen = Time.get_ticks_msec() / 1000.0


# ---------- loop ----------
func _process(delta: float) -> void:
	var total := slots.size()
	speed_mult = 1.0 + minf(pending, 200.0) / 90.0
	world.set_pile(pending)
	if not celebrating and next_slot < total:
		if pending > RAIN_THRESHOLD:
			rain_t += delta
			var interval := clampf(0.25 - pending / 2500.0, 0.04, 0.25)
			while rain_t > interval and pending > RAIN_THRESHOLD:
				rain_t -= interval
				_rain_block()
		elif pending == 0:
			idle_t += delta
			if idle_t > IDLE_BLOCK_EVERY:
				idle_t = 0.0
				pending += 1
	for i in pop_anim.keys():
		var t: float = pop_anim[i] + delta
		if t >= 0.28:
			pop_anim.erase(i)
			mm.set_instance_transform(i, Transform3D(Basis(), slots[i]))
		else:
			pop_anim[i] = t
			var s := 1.0 + 0.22 * sin(t / 0.28 * PI)
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, 2.0 - s, s)), slots[i]))
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 1.2)
		cam.h_offset = randf_range(-1, 1) * shake * 0.7
		cam.v_offset = randf_range(-1, 1) * shake * 0.7
	tops_t += delta
	if tops_dirty and tops_t > 1.0:
		tops_t = 0.0
		tops_dirty = false
		ui.set_top(ui.top_likes_rows, _sorted_top(top_builders))
		ui.set_top(ui.top_donors_rows, _sorted_top(top_donors))
	ttl_t += delta
	if ttl_t > 0.5:
		ttl_t = 0.0
		var now := Time.get_ticks_msec() / 1000.0
		for w in workers.duplicate():
			if w.npc or not w.like_only:
				continue
			var idle: float = now - w.last_seen
			# leave after 15 s without likes once the hands are empty (hard limit 25 s)
			if idle > LIKE_WORKER_TTL and ((w.carry == 0 and w.own == 0) or idle > LIKE_WORKER_TTL + 10.0):
				user_likes.erase(w.user_id)
				_remove_worker(w)
	perf_t += delta
	if perf_t > 2.0:
		perf_t = 0.0
		net.send({"type": "perf", "fps": Engine.get_frames_per_second(), "ua": "Godot PyramidLive",
			"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"workers": workers.size(), "pending": pending, "placed": placed_count, "total": total,
			"w": get_viewport().size.x, "h": get_viewport().size.y})
	if args.has("reel"):
		_reel(delta)
	if args.has("demo"):
		demo_t -= delta
		if demo_t <= 0.0:
			demo_t = randf_range(0.6, 2.0)
			_demo_event(["like", "like", "like", "gift", "gift", "follow"].pick_random())


# ---------- scripted clip for TikTok (--reel, ~13.5 s) ----------
var reel_t := 0.0
var reel_like_t := 0.0
var reel_done := {}
const REEL_CAST := [   # name, level, skin
	["pharaoh_max", 22, "gold_pharaoh"], ["cleo_patra", 6, "cleopatra"], ["desert_fox", 3, "explorer"],
	["anubis_fan", 12, "anubis"], ["mummy_mia", 1, "mummy"], ["scarab77", 5, "ninja"],
	["nile_boy", 2, "steve"], ["oasis_girl", 55, "pharaoh"],
]


func _reel_user(n: String) -> Dictionary:
	return {"id": n, "name": n, "avatar": "https://api.dicebear.com/9.x/thumbs/png?seed=%s&size=96" % n}


func _reel_once(key: String, at: float) -> bool:
	if reel_t >= at and not reel_done.has(key):
		reel_done[key] = true
		return true
	return false


func _reel(delta: float) -> void:
	reel_t += delta
	if _reel_once("prebuild", 0.0):   # start with a pyramid ~60% done so the quake has something to wreck
		for k in int(slots.size() * 0.6):
			_place(_reserve())
	# the cast walks in one by one, already levelled (auras) and dressed, without extra blocks or banners
	for i in REEL_CAST.size():
		if _reel_once("cast%d" % i, 0.15 + i * 0.3):
			var c: Array = REEL_CAST[i]
			viewer_stats[c[0]] = {"likes": 0, "coins": (int(c[1]) - 1) * COINS_PER_LEVEL}
			var w = _spawn_worker(c[0], c[0], true, c[2])
			w.like_only = false
			w.set_level(int(c[1]))
			_tally(top_builders, _reel_user(c[0]), 40 + int(c[1]) * 9)
	reel_like_t -= delta
	if reel_t > 1.0 and reel_t < 10.0 and reel_like_t <= 0.0:
		reel_like_t = 0.3
		_on_event({"type": "like", "user": _reel_user(REEL_CAST.pick_random()[0]), "likes": 15})
	if _reel_once("galaxy", 3.6):
		_on_event({"type": "gift", "user": _reel_user("oasis_girl"), "giftName": "Galaxy", "count": 1, "coins": 0, "blocks": 60})
	if _reel_once("quake", 7.4):
		_on_event({"type": "quake", "user": _reel_user("anubis_fan"), "giftName": "GG", "power": 18, "coins": 0})
	if _reel_once("lion", 9.2):
		_on_event({"type": "gift", "user": _reel_user("pharaoh_max"), "giftName": "Lion", "count": 1, "coins": 0, "blocks": 80})
	if reel_t > 10.6 and not celebrating and next_slot < slots.size():
		for k in 4:   # capstone lands at the end of the track
			if next_slot < slots.size():
				_place(_reserve())


# ---------- demo / test ----------
const NAMES := ["pharaoh_max", "desert_fox", "sandy", "cleo_patra", "mummy_mia", "ra_ra", "anubis_fan",
	"camel_rider", "oasis_girl", "scarab77", "nile_boy", "sphinxy"]


func _fake_user() -> Dictionary:
	var n: String = NAMES.pick_random()
	return {"id": n, "name": n, "avatar": null}


func _demo_event(kind: String) -> void:
	match kind:
		"like":
			_on_event({"type": "like", "user": _fake_user(), "likes": randi_range(5, 25)})
		"gift":
			var d: int = [1, 1, 1, 5, 10, 30, 99].pick_random()
			_on_event({"type": "gift", "user": _fake_user(), "giftName": ["Rose", "Heart", "Donut", "Perfume", "Hat"].pick_random(), "count": 1, "blocks": d})
		"big":
			_on_event({"type": "gift", "user": _fake_user(), "giftName": "Galaxy", "count": 1, "blocks": 300})
		"follow":
			_on_event({"type": "follow", "user": _fake_user(), "blocks": 5})
		"quake":
			_on_event({"type": "quake", "user": _fake_user(), "giftName": "GG", "power": 5})


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if not args.has("debug"):   # test keys would create fake viewers on stream
		return
	match e.keycode:
		KEY_L: _demo_event("like")
		KEY_G: _demo_event("gift")
		KEY_H: _demo_event("big")
		KEY_F: _demo_event("follow")
		KEY_B: _demo_event("quake")
		KEY_K:
			for i in 10:
				_demo_event("like")
		KEY_E:
			while next_slot < slots.size():
				_place(_reserve())
		KEY_D:
			ui.fps_label.visible = not ui.fps_label.visible


func _take_shot() -> void:
	var delay := float(args.get("shot-delay", "6"))
	if args.has("shot-events"):
		for k in str(args["shot-events"]).split(","):
			if k == "E" or k == "half":
				var upto := slots.size() - 3 if k == "E" else slots.size() / 2
				while next_slot < upto:
					var i := _reserve()
					slot_state[i] = 2
					placed_count += 1
					mm.set_instance_transform(i, Transform3D(Basis(), slots[i]))
			else:
				_demo_event(k)
	await get_tree().create_timer(delay).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(str(args.shot))
	print("[shot] saved ", args.shot, " fps=", Engine.get_frames_per_second())
	if args.has("quit"):
		get_tree().quit()
