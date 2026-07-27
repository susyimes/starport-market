extends Control
## Living market strip v3: layered night dock, warm stall glow, ground reflections,
## strolling customers with stall pauses, tiered light motes.
## API frozen (spec §0): set_mode(m), set_focus_group(gid), tick(delta).

const GROUPS := [
	{"key": "dock_workers", "tex": "res://assets/characters/customer_dock.png"},
	{"key": "transit_pilots", "tex": "res://assets/characters/customer_pilot.png"},
	{"key": "star_tourists", "tex": "res://assets/characters/customer_tourist.png"},
	{"key": "night_monks", "tex": "res://assets/characters/customer_monk.png"},
	{"key": "scrap_traders", "tex": "res://assets/characters/customer_scrap.png"},
	{"key": "luxe_envoys", "tex": "res://assets/characters/customer_luxe.png"},
]

const LIME := Color("#B8FF3D")
const GOLD := Color("#FFD166")
const VIOLET := Color("#9A7BFF")
const CYAN := Color("#4DE3FF")
const MAGENTA := Color("#FF6EE7")

const VENDOR_TOP := 0.56
const VENDOR_BOTTOM := 0.96
const GROUND_NEAR := 0.99   # near-lane baseline on the dock plating
const GROUND_FAR := 0.92    # far lane stands higher up the plating (depth), never on the skyline
const BG_HORIZON := 0.76    # dock ground starts here in bg_dock (205/270)
const ART_W := 32.0         # customer sprite base art size (gen_art 32×44)
const ART_H := 44.0

var mode: String = "ambient"  # ambient | living
var _t: float = 0.0
var _focus_group: String = ""
var _customers: Array = []  # {node, glow, group, idle_x, x, dir, speed, pause, can_pause, lane_y, scale, phase}
var _motes: Array = []      # {node, x, y, speed, drift, phase, size, alpha}
var _vendor: TextureRect
var _bg: TextureRect


func _ready() -> void:
	_build()


func set_mode(m: String) -> void:
	mode = m
	if mode == "living":
		# scatter walkers so they do not clump on mode switch
		for i in _customers.size():
			var c: Dictionary = _customers[i]
			c["x"] = fposmod(0.13 * i + 0.05, 1.0)
			c["pause"] = 0.0
			c["can_pause"] = true


func set_focus_group(gid: String) -> void:
	_focus_group = gid
	for c in _customers:
		var on: bool = gid == "" or c["group"] == gid
		c["node"].modulate.a = 1.0 if on else 0.4
		c["glow"].visible = gid != "" and c["group"] == gid


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _layout_bg() -> void:
	if _bg == null or _bg.texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var ts: Vector2 = _bg.texture.get_size()
	var s: float = maxf(size.x / ts.x, size.y / ts.y)
	var w: float = ts.x * s
	var h: float = ts.y * s
	# right-pinned; horizon aimed at ~30% height, clamped to the cover range
	var top: float = clampf(size.y * 0.30 - h * BG_HORIZON, size.y - h, 0.0)
	_bg.position = Vector2(size.x - w, top)
	_bg.size = Vector2(w, h)


func _glow_rect(color: Color, alpha: float) -> TextureRect:
	var g := TextureRect.new()
	g.texture = _tex("res://assets/ui/dot_glow.png")
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.self_modulate = Color(color, alpha)
	g.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(g)
	return g


func _anchor(n: Control, l: float, t: float, r: float, b: float) -> void:
	n.anchor_left = l
	n.anchor_top = t
	n.anchor_right = r
	n.anchor_bottom = b
	n.offset_left = 0
	n.offset_top = 0
	n.offset_right = 0
	n.offset_bottom = 0


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_customers.clear()
	_motes.clear()
	clip_contents = true
	mouse_filter = MOUSE_FILTER_IGNORE

	# backdrop: cover-scaled by hand so the crop is pinned right (ringed planet
	# stays whole inside the frame) and the horizon sits high (walkers always
	# stand on dock plating, never on the skyline)
	_bg = TextureRect.new()
	_bg.texture = _tex("res://assets/backgrounds/bg_dock.png")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_bg)
	if not resized.is_connected(_layout_bg):
		resized.connect(_layout_bg)
	_layout_bg()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, 0.22)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)

	# far-lane motes (behind stall)
	_spawn_motes(5, 0)

	# warm halo behind the stall (spec §3.7)
	var warm := _glow_rect(GOLD, 0.20)
	_anchor(warm, 0.16, 0.18, 0.84, 1.08)

	# stall
	var stall := TextureRect.new()
	stall.texture = _tex("res://assets/characters/stall.png")
	stall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(stall)
	_anchor(stall, 0.20, 0.06, 0.80, 0.84)

	# ground neon reflections: broken colored streaks near the bottom
	var refl_cols := [LIME, MAGENTA, CYAN, VIOLET]
	var refl_x := [0.16, 0.38, 0.58, 0.78]
	for i in refl_cols.size():
		var r := _glow_rect(refl_cols[i], 0.10)
		var cx: float = refl_x[i]
		_anchor(r, cx - 0.10, 0.90, cx + 0.10, 1.02)
	# lime pool right under the stall counter
	var pool := _glow_rect(LIME, 0.13)
	_anchor(pool, 0.28, 0.84, 0.72, 1.04)

	# vendor in front of the stall
	_vendor = TextureRect.new()
	_vendor.texture = _tex("res://assets/characters/vendor_m0x.png")
	_vendor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vendor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vendor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_vendor)
	_anchor(_vendor, 0.44, VENDOR_TOP, 0.56, VENDOR_BOTTOM)

	# customers, two depth lanes: every walker in a lane shares one integer pixel
	# scale (crisp NEAREST), and the far lane's baseline sits higher up the dock
	# plating so depth reads without anyone floating on the skyline
	var idle_xs := [0.075, 0.185, 0.775, 0.925, 0.315, 0.615]
	for i in GROUPS.size():
		var g: Dictionary = GROUPS[i]
		var lane := i % 2  # 0 = near, 1 = far
		var glow := _glow_rect(LIME, 0.5)
		glow.visible = false
		var tr := TextureRect.new()
		tr.texture = _tex(g["tex"])
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(tr)
		_customers.append({
			"node": tr, "glow": glow, "group": g["key"],
			"idle_x": idle_xs[i], "x": idle_xs[i],
			"dir": 1.0 if i % 2 == 0 else -1.0,
			"speed": 0.045 + (i % 3) * 0.02,
			"pause": 0.0, "can_pause": true,
			"lane": lane,
			"lane_y": GROUND_NEAR if lane == 0 else GROUND_FAR,
			"phase": i * 1.7,
		})
		_place_customer(_customers[i], idle_xs[i], 0.0)

	# near-lane motes (in front of everything)
	_spawn_motes(9, 1)


func _spawn_motes(count: int, layer: int) -> void:
	var mote_cols := [LIME, VIOLET, Color(0.9, 0.95, 1.0), CYAN]
	for i in count:
		var tier := i % 3  # 0 small/slow · 1 mid · 2 large/fast (spec §3.7)
		var m := _glow_rect(mote_cols[(i + layer) % mote_cols.size()], 1.0)
		var base_size: float = [3.5, 6.5, 10.0][tier]
		var base_speed: float = [0.012, 0.022, 0.036][tier]
		var base_alpha: float = [0.16, 0.26, 0.38][tier]
		_motes.append({
			"node": m, "x": randf(), "y": randf(),
			"speed": base_speed + randf() * 0.008,
			"drift": (randf() - 0.5) * 0.016,
			"phase": randf() * TAU,
			"size": base_size + randf() * 2.0,
			"alpha": base_alpha * (0.5 if layer == 0 else 1.0),
		})


## Integer pixel scale for a depth lane: every sprite in the lane shares it.
func _lane_k(lane: int) -> int:
	var near_k := maxi(1, int(size.y * 0.36 / ART_H))
	if lane == 0:
		return near_k
	return maxi(1, int(round(near_k * 0.64)))


func _place_customer(c: Dictionary, x: float, bob: float) -> void:
	var n: TextureRect = c["node"]
	if size.y <= 0.0:
		return
	var k := _lane_k(int(c.get("lane", 0)))
	var w_px := ART_W * k
	var h_px := ART_H * k
	var bob_px: float = bob * size.y
	var gy: float = c["lane_y"]
	n.anchor_left = x
	n.anchor_right = x
	n.anchor_top = gy
	n.anchor_bottom = gy
	n.offset_left = floorf(-w_px / 2.0)
	n.offset_right = n.offset_left + w_px
	n.offset_top = floorf(-h_px - bob_px)
	n.offset_bottom = n.offset_top + h_px
	var g: TextureRect = c["glow"]
	g.anchor_left = x
	g.anchor_right = x
	g.anchor_top = gy
	g.anchor_bottom = gy
	g.offset_left = -w_px * 0.65
	g.offset_right = w_px * 0.65
	g.offset_top = -h_px * 0.4
	g.offset_bottom = h_px * 0.06


func tick(delta: float) -> void:
	_t += delta
	if _vendor:
		var vbob := sin(_t * 2.6) * 0.006
		_vendor.anchor_top = VENDOR_TOP + vbob
		_vendor.anchor_bottom = VENDOR_BOTTOM + vbob
	for i in _customers.size():
		var c: Dictionary = _customers[i]
		var bob := absf(sin((_t + c["phase"]) * 5.0)) * 0.008
		if mode == "ambient":
			var sway := sin(_t * 1.2 + c["phase"]) * 0.014
			_place_customer(c, c["idle_x"] + sway, bob)
		else:
			if c["pause"] > 0.0:
				c["pause"] -= delta
				bob *= 0.25
			else:
				c["x"] += c["dir"] * c["speed"] * delta
				if c["x"] > 1.10:
					c["x"] = -0.10
				elif c["x"] < -0.10:
					c["x"] = 1.10
				# brief window-shopping stop near the stall (spec §3.7)
				if c["can_pause"] and absf(c["x"] - 0.5) < 0.035:
					c["pause"] = 0.9 + fposmod(c["phase"], 1.1)
					c["can_pause"] = false
				elif absf(c["x"] - 0.5) > 0.24:
					c["can_pause"] = true
			_place_customer(c, c["x"], bob)
			var edge_d: float = minf(c["x"] + 0.08, 1.08 - c["x"])
			var base: float = clampf(edge_d / 0.14, 0.0, 1.0)
			if _focus_group != "" and c["group"] != _focus_group:
				base = minf(base, 0.4)
			c["node"].modulate.a = base
	for m in _motes:
		m["y"] -= m["speed"] * delta
		m["x"] += m["drift"] * delta
		if m["y"] < -0.05:
			m["y"] = 1.05
			m["x"] = randf()
		if m["x"] < -0.05 or m["x"] > 1.05:
			m["x"] = randf()
		var n: TextureRect = m["node"]
		var s: float = m["size"] / maxf(size.y, 1.0)
		var cx: float = m["x"] + sin(_t * 0.8 + m["phase"]) * 0.008
		n.anchor_left = cx - s / 2
		n.anchor_right = cx + s / 2
		n.anchor_top = m["y"] - s / 2
		n.anchor_bottom = m["y"] + s / 2
		n.offset_left = 0
		n.offset_right = 0
		n.offset_top = 0
		n.offset_bottom = 0
		n.self_modulate.a = m["alpha"] * (0.7 + 0.3 * sin(_t * 2.0 + m["phase"]))
