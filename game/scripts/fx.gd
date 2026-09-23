extends Node3D
## Particles (dust puffs, confetti, quake dust) and sounds (block thud, meme gift clips, follow thanks).

var game
var dust_pool: Array = []
var dust_i := 0
var dust_cool := 0.0
var confetti: GPUParticles3D
var boom_p: GPUParticles3D
var soft_mat: StandardMaterial3D

var thud_player: AudioStreamPlayer
var meme_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer
var memes: Array = []
var last_meme := -1
var follow_stream: AudioStreamMP3
var obama_stream: AudioStreamMP3
var obama_next := false
var thud_cool := 0.0


func setup(g) -> void:
	game = g
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	soft_mat = StandardMaterial3D.new()
	soft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	soft_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	soft_mat.vertex_color_use_as_albedo = true
	soft_mat.albedo_texture = gt
	for i in 20:
		dust_pool.append(_make_dust(14, 0.75, Color(1, 0.94, 0.8, 0.9), 2.4))
	boom_p = _make_dust(90, 2.2, Color(0.9, 0.72, 0.5, 0.95), 7.0)
	confetti = _make_confetti()

	thud_player = AudioStreamPlayer.new()
	thud_player.stream = _make_thud()
	thud_player.max_polyphony = 6
	thud_player.volume_db = -4.0
	add_child(thud_player)
	meme_player = AudioStreamPlayer.new()
	add_child(meme_player)
	voice_player = AudioStreamPlayer.new()
	voice_player.finished.connect(_on_voice_done)
	add_child(voice_player)
	for f in DirAccess.get_files_at("res://sounds"):
		if f.begins_with("gift-") and f.ends_with(".mp3"):
			memes.append(_mp3("res://sounds/" + f))
	follow_stream = _mp3("res://sounds/follow.mp3")
	obama_stream = _mp3("res://sounds/thanks-obama.mp3")


func _mp3(path: String) -> AudioStreamMP3:
	var s := AudioStreamMP3.new()
	s.data = FileAccess.get_file_as_bytes(path)
	return s


func _process(delta: float) -> void:
	dust_cool -= delta
	thud_cool -= delta


# ---------- particles ----------
func _make_dust(amount: int, size: float, color: Color, vel: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 1.0
	p.explosiveness = 0.95
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 10, 16))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 75.0
	m.initial_velocity_min = vel * 0.4
	m.initial_velocity_max = vel
	m.gravity = Vector3(0, -2.0, 0)
	m.damping_min = 2.0
	m.damping_max = 3.5
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.5, 0.05, 0.5) * (size / 0.75)
	m.scale_min = 0.6
	m.scale_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1, 0.5))
	var ct := CurveTexture.new()
	ct.curve = c
	m.scale_curve = ct
	var g := Gradient.new()
	g.colors = PackedColorArray([color, Color(color.r, color.g, color.b, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = soft_mat
	p.draw_pass_1 = q
	add_child(p)
	return p


func _make_confetti() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 500
	p.lifetime = 3.5
	p.explosiveness = 0.9
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 40, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 40.0
	m.initial_velocity_min = 9.0
	m.initial_velocity_max = 17.0
	m.gravity = Vector3(0, -6.0, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.0
	m.angular_velocity_min = -400.0
	m.angular_velocity_max = 400.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 0.25, 0.3), Color(1, 0.8, 0.1), Color(0.2, 0.85, 0.35),
		Color(0.2, 0.6, 1), Color(0.8, 0.3, 1), Color(1, 0.5, 0.1)])
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_initial_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.18)
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	cm.vertex_color_use_as_albedo = true
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = cm
	p.draw_pass_1 = q
	add_child(p)
	return p


func dust(pos: Vector3) -> void:
	if dust_cool > 0.0:
		return
	dust_cool = 0.04
	var p: GPUParticles3D = dust_pool[dust_i]
	dust_i = (dust_i + 1) % dust_pool.size()
	p.global_position = pos
	p.restart()
	p.emitting = true


func boom(pos: Vector3) -> void:
	boom_p.global_position = pos
	boom_p.restart()
	boom_p.emitting = true


func party(pos: Vector3) -> void:
	confetti.global_position = pos
	confetti.restart()
	confetti.emitting = true


# ---------- sound ----------
func _make_thud() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.22)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var f := lerpf(170.0, 55.0, minf(t / 0.12, 1.0))
		ph += TAU * f / rate
		var v := sin(ph) * exp(-t * 20.0) * 0.8 + (randf() * 2.0 - 1.0) * exp(-t * 80.0) * 0.4
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s


func thud() -> void:
	if thud_cool > 0.0:
		return
	thud_cool = 0.05
	thud_player.pitch_scale = randf_range(0.8, 1.25)
	thud_player.play()


func gift_sound() -> void:
	# one meme at a time; never the same twice in a row
	if meme_player.playing or memes.is_empty():
		return
	var i := randi() % memes.size()
	if i == last_meme and memes.size() > 1:
		i = (i + 1) % memes.size()
	last_meme = i
	meme_player.stream = memes[i]
	meme_player.play()


func follow_sound() -> void:
	if voice_player.playing:
		return
	voice_player.stream = follow_stream
	obama_next = true
	voice_player.play()


func _on_voice_done() -> void:
	if obama_next:
		obama_next = false
		voice_player.stream = obama_stream
		voice_player.play()
