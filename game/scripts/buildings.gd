extends RefCounted
## Block-by-block blueprints. Every building is a list of 1x1x1 block slots in build order
## (bottom layer first, back to front) plus a colour per slot and where the crown goes.
## tier 0..4 grows the building from round to round.

const SAND := 0
const STONE := 1
const GOLD := 2
const LAPIS := 3
const WHITE := 4
const TERRA := 5
const DARK := 6

const PALETTE := {
	SAND: Color(0.97, 0.76, 0.45),
	STONE: Color(0.78, 0.6, 0.42),
	GOLD: Color(1.0, 0.8, 0.25),
	LAPIS: Color(0.22, 0.42, 0.85),
	WHITE: Color(0.97, 0.94, 0.86),
	TERRA: Color(0.86, 0.42, 0.26),
	DARK: Color(0.55, 0.42, 0.32),
}

const TYPES := ["pyramid", "ziggurat", "obelisk", "castle", "temple", "lighthouse"]
const TITLES := {
	"pyramid": "PYRAMID", "ziggurat": "ZIGGURAT", "obelisk": "OBELISK",
	"castle": "FORTRESS", "temple": "TEMPLE", "lighthouse": "LIGHTHOUSE",
}

var _cells := {}   # Vector3i -> colour code


## Returns {type, title, slots: Array[Vector3], colors: Array[int], half: float, height: float, top: Vector3, crown: String}
func make(type: String, tier: int) -> Dictionary:
	_cells.clear()
	tier = clampi(tier, 0, 4)
	var crown := "flag"
	match type:
		"ziggurat": _ziggurat(9 + tier * 2 - (2 if tier == 4 else 0))
		"obelisk":
			_obelisk(6 + tier * 2)
			crown = "pyramidion"
		"castle": _castle(9 + mini(tier, 3) * 2)
		"temple": _temple(9 + mini(tier, 3) * 2)
		"lighthouse":
			_lighthouse(2 + tier / 2, 9 + tier * 2)
			crown = "light"
		_:
			type = "pyramid"
			_pyramid(7 + tier * 2)
			crown = "pyramidion"
	var keys := _cells.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		if a.z != b.z:
			return a.z < b.z
		return a.x < b.x)
	var slots := []
	var colors := []
	var half := 0.0
	var top_y := 0
	for k in keys:
		slots.append(Vector3(k.x, k.y + 0.5, k.z))
		colors.append(_cells[k])
		half = maxf(half, maxf(absf(k.x), absf(k.z)) + 0.5)
		top_y = maxi(top_y, k.y)
	# crown sits on the highest block closest to the centre
	var top := Vector3.ZERO
	var best := 1e9
	for k in keys:
		if k.y == top_y and absf(k.x) + absf(k.z) < best:
			best = absf(k.x) + absf(k.z)
			top = Vector3(k.x, k.y + 0.5, k.z)
	return {"type": type, "title": TITLES[type], "slots": slots, "colors": colors, "half": half,
		"height": float(top_y + 1), "top": top, "crown": crown}


func _put(x: int, y: int, z: int, c: int) -> void:
	_cells[Vector3i(x, y, z)] = c


func _box(x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, c: int) -> void:
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				_put(x, y, z, c)


func _ring(r: int, y: int, c: int) -> void:   # square outline, half-width r
	for i in range(-r, r + 1):
		_put(i, y, -r, c)
		_put(i, y, r, c)
		_put(-r, y, i, c)
		_put(r, y, i, c)


# ---------- blueprints ----------
func _pyramid(n: int) -> void:
	var layer := 0
	var r := (n - 1) / 2
	while r >= 0:
		_box(-r, r, layer, layer, -r, r, SAND)
		r -= 1
		layer += 1


func _ziggurat(n: int) -> void:
	# chunky 2-block steps in alternating stone, a blue shrine with a gold roof, and a front stairway
	var r := (n - 1) / 2
	var y := 0
	var step := 0
	while r >= 2:
		_box(-r, r, y, y + 1, -r, r, SAND if step % 2 == 0 else STONE)
		_ring(r, y + 1, DARK if step % 2 == 0 else SAND)   # darker lip on each step
		r -= 2
		y += 2
		step += 1
	_box(-1, 1, y, y + 1, -1, 1, LAPIS)
	_box(-1, 1, y + 2, y + 2, -1, 1, GOLD)
	var front := (n - 1) / 2
	for k in y:   # stairway up the front face
		var z := front - k / 2
		if z >= -1:
			_put(0, k, z + 1, WHITE)


func _obelisk(shaft: int) -> void:
	_box(-3, 3, 0, 0, -3, 3, STONE)
	_box(-2, 2, 1, 1, -2, 2, SAND)
	for y in range(2, 2 + shaft):
		var c := WHITE
		if y % 3 == 0:
			c = LAPIS   # hieroglyph bands
		_box(-1, 1, y, y, -1, 1, c)
	_put(0, 2 + shaft, 0, GOLD)


func _castle(n: int) -> void:
	var r := (n - 1) / 2
	for y in 3:
		_ring(r, y, STONE)
	for i in range(-r, r + 1, 2):   # crenellations
		_put(i, 3, -r, STONE)
		_put(i, 3, r, STONE)
		_put(-r, 3, i, STONE)
		_put(r, 3, i, STONE)
	for y in 2:   # gate in the front wall
		for x in range(-1, 2):
			_cells.erase(Vector3i(x, y, r))
	for cx in [-r, r]:
		for cz in [-r, r]:
			_box(cx - 1 if cx > 0 else cx, cx if cx > 0 else cx + 1, 0, 4, cz - 1 if cz > 0 else cz, cz if cz > 0 else cz + 1, SAND)
			_put(cx, 5, cz, TERRA)
	var k := 2 if n < 13 else 3
	_box(-k, k, 0, 5, -k, k, SAND)
	_box(-k, k, 6, 6, -k, k, TERRA)
	for i in range(-k, k + 1, 2):
		_put(i, 7, -k, TERRA)
		_put(i, 7, k, TERRA)
		_put(-k, 7, i, TERRA)
		_put(k, 7, i, TERRA)
	_put(0, 7, 0, GOLD)


func _temple(n: int) -> void:
	var rx := (n - 1) / 2
	var rz := rx - 1
	_box(-rx, rx, 0, 0, -rz, rz, STONE)
	_box(-rx + 1, rx - 1, 1, 1, -rz + 1, rz - 1, WHITE)
	var cx := rx - 1
	var cz := rz - 1
	for x in range(-cx, cx + 1, 2):   # columns around the edge
		for z in [-cz, cz]:
			_box(x, x, 2, 5, z, z, WHITE)
	for z in range(-cz, cz + 1, 2):
		for x in [-cx, cx]:
			_box(x, x, 2, 5, z, z, WHITE)
	_box(-cx + 3, cx - 3, 2, 4, -cz + 3, cz - 3, SAND)   # inner sanctum
	_box(-cx, cx, 6, 6, -cz, cz, GOLD if n >= 13 else SAND)   # architrave
	var w := cz
	var y := 7
	while w >= 0:   # gable roof, ridge along x
		_box(-cx, cx, y, y, -w, w, TERRA)
		w -= 2
		y += 1


func _lighthouse(r: int, h: int) -> void:
	_box(-r - 1, r + 1, 0, 0, -r - 1, r + 1, STONE)
	for y in range(1, h + 1):
		var c := WHITE if (y / 2) % 2 == 0 else TERRA
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				var d := sqrt(x * x + z * z)
				if d <= r + 0.35 and d >= r - 0.75:
					_put(x, y, z, c)
		if y % 4 == 2:
			_cells.erase(Vector3i(0, y, r))   # windows
	for z in range(-r - 1, r + 2):   # gallery
		for x in range(-r - 1, r + 2):
			var d := sqrt(x * x + z * z)
			if d <= r + 1.4 and d >= r - 0.2:
				_put(x, h + 1, z, DARK)
	_box(-1, 1, h + 2, h + 3, -1, 1, GOLD)
