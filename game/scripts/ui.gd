extends CanvasLayer
## HUD in 1080x1920 logical pixels: pyramid progress, rules, gift/follow banners with avatars,
## big popups and the end-of-pyramid leaderboard. The bottom ~27% stays clear for TikTok chat.

const BROWN := Color(0.22, 0.11, 0.02)
const GOLD := Color(1.0, 0.8, 0.22)

var game
var font: Font
var root: Control
var title: Label
var bar_fill: Panel
var count_label: Label
var rules: Label
var banner: PanelContainer
var banner_avatar: TextureRect
var banner_name: Label
var banner_text: Label
var banner_queue: Array = []
var banner_busy := false
var banner_url := ""
var popup_label: Label
var board: PanelContainer
var board_title: Label
var board_list: VBoxContainer
var fps_label: Label
var top_likes_rows: Array = []
var top_donors_rows: Array = []
var avatar_cache := {}
var placeholder: Texture2D
var bar_w := 780.0


func setup(g) -> void:
	game = g
	font = g.font
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_progress()
	_build_banner()
	_build_board()
	top_likes_rows = _build_top(Vector2(28, 404), "TOP LIKERS", Color(1, 0.55, 0.62))
	top_donors_rows = _build_top(Vector2(552, 404), "TOP DONORS", GOLD)
	popup_label = _label("", 110, GOLD, 26)
	popup_label.position = Vector2(0, 880)
	popup_label.size = Vector2(1080, 160)
	popup_label.pivot_offset = Vector2(540, 80)
	popup_label.modulate.a = 0.0
	root.add_child(popup_label)
	fps_label = _label("", 28, Color.WHITE, 8)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	fps_label.position = Vector2(20, 1860)
	fps_label.visible = g.args.has("debug")
	root.add_child(fps_label)
	var pg := Gradient.new()
	pg.colors = PackedColorArray([Color(1, 0.75, 0.3), Color(0.85, 0.45, 0.15)])
	var pt := GradientTexture2D.new()
	pt.gradient = pg
	pt.fill = GradientTexture2D.FILL_RADIAL
	pt.fill_from = Vector2(0.5, 0.3)
	pt.fill_to = Vector2(0.5, 1.0)
	placeholder = pt


func _label(text: String, size: int, color := Color.WHITE, outline := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", BROWN)
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _flat(bg: Color, radius: int, border := 0, border_color := Color.WHITE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.anti_aliasing = true
	return s


func _build_progress() -> void:
	title = _label("", 66, Color.WHITE, 18)   # kept for set_progress(), not shown
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", _flat(Color(0.15, 0.08, 0.02, 0.6), 26, 5, Color(1, 0.95, 0.8)))
	bg.position = Vector2(150, 262)
	bg.size = Vector2(780, 52)
	root.add_child(bg)
	bar_fill = Panel.new()
	bar_fill.add_theme_stylebox_override("panel", _flat(GOLD, 20))
	bar_fill.position = Vector2(156, 268)
	bar_fill.size = Vector2(0, 40)
	root.add_child(bar_fill)
	bar_w = 768.0
	count_label = _label("0 / 0", 34, Color.WHITE, 10)
	count_label.position = Vector2(150, 262)
	count_label.size = Vector2(780, 52)
	root.add_child(count_label)
	rules = _label("", 29, Color(1, 0.97, 0.88), 10)
	rules.position = Vector2(0, 318)
	rules.size = Vector2(1080, 80)
	root.add_child(rules)


func set_rules(likes_per_block: int) -> void:
	rules.text = "%d LIKES = 1 BLOCK  •  1 COIN = 1 BLOCK\nFOLLOW = YOUR OWN WORKER  •  GG = EARTHQUAKE" % likes_per_block


func set_progress(no: int, done: int, total: int) -> void:
	title.text = "PYRAMID #%d" % no
	count_label.text = "%d / %d" % [done, total]
	var w := 0.0 if total == 0 else bar_w * float(done) / float(total)
	bar_fill.size.x = maxf(w, 0.0)
	bar_fill.visible = w >= 40.0


func _build_banner() -> void:
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", _flat(Color(0.14, 0.08, 0.02, 0.86), 36, 6, GOLD))
	banner.position = Vector2(90, 720)
	banner.custom_minimum_size = Vector2(900, 150)
	banner.size = Vector2(900, 150)
	banner.pivot_offset = Vector2(450, 75)
	banner.modulate.a = 0.0
	root.add_child(banner)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	banner.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	m.add_child(h)
	banner_avatar = TextureRect.new()
	banner_avatar.custom_minimum_size = Vector2(118, 118)
	banner_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat d = length(UV - vec2(0.5));\n\tc.a *= 1.0 - smoothstep(0.47, 0.5, d);\n\tCOLOR = c;\n}\n"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	banner_avatar.material = sm
	h.add_child(banner_avatar)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	banner_name = _label("", 46, GOLD, 12)
	banner_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	banner_name.clip_text = true
	banner_name.custom_minimum_size = Vector2(700, 0)
	v.add_child(banner_name)
	banner_text = _label("", 38, Color.WHITE, 10)
	banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	banner_text.clip_text = true
	banner_text.custom_minimum_size = Vector2(700, 0)
	v.add_child(banner_text)


func show_banner(user: Dictionary, text: String, color := GOLD) -> void:
	banner_queue.append({"user": user, "text": text, "color": color})
	if banner_queue.size() > 12:
		banner_queue.pop_front()
	if not banner_busy:
		_next_banner()


func _next_banner() -> void:
	if banner_queue.is_empty():
		banner_busy = false
		return
	banner_busy = true
	var b: Dictionary = banner_queue.pop_front()
	var u: Dictionary = b.user
	banner_name.text = str(u.get("name", "Someone"))
	banner_name.add_theme_color_override("font_color", b.color)
	banner_text.text = b.text
	var st: StyleBoxFlat = banner.get_theme_stylebox("panel")
	st.border_color = b.color
	_load_avatar(str(u.get("avatar", "")) if u.get("avatar") != null else "")
	var hold := 1.3 if banner_queue.size() > 3 else 2.6
	banner.scale = Vector2(0.7, 0.7)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.18)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(banner, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(_next_banner)


func _load_avatar(url: String) -> void:
	banner_url = url
	if url == "":
		banner_avatar.texture = placeholder
		return
	if avatar_cache.has(url):
		banner_avatar.texture = avatar_cache[url]
		return
	banner_avatar.texture = placeholder
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_avatar.bind(url, req))
	if req.request(url) != OK:
		req.queue_free()


func _on_avatar(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, url: String, req: HTTPRequest) -> void:
	req.queue_free()
	if code != 200 or body.size() < 16:
		return
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if body[0] == 0xFF and body[1] == 0xD8:
		err = img.load_jpg_from_buffer(body)
	elif body[0] == 0x89 and body[1] == 0x50:
		err = img.load_png_from_buffer(body)
	elif body[0] == 0x52 and body[8] == 0x57:
		err = img.load_webp_from_buffer(body)
	if err != OK:
		return
	var tex := ImageTexture.create_from_image(img)
	avatar_cache[url] = tex
	if banner_url == url:
		banner_avatar.texture = tex


# ---------- live leaderboards (whole stream) ----------
func _build_top(pos: Vector2, heading: String, color: Color) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(Color(0.14, 0.08, 0.02, 0.62), 26, 4, color))
	p.position = pos
	p.custom_minimum_size = Vector2(500, 0)
	root.add_child(p)
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	p.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	m.add_child(v)
	v.add_child(_label(heading, 34, color, 10))
	var rows := []
	for i in 5:
		var h := HBoxContainer.new()
		v.add_child(h)
		var name := _label("", 29, Color.WHITE, 8)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.clip_text = true
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := _label("", 29, color, 8)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.custom_minimum_size = Vector2(110, 0)
		h.add_child(name)
		h.add_child(val)
		rows.append([name, val])
	rows[0][0].text = "—"
	return rows


static func short_num(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fK" % (n / 1000.0)
	return str(n)


## entries: [{name, n}] sorted high to low
func set_top(rows: Array, entries: Array) -> void:
	var medals := [GOLD, Color(0.85, 0.88, 0.95), Color(0.95, 0.6, 0.3)]
	for i in rows.size():
		var r: Array = rows[i]
		if i < entries.size():
			r[0].text = "%d. %s" % [i + 1, str(entries[i].name).substr(0, 14)]
			r[0].add_theme_color_override("font_color", medals[i] if i < 3 else Color.WHITE)
			r[1].text = short_num(int(entries[i].n))
		else:
			r[0].text = "—" if i == 0 and entries.is_empty() else ""
			r[1].text = ""


func popup(text: String, color := GOLD) -> void:
	popup_label.text = text
	popup_label.add_theme_color_override("font_color", color)
	popup_label.scale = Vector2(0.4, 0.4)
	popup_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(popup_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(popup_label, "modulate:a", 0.0, 0.4)


func _build_board() -> void:
	board = PanelContainer.new()
	board.add_theme_stylebox_override("panel", _flat(Color(0.14, 0.08, 0.02, 0.9), 40, 7, GOLD))
	board.position = Vector2(120, 880)
	board.custom_minimum_size = Vector2(840, 0)
	board.pivot_offset = Vector2(420, 300)
	board.visible = false
	root.add_child(board)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 34)
	board.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	board_title = _label("", 62, GOLD, 16)
	v.add_child(board_title)
	var sub := _label("TOP BUILDERS", 38, Color.WHITE, 10)
	v.add_child(sub)
	board_list = VBoxContainer.new()
	board_list.add_theme_constant_override("separation", 8)
	v.add_child(board_list)


func show_board(no: int, top: Array, theme_name: String) -> void:
	board_title.text = "PYRAMID #%d DONE!" % no
	for c in board_list.get_children():
		c.queue_free()
	if top.is_empty():
		board_list.add_child(_label("The workers did it alone!", 40, Color(1, 0.95, 0.85), 10))
	var medals := [Color(1, 0.84, 0.2), Color(0.85, 0.88, 0.95), Color(0.95, 0.6, 0.3)]
	for i in mini(top.size(), 5):
		var e: Dictionary = top[i]
		var l := _label("%d.  %s  —  %d" % [i + 1, str(e.name).substr(0, 16), int(e.blocks)], 44,
			medals[i] if i < 3 else Color.WHITE, 12)
		board_list.add_child(l)
	board_list.add_child(_label("Next: " + theme_name, 34, Color(0.8, 0.95, 1.0), 10))
	board.visible = true
	board.scale = Vector2(0.6, 0.6)
	board.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(board, "modulate:a", 1.0, 0.25)
	tw.tween_property(board, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_board() -> void:
	var tw := create_tween()
	tw.tween_property(board, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): board.visible = false)


func _process(_delta: float) -> void:
	if fps_label.visible:
		fps_label.text = "%d FPS  draw %d  workers %d  pile %d" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), game.workers.size(), game.pending]
