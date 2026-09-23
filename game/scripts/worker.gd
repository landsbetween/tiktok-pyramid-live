extends Node3D
## A blocky builder: walks quarry -> pyramid with blocks on its head, throws them, walks back.

enum { IDLE, WANDER, TO_PYRAMID, THROW, BACK }

const SKIN := Color(0.98, 0.8, 0.28)
const INK := Color(0.08, 0.08, 0.1)
const CARRY_SCALE := 0.62

var game
var user_id := ""
var display_name := ""
var npc := true
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
var stack: Node3D
var label: Label3D


func setup(g, uid: String, uname: String, shirt: Color, pants: Color) -> void:
	game = g
	user_id = uid
	display_name = uname
	npc = uid == ""
	speed = randf_range(2.9, 3.5)
	anim_t = randf() * 10.0
	rig = Node3D.new()
	add_child(rig)
	leg_l = _limb(Vector3(-0.1, 0.36, 0), Vector3(0.17, 0.36, 0.2), pants)
	leg_r = _limb(Vector3(0.1, 0.36, 0), Vector3(0.17, 0.36, 0.2), pants)
	_box(rig, Vector3(0, 0.55, 0), Vector3(0.44, 0.4, 0.24), shirt)
	arm_l = _limb(Vector3(-0.29, 0.72, 0), Vector3(0.14, 0.36, 0.17), SKIN)
	arm_r = _limb(Vector3(0.29, 0.72, 0), Vector3(0.14, 0.36, 0.17), SKIN)
	# short sleeves
	_box(arm_l, Vector3(0, -0.07, 0), Vector3(0.16, 0.15, 0.19), shirt)
	_box(arm_r, Vector3(0, -0.07, 0), Vector3(0.16, 0.15, 0.19), shirt)
	var head := _box(rig, Vector3(0, 0.93, 0), Vector3(0.34, 0.34, 0.34), SKIN)
	_box(head, Vector3(-0.075, 0.035, 0.171), Vector3(0.055, 0.08, 0.01), INK)
	_box(head, Vector3(0.075, 0.035, 0.171), Vector3(0.055, 0.08, 0.01), INK)
	_box(head, Vector3(0, -0.075, 0.171), Vector3(0.13, 0.03, 0.01), INK)
	stack = Node3D.new()
	stack.position = Vector3(0, 1.1, 0)
	rig.add_child(stack)
	if not npc:
		label = Label3D.new()
		label.text = uname.substr(0, 14)
		label.font = game.font
		label.font_size = 72
		label.pixel_size = 0.0095
		label.outline_size = 22
		label.outline_modulate = Color(0.2, 0.1, 0.02)
		label.modulate = Color(1, 0.95, 0.75)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 10
		label.outline_render_priority = 9
		label.position = Vector3(0, 1.5, 0)
		add_child(label)


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
	if label:
		label.position.y = 1.5 + n * CARRY_SCALE


func jump() -> void:
	jump_t = 0.6


func _process(delta: float) -> void:
	anim_t += delta
	timer -= delta
	match state:
		IDLE:
			_pose_idle(delta)
			if timer <= 0.0:
				timer = 0.2 + randf() * 0.2
				var n: int = game.take_blocks()
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
