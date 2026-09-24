extends Node3D
## A blocky builder: walks quarry -> pyramid with blocks on its head, throws them, walks back.
## Wears one of several skins (pharaoh, anubis, mummy, ...) and a Minecraft-style name tag.

enum { IDLE, WANDER, TO_PYRAMID, THROW, BACK, GONE }

const INK := Color(0.08, 0.08, 0.1)
const CARRY_SCALE := 0.62
const TAG_Y := 1.55

const GOLD := Color(1.0, 0.78, 0.2)
const LAPIS := Color(0.12, 0.28, 0.75)
const LINEN := Color(0.96, 0.94, 0.86)
const TAN := Color(0.86, 0.62, 0.38)
const LIGHT := Color(0.98, 0.8, 0.6)

## Skins everyone can get (likes); ROYAL skins are for gifters.
const COMMON := ["worker", "worker", "steve", "explorer", "bedouin", "mummy", "ninja", "spartan", "cleopatra"]
const ROYAL := ["pharaoh", "anubis", "cleopatra"]

var game
var user_id := ""
var display_name := ""
var npc := true
var skin := "worker"
var like_only := false      # spawned by likes: leaves after a while without likes
var last_seen := 0.0        # seconds (engine time) of the last like/gift from this viewer
var own := 0                # blocks this viewer paid for with likes; this worker carries them itself
var state := IDLE
var target := Vector3.ZERO
var carry := 0
var speed := 3.2
var anim_t := 0.0
var timer := 0.0
var jump_t := 0.0

var rig: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var head: Node3D
var stack: Node3D
var tag: Node3D


func setup(g, uid: String, uname: String, skin_name: String) -> void:
	game = g
	user_id = uid
	display_name = uname
	npc = uid == ""
	speed = randf_range(2.9, 3.5)
	anim_t = randf() * 10.0
	last_seen = Time.get_ticks_msec() / 1000.0
	stack = Node3D.new()
	stack.position = Vector3(0, 1.1, 0)
	build(skin_name)
	if not npc:
		_make_tag(uname)


# ---------- body / skins ----------
func build(skin_name: String) -> void:
	skin = skin_name
	if rig:
		rig.remove_child(stack)
		rig.queue_free()
	rig = Node3D.new()
	add_child(rig)
	var tone := LIGHT
	var shirt := Color.from_hsv(randf(), randf_range(0.55, 0.8), randf_range(0.8, 0.95))
	var pants: Color = [Color(0.2, 0.35, 0.8), Color(0.16, 0.16, 0.22), Color(0.4, 0.28, 0.16), Color(0.2, 0.5, 0.3)].pick_random()
	var arms := tone
	var sleeves := true
	match skin:
		"pharaoh", "gold_pharaoh":
			tone = TAN; shirt = LINEN; pants = LINEN; arms = TAN; sleeves = false
			if skin == "gold_pharaoh":
				shirt = GOLD; pants = GOLD.darkened(0.15)
		"anubis":
			tone = Color(0.1, 0.1, 0.12); shirt = LINEN; pants = LINEN; arms = Color(0.1, 0.1, 0.12); sleeves = false
		"cleopatra":
			tone = TAN; shirt = LINEN; pants = LINEN; arms = TAN; sleeves = false
		"mummy":
			tone = Color(0.9, 0.87, 0.74); shirt = tone; pants = tone; arms = tone
		"explorer":
			shirt = Color(0.78, 0.68, 0.45); pants = Color(0.45, 0.33, 0.2)
		"bedouin":
			tone = TAN; shirt = Color(0.93, 0.88, 0.76); pants = shirt; arms = TAN
		"ninja":
			shirt = Color(0.1, 0.1, 0.13); pants = shirt; arms = shirt
		"spartan":
			tone = TAN; shirt = Color(0.75, 0.12, 0.1); pants = Color(0.55, 0.38, 0.2); arms = TAN; sleeves = false
		"steve":
			shirt = Color(0.0, 0.66, 0.66); pants = Color(0.22, 0.2, 0.62); tone = Color(0.78, 0.56, 0.42); arms = tone
	leg_l = _limb(Vector3(-0.1, 0.36, 0), Vector3(0.17, 0.36, 0.2), pants)
	leg_r = _limb(Vector3(0.1, 0.36, 0), Vector3(0.17, 0.36, 0.2), pants)
	var body := _box(rig, Vector3(0, 0.55, 0), Vector3(0.44, 0.4, 0.24), shirt)
	arm_l = _limb(Vector3(-0.29, 0.72, 0), Vector3(0.14, 0.36, 0.17), arms)
	arm_r = _limb(Vector3(0.29, 0.72, 0), Vector3(0.14, 0.36, 0.17), arms)
	if sleeves:
		_box(arm_l, Vector3(0, -0.07, 0), Vector3(0.16, 0.15, 0.19), shirt)
		_box(arm_r, Vector3(0, -0.07, 0), Vector3(0.16, 0.15, 0.19), shirt)
	head = _box(rig, Vector3(0, 0.93, 0), Vector3(0.34, 0.34, 0.34), tone)
	_face(skin != "ninja" and skin != "anubis")
	_dress(body)
	rig.add_child(stack)


func _face(normal: bool) -> void:
	if not normal:
		return
	var eye := INK
	if skin == "mummy":
		eye = Color(0.2, 0.9, 0.5)
	_box(head, Vector3(-0.075, 0.035, 0.171), Vector3(0.055, 0.08, 0.01), eye)
	_box(head, Vector3(0.075, 0.035, 0.171), Vector3(0.055, 0.08, 0.01), eye)
	if skin != "mummy":
		_box(head, Vector3(0, -0.075, 0.171), Vector3(0.13, 0.03, 0.01), INK)


func _dress(body: Node3D) -> void:
	match skin:
		"pharaoh", "gold_pharaoh":
			# nemes headdress with blue/gold stripes, lappets over the shoulders, beard, cobra, collar and belt
			var a := GOLD
			var b := LAPIS if skin == "pharaoh" else Color(0.95, 0.9, 0.7)
			for i in 5:
				_box(head, Vector3(0, 0.19 - i * 0.012, -0.02), Vector3(0.38 - i * 0.004, 0.012, 0.36), a if i % 2 == 0 else b)
			_box(head, Vector3(0, 0.08, -0.03), Vector3(0.38, 0.2, 0.34), b)
			for i in 4:
				_box(head, Vector3(0, 0.15 - i * 0.07, -0.03), Vector3(0.385, 0.03, 0.345), a)
			for s in [-1, 1]:
				_box(head, Vector3(s * 0.2, -0.16, 0.06), Vector3(0.07, 0.26, 0.14), b)
				_box(head, Vector3(s * 0.2, -0.1, 0.06), Vector3(0.075, 0.03, 0.145), a)
			_box(head, Vector3(0, -0.23, 0.12), Vector3(0.07, 0.14, 0.07), a)
			_box(head, Vector3(0, 0.24, 0.16), Vector3(0.05, 0.1, 0.04), a)
			_box(body, Vector3(0, 0.12, 0.01), Vector3(0.48, 0.12, 0.27), a)
			_box(body, Vector3(0, 0.05, 0.13), Vector3(0.3, 0.06, 0.02), LAPIS)
			_box(body, Vector3(0, -0.17, 0), Vector3(0.46, 0.06, 0.26), a)
			for s in [arm_l, arm_r]:
				_box(s, Vector3(0, -0.2, 0), Vector3(0.16, 0.06, 0.19), a)
		"anubis":
			_box(head, Vector3(0, -0.04, 0.2), Vector3(0.16, 0.12, 0.14), Color(0.1, 0.1, 0.12))
			_box(head, Vector3(0, -0.02, 0.28), Vector3(0.08, 0.06, 0.04), GOLD)
			for s in [-1, 1]:
				_box(head, Vector3(s * 0.1, 0.27, -0.02), Vector3(0.08, 0.22, 0.06), Color(0.1, 0.1, 0.12))
				_box(head, Vector3(s * 0.1, 0.27, 0.015), Vector3(0.04, 0.15, 0.01), GOLD)
				_box(head, Vector3(s * 0.075, 0.05, 0.171), Vector3(0.06, 0.035, 0.01), GOLD)
			_box(body, Vector3(0, 0.12, 0.01), Vector3(0.48, 0.12, 0.27), GOLD)
			_box(body, Vector3(0, -0.17, 0), Vector3(0.46, 0.06, 0.26), GOLD)
		"cleopatra":
			var hair := Color(0.06, 0.05, 0.07)
			_box(head, Vector3(0, 0.1, -0.03), Vector3(0.38, 0.2, 0.34), hair)
			_box(head, Vector3(0, 0.15, 0.16), Vector3(0.36, 0.06, 0.04), hair)
			for s in [-1, 1]:
				_box(head, Vector3(s * 0.19, -0.08, 0.0), Vector3(0.05, 0.3, 0.3), hair)
			_box(head, Vector3(0, 0.13, 0.182), Vector3(0.37, 0.035, 0.01), GOLD)
			_box(head, Vector3(0, 0.2, 0.19), Vector3(0.05, 0.08, 0.03), GOLD)
			_box(body, Vector3(0, 0.12, 0.01), Vector3(0.48, 0.1, 0.27), GOLD)
			_box(body, Vector3(0, 0.07, 0.13), Vector3(0.3, 0.04, 0.02), Color(0.2, 0.7, 0.6))
		"mummy":
			var band := Color(0.72, 0.68, 0.55)
			for y in [-0.12, 0.0, 0.1]:
				_box(body, Vector3(0, y, 0), Vector3(0.455, 0.025, 0.255), band)
			for y in [0.12, -0.02, -0.12]:
				_box(head, Vector3(0, y, 0), Vector3(0.35, 0.02, 0.35), band)
			for l in [leg_l, leg_r, arm_l, arm_r]:
				_box(l, Vector3(0, -0.15, 0), Vector3(0.18, 0.025, 0.21), band)
				_box(l, Vector3(0, -0.27, 0), Vector3(0.18, 0.025, 0.21), band)
		"explorer":
			var hat := Color(0.9, 0.84, 0.66)
			_box(head, Vector3(0, 0.2, 0), Vector3(0.5, 0.03, 0.5), hat)
			_box(head, Vector3(0, 0.26, 0), Vector3(0.34, 0.1, 0.34), hat)
			_box(head, Vector3(0, 0.23, 0), Vector3(0.35, 0.03, 0.35), Color(0.45, 0.33, 0.2))
			_box(body, Vector3(0, 0.02, -0.19), Vector3(0.34, 0.34, 0.14), Color(0.5, 0.38, 0.22))
			_box(body, Vector3(0.12, 0.0, 0.0), Vector3(0.03, 0.42, 0.25), Color(0.45, 0.33, 0.2))
		"bedouin":
			var scarf := Color(0.92, 0.9, 0.86)
			_box(head, Vector3(0, 0.1, -0.03), Vector3(0.38, 0.2, 0.35), scarf)
			for s in [-1, 1]:
				_box(head, Vector3(s * 0.19, -0.1, -0.03), Vector3(0.04, 0.3, 0.3), scarf)
			_box(head, Vector3(0, -0.05, -0.2), Vector3(0.36, 0.36, 0.04), scarf)
			_box(head, Vector3(0, 0.19, 0), Vector3(0.4, 0.04, 0.38), Color(0.12, 0.12, 0.14))
			for i in 3:
				_box(head, Vector3(-0.1 + i * 0.1, 0.15, -0.035), Vector3(0.02, 0.2, 0.36), Color(0.8, 0.15, 0.15))
			_box(body, Vector3(0, -0.28, 0), Vector3(0.46, 0.3, 0.26), Color(0.93, 0.88, 0.76))
		"ninja":
			_box(head, Vector3(0, 0.04, 0.172), Vector3(0.3, 0.08, 0.01), Color(0.85, 0.7, 0.55))
			_box(head, Vector3(-0.07, 0.04, 0.178), Vector3(0.05, 0.03, 0.01), INK)
			_box(head, Vector3(0.07, 0.04, 0.178), Vector3(0.05, 0.03, 0.01), INK)
			_box(head, Vector3(0, 0.12, 0), Vector3(0.35, 0.04, 0.35), Color(0.8, 0.1, 0.12))
			_box(head, Vector3(0.05, 0.1, -0.22), Vector3(0.04, 0.03, 0.12), Color(0.8, 0.1, 0.12))
			_box(body, Vector3(0.0, 0.0, -0.14), Vector3(0.05, 0.5, 0.05), Color(0.5, 0.5, 0.55))
		"spartan":
			var bronze := Color(0.8, 0.55, 0.22)
			_box(head, Vector3(0, 0.06, -0.01), Vector3(0.37, 0.28, 0.36), bronze)
			_box(head, Vector3(0, 0.05, 0.176), Vector3(0.06, 0.2, 0.02), bronze)
			_box(head, Vector3(0, 0.27, -0.02), Vector3(0.07, 0.12, 0.42), Color(0.85, 0.1, 0.1))
			var shield := _box(arm_l, Vector3(-0.1, -0.22, 0.02), Vector3(0.04, 0.34, 0.34), bronze)
			_box(shield, Vector3(-0.025, 0, 0), Vector3(0.01, 0.12, 0.12), Color(0.85, 0.1, 0.1))
		"steve":
			var hair := Color(0.3, 0.2, 0.1)
			_box(head, Vector3(0, 0.15, -0.01), Vector3(0.35, 0.06, 0.35), hair)
			_box(head, Vector3(0, 0.0, -0.172), Vector3(0.35, 0.3, 0.02), hair)
			_box(head, Vector3(0, -0.1, 0.172), Vector3(0.18, 0.05, 0.01), Color(0.45, 0.3, 0.2))
		_:
			if randf() < 0.6:
				var hair: Color = [Color(0.2, 0.13, 0.07), Color(0.9, 0.75, 0.3), Color(0.08, 0.06, 0.06), Color(0.7, 0.3, 0.15)].pick_random()
				_box(head, Vector3(0, 0.15, -0.01), Vector3(0.35, 0.06, 0.35), hair)
			if randf() < 0.4:
				var cap: Color = Color.from_hsv(randf(), 0.7, 0.9)
				_box(head, Vector3(0, 0.2, 0), Vector3(0.36, 0.08, 0.36), cap)
				_box(head, Vector3(0, 0.17, 0.22), Vector3(0.3, 0.03, 0.12), cap)


func set_skin(skin_name: String) -> void:
	if skin_name == skin:
		return
	var c := carry
	build(skin_name)
	set_carry(c)


# ---------- Minecraft-style name tag ----------
func _make_tag(uname: String) -> void:
	var text := uname.substr(0, 16)
	tag = Node3D.new()
	tag.position = Vector3(0, TAG_Y, 0)
	add_child(tag)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font = game.tag_font
	lbl.font_size = 16
	lbl.pixel_size = 0.026
	lbl.outline_size = 0
	lbl.modulate = Color(1, 1, 1)
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 11
	lbl.shaded = false
	tag.add_child(lbl)
	var sz: Vector2 = game.tag_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(sz.x * 0.026 + 0.16, 16 * 0.026 + 0.08)
	q.mesh = qm
	q.material_override = game.tag_bg_mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tag.add_child(q)


# ---------- helpers ----------
func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = game.box_mesh(size)
	mi.material_override = game.mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(pivot: Vector3, size: Vector3, color: Color) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	rig.add_child(p)
	_box(p, Vector3(0, -size.y * 0.5, 0), size, color)
	return p


func set_carry(n: int) -> void:
	carry = n
	for c in stack.get_children():
		c.queue_free()
	for i in n:
		var b := MeshInstance3D.new()
		b.mesh = game.block_mesh
		b.material_override = game.carry_mat
		b.scale = Vector3.ONE * CARRY_SCALE
		b.position = Vector3(0, CARRY_SCALE * (0.5 + i), 0)
		stack.add_child(b)
	if tag:
		tag.position.y = TAG_Y + n * CARRY_SCALE


func jump() -> void:
	jump_t = 0.6


## Poof: shrink away with a dust cloud; any blocks it still had go back to the shared pile.
func vanish() -> void:
	if state == GONE:
		return
	state = GONE
	game.pending += carry + own
	own = 0
	set_carry(0)
	game.fx.dust(global_position + Vector3(0, 0.4, 0))
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.25, 1.25, 1.25), 0.12)
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	if state == GONE:
		return
	anim_t += delta
	timer -= delta
	match state:
		IDLE:
			_pose_idle(delta)
			if timer <= 0.0:
				timer = 0.2 + randf() * 0.2
				var n: int = game.take_blocks_for(self)
				if n > 0:
					set_carry(n)
					target = game.drop_point()
					state = TO_PYRAMID
				elif randf() < 0.08:
					target = game.quarry_point()
					state = WANDER
		WANDER:
			if _walk(delta, 0.5):
				state = IDLE
		TO_PYRAMID:
			if _walk(delta, 1.0):
				state = THROW
				timer = 0.22
				var to: Vector3 = game.aim_point() - position
				rotation.y = atan2(to.x, to.z)
		THROW:
			var k := clampf(1.0 - timer / 0.22, 0.0, 1.0)
			arm_l.rotation.x = lerpf(PI + 0.15, PI * 0.55, k)
			arm_r.rotation.x = arm_l.rotation.x
			if timer <= 0.0:
				game.throw_blocks(stack.global_position, carry, user_id)
				set_carry(0)
				target = game.quarry_point()
				state = BACK
		BACK:
			if _walk(delta, 1.0):
				state = IDLE
				timer = randf() * 0.3
	if jump_t > 0.0:
		jump_t = maxf(0.0, jump_t - delta)
		rig.position.y = sin((1.0 - jump_t / 0.6) * PI) * 0.8


func _walk(delta: float, speed_k: float) -> bool:
	var to := target - position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.08:
		return true
	var step: float = minf(dist, speed * speed_k * game.speed_mult * delta)
	position += to / dist * step
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, 12.0 * delta))
	var f: float = 13.0 * game.speed_mult * speed_k
	var swing := sin(anim_t * f) * 0.7
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	if carry > 0:
		arm_l.rotation.x = PI + 0.15
		arm_r.rotation.x = PI + 0.15
	else:
		arm_l.rotation.x = -swing * 0.8
		arm_r.rotation.x = swing * 0.8
	if jump_t <= 0.0:
		rig.position.y = absf(sin(anim_t * f)) * 0.05
	return false


func _pose_idle(delta: float) -> void:
	var k := minf(1.0, 10.0 * delta)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, k)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, k)
	var sway := sin(anim_t * 2.0) * 0.08
	arm_l.rotation.x = lerpf(arm_l.rotation.x, sway, k)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -sway, k)
	if jump_t <= 0.0:
		rig.position.y = lerpf(rig.position.y, 0.0, k)
