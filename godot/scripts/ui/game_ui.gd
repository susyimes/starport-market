extends Control
## Dockline Neon v3 UI (runtime-built). Chinese default. Economy = MarketGame only.
## Design system: docs/redesign-v3-spec.md §3 · gameplay hooks: docs/gameplay-v3-final.md §6.
## Public API (§0) is frozen: game, enter_plan, select_product, adjust_order,
## adjust_price, select_permit, cycle_campaign, cycle_upgrade, open_market,
## continue_from_report, new_game, show_mode, Mode.

enum Mode { TITLE, PLAN, REPORT, GAME_OVER }

# ─── palette (spec §1) ───────────────────────────────────────────────────────
const COL_BG := Color("#0A0C16")
const COL_PANEL := Color("#101322f5")
const COL_PANEL_ALT := Color("#161A2E")
const COL_INSET := Color("#0C0F1D")
const COL_BORDER := Color("#2A3050")
const COL_BORDER_HI := Color("#3D4670")
const COL_TEXT := Color("#E8ECF8")
const COL_DIM := Color("#8B93B0")
const COL_FAINT := Color("#5A6180")
const COL_LIME := Color("#B8FF3D")
const COL_VIOLET := Color("#9A7BFF")
const COL_GOLD := Color("#FFD166")
const COL_MINT := Color("#3DFFA8")
const COL_RED := Color("#FF4D6D")
const COL_CYAN := Color("#4DE3FF")
const COL_MAGENTA := Color("#FF6EE7")
const COL_INK := Color("#0C1206")

# manifest column widths — header and data rows are built by the SAME slot
# factory (_manifest_cells) so the two can never drift apart
const W_TREND := 48
const W_STOCK := 46
const W_ORDER := 108
const W_PRICE := 108
const W_COST := 54
const W_FCST := 66
const ROW_SEP := 10

var seed: int = 7
var game: MarketGame
var mode: Mode = Mode.TITLE
var selected_product: int = 0
var orders: Dictionary = {}
var prices: Dictionary = {}
var upgrade_index: int = 0
var smuggle_sel: Dictionary = {}     # pid -> qty
var contracts_sel: Array = []        # accepted board contract ids
var visitor_accept: bool = false
var route_index: int = -1            # -1 = undecided
var favor_index: int = 0
var loan_take: bool = false
var ledger_open: bool = false
var worst_open: bool = false         # worst-case audit sub-rows folded by default (§6)
var report: Dictionary = {}
var help_open: bool = false
var help_page: int = 0
var toast: String = ""
var toast_until: float = 0.0
var _time: float = 0.0
var _font: Font
var _font_b: Font
var _hover_row: int = -1
var _cta_pulse: Array = []           # StyleBoxFlat refs animated on title
var _obs: Dictionary = {}            # cached observation for the current plan
var _quote: Variant = null           # cached quote for the current plan

var screen_title: Control
var screen_plan: Control
var screen_report: Control
var screen_over: Control
var screen_help: Control
var title_market: Control
var report_market: Control

var title_label: Label
var tag_label: Label
var blurb_label: Label
var start_btn: Button
var seed_label: Label

# plan: header + event strip
var hdr_night: Label
var hdr_cash: Label
var hdr_rep: Label
var hdr_cargo: Label
var hdr_cargo_bar: ColorRect
var hdr_risk: Label
var hdr_risk_bar: ColorRect
var signal_name: Label
var signal_head: Label
var rumor_row: HBoxContainer
var fog_row: HBoxContainer
var crowd_text: Label
var crowd_tags: HBoxContainer
var crowd_icon: TextureRect
# plan: manifest
var product_list: VBoxContainer
var _rows: Array = []
# plan: strategy column
var plan_kv: Dictionary = {}
var worst_rows: Dictionary = {}      # worst-case audit sub-rows (strict decomposition)
var worst_key_label: Label
var strategy_scroll: ScrollContainer
var strategy_fade: Control           # bottom fade + "▼ 更多" overflow cue (§6)
var plan_block_label: Label
var plan_hint: Label
var favor_hint: Label
var contracts_box: GridContainer
var active_box: VBoxContainer
var smuggle_box: VBoxContainer
var smuggle_note: Label
var visitor_section: HBoxContainer
var visitor_panel: PanelContainer
var visitor_name_l: Label
var visitor_line_l: Label
var visitor_num_l: Label
var visitor_btns: HBoxContainer
var route_section: HBoxContainer
var route_row: HBoxContainer
var route_cards_ui: Array = []       # {panel, chip, name, desc}
var upg_card: PanelContainer
var upg_name: Label
var upg_sub: Label
var favor_card: PanelContainer
var favor_name: Label
var favor_sub: Label
var favor_menu: PopupMenu
# plan: risk ledger drawer
var ledger_panel: PanelContainer
var ledger_kv: Dictionary = {}
var ledger_inspect_detail: Label
var ledger_debt: Label
var ledger_assess: Label
var ledger_finale: Label
var ledger_streak: Label
var loan_btn: Button
# plan: bottom bar
var detail_icon: TextureRect
var detail_name: Label
var detail_desc: Label
var detail_batches: Label
var tip_chip: PanelContainer
var toast_label: Label
var open_btn: Button

# report
var report_title: Label
var report_flavor: Label
var report_profit: Label
var metric_sales: Label
var metric_sold: Label
var metric_waste: Label
var metric_profit: Label
var inspect_panel: PanelContainer
var inspect_label: Label
var inspect_amt: Label
var inspect_sub: Label
var clean_panel: PanelContainer
var clean_label: Label
var visitor_res_panel: PanelContainer
var visitor_res_label: Label
var contract_panel: PanelContainer
var contract_label: Label
var contract_amt: Label
var cp_panel: PanelContainer
var cp_label: Label
var report_ach_panel: PanelContainer
var report_ach: Label
var report_products: VBoxContainer
var bill_rows: VBoxContainer
var report_prompt: Label
var continue_btn: Button

# game over
var final_title: Label
var final_rank: Label
var final_score: Label
var final_ledger_rows: Array = []
var final_seed: Label
var final_flavor: Label
var replay_btn: Button
var title_btn: Button

var help_title: Label
var help_body: Label
var help_dots: Label
var help_close: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_font = _make_font(400)
	_font_b = _make_font(700)
	_build_ui()
	new_game(seed)
	show_mode(Mode.TITLE)
	print("[Starport] Godot Dockline v3 ready · zh · seed=%s" % seed)


func _make_font(weight: int) -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans SC", "SimHei", "Segoe UI"])
	sf.font_weight = weight
	return sf


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# ─── style factory ───────────────────────────────────────────────────────────

## Generic flat box. bw=0 → no border. shadow → soft drop per spec §3.1.
func _sb(bg: Color, border: Color = COL_BORDER, radius: int = 10, bw: int = 1, mh: int = 14, mv: int = 10, shadow: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = mh
	sb.content_margin_right = mh
	sb.content_margin_top = mv
	sb.content_margin_bottom = mv
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 3)
	return sb


func _btn_styles(accent: Color, filled: bool = false, glow: bool = false) -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(1)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover: StyleBoxFlat = normal.duplicate()
	var pressed: StyleBoxFlat = normal.duplicate()
	var disabled: StyleBoxFlat = normal.duplicate()
	var focus := StyleBoxFlat.new()
	focus.set_corner_radius_all(8)
	focus.set_border_width_all(2)
	focus.border_color = accent
	focus.bg_color = Color(0, 0, 0, 0)
	if filled:
		normal.bg_color = accent
		normal.border_color = accent.lightened(0.22)
		hover.bg_color = accent.lightened(0.12)
		hover.border_color = Color.WHITE
		pressed.bg_color = accent.darkened(0.2)
		pressed.border_color = accent
		disabled.bg_color = Color(accent.darkened(0.55), 0.7)
		disabled.border_color = accent.darkened(0.4)
		if glow:
			normal.shadow_color = Color(accent, 0.35)
			normal.shadow_size = 12
			normal.shadow_offset = Vector2.ZERO
			hover.shadow_color = Color(accent, 0.5)
			hover.shadow_size = 16
			hover.shadow_offset = Vector2.ZERO
			pressed.shadow_color = Color(accent, 0.22)
			pressed.shadow_size = 6
			pressed.shadow_offset = Vector2.ZERO
	else:
		normal.bg_color = COL_PANEL_ALT
		normal.border_color = COL_BORDER_HI
		hover.bg_color = Color("#1C2138")
		hover.border_color = accent
		pressed.bg_color = COL_INSET
		pressed.border_color = accent.darkened(0.2)
		disabled.bg_color = Color("#0E1120")
		disabled.border_color = Color("#1C2136")
	return {
		"normal": normal, "hover": hover, "pressed": pressed,
		"disabled": disabled, "focus": focus,
	}


func _lbl(parent: Node, text: String = "", size_px: int = 16, color: Color = COL_TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_b if bold else _font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


## Fixed-width numeric cell label: bold, no wrap, right aligned by default.
func _num(parent: Node, text: String, size_px: int, color: Color, width: int, align: int = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l := _lbl(parent, text, size_px, color, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = align
	return l


func _btn(parent: Node, text: String, size_px: Vector2 = Vector2(200, 48), accent: Color = COL_LIME, filled: bool = false, font_size: int = 16, glow: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size_px
	b.focus_mode = FOCUS_NONE
	b.add_theme_font_override("font", _font_b if filled else _font)
	b.add_theme_font_size_override("font_size", font_size)
	var st := _btn_styles(accent, filled, glow)
	for k in st:
		b.add_theme_stylebox_override(k, st[k])
	if filled:
		b.add_theme_color_override("font_color", COL_INK)
		b.add_theme_color_override("font_hover_color", Color("#060903"))
		b.add_theme_color_override("font_pressed_color", Color("#1A2410"))
		b.add_theme_color_override("font_disabled_color", Color("#3A4230"))
	else:
		b.add_theme_color_override("font_color", COL_TEXT)
		b.add_theme_color_override("font_hover_color", accent)
		b.add_theme_color_override("font_pressed_color", accent)
		b.add_theme_color_override("font_disabled_color", COL_FAINT)
	parent.add_child(b)
	return b


func _panel(parent: Node, color: Color = COL_PANEL, radius: int = 12, border: Color = COL_BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(color, border, radius, 1, 14, 10, true))
	parent.add_child(p)
	return p


## Chip: inset bg + 6px radius + 11px text (spec §3.1). Inner label in meta.
func _chip(parent: Node, text: String, fg: Color = COL_DIM, border: Color = COL_BORDER, bg: Color = COL_INSET) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border, 6, 1, 8, 2))
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", fg)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	p.set_meta("label", l)
	parent.add_child(p)
	return p


## Feature chip: one shared look for every title-screen trait chip (fix B11).
func _feat_chip(parent: Node, text: String, accent: Color) -> PanelContainer:
	return _chip(parent, text, accent, Color(accent, 0.4))


## Micro tag chip — ONE look shared by manifest-row tags, rumor gain tags and
## the shelf-life chip (§2/§3): 10px text, tight margins, tag-colored border.
func _tag_chip(parent: Node, text: String, fg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(COL_INSET, Color(fg, 0.4), 5, 1, 5, 0))
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", fg)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	p.set_meta("label", l)
	parent.add_child(p)
	return p


## Section header: 3×14 lime bar + 12px dim bold + optional right chips.
func _section(parent: Node, text: String, chips: Array = [], accent: Color = COL_LIME) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3, 14)
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(bar)
	var l := _lbl(h, text, 12, COL_DIM, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(sp)
	for c in chips:
		_chip(h, str(c))
	return h


## Icon plate: inset rounded board with pixel icon centered. Returns inner TextureRect.
## mh=2 keeps a 48px plate's inner box at 44px so 32×44 customer art lands at an
## exact 1× art-pixel scale (fix B10).
func _plate(parent: Node, px: int, tex: Texture2D = null, mh: int = 4) -> TextureRect:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(COL_INSET, COL_BORDER, 8, 1, mh, mh))
	p.custom_minimum_size = Vector2(px, px)
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.add_child(t)
	parent.add_child(p)
	return t


## Metric card: accent left bar + 11px dim label + 22px bold value (spec §3.3).
func _metric_card(parent: Node, glyph: String, title: String, accent: Color) -> Dictionary:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sb(COL_PANEL, COL_BORDER, 10, 1, 12, 8, true))
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3, 0)
	h.add_child(bar)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var lab := _lbl(v, "%s  %s" % [glyph, title], 11, COL_DIM)
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	var val := _lbl(v, "—", 22, accent, true)
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	return {"value": val, "bar": bar, "label": lab, "panel": card}


func _spacer(parent: Node, vertical: bool = true) -> Control:
	var s := Control.new()
	if vertical:
		s.size_flags_vertical = SIZE_EXPAND_FILL
	else:
		s.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(s)
	return s


func _kv_row(parent: Node, key: String, val_color: Color) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	var k := _lbl(h, key, 13, COL_DIM)
	k.size_flags_horizontal = SIZE_EXPAND_FILL
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	var v := _lbl(h, "—", 14, val_color, true)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return v


## Indented 11px audit sub-row (e.g. worst-case breakdown under the total).
func _sub_row(parent: Node, key: String) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	var k := _lbl(h, "⌞ " + key, 11, COL_FAINT)
	k.size_flags_horizontal = SIZE_EXPAND_FILL
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	var v := _lbl(h, "—", 11, COL_DIM, true)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.visible = false
	return v


## Set a worst-case audit sub-row: hidden at zero, red when it costs money.
func _set_sub(v: Label, amount: int) -> void:
	(v.get_parent() as Control).visible = amount != 0
	v.text = Loc.money(amount)
	v.add_theme_color_override("font_color", COL_RED if amount < 0 else COL_DIM)


func _mini_card(parent: Node, title: String, accent: Color, hint: String) -> Dictionary:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sb(COL_INSET, COL_BORDER, 10, 1, 10, 6))
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 64)
	card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _lbl(head, title, 11, Color(accent, 0.9), true)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	var hl := _lbl(head, hint, 10, COL_FAINT)
	hl.autowrap_mode = TextServer.AUTOWRAP_OFF
	var nm := _lbl(v, "—", 13, COL_TEXT, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var sub := _lbl(v, "", 11, COL_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return {"panel": card, "name": nm, "sub": sub}


## 5-night procurement trend: bottom-aligned mini bars, tonight brightest.
func _sparkline(parent: Node, series: Array) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_vertical = SIZE_SHRINK_END
	box.alignment = BoxContainer.ALIGNMENT_END
	parent.add_child(box)
	var n := series.size()
	for i in n:
		var v := float(series[i])
		var t := clampf((v - 0.85) / 0.35, 0.0, 1.0)
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(5, 4.0 + t * 14.0)
		bar.size_flags_vertical = SIZE_SHRINK_END
		var col := COL_MINT if v <= 1.0 else (COL_GOLD if v <= 1.1 else COL_RED)
		bar.color = Color(col, 0.4 + 0.6 * float(i + 1) / float(maxi(1, n)))
		box.add_child(bar)


# ─── build ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = _tex("res://assets/backgrounds/bg_dock.png")
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(COL_BG, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)

	_build_title()
	_build_plan()
	_build_report()
	_build_game_over()
	_build_help()
	_build_overlay()


## Vignette + tiled scanlines, topmost, click-through (spec §3.1).
func _build_overlay() -> void:
	var vin := TextureRect.new()
	vin.name = "Vignette"
	vin.texture = _tex("res://assets/ui/vignette.png")
	vin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vin.stretch_mode = TextureRect.STRETCH_SCALE
	vin.self_modulate = Color(1, 1, 1, 0.28)
	vin.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(vin)
	var scan := TextureRect.new()
	scan.name = "Scanlines"
	scan.texture = _tex("res://assets/ui/scanlines.png")
	scan.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scan.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scan.stretch_mode = TextureRect.STRETCH_TILE
	scan.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	scan.self_modulate = Color(1, 1, 1, 0.5)
	scan.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(scan)


func _build_title() -> void:
	screen_title = Control.new()
	screen_title.name = "ScreenTitle"
	screen_title.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen_title.offset_left = 32
	screen_title.offset_top = 28
	screen_title.offset_right = -32
	screen_title.offset_bottom = -28
	add_child(screen_title)

	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 20)
	screen_title.add_child(h)

	# left: brand panel (38%)
	var brand := _panel(h, COL_PANEL_ALT)
	brand.size_flags_horizontal = SIZE_EXPAND_FILL
	brand.size_flags_stretch_ratio = 0.38
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	brand.add_child(bv)
	var chiprow := HBoxContainer.new()
	bv.add_child(chiprow)
	_feat_chip(chiprow, Loc.t("dockline"), COL_LIME)
	title_label = _lbl(bv, Loc.t("app_title_line"), 64, Color("#F4F7FF"), true)
	var title_font := FontVariation.new()          # letter-spaced so glows don't touch
	title_font.base_font = _font_b
	title_font.spacing_glyph = 5
	title_label.add_theme_font_override("font", title_font)
	title_label.add_theme_color_override("font_shadow_color", Color(COL_LIME, 0.45))
	title_label.add_theme_constant_override("shadow_offset_x", 0)
	title_label.add_theme_constant_override("shadow_offset_y", 0)
	title_label.add_theme_constant_override("shadow_outline_size", 14)
	title_label.add_theme_constant_override("line_spacing", -14)
	tag_label = _lbl(bv, Loc.t("tagline"), 17, COL_GOLD, true)
	blurb_label = _lbl(bv, Loc.t("blurb_v3"), 14, COL_DIM)
	var feats := HBoxContainer.new()
	feats.add_theme_constant_override("separation", 8)
	bv.add_child(feats)
	_feat_chip(feats, Loc.t("feat_nights"), COL_LIME)
	_feat_chip(feats, Loc.t("feat_products"), COL_CYAN)
	_feat_chip(feats, Loc.t("feat_contract"), COL_GOLD)
	_feat_chip(feats, Loc.t("feat_smuggle"), COL_RED)
	_feat_chip(feats, Loc.t("feat_route"), COL_VIOLET)
	var sp_a := _spacer(bv)
	sp_a.size_flags_stretch_ratio = 2.0
	var vendor := TextureRect.new()
	vendor.texture = _tex("res://assets/characters/vendor_m0x.png")
	vendor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vendor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vendor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vendor.custom_minimum_size = Vector2(0, 308)   # 44px art × 7 — integer zoom
	bv.add_child(vendor)
	var sp_b := _spacer(bv)
	sp_b.size_flags_stretch_ratio = 1.0
	start_btn = _btn(bv, Loc.t("open_stall"), Vector2(300, 60), COL_LIME, true, 20, true)
	_cta_pulse = [
		start_btn.get_theme_stylebox("normal"),
		start_btn.get_theme_stylebox("hover"),
	]
	start_btn.pressed.connect(enter_plan)
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 8)
	bv.add_child(hints)
	_chip(hints, Loc.t("chip_space"))
	_chip(hints, Loc.t("chip_help"))
	_chip(hints, Loc.t("risk_chip"))
	_chip(hints, Loc.t("chip_esc"))
	var seed_chip := _chip(hints, Loc.t("seed") + "  0007", COL_FAINT)
	seed_label = seed_chip.get_meta("label")

	# right: live dock stage (62%)
	var stage_panel := _panel(h)
	stage_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	stage_panel.size_flags_stretch_ratio = 0.62
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	stage_panel.add_child(sv)
	_section(sv, Loc.t("live_dock"))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.3), Color(COL_LIME, 0.5), 8, 1, 3, 3))
	frame.size_flags_vertical = SIZE_EXPAND_FILL
	sv.add_child(frame)
	title_market = _make_market(frame, 520)


func _make_market(parent: Node, min_h: int) -> Control:
	var m := Control.new()
	m.custom_minimum_size = Vector2(0, min_h)
	m.size_flags_vertical = SIZE_EXPAND_FILL
	m.clip_contents = true
	m.set_script(load("res://scripts/ui/market_scene.gd"))
	parent.add_child(m)
	return m


# ─── plan build ──────────────────────────────────────────────────────────────

## Fixed column slots shared by the manifest header AND every product row.
## One coordinate system → header can never drift from the data (fix B1).
func _manifest_cells(h: HBoxContainer) -> Dictionary:
	var cells := {}
	var marker := HBoxContainer.new()
	marker.custom_minimum_size = Vector2(14, 0)
	marker.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(marker)
	cells["marker"] = marker
	var icon := CenterContainer.new()
	icon.custom_minimum_size = Vector2(42, 0)
	h.add_child(icon)
	cells["icon"] = icon
	var name_c := VBoxContainer.new()
	name_c.size_flags_horizontal = SIZE_EXPAND_FILL
	name_c.size_flags_vertical = SIZE_SHRINK_CENTER
	name_c.add_theme_constant_override("separation", 2)
	h.add_child(name_c)
	cells["name"] = name_c
	for spec in [["trend", W_TREND, BoxContainer.ALIGNMENT_END], ["stock", W_STOCK, BoxContainer.ALIGNMENT_END],
			["order", W_ORDER, BoxContainer.ALIGNMENT_CENTER], ["price", W_PRICE, BoxContainer.ALIGNMENT_END],
			["cost", W_COST, BoxContainer.ALIGNMENT_END], ["fcst", W_FCST, BoxContainer.ALIGNMENT_END]]:
		var c := HBoxContainer.new()
		c.custom_minimum_size = Vector2(spec[1], 0)
		c.alignment = spec[2]
		c.add_theme_constant_override("separation", 4)
		h.add_child(c)
		cells[spec[0]] = c
	return cells


func _hdr_cell(cell: Node, text: String, align: int = HORIZONTAL_ALIGNMENT_RIGHT) -> void:
	var l := _lbl(cell, text, 11, COL_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	l.horizontal_alignment = align


func _build_plan() -> void:
	screen_plan = Control.new()
	screen_plan.name = "ScreenPlan"
	screen_plan.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen_plan.offset_left = 24
	screen_plan.offset_top = 20
	screen_plan.offset_right = -24
	screen_plan.offset_bottom = -20
	add_child(screen_plan)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	screen_plan.add_child(root)

	# ── top metric cards
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 64)
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var m1 := _metric_card(header, "☾", Loc.t("night"), COL_LIME)
	hdr_night = m1["value"]
	var m2 := _metric_card(header, "＄", Loc.t("credits"), COL_GOLD)
	hdr_cash = m2["value"]
	var m3 := _metric_card(header, "★", Loc.t("reputation"), COL_VIOLET)
	hdr_rep = m3["value"]
	var m4 := _metric_card(header, "◆", Loc.t("cargo"), COL_MINT)
	hdr_cargo = m4["value"]
	hdr_cargo_bar = m4["bar"]
	var m5 := _metric_card(header, "♨", Loc.t("risk_metric"), COL_RED)
	hdr_risk = m5["value"]
	hdr_risk_bar = m5["bar"]
	var risk_panel: PanelContainer = m5["panel"]
	risk_panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	risk_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			toggle_ledger())

	# ── event strip: violet bar + event, rumor capsule, right crowd card
	var signal_panel := _panel(root)
	signal_panel.custom_minimum_size = Vector2(0, 82)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 14)
	signal_panel.add_child(sh)
	var evbar := ColorRect.new()
	evbar.color = COL_VIOLET
	evbar.custom_minimum_size = Vector2(3, 0)
	sh.add_child(evbar)
	var sigv := VBoxContainer.new()
	sigv.size_flags_horizontal = SIZE_EXPAND_FILL
	sigv.size_flags_vertical = SIZE_SHRINK_CENTER
	sigv.add_theme_constant_override("separation", 2)
	sh.add_child(sigv)
	signal_name = _lbl(sigv, "", 20, COL_VIOLET, true)
	signal_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	signal_head = _lbl(sigv, "", 13, COL_DIM)
	signal_head.autowrap_mode = TextServer.AUTOWRAP_OFF
	signal_head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# rumor capsule (§2.1): tomorrow pair + later fog
	var rum_panel := PanelContainer.new()
	rum_panel.add_theme_stylebox_override("panel", _sb(COL_INSET, Color(COL_CYAN, 0.35), 10, 1, 10, 6))
	rum_panel.size_flags_vertical = SIZE_SHRINK_CENTER
	sh.add_child(rum_panel)
	var rum_v := VBoxContainer.new()
	rum_v.add_theme_constant_override("separation", 4)
	rum_panel.add_child(rum_v)
	rumor_row = HBoxContainer.new()
	rumor_row.add_theme_constant_override("separation", 6)
	rum_v.add_child(rumor_row)
	fog_row = HBoxContainer.new()
	fog_row.add_theme_constant_override("separation", 6)
	rum_v.add_child(fog_row)
	# crowd card
	var crowd := PanelContainer.new()
	crowd.add_theme_stylebox_override("panel", _sb(COL_INSET, COL_BORDER, 10, 1, 10, 6))
	crowd.custom_minimum_size = Vector2(300, 0)
	sh.add_child(crowd)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	crowd.add_child(ch)
	crowd_icon = _plate(ch, 48, null, 2)
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = SIZE_EXPAND_FILL
	cv.size_flags_vertical = SIZE_SHRINK_CENTER
	cv.add_theme_constant_override("separation", 4)
	ch.add_child(cv)
	var crowd_head := HBoxContainer.new()
	crowd_head.add_theme_constant_override("separation", 8)
	cv.add_child(crowd_head)
	var ct := _chip(crowd_head, Loc.t("crowd_tonight"), COL_FAINT)
	ct.size_flags_vertical = SIZE_SHRINK_CENTER
	crowd_text = _lbl(crowd_head, "", 15, COL_LIME, true)
	crowd_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	crowd_tags = HBoxContainer.new()
	crowd_tags.add_theme_constant_override("separation", 6)
	cv.add_child(crowd_tags)

	# ── body: manifest (64%) + strategy (36%)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	var manifest := _panel(body)
	manifest.size_flags_horizontal = SIZE_EXPAND_FILL
	manifest.size_flags_stretch_ratio = 0.64
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	manifest.add_child(mv)
	_section(mv, Loc.t("cargo_manifest"), [Loc.t("key_select"), Loc.t("key_load"), Loc.t("key_price")])
	# column header — same slot factory as rows; right margin compensates the
	# scrollbar (8) + gutter (8) that inset the rows below
	var head_wrap := PanelContainer.new()
	head_wrap.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 12, 2))
	var head_sb: StyleBoxFlat = head_wrap.get_theme_stylebox("panel")
	head_sb.content_margin_right = 28
	mv.add_child(head_wrap)
	var colh := HBoxContainer.new()
	colh.add_theme_constant_override("separation", ROW_SEP)
	head_wrap.add_child(colh)
	var hc := _manifest_cells(colh)
	_hdr_cell(hc["name"], Loc.t("item"), HORIZONTAL_ALIGNMENT_LEFT)
	_hdr_cell(hc["trend"], Loc.t("market_trend"))
	_hdr_cell(hc["stock"], Loc.t("have"))
	_hdr_cell(hc["order"], Loc.t("load"), HORIZONTAL_ALIGNMENT_CENTER)
	_hdr_cell(hc["price"], Loc.t("ask"))
	var price_pad := Control.new()          # header lands on the digits' right edge
	price_pad.custom_minimum_size = Vector2(28, 0)   # stepper 24 + separation 4
	hc["price"].add_child(price_pad)
	_hdr_cell(hc["cost"], Loc.t("cost"))
	_hdr_cell(hc["fcst"], Loc.t("fcst"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(scroll)
	var vsb := scroll.get_v_scroll_bar()
	vsb.custom_minimum_size = Vector2(8, 0)
	vsb.add_theme_stylebox_override("scroll", _sb(COL_INSET, COL_INSET, 4, 0, 2, 2))
	vsb.add_theme_stylebox_override("grabber", _sb(COL_BORDER, COL_BORDER, 4, 0, 2, 2))
	vsb.add_theme_stylebox_override("grabber_highlight", _sb(COL_BORDER_HI, COL_BORDER_HI, 4, 0, 2, 2))
	vsb.add_theme_stylebox_override("grabber_pressed", _sb(COL_BORDER_HI, COL_BORDER_HI, 4, 0, 2, 2))
	var gut := MarginContainer.new()
	gut.size_flags_horizontal = SIZE_EXPAND_FILL
	gut.add_theme_constant_override("margin_right", 8)
	scroll.add_child(gut)
	product_list = VBoxContainer.new()
	product_list.size_flags_horizontal = SIZE_EXPAND_FILL
	product_list.add_theme_constant_override("separation", 5)
	gut.add_child(product_list)

	# ── strategy column (scrolls: plan → contracts → smuggle → visitor → route → upgrades/favor)
	var strategy := _panel(body, COL_PANEL_ALT)
	strategy.size_flags_horizontal = SIZE_EXPAND_FILL
	strategy.size_flags_stretch_ratio = 0.36
	var sscroll := ScrollContainer.new()
	sscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sscroll.size_flags_vertical = SIZE_EXPAND_FILL
	strategy.add_child(sscroll)
	strategy_scroll = sscroll
	var svsb := sscroll.get_v_scroll_bar()
	svsb.custom_minimum_size = Vector2(8, 0)
	svsb.add_theme_stylebox_override("scroll", _sb(COL_INSET, COL_INSET, 4, 0, 2, 2))
	svsb.add_theme_stylebox_override("grabber", _sb(COL_BORDER, COL_BORDER, 4, 0, 2, 2))
	svsb.add_theme_stylebox_override("grabber_highlight", _sb(COL_BORDER_HI, COL_BORDER_HI, 4, 0, 2, 2))
	svsb.add_theme_stylebox_override("grabber_pressed", _sb(COL_BORDER_HI, COL_BORDER_HI, 4, 0, 2, 2))
	# bottom fade + "▼ 更多" cue while the column still scrolls further (§6)
	strategy_fade = Control.new()
	strategy_fade.mouse_filter = MOUSE_FILTER_IGNORE
	strategy.add_child(strategy_fade)
	var fade_tex := TextureRect.new()
	var fade_grad := Gradient.new()
	fade_grad.colors = PackedColorArray([Color(COL_PANEL_ALT, 0.0), Color(COL_PANEL_ALT, 0.95)])
	fade_grad.offsets = PackedFloat32Array([0.0, 1.0])
	var fade_gt := GradientTexture2D.new()
	fade_gt.gradient = fade_grad
	fade_gt.fill_from = Vector2(0, 0)
	fade_gt.fill_to = Vector2(0, 1)
	fade_tex.texture = fade_gt
	fade_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade_tex.stretch_mode = TextureRect.STRETCH_SCALE
	fade_tex.mouse_filter = MOUSE_FILTER_IGNORE
	fade_tex.set_anchors_preset(PRESET_BOTTOM_WIDE)
	fade_tex.offset_top = -34
	strategy_fade.add_child(fade_tex)
	var more_l := _lbl(strategy_fade, "▼ " + Loc.t("more_below"), 11, COL_DIM, true)
	more_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	more_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	more_l.set_anchors_preset(PRESET_BOTTOM_WIDE)
	more_l.offset_top = -17
	strategy_fade.visible = false
	var sgut := MarginContainer.new()
	sgut.size_flags_horizontal = SIZE_EXPAND_FILL
	sgut.add_theme_constant_override("margin_right", 8)   # keep the thumb off the text
	sscroll.add_child(sgut)
	var stv := VBoxContainer.new()
	stv.size_flags_horizontal = SIZE_EXPAND_FILL
	stv.add_theme_constant_override("separation", 4)
	sgut.add_child(stv)

	# plan key/values incl. best/worst (§6)
	_section(stv, Loc.t("plan"), [Loc.t("risk_chip")])
	var plan_box := PanelContainer.new()
	plan_box.add_theme_stylebox_override("panel", _sb(COL_INSET, COL_BORDER, 10, 1, 12, 7))
	stv.add_child(plan_box)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	plan_box.add_child(pv)
	# cargo + inspection odds live in the header metric cards — the plan box
	# keeps the money story: spend / deposits / cash left / forecast / best / worst
	plan_kv["spend"] = _kv_row(pv, Loc.t("spend"), COL_TEXT)
	# rent is a certain nightly expense — it lives with the spend block (§4)
	plan_kv["rent"] = _kv_row(pv, Loc.t("li_rent"), COL_TEXT)
	plan_kv["deposit"] = _kv_row(pv, Loc.t("deposit_row"), COL_GOLD)
	var safe_val := _kv_row(pv, Loc.t("safe"), COL_GOLD)
	safe_val.add_theme_font_size_override("font_size", 20)
	plan_kv["safe"] = safe_val
	plan_kv["fcst"] = _kv_row(pv, Loc.t("est_rev"), COL_CYAN)
	plan_kv["best"] = _kv_row(pv, Loc.t("best_case"), COL_MINT)
	plan_kv["worst"] = _kv_row(pv, Loc.t("worst_case"), COL_RED)
	# worst-case audit trail (§4/§6): strict decomposition — the sub-rows sum
	# exactly to the worst value. Folded by default; the row itself toggles.
	var worst_row_h := plan_kv["worst"].get_parent() as Control
	worst_key_label = worst_row_h.get_child(0) as Label
	worst_row_h.mouse_filter = MOUSE_FILTER_PASS
	worst_row_h.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	worst_row_h.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			worst_open = not worst_open
			refresh_plan())
	worst_rows["from_best"] = _sub_row(pv, Loc.t("wc_from_best"))
	worst_rows["est_low"] = _sub_row(pv, Loc.t("wc_est_low"))
	worst_rows["due_rev"] = _sub_row(pv, Loc.t("wc_due_rev"))
	worst_rows["seize"] = _sub_row(pv, Loc.t("wc_seize"))
	worst_rows["breach"] = _sub_row(pv, Loc.t("wc_breach"))
	# standing breach exposure across active + accepted contracts (§7)
	plan_kv["exposure"] = _kv_row(pv, Loc.t("contract_exposure"), COL_GOLD)
	# favor points always on display — the row itself opens the spend menu (§5)
	plan_kv["favor"] = _kv_row(pv, Loc.t("favor_title"), COL_MINT)
	var favor_row_h := plan_kv["favor"].get_parent() as Control
	var favor_key := _lbl(favor_row_h, "[F] " + Loc.t("favor_spend"), 11, COL_FAINT)
	favor_key.autowrap_mode = TextServer.AUTOWRAP_OFF
	favor_key.size_flags_vertical = SIZE_SHRINK_CENTER
	favor_row_h.move_child(favor_key, 1)   # key · [F] 花费 · value
	favor_row_h.mouse_filter = MOUSE_FILTER_PASS
	favor_row_h.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	favor_row_h.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_open_favor_menu())
	plan_block_label = _lbl(pv, "", 12, COL_RED)
	plan_block_label.visible = false
	plan_hint = _lbl(stv, "", 12, COL_GOLD)
	plan_hint.visible = false
	favor_hint = _lbl(stv, "", 12, COL_MINT)
	favor_hint.visible = false

	# route cards — the old permit slot, nights 1/7/13 only (§2.4)
	route_section = _section(stv, Loc.t("route_title"), [Loc.t("key_route")], COL_CYAN)
	route_row = HBoxContainer.new()
	route_row.add_theme_constant_override("separation", 8)
	stv.add_child(route_row)
	route_cards_ui.clear()
	for i in 2:
		var rcard := PanelContainer.new()
		# narrow horizontal strip (§6): chip + name inline, one-line description;
		# both states share margins — selection only recolors (fix B9)
		rcard.custom_minimum_size = Vector2(0, 44)
		rcard.size_flags_horizontal = SIZE_EXPAND_FILL
		rcard.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		route_row.add_child(rcard)
		var cvb := VBoxContainer.new()
		cvb.add_theme_constant_override("separation", 2)
		rcard.add_child(cvb)
		var chip_row := HBoxContainer.new()
		chip_row.add_theme_constant_override("separation", 6)
		cvb.add_child(chip_row)
		var pchip := _chip(chip_row, "%d" % (i + 1), COL_LIME, Color(COL_LIME, 0.4))
		pchip.size_flags_vertical = SIZE_SHRINK_CENTER
		var pname := _lbl(chip_row, "—", 13, COL_TEXT, true)
		pname.autowrap_mode = TextServer.AUTOWRAP_OFF
		pname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		pname.size_flags_horizontal = SIZE_EXPAND_FILL
		pname.size_flags_vertical = SIZE_SHRINK_CENTER
		var pdesc := _lbl(cvb, "", 10, COL_DIM)
		pdesc.autowrap_mode = TextServer.AUTOWRAP_OFF
		pdesc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var pidx := i
		rcard.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				select_permit(pidx))
		route_cards_ui.append({"panel": rcard, "chip": pchip, "name": pname, "desc": pdesc})

	# contract board (§2.2)
	_section(stv, Loc.sec("contracts", "board_title", "契约看板"), [Loc.t("key_contract")], COL_GOLD)
	contracts_box = GridContainer.new()
	contracts_box.columns = 2
	contracts_box.add_theme_constant_override("h_separation", 8)
	contracts_box.add_theme_constant_override("v_separation", 8)
	stv.add_child(contracts_box)
	active_box = VBoxContainer.new()
	active_box.add_theme_constant_override("separation", 4)
	stv.add_child(active_box)

	# smuggle bay (§2.3) — the heat/inspection readout rides in the header so
	# the column never ends on a clipped half-height caption row
	var smug_hdr := _section(stv, Loc.sec("smuggle", "title"), [], COL_RED)
	smuggle_note = _lbl(smug_hdr, "", 11, COL_DIM)
	smuggle_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	smuggle_note.size_flags_vertical = SIZE_SHRINK_CENTER
	smuggle_box = VBoxContainer.new()
	smuggle_box.add_theme_constant_override("separation", 4)
	stv.add_child(smuggle_box)

	# dusk visitor (§2.5)
	visitor_section = _section(stv, Loc.t("visitor_title"), [Loc.t("key_visitor")], COL_MAGENTA)
	visitor_panel = PanelContainer.new()
	visitor_panel.add_theme_stylebox_override("panel", _sb(COL_INSET, Color(COL_MAGENTA, 0.5), 10, 1, 10, 6))
	stv.add_child(visitor_panel)
	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 4)
	visitor_panel.add_child(vv)
	visitor_name_l = _lbl(vv, "", 14, COL_MAGENTA, true)
	visitor_name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	visitor_line_l = _lbl(vv, "", 12, COL_DIM)
	visitor_num_l = _lbl(vv, "", 13, COL_GOLD, true)
	visitor_num_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	visitor_btns = HBoxContainer.new()
	visitor_btns.add_theme_constant_override("separation", 8)
	vv.add_child(visitor_btns)

	# upgrade + favor mini cards
	_section(stv, "%s / %s" % [Loc.t("upgrade_title"), Loc.t("favor_title")], [Loc.t("key_upgrade"), Loc.t("key_favor")])
	var mini := HBoxContainer.new()
	mini.add_theme_constant_override("separation", 8)
	stv.add_child(mini)
	var uc := _mini_card(mini, Loc.t("upgrade_title") + "  [B]", COL_GOLD, Loc.t("click_cycle"))
	upg_card = uc["panel"]
	upg_name = uc["name"]
	upg_sub = uc["sub"]
	upg_card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			cycle_upgrade())
	var fc := _mini_card(mini, Loc.t("favor_title") + "  [F]", COL_MINT, Loc.t("click_pick"))
	favor_card = fc["panel"]
	favor_name = fc["name"]
	favor_sub = fc["sub"]
	# favor spends pick from a three-option popup instead of blind cycling
	favor_menu = PopupMenu.new()
	favor_menu.add_theme_font_override("font", _font)
	favor_menu.add_theme_font_size_override("font_size", 13)
	favor_card.add_child(favor_menu)
	favor_menu.id_pressed.connect(func(id: int) -> void:
		favor_index = id
		refresh_plan())
	favor_card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_open_favor_menu())

	# ── bottom detail bar
	var bottom := _panel(root)
	bottom.custom_minimum_size = Vector2(0, 92)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 14)
	bottom.add_child(bh)
	detail_icon = _plate(bh, 56)
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = SIZE_EXPAND_FILL
	dv.size_flags_vertical = SIZE_SHRINK_CENTER
	dv.add_theme_constant_override("separation", 3)
	bh.add_child(dv)
	detail_name = _lbl(dv, "", 17, COL_LIME, true)
	detail_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	detail_desc = _lbl(dv, "", 12, COL_DIM)
	detail_batches = _lbl(dv, "", 11, COL_FAINT)
	detail_batches.autowrap_mode = TextServer.AUTOWRAP_OFF
	detail_batches.visible = false
	var tipbox := HBoxContainer.new()
	tipbox.add_theme_constant_override("separation", 8)
	tipbox.size_flags_vertical = SIZE_SHRINK_CENTER
	bh.add_child(tipbox)
	tip_chip = _chip(tipbox, Loc.t("tip"), COL_CYAN, Color(COL_CYAN, 0.4))
	tip_chip.size_flags_vertical = SIZE_SHRINK_CENTER
	toast_label = _lbl(tipbox, "", 12, COL_DIM)
	toast_label.custom_minimum_size = Vector2(280, 0)
	toast_label.size_flags_vertical = SIZE_SHRINK_CENTER
	var cta_gap := Control.new()
	cta_gap.custom_minimum_size = Vector2(4, 0)
	bh.add_child(cta_gap)
	open_btn = _btn(bh, Loc.t("open_market"), Vector2(210, 56), COL_LIME, true, 18, true)
	open_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	open_btn.pressed.connect(open_market)

	_build_ledger_drawer()


## Risk ledger drawer (§6): the only NEW panel — right-side slide-over, key R.
func _build_ledger_drawer() -> void:
	ledger_panel = PanelContainer.new()
	ledger_panel.name = "RiskLedger"
	ledger_panel.add_theme_stylebox_override("panel", _sb(Color("#0E1120fa"), COL_BORDER_HI, 12, 1, 16, 12, true))
	ledger_panel.anchor_left = 1.0
	ledger_panel.anchor_right = 1.0
	ledger_panel.anchor_top = 0.0
	ledger_panel.anchor_bottom = 1.0
	ledger_panel.offset_left = -372
	ledger_panel.offset_right = 0
	ledger_panel.offset_top = 0
	ledger_panel.offset_bottom = 0
	ledger_panel.visible = false
	screen_plan.add_child(ledger_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	ledger_panel.add_child(v)
	_section(v, Loc.t("risk_ledger"), [Loc.t("close_chip")], COL_RED)
	# heat block
	ledger_kv["heat"] = _kv_row(v, Loc.sec("smuggle", "heat"), COL_RED)
	ledger_kv["inspect"] = _kv_row(v, Loc.t("tonight_inspection"), COL_RED)
	ledger_inspect_detail = _lbl(v, "", 11, COL_FAINT)
	ledger_kv["smuggled"] = _kv_row(v, Loc.t("cum_smuggled"), COL_DIM)
	ledger_kv["exposure"] = _kv_row(v, Loc.t("contract_exposure"), COL_GOLD)
	_ledger_sep(v)
	# debt block
	_section(v, Loc.t("debt_title"), [], COL_GOLD)
	ledger_debt = _lbl(v, "", 12, COL_DIM)
	loan_btn = _btn(v, Loc.t("take_loan"), Vector2(0, 40), COL_GOLD, false, 14)
	loan_btn.pressed.connect(toggle_loan)
	ledger_streak = _lbl(v, "", 12, COL_RED)
	ledger_streak.visible = false
	_ledger_sep(v)
	# checkpoint block
	_section(v, Loc.t("assess_title"), [], COL_VIOLET)
	ledger_assess = _lbl(v, "", 12, COL_DIM)
	_ledger_sep(v)
	# finale intel
	_section(v, Loc.t("finale_intel_title"), [], COL_CYAN)
	ledger_finale = _lbl(v, "", 12, COL_DIM)
	_ledger_sep(v)
	ledger_kv["net"] = _kv_row(v, Loc.t("net_worth"), COL_MINT)
	var score_val := _kv_row(v, Loc.t("score_est"), COL_GOLD)
	score_val.add_theme_font_size_override("font_size", 22)
	ledger_kv["score"] = score_val
	_spacer(v)


func _ledger_sep(parent: Node) -> void:
	var sep := ColorRect.new()
	sep.color = Color(COL_BORDER, 0.6)
	sep.custom_minimum_size = Vector2(0, 1)
	parent.add_child(sep)


# ─── report build ────────────────────────────────────────────────────────────

func _build_report() -> void:
	screen_report = Control.new()
	screen_report.name = "ScreenReport"
	screen_report.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen_report.offset_left = 46
	screen_report.offset_top = 24
	screen_report.offset_right = -46
	screen_report.offset_bottom = -24
	add_child(screen_report)

	var card := _panel(screen_report, COL_PANEL)
	card.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	# header: title + flavor left, profit big number right
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var hl := VBoxContainer.new()
	hl.size_flags_horizontal = SIZE_EXPAND_FILL
	hl.add_theme_constant_override("separation", 2)
	head.add_child(hl)
	report_title = _lbl(hl, "", 24, COL_TEXT, true)
	report_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	report_flavor = _lbl(hl, "", 13, COL_DIM)
	report_flavor.autowrap_mode = TextServer.AUTOWRAP_OFF
	var hr := VBoxContainer.new()
	hr.add_theme_constant_override("separation", 0)
	head.add_child(hr)
	var pl := _lbl(hr, Loc.t("profit_night"), 11, COL_DIM)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	report_profit = _lbl(hr, "", 34, COL_MINT, true)
	report_profit.autowrap_mode = TextServer.AUTOWRAP_OFF
	report_profit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# living market strip (soaks up slack height)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.3), COL_BORDER, 8, 1, 3, 3))
	frame.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(frame)
	report_market = _make_market(frame, 96)

	# inspection banner — hits hard when customs catch you (§6)
	inspect_panel = PanelContainer.new()
	inspect_panel.add_theme_stylebox_override("panel", _sb(Color("#2A0712"), COL_RED, 8, 2, 14, 8, true))
	v.add_child(inspect_panel)
	var iv := HBoxContainer.new()
	iv.add_theme_constant_override("separation", 12)
	inspect_panel.add_child(iv)
	var ibar := ColorRect.new()
	ibar.color = COL_RED
	ibar.custom_minimum_size = Vector2(4, 0)
	iv.add_child(ibar)
	var ivv := VBoxContainer.new()
	ivv.size_flags_horizontal = SIZE_EXPAND_FILL
	ivv.size_flags_vertical = SIZE_SHRINK_CENTER
	ivv.add_theme_constant_override("separation", 1)
	iv.add_child(ivv)
	inspect_label = _lbl(ivv, "", 17, COL_RED, true)
	inspect_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	inspect_sub = _lbl(ivv, "", 12, Color("#D98A9B"))
	inspect_sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	inspect_amt = _lbl(iv, "", 24, COL_RED, true)
	inspect_amt.autowrap_mode = TextServer.AUTOWRAP_OFF
	inspect_amt.size_flags_vertical = SIZE_SHRINK_CENTER
	# clean pass strip (smuggled but not caught)
	clean_panel = PanelContainer.new()
	clean_panel.add_theme_stylebox_override("panel", _sb(COL_INSET, Color(COL_MINT, 0.35), 8, 1, 12, 4))
	v.add_child(clean_panel)
	clean_label = _lbl(clean_panel, "", 12, Color(COL_MINT, 0.85))
	clean_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	# contract settlement banner
	contract_panel = PanelContainer.new()
	contract_panel.add_theme_stylebox_override("panel", _sb(Color("#1A1710"), Color(COL_GOLD, 0.55), 8, 1, 12, 6))
	v.add_child(contract_panel)
	var cbh := HBoxContainer.new()
	cbh.add_theme_constant_override("separation", 10)
	contract_panel.add_child(cbh)
	var cbar := ColorRect.new()
	cbar.color = COL_GOLD
	cbar.custom_minimum_size = Vector2(3, 0)
	cbh.add_child(cbar)
	contract_label = _lbl(cbh, "", 14, COL_GOLD, true)
	contract_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	contract_label.size_flags_vertical = SIZE_SHRINK_CENTER
	contract_label.size_flags_horizontal = SIZE_EXPAND_FILL
	contract_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	contract_amt = _lbl(cbh, "", 18, COL_GOLD, true)
	contract_amt.autowrap_mode = TextServer.AUTOWRAP_OFF
	contract_amt.size_flags_vertical = SIZE_SHRINK_CENTER

	# visitor result strip
	visitor_res_panel = PanelContainer.new()
	visitor_res_panel.add_theme_stylebox_override("panel", _sb(Color("#1D1226"), Color(COL_MAGENTA, 0.45), 8, 1, 12, 5))
	v.add_child(visitor_res_panel)
	visitor_res_label = _lbl(visitor_res_panel, "", 13, Color("#E8B7DF"))
	visitor_res_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	visitor_res_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	# checkpoint banner
	cp_panel = PanelContainer.new()
	cp_panel.add_theme_stylebox_override("panel", _sb(Color("#151129"), Color(COL_VIOLET, 0.5), 8, 1, 12, 5))
	v.add_child(cp_panel)
	cp_label = _lbl(cp_panel, "", 13, COL_VIOLET, true)
	cp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	cp_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	# milestone banner
	report_ach_panel = PanelContainer.new()
	report_ach_panel.add_theme_stylebox_override("panel", _sb(Color("#151129"), Color(COL_VIOLET, 0.5), 8, 1, 12, 5))
	v.add_child(report_ach_panel)
	var abh := HBoxContainer.new()
	abh.add_theme_constant_override("separation", 10)
	report_ach_panel.add_child(abh)
	var astar := _lbl(abh, "★", 15, COL_VIOLET, true)
	astar.autowrap_mode = TextServer.AUTOWRAP_OFF
	astar.size_flags_vertical = SIZE_SHRINK_CENTER
	report_ach = _lbl(abh, "", 13, COL_TEXT, true)
	report_ach.autowrap_mode = TextServer.AUTOWRAP_OFF
	report_ach.size_flags_vertical = SIZE_SHRINK_CENTER

	# metric cards
	var metrics := HBoxContainer.new()
	metrics.custom_minimum_size = Vector2(0, 62)
	metrics.add_theme_constant_override("separation", 10)
	v.add_child(metrics)
	metric_sales = _metric_card(metrics, "＄", Loc.t("sales"), COL_GOLD)["value"]
	metric_sold = _metric_card(metrics, "◆", Loc.t("sold"), COL_LIME)["value"]
	metric_waste = _metric_card(metrics, "✕", Loc.t("waste"), COL_RED)["value"]
	metric_profit = _metric_card(metrics, "▲", Loc.t("profit"), COL_MINT)["value"]

	# body: product table (full remaining width, fix B3) + night bill card
	var rbody := HBoxContainer.new()
	rbody.add_theme_constant_override("separation", 12)
	v.add_child(rbody)
	var tblv := VBoxContainer.new()
	tblv.size_flags_horizontal = SIZE_EXPAND_FILL
	tblv.add_theme_constant_override("separation", 4)
	rbody.add_child(tblv)
	_section(tblv, Loc.t("per_product"))
	var tab_head := HBoxContainer.new()
	tab_head.add_theme_constant_override("separation", 10)
	tblv.add_child(tab_head)
	var thp := Control.new()
	thp.custom_minimum_size = Vector2(34, 0)   # row inset 10 + icon 24
	tab_head.add_child(thp)
	var th0 := _lbl(tab_head, Loc.t("item"), 11, COL_FAINT)
	th0.size_flags_horizontal = SIZE_EXPAND_FILL
	th0.autowrap_mode = TextServer.AUTOWRAP_OFF
	_num(tab_head, Loc.t("sold_demand"), 11, COL_FAINT, 90).add_theme_font_override("font", _font)
	_num(tab_head, Loc.t("stockout_tag"), 11, COL_FAINT, 78, HORIZONTAL_ALIGNMENT_CENTER).add_theme_font_override("font", _font)
	_num(tab_head, Loc.t("col_revenue"), 11, COL_FAINT, 90).add_theme_font_override("font", _font)
	var thp2 := Control.new()
	thp2.custom_minimum_size = Vector2(10, 0)
	tab_head.add_child(thp2)
	report_products = VBoxContainer.new()
	report_products.size_flags_horizontal = SIZE_EXPAND_FILL
	report_products.add_theme_constant_override("separation", 2)
	tblv.add_child(report_products)
	# right: night bill card (contract income / breach fines / seizure / interest …)
	var bill_panel := PanelContainer.new()
	bill_panel.add_theme_stylebox_override("panel", _sb(COL_INSET, COL_BORDER, 10, 1, 14, 8))
	bill_panel.custom_minimum_size = Vector2(300, 0)
	rbody.add_child(bill_panel)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 3)
	bill_panel.add_child(bv)
	_section(bv, Loc.t("bill_title"), [], COL_GOLD)
	bill_rows = VBoxContainer.new()
	bill_rows.add_theme_constant_override("separation", 2)
	bv.add_child(bill_rows)

	var bot := HBoxContainer.new()
	v.add_child(bot)
	# shortcut hint as key-chip + caption, matching title/plan screens
	var hint_box := HBoxContainer.new()
	hint_box.add_theme_constant_override("separation", 8)
	hint_box.size_flags_horizontal = SIZE_EXPAND_FILL
	hint_box.size_flags_vertical = SIZE_SHRINK_CENTER
	bot.add_child(hint_box)
	var key_chip := _chip(hint_box, Loc.t("key_space"))
	key_chip.size_flags_vertical = SIZE_SHRINK_CENTER
	report_prompt = _lbl(hint_box, "", 13, COL_FAINT)
	report_prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	report_prompt.size_flags_horizontal = SIZE_EXPAND_FILL
	report_prompt.size_flags_vertical = SIZE_SHRINK_CENTER
	continue_btn = _btn(bot, Loc.t("continue"), Vector2(190, 48), COL_LIME, true, 16, true)
	continue_btn.pressed.connect(continue_from_report)


func _build_game_over() -> void:
	screen_over = Control.new()
	screen_over.name = "ScreenGameOver"
	screen_over.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(screen_over)
	var card := _panel(screen_over, COL_PANEL)
	card.set_anchors_preset(PRESET_CENTER)
	card.offset_left = -500
	card.offset_top = -340
	card.offset_right = 500
	card.offset_bottom = 340
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	final_title = _lbl(v, Loc.t("season_complete"), 26, COL_GOLD, true)
	final_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_title.add_theme_color_override("font_shadow_color", Color(COL_GOLD, 0.35))
	final_title.add_theme_constant_override("shadow_offset_x", 0)
	final_title.add_theme_constant_override("shadow_offset_y", 0)
	final_title.add_theme_constant_override("shadow_outline_size", 10)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 14)
	v.add_child(mid)
	# left: medal panel
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _sb(COL_INSET, COL_BORDER, 10, 1, 14, 12))
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.38
	mid.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	final_rank = _lbl(lv, "—", 34, COL_GOLD, true)
	final_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_rank.add_theme_color_override("font_shadow_color", Color(COL_GOLD, 0.4))
	final_rank.add_theme_constant_override("shadow_offset_x", 0)
	final_rank.add_theme_constant_override("shadow_offset_y", 0)
	final_rank.add_theme_constant_override("shadow_outline_size", 12)
	final_score = _lbl(lv, "", 23, COL_TEXT, true)
	final_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gowrap := Control.new()
	gowrap.size_flags_vertical = SIZE_EXPAND_FILL
	gowrap.custom_minimum_size = Vector2(0, 170)
	lv.add_child(gowrap)
	var halo := TextureRect.new()
	halo.texture = _tex("res://assets/ui/dot_glow.png")
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.self_modulate = Color(COL_LIME, 0.22)
	halo.set_anchors_preset(PRESET_FULL_RECT)
	halo.anchor_left = 0.12
	halo.anchor_right = 0.88
	halo.anchor_top = 0.05
	halo.anchor_bottom = 0.95
	gowrap.add_child(halo)
	var gov := TextureRect.new()
	gov.texture = _tex("res://assets/characters/vendor_m0x.png")
	gov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gov.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gov.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gov.set_anchors_preset(PRESET_FULL_RECT)
	gowrap.add_child(gov)
	final_flavor = _lbl(lv, "", 13, COL_DIM)
	final_flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# right: final ledger — score breakdown + season stats; rows share the panel
	# height evenly (fix B6), seed stays in the faint footer
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", _sb(COL_INSET, COL_BORDER, 10, 1, 16, 12))
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.62
	mid.add_child(right)
	var rv0 := VBoxContainer.new()
	rv0.add_theme_constant_override("separation", 6)
	right.add_child(rv0)
	_section(rv0, Loc.t("final_ledger"))
	var rv := VBoxContainer.new()
	rv.size_flags_vertical = SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 0)
	rv0.add_child(rv)
	final_ledger_rows.clear()
	var keys := [
		[Loc.t("bd_cash"), COL_GOLD],
		[Loc.t("bd_liq"), COL_TEXT],
		[Loc.t("bd_debt"), COL_RED],
		[Loc.t("bd_rep"), COL_VIOLET],
		[Loc.t("bd_fulfill"), COL_MINT],
		[Loc.t("bd_breach"), COL_RED],
		[Loc.t("bd_ultimate"), COL_GOLD],
		[Loc.t("go_seizures"), COL_RED],
		[Loc.t("go_smuggled"), COL_DIM],
		[Loc.t("go_favor"), COL_MINT],
		[Loc.t("go_total"), COL_GOLD],
	]
	for i in keys.size():
		var kk: Array = keys[i]
		if i == keys.size() - 1:
			var sep := ColorRect.new()
			sep.color = Color(COL_BORDER_HI, 0.9)
			sep.custom_minimum_size = Vector2(0, 1)
			rv.add_child(sep)
		var v2 := _kv_row(rv, str(kk[0]), kk[1])
		v2.add_theme_font_size_override("font_size", 20 if i == keys.size() - 1 else 15)
		var row_h := v2.get_parent() as Control
		row_h.size_flags_vertical = SIZE_EXPAND_FILL   # even vertical rhythm
		for c in row_h.get_children():
			if c is Label:
				c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		final_ledger_rows.append(v2)
	final_seed = _lbl(rv0, "", 11, COL_FAINT)
	final_seed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bot := HBoxContainer.new()
	bot.alignment = BoxContainer.ALIGNMENT_CENTER
	bot.add_theme_constant_override("separation", 14)
	v.add_child(bot)
	replay_btn = _btn(bot, Loc.t("new_seed"), Vector2(180, 48), COL_GOLD, true, 16, true)
	title_btn = _btn(bot, Loc.t("to_title"), Vector2(150, 48), COL_DIM)
	replay_btn.pressed.connect(func(): new_game(seed + 1); enter_plan())
	title_btn.pressed.connect(func(): new_game(seed); show_mode(Mode.TITLE))


func _build_help() -> void:
	screen_help = Control.new()
	screen_help.name = "ScreenHelp"
	screen_help.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen_help.visible = false
	add_child(screen_help)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen_help.add_child(dim)
	var panel := _panel(screen_help, COL_PANEL_ALT)
	panel.set_anchors_preset(PRESET_CENTER)
	panel.offset_left = -430
	panel.offset_top = -280
	panel.offset_right = 430
	panel.offset_bottom = 280
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	help_title = _lbl(v, Loc.t("field_guide"), 22, COL_LIME, true)
	help_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_body = _lbl(v, "", 15)
	help_body.size_flags_vertical = SIZE_EXPAND_FILL
	help_body.add_theme_constant_override("line_spacing", 6)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	_chip(hb, Loc.t("help_pages"))
	help_dots = _lbl(hb, "● ○", 12, COL_LIME)
	help_dots.autowrap_mode = TextServer.AUTOWRAP_OFF
	help_dots.size_flags_vertical = SIZE_SHRINK_CENTER
	_chip(hb, Loc.t("help_close_chip"))
	help_close = _btn(hb, Loc.t("help_close"), Vector2(140, 36), COL_LIME, false, 13)
	help_close.pressed.connect(func(): help_open = false; _refresh_help())


# ─── game flow (frozen API) ──────────────────────────────────────────────────

func new_game(new_seed: int) -> void:
	seed = new_seed
	game = MarketGame.new(seed)
	report = {}
	help_open = false
	_reset_plan()
	if seed_label:
		seed_label.text = "%s  %04d" % [Loc.t("seed", "种子"), seed]


func _reset_plan() -> void:
	orders = {}
	prices = {}
	smuggle_sel = {}
	contracts_sel = []
	visitor_accept = false
	route_index = -1
	favor_index = 0
	loan_take = false
	_obs = game.observation()
	var prods: Dictionary = _obs["products"]
	for id in game.product_ids:
		orders[id] = 0
		prices[id] = int(prods[id]["price"])
	upgrade_index = 0
	selected_product = clampi(selected_product, 0, game.product_ids.size() - 1)


func _upgrade_choices() -> Array:
	var a: Array = [null]
	for k in game.upgrades.keys():
		a.append(k)
	return a


## Favor spends the player can arm this night (favor_use payloads).
func _favor_options() -> Array:
	var opts: Array = [null, {"type": "contract_waive"}, {"type": "rent_free"}]
	if int(_obs.get("day", 1)) < int(_obs.get("total_days", 18)):
		opts.append({"type": "restock", "product_id": game.product_ids[selected_product]})
	return opts


func _favor_option_label(opt: Variant) -> String:
	if opt == null:
		return Loc.t("favor_none")
	match str((opt as Dictionary).get("type", "")):
		"contract_waive":
			return Loc.t("favor_waive")
		"rent_free":
			return Loc.t("favor_rent")
		"restock":
			return "%s · %s" % [Loc.t("favor_restock"), Loc.product(game.product_ids[selected_product], "short_name", "")]
	return Loc.t("favor_none")


func _build_action() -> Dictionary:
	var o := {}
	var p := {}
	for id in game.product_ids:
		o[id] = orders[id]
		p[id] = prices[id]
	var a := {
		"orders": o, "prices": p,
		"upgrade": _upgrade_choices()[upgrade_index],
		"contracts_accept": contracts_sel.duplicate(),
		"smuggle": {}, "visitor": visitor_accept,
		"route_card": null, "favor_use": null, "loan": false,
	}
	for pid in smuggle_sel:
		if int(smuggle_sel[pid]) > 0:
			a["smuggle"][pid] = int(smuggle_sel[pid])
	var ro: Array = _obs.get("route_offer", [])
	if route_index >= 0 and route_index < ro.size():
		a["route_card"] = str(ro[route_index]["id"])
	if favor_index > 0 and int(_obs.get("favor", 0)) > 0:
		var opts := _favor_options()
		if favor_index < opts.size():
			a["favor_use"] = opts[favor_index]
	if loan_take and bool((_obs.get("debt", {}) as Dictionary).get("loan_available", false)):
		a["loan"] = true
	return a


## Frozen API — historically the permit picker; now selects a route card.
## Clicking / pressing the selected index again cancels the choice.
func select_permit(i: int) -> void:
	var ro: Array = _obs.get("route_offer", [])
	if ro.is_empty():
		return
	var idx := clampi(i, 0, ro.size() - 1)
	route_index = -1 if route_index == idx else idx
	refresh_plan()


func show_mode(m: Mode) -> void:
	mode = m
	screen_title.visible = m == Mode.TITLE
	screen_plan.visible = m == Mode.PLAN
	screen_report.visible = m == Mode.REPORT
	screen_over.visible = m == Mode.GAME_OVER
	_refresh_help()
	if m == Mode.TITLE:
		_refresh_title()
	elif m == Mode.PLAN:
		refresh_plan()
	elif m == Mode.REPORT:
		refresh_report()
	elif m == Mode.GAME_OVER:
		refresh_game_over()


func _refresh_help() -> void:
	screen_help.visible = help_open
	if not help_open:
		return
	if help_page == 0:
		help_title.text = Loc.t("help_p1_title")
		help_body.text = Loc.t("help_v3_p1")
	else:
		help_title.text = Loc.t("help_p2_title")
		help_body.text = Loc.t("help_v3_p2")
	if help_dots:
		help_dots.text = "● ○" if help_page == 0 else "○ ●"


func _refresh_title() -> void:
	title_label.text = Loc.t("app_title_line")
	tag_label.text = Loc.t("tagline")
	blurb_label.text = Loc.t("blurb_v3")
	start_btn.text = Loc.t("open_stall")
	if title_market.has_method("set_mode"):
		title_market.set_mode("ambient")


func enter_plan() -> void:
	_reset_plan()
	show_mode(Mode.PLAN)


func open_market() -> void:
	var result = game.try_step(_build_action())
	if result == null:
		toast = game.last_error
		toast_until = _time + 3.5
		refresh_plan()
		return
	report = result["report"]
	show_mode(Mode.REPORT)


func continue_from_report() -> void:
	if game.state.get("done", false):
		show_mode(Mode.GAME_OVER)
	else:
		enter_plan()


## Frozen API — campaigns were removed with gameplay v3; kept as a no-op.
func cycle_campaign() -> void:
	pass


func cycle_upgrade() -> void:
	for _i in _upgrade_choices().size():
		upgrade_index = (upgrade_index + 1) % _upgrade_choices().size()
		var id = _upgrade_choices()[upgrade_index]
		if id == null:
			break
		if int(game.state["upgrade_levels"][id]) < int(game.upgrades[id]["max_level"]):
			break
	refresh_plan()


func cycle_favor() -> void:
	favor_index = (favor_index + 1) % _favor_options().size()
	refresh_plan()


## Click on the favor mini card: pick the spend from a popup (no blind cycling).
func _open_favor_menu() -> void:
	if int(_obs.get("favor", 0)) <= 0:
		toast = Loc.t("favor_empty_sub")
		toast_until = _time + 2.5
		refresh_plan()
		return
	favor_menu.clear()
	var opts := _favor_options()
	for i in opts.size():
		favor_menu.add_radio_check_item(_favor_option_label(opts[i]), i)
		favor_menu.set_item_checked(i, i == favor_index)
	favor_menu.position = Vector2i(get_global_mouse_position()) + Vector2i(6, 6)
	favor_menu.popup()


func toggle_contract(i: int) -> void:
	var board: Array = (_obs.get("contracts", {}) as Dictionary).get("board", [])
	if i < 0 or i >= board.size():
		return
	var cid := str(board[i]["id"])
	if cid in contracts_sel:
		contracts_sel.erase(cid)
	else:
		contracts_sel.append(cid)
	refresh_plan()


func adjust_smuggle(offer_idx: int, delta: int) -> void:
	var offers: Array = _obs.get("smuggle", [])
	if offer_idx < 0 or offer_idx >= offers.size():
		return
	var o: Dictionary = offers[offer_idx]
	var pid := str(o["product_id"])
	var old := int(smuggle_sel.get(pid, 0))
	var q := clampi(old + delta, 0, int(o["limit"]))
	smuggle_sel[pid] = q
	if q != old and game.try_quote_action(_build_action()) == null:
		smuggle_sel[pid] = old
		toast = game.last_error
		toast_until = _time + 3.5
	refresh_plan()


func set_visitor(v: bool) -> void:
	visitor_accept = v
	refresh_plan()


func toggle_loan() -> void:
	if not bool((_obs.get("debt", {}) as Dictionary).get("loan_available", false)):
		toast = Loc.t("loan_na")
		toast_until = _time + 3.0
		refresh_plan()
		return
	loan_take = not loan_take
	refresh_plan()


func toggle_ledger() -> void:
	ledger_open = not ledger_open
	ledger_panel.visible = ledger_open
	if ledger_open:
		_refresh_ledger()


func select_product(i: int) -> void:
	selected_product = posmod(i, game.product_ids.size())
	refresh_plan()


func adjust_order(delta: int) -> void:
	var id: String = game.product_ids[selected_product]
	var old := int(orders[id])
	orders[id] = clampi(old + delta, 0, 99)
	if game.try_quote_action(_build_action()) == null:
		orders[id] = old
		toast = game.last_error
		toast_until = _time + 3.5
	refresh_plan()


func adjust_price(delta: int) -> void:
	var id: String = game.product_ids[selected_product]
	var b := game.price_bounds(id)
	prices[id] = clampi(int(prices[id]) + delta, b.x, b.y)
	refresh_plan()


# ─── plan screen rendering ───────────────────────────────────────────────────

func _style_row(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	var r: Dictionary = _rows[i]
	var row: PanelContainer = r["panel"]
	var sel := i == selected_product
	if sel:
		row.add_theme_stylebox_override("panel", _sb(Color("#1A2033"), COL_LIME, 10, 1, 12, 6))
	elif i == _hover_row:
		row.add_theme_stylebox_override("panel", _sb(Color("#131728"), COL_BORDER_HI, 10, 1, 12, 6))
	else:
		row.add_theme_stylebox_override("panel", _sb(COL_INSET, Color("#1E2338"), 10, 1, 12, 6))
	var marker: Label = r["marker"]
	marker.modulate.a = 1.0 if sel else 0.0
	# steppers live in fixed slots on every row; unselected rows just fade them
	# and drop the hit-test so the number column never shifts (fix B2)
	for b in r["btns"]:
		var btn: Button = b
		btn.modulate.a = 1.0 if sel else 0.0
		btn.disabled = not sel
		btn.mouse_filter = MOUSE_FILTER_STOP if sel else MOUSE_FILTER_IGNORE


func _stepper(parent: Node, glyph: String, cb: Callable) -> Button:
	var b := _btn(parent, glyph, Vector2(24, 24), COL_LIME, false, 13)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	for k in ["normal", "hover", "pressed", "disabled"]:
		var sbx: StyleBoxFlat = b.get_theme_stylebox(k)
		sbx.content_margin_left = 2
		sbx.content_margin_right = 2
		sbx.content_margin_top = 1
		sbx.content_margin_bottom = 1
		sbx.set_corner_radius_all(6)
	b.pressed.connect(cb)
	return b


func _rebuild_rows(prods: Dictionary, trend: Dictionary, forecasts: Dictionary) -> void:
	for c in product_list.get_children():
		c.queue_free()
	_rows.clear()
	var lead_tags := _leading_gain_tags()
	for i in game.product_ids.size():
		var id: String = game.product_ids[i]
		var p: Dictionary = prods[id]
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, 62)
		row.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", ROW_SEP)
		row.add_child(h)
		var cells := _manifest_cells(h)
		# marker
		var marker := _lbl(cells["marker"], "▶", 13, COL_LIME, true)
		marker.autowrap_mode = TextServer.AUTOWRAP_OFF
		# icon plate
		_plate(cells["icon"], 42, _tex("res://assets/icons/product_%s.png" % id))
		# name + memory hint + tags
		var nrow := HBoxContainer.new()
		nrow.add_theme_constant_override("separation", 8)
		cells["name"].add_child(nrow)
		var nm := _lbl(nrow, Loc.product(id, "name", str(p["name"])), 15, COL_TEXT, true)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		var mem := float(p.get("price_memory", 1.0))
		if mem < 0.999:
			var mc := _chip(nrow, "↩ " + Loc.t("mem_high"), COL_RED, Color(COL_RED, 0.45))
			mc.size_flags_vertical = SIZE_SHRINK_CENTER
		elif mem > 1.001:
			var mc2 := _chip(nrow, "↩ " + Loc.t("mem_low"), COL_MINT, Color(COL_MINT, 0.45))
			mc2.size_flags_vertical = SIZE_SHRINK_CENTER
		# late-season perishables: stock bought now dies before the finale (§2.9)
		var day_now := int(_obs.get("day", 1))
		var total_days := int(_obs.get("total_days", 18))
		var sl = p.get("shelf_life", null)
		if sl != null and day_now >= 13 and day_now + int(sl) - 1 < total_days:
			var xc := _chip(nrow, "⏳ " + Loc.t("expire_finale_chip"), COL_RED, Color(COL_RED, 0.45))
			xc.size_flags_vertical = SIZE_SHRINK_CENTER
		# tag line: fixed shelf-life chip + colored tag chips + tomorrow badge (§2/§3)
		var tag_row := HBoxContainer.new()
		tag_row.add_theme_constant_override("separation", 4)
		cells["name"].add_child(tag_row)
		if sl == null:
			_tag_chip(tag_row, Loc.t("durable_chip"), COL_DIM)
		else:
			_tag_chip(tag_row, "%s%d%s" % [Loc.t("life"), int(sl), Loc.t("nights_unit")],
				COL_GOLD if int(sl) <= 2 else COL_DIM)
		var hits_lead := false
		for tg in p.get("tags", []):
			var tgs := str(tg)
			_tag_chip(tag_row, Loc.rumor_tag(tgs), _tag_color(tgs))
			if tgs in lead_tags:
				hits_lead = true
		if hits_lead:
			_tag_chip(tag_row, Loc.t("tomorrow_up"), COL_GOLD)
		# 5-night procurement trend sparkline (§2.1)
		_sparkline(cells["trend"], trend.get(id, []))
		# stock + shelf-life badge: earliest batch days-left × units (FIFO signal)
		var inv: Dictionary = p["inventory"]
		var scol := VBoxContainer.new()
		scol.add_theme_constant_override("separation", 0)
		scol.size_flags_vertical = SIZE_SHRINK_CENTER
		cells["stock"].add_child(scol)
		_num(scol, str(inv["units"]), 14, COL_RED if int(inv.get("expiring", 0)) > 0 else COL_TEXT, W_STOCK - 4)
		var mdl := int(inv.get("min_days_left", -1))
		if mdl >= 1 and mdl <= 2:
			var badge := _num(scol, "⏳%d%s×%d" % [mdl, Loc.t("nights_unit"), int(inv.get("min_days_units", 0))],
				9, COL_RED if mdl == 1 else COL_GOLD, W_STOCK - 4)
			badge.add_theme_font_override("font", _font)
		# order stepper (fixed slots)
		var bminus := _stepper(cells["order"], "−", adjust_order.bind(-1))
		var onum := int(orders[id])
		var oval := _num(cells["order"], str(onum), 15, COL_LIME if onum > 0 else COL_FAINT, 34, HORIZONTAL_ALIGNMENT_CENTER)
		if onum == 0:
			oval.add_theme_font_override("font", _font)
		oval.size_flags_vertical = SIZE_SHRINK_CENTER
		var bplus := _stepper(cells["order"], "＋", adjust_order.bind(1))
		# price stepper — digits right-aligned in a fixed slot (spec 3.3), the
		# ↓/↑ steppers hang on both sides of the aligned number
		var bdown := _stepper(cells["price"], "↓", adjust_price.bind(-1))
		var pval := _num(cells["price"], Loc.money(int(prices[id])), 15, COL_GOLD, 40)
		pval.size_flags_vertical = SIZE_SHRINK_CENTER
		var bup := _stepper(cells["price"], "↑", adjust_price.bind(1))
		# cost / forecast — the forecast cell goes gold when planned supply cannot
		# even reach the demand band's floor (§8: sales limited by stocking)
		var cost := _num(cells["cost"], Loc.money(int(p["unit_cost_today"])), 13, COL_DIM, W_COST - 4)
		cost.size_flags_vertical = SIZE_SHRINK_CENTER
		var fc: Dictionary = forecasts.get(id, p.get("forecast", {"low": 0, "high": 0}))
		var planned_supply := int(inv["units"]) + int(orders[id]) + int(smuggle_sel.get(id, 0))
		var supply_short := planned_supply < int(fc["low"])
		var fcl := _num(cells["fcst"], "%d–%d" % [int(fc["low"]), int(fc["high"])], 13,
			COL_GOLD if supply_short else COL_DIM, W_FCST - 4)
		if supply_short:
			fcl.tooltip_text = Loc.t("stock_limited")
		fcl.size_flags_vertical = SIZE_SHRINK_CENTER
		var idx := i
		row.gui_input.connect(_on_row_input.bind(idx))
		row.mouse_entered.connect(func(): _hover_row = idx; _style_row(idx))
		row.mouse_exited.connect(func():
			if _hover_row == idx:
				_hover_row = -1
			_style_row(idx))
		product_list.add_child(row)
		_rows.append({"panel": row, "marker": marker, "btns": [bminus, bplus, bdown, bup]})
		_style_row(i)


func _on_row_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_product(idx)


## Shared tag palette — manifest rows, crowd card and rumor gain chips all
## color a tag the same way (§3).
func _tag_color(tag: String) -> Color:
	match tag:
		"food", "drink", "sweet", "protein":
			return COL_GOLD
		"tech", "glow", "fizzy":
			return COL_CYAN
		"luxury", "premium", "exotic":
			return COL_VIOLET
		"cute", "gift":
			return COL_MAGENTA
		"calm", "bio":
			return COL_MINT
		_:
			return COL_DIM


func _kind_color(kind: String) -> Color:
	match kind:
		"bulk":
			return COL_GOLD
		"ultimate":
			return COL_MAGENTA
		_:
			return COL_CYAN


func refresh_plan() -> void:
	var obs: Dictionary = game.observation()
	_obs = obs
	_quote = game.try_quote_action(_build_action())
	hdr_night.text = "%02d / %02d" % [obs["day"], obs["total_days"]]
	hdr_cash.text = Loc.money(int(obs["cash"]))
	hdr_rep.text = str(int(obs["reputation"]))
	var used := int(obs["inventory_used"])
	var cap := int(obs["capacity"])
	hdr_cargo.text = "%d / %d" % [used, cap]
	var full := cap > 0 and float(used) / float(cap) >= 0.85
	hdr_cargo.add_theme_color_override("font_color", COL_RED if full else COL_MINT)
	hdr_cargo_bar.color = COL_RED if full else COL_MINT
	# risk metric card: projected heat + tonight's inspection odds (§2.3) — the
	# arrow shows where THIS plan pushes the heat, matching the quoted odds
	var iprob := float(obs["inspection_prob"])
	var heat_now := int(obs["heat"])
	var heat_proj := heat_now
	if _quote != null:
		iprob = float(_quote["inspection_prob"])
		heat_proj = int(_quote["projected_heat"])
	# one decimal everywhere — same rounding as the smuggle-bay footer (§1)
	if heat_proj != heat_now:
		hdr_risk.text = "%d→%d · %.1f%%" % [heat_now, heat_proj, iprob]
	else:
		hdr_risk.text = "%d · %.1f%%" % [heat_now, iprob]
	var risk_col := COL_RED if iprob >= 25.0 else (COL_GOLD if heat_proj > 0 else COL_MINT)
	hdr_risk.add_theme_color_override("font_color", risk_col)
	hdr_risk_bar.color = risk_col
	# event + rumors
	var market: Dictionary = obs["market"]
	var ev: Dictionary = market["event"]
	var gr: Dictionary = market["customer_group"]
	signal_name.text = Loc.event(str(ev["id"]), "name", str(ev["name"]))
	signal_head.text = Loc.event(str(ev["id"]), "headline", str(ev.get("headline", "")))
	_refresh_rumors(obs)
	crowd_text.text = Loc.group(str(gr["id"]), "name", str(gr["name"]))
	for c in crowd_tags.get_children():
		c.queue_free()
	for tag in gr.get("preferred_tags", []):
		var tg := str(tag)
		_chip(crowd_tags, Loc.rumor_tag(tg), _tag_color(tg))
	var gtex := _customer_tex(str(gr["id"]))
	if gtex:
		crowd_icon.texture = gtex
	# manifest
	var forecasts: Dictionary = {}
	if _quote != null:
		forecasts = _quote["demand_forecasts"]
	_rebuild_rows(obs["products"], obs.get("market_trend", {}), forecasts)
	# strategy panels
	_refresh_plan_box(obs)
	_refresh_contracts(obs)
	_refresh_smuggle(obs)
	_refresh_visitor(obs)
	_refresh_route(obs)
	_refresh_upgrade_favor(obs)
	if ledger_open:
		_refresh_ledger()
	# bottom detail
	var prods: Dictionary = obs["products"]
	var sid: String = game.product_ids[selected_product]
	var sp: Dictionary = prods[sid]
	detail_name.text = Loc.product(sid, "name", str(sp["name"]))
	detail_desc.text = Loc.product(sid, "description", str(sp["description"]))
	detail_icon.texture = _tex("res://assets/icons/product_%s.png" % sid)
	# selected product's batch spread: days-left × units, oldest first
	var bparts: Array = []
	for b in (sp["inventory"] as Dictionary).get("batches", []):
		bparts.append("%d%s×%d" % [int(b["days_left"]), Loc.t("nights_unit"), int(b["units"])])
	detail_batches.visible = not bparts.is_empty()
	detail_batches.text = ("%s：%s" % [Loc.t("batches_label"), " · ".join(bparts)]) if not bparts.is_empty() else ""
	if toast != "" and _time < toast_until:
		tip_chip.visible = false
		toast_label.text = "⚠ " + toast
		toast_label.add_theme_color_override("font_color", COL_RED)
	elif _quote != null and int(_quote["projected_units"]) >= int(_quote["projected_capacity"]):
		# warnings are red across the board (spec 3.3) — gold stays for tips
		tip_chip.visible = false
		toast_label.text = "⚠ " + Loc.t("cargo_full")
		toast_label.add_theme_color_override("font_color", COL_RED)
	else:
		toast = ""
		tip_chip.visible = true
		toast_label.text = Loc.tip(int(obs["day"]) - 1)
		toast_label.add_theme_color_override("font_color", COL_DIM)


## Top-2 demand-boost tags of an event — the "why bet on this rumor" half of
## the capsule, derived straight from the event's demand table.
func _event_gain_tags(eid: String) -> Array:
	var ev: Dictionary = game.events.get(eid, {})
	var eff: Dictionary = ev.get("effects", {})
	var tag_mults: Dictionary = eff.get("demand_tags", {})
	var gains: Array = []
	for t in tag_mults:
		if float(tag_mults[t]) > 1.0:
			gains.append([str(t), float(tag_mults[t])])
	gains.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array = []
	for i in mini(2, gains.size()):
		out.append(str(gains[i][0]))
	return out


## Gain tags as standalone mini chips, same word list + palette as the
## manifest-row tag chips (§3).
func _append_gain_chips(parent: Node, eid: String) -> void:
	var tags := _event_gain_tags(eid)
	for t in tags:
		_tag_chip(parent, "%s↑" % Loc.rumor_tag(str(t)), _tag_color(str(t)))
	if tags.is_empty():
		var eff: Dictionary = (game.events.get(eid, {}) as Dictionary).get("effects", {})
		if float(eff.get("demand_all", 1.0)) > 1.0:
			_tag_chip(parent, "%s↑" % Loc.t("all_goods"), COL_GOLD)


## Gain tags of tomorrow's leading rumor candidate → "明晚↑" row badges (§3).
func _leading_gain_tags() -> Array:
	var pair: Array = (_obs.get("rumors", {}) as Dictionary).get("tomorrow", [])
	if pair.is_empty():
		return []
	var lead: Dictionary = pair[0]
	for cand in pair:
		if int(cand["prob"]) > int(lead["prob"]):
			lead = cand
	return _event_gain_tags(str(lead["event_id"]))


## Tomorrow's rumor pair + the fog icon for the night after (§2.1).
func _refresh_rumors(obs: Dictionary) -> void:
	for c in rumor_row.get_children():
		c.queue_free()
	for c in fog_row.get_children():
		c.queue_free()
	var ru: Dictionary = obs.get("rumors", {})
	var lab := _lbl(rumor_row, Loc.t("rumor_tomorrow"), 11, COL_FAINT)
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.size_flags_vertical = SIZE_SHRINK_CENTER
	var pair: Array = ru.get("tomorrow", [])
	if pair.is_empty():
		_chip(rumor_row, "—", COL_FAINT)
	elif bool(ru.get("certain", false)):
		var e0 := str(pair[0]["event_id"])
		_chip(rumor_row, "%s · %s 100%%" % [Loc.t("rumor_certain"), Loc.event(e0, "name", e0)], COL_GOLD, Color(COL_GOLD, 0.5))
		_append_gain_chips(rumor_row, e0)
	else:
		for j in pair.size():
			var cand: Dictionary = pair[j]
			var eid := str(cand["event_id"])
			var main := int(cand["prob"]) >= 50
			_chip(rumor_row, "%s %d%%" % [Loc.event(eid, "name", eid), int(cand["prob"])],
				COL_CYAN if main else COL_DIM, Color(COL_CYAN, 0.45) if main else COL_BORDER)
			_append_gain_chips(rumor_row, eid)
			if j == 0 and pair.size() > 1:
				var sl := _lbl(rumor_row, "/", 11, COL_FAINT)
				sl.size_flags_vertical = SIZE_SHRINK_CENTER
	# night after: fog tag, or full pair with intel antenna Lv2
	var later: Array = ru.get("later", [])
	var flab := _lbl(fog_row, Loc.t("rumor_later"), 11, COL_FAINT)
	flab.autowrap_mode = TextServer.AUTOWRAP_OFF
	flab.size_flags_vertical = SIZE_SHRINK_CENTER
	if not later.is_empty():
		for j in later.size():
			var cand2: Dictionary = later[j]
			var eid2 := str(cand2["event_id"])
			_chip(fog_row, "%s %d%%" % [Loc.event(eid2, "name", eid2), int(cand2["prob"])], COL_VIOLET, Color(COL_VIOLET, 0.4))
			_append_gain_chips(fog_row, eid2)
	else:
		var hint := str(ru.get("later_hint", ""))
		if hint == "":
			_chip(fog_row, "？", COL_FAINT)
		else:
			_chip(fog_row, "◌ %s" % Loc.rumor_tag(hint), COL_VIOLET, Color(COL_VIOLET, 0.4))


func _refresh_plan_box(obs: Dictionary) -> void:
	if _quote != null:
		var spend := int(_quote["total_spend"])
		var deposits := int(_quote["deposits"])
		var loan_amt := int(_quote["loan_amount"])
		var left := int(obs["cash"]) + loan_amt + deposits - spend
		var est: Dictionary = _quote["estimated_revenue"]
		plan_kv["spend"].text = Loc.money(spend)
		var dep_row := plan_kv["deposit"].get_parent() as Control
		dep_row.visible = deposits > 0
		plan_kv["deposit"].text = "+" + Loc.money(deposits)
		plan_kv["safe"].text = Loc.money(left)
		plan_kv["safe"].add_theme_color_override("font_color", COL_RED if left < 10 else COL_GOLD)
		var est_lo := int(est["low"])
		var est_hi := int(est["high"])
		plan_kv["fcst"].text = Loc.money(est_lo) if est_lo == est_hi else "%s–%s" % [Loc.money(est_lo), Loc.money(est_hi)]
		# rent rides with the spend block — a certain expense, not a worst case (§4)
		plan_kv["rent"].text = Loc.money(-int(_quote["rent"]))
		var best := int(_quote["best_case"])
		var worst := int(_quote["worst_case"])
		plan_kv["best"].text = ("+" if best >= 0 else "") + Loc.money(best)
		plan_kv["worst"].text = ("+" if worst >= 0 else "") + Loc.money(worst)
		plan_kv["worst"].add_theme_color_override("font_color", COL_RED if worst < 0 else COL_DIM)
		# worst-case audit trail (§4): strict sum — best + the rows below = worst
		# (visitor deltas are identical in both cases, rent cancels out)
		_set_sub(worst_rows["from_best"], best)
		_set_sub(worst_rows["est_low"], -(est_hi - est_lo))
		_set_sub(worst_rows["due_rev"], -int(_quote["contract_due_revenue"]))
		_set_sub(worst_rows["seize"], -int(_quote["worst_inspect"]))
		_set_sub(worst_rows["breach"], -int(_quote["worst_due_penalty"]))
		if not worst_open:
			for k in worst_rows:
				(worst_rows[k].get_parent() as Control).visible = false
		worst_key_label.text = "%s %s" % [Loc.t("worst_case"), "▾" if worst_open else "▸"]
		# standing contract exposure — red once it outruns the worst-case cash
		var expo := int(_quote["contract_exposure"])
		(plan_kv["exposure"].get_parent() as Control).visible = expo > 0
		plan_kv["exposure"].text = Loc.money(expo)
		plan_kv["exposure"].add_theme_color_override("font_color",
			COL_RED if expo > int(obs["cash"]) + worst else COL_GOLD)
		# header cargo card tracks the planned load so both readouts agree
		var pu := int(_quote["projected_units"])
		var pcap := int(_quote["projected_capacity"])
		hdr_cargo.text = "%d / %d" % [pu, pcap]
		var pfull := pcap > 0 and float(pu) / float(pcap) >= 0.85
		hdr_cargo.add_theme_color_override("font_color", COL_RED if pfull else COL_MINT)
		hdr_cargo_bar.color = COL_RED if pfull else COL_MINT
		plan_block_label.visible = false
		open_btn.disabled = false
		open_btn.text = Loc.t("open_market")
	else:
		for k in plan_kv:
			plan_kv[k].text = "—"
		(plan_kv["deposit"].get_parent() as Control).visible = false
		(plan_kv["exposure"].get_parent() as Control).visible = false
		for k in worst_rows:
			(worst_rows[k].get_parent() as Control).visible = false
		worst_key_label.text = "%s %s" % [Loc.t("worst_case"), "▾" if worst_open else "▸"]
		plan_block_label.text = "%s：%s" % [Loc.t("plan_blocked"), game.last_error]
		plan_block_label.visible = true
		open_btn.disabled = true
		open_btn.text = Loc.t("blocked")
	# favor stock is visible whether or not the quote went through
	plan_kv["favor"].text = "%d / 3" % int(obs.get("favor", 0))
	# armed favor spend echoes back like the loan plan does
	var fopts := _favor_options()
	if favor_index > 0 and favor_index < fopts.size() and int(obs.get("favor", 0)) > 0:
		favor_hint.visible = true
		favor_hint.text = "✓ %s：%s" % [Loc.t("favor_armed"), _favor_option_label(fopts[favor_index])]
	else:
		favor_hint.visible = false
	# loan hint under the plan box
	var debt: Dictionary = obs.get("debt", {})
	if loan_take:
		plan_hint.visible = true
		plan_hint.text = "✓ " + Loc.t("loan_planned")
		plan_hint.add_theme_color_override("font_color", COL_MINT)
	elif bool(debt.get("loan_available", false)):
		plan_hint.visible = true
		plan_hint.text = "⚠ " + Loc.t("loan_hint")
		plan_hint.add_theme_color_override("font_color", COL_GOLD)
	else:
		plan_hint.visible = false


## Contract board cards + active contract countdown rows (§2.2).
func _refresh_contracts(obs: Dictionary) -> void:
	for c in contracts_box.get_children():
		c.queue_free()
	for c in active_box.get_children():
		c.queue_free()
	var cons: Dictionary = obs.get("contracts", {})
	var board: Array = cons.get("board", [])
	var active_list: Array = cons.get("active", [])
	var day := int(obs["day"])
	# planned supply per product (stock + orders + smuggle + armed favor restock)
	# — same net-of-reservations arithmetic the quote uses for due contracts
	var restock_pid := ""
	var restock_units := 0
	if favor_index > 0 and int(obs.get("favor", 0)) > 0:
		var fopts := _favor_options()
		if favor_index < fopts.size() and fopts[favor_index] != null \
				and str((fopts[favor_index] as Dictionary).get("type", "")) == "restock":
			restock_pid = str((fopts[favor_index] as Dictionary).get("product_id", ""))
			restock_units = int(game.favor_cfg.get("restock_qty", 5))
	for i in board.size():
		var card: Dictionary = board[i]
		var kind := str(card["kind"])
		var kcol := _kind_color(kind)
		var accepted := str(card["id"]) in contracts_sel
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel",
			_sb(Color(kcol, 0.09) if accepted else COL_INSET, Color(kcol, 0.9 if accepted else 0.45), 10, 1, 10, 5))
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
		contracts_box.add_child(panel)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		panel.add_child(cv)
		var r1 := HBoxContainer.new()
		r1.add_theme_constant_override("separation", 6)
		cv.add_child(r1)
		var kc := _chip(r1, "%d·%s" % [i + 3, Loc.contract_line(kind, "name")], kcol, Color(kcol, 0.5))
		kc.size_flags_vertical = SIZE_SHRINK_CENTER
		_spacer(r1, false)
		var tot := _lbl(r1, Loc.money(int(card["total"])), 14, COL_GOLD, true)
		tot.autowrap_mode = TextServer.AUTOWRAP_OFF
		var pid := str(card["product_id"])
		var nm := _lbl(cv, "%s ×%d" % [Loc.product(pid, "name", pid), int(card["qty"])], 13, COL_TEXT, true)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var due := int(card["due_day"])
		var due_txt := Loc.t("due_tonight") if due <= day else "%s 夜%02d（%s%d%s）" % [Loc.t("deadline"), due, Loc.t("nights_left"), due - day, Loc.t("nights_unit")]
		var dep_txt := ""
		if int(card["deposit"]) > 0:
			dep_txt = " · %s+%s" % [Loc.sec("contracts", "deposit", "定金"), Loc.money(int(card["deposit"]))]
		var l2 := _lbl(cv, "%s ×%d%s · %s" % [Loc.money(int(card["unit_price"])), int(card["qty"]), dep_txt, due_txt], 10, COL_DIM)
		l2.autowrap_mode = TextServer.AUTOWRAP_OFF
		l2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		# penalty detail line
		var l3 := _lbl(cv, "%s %s · %s −%d" % [Loc.t("penalty_short"), Loc.money(int(card["penalty"])), Loc.t("reputation"), int(card["rep_penalty"])], 10, Color(COL_RED, 0.85))
		l3.autowrap_mode = TextServer.AUTOWRAP_OFF
		l3.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		# delivery feasibility: planned supply minus what other contracts claim
		var supply := int(((obs["products"] as Dictionary)[pid]["inventory"])["units"]) \
			+ int(orders.get(pid, 0)) + int(smuggle_sel.get(pid, 0))
		if pid == restock_pid:
			supply += restock_units
		var reserved := 0
		for j in board.size():
			if j != i and str(board[j]["id"]) in contracts_sel and str(board[j]["product_id"]) == pid:
				reserved += int(board[j]["qty"])
		for ac in active_list:
			if str(ac["product_id"]) == pid:
				reserved += int(ac["qty"])
		var got := clampi(supply - reserved, 0, int(card["qty"]))
		var gap := int(card["qty"]) - got
		var l4txt := "%s %d/%d" % [Loc.t("stocked_label"), got, int(card["qty"])]
		if gap > 0:
			l4txt += " · %s%d" % [Loc.t("stockout_short"), gap]
		var l4 := _lbl(cv, l4txt, 10, COL_RED if gap > 0 else Color(COL_MINT, 0.85), gap > 0)
		l4.autowrap_mode = TextServer.AUTOWRAP_OFF
		var acc_btn := _btn(cv, ("✓ %s / %s" % [Loc.t("accepted_chip"), Loc.sec("contracts", "decline", "放弃")]) if accepted else Loc.sec("contracts", "accept", "接单"),
			Vector2(0, 24), kcol, accepted, 11)
		if gap > 0:
			# shortfall warning ring on the accept button
			for sk in ["normal", "hover"]:
				var wsb: StyleBoxFlat = acc_btn.get_theme_stylebox(sk)
				wsb.border_color = COL_RED
		var bi := i
		acc_btn.pressed.connect(toggle_contract.bind(bi))
	# active contracts with countdown
	var active: Array = cons.get("active", [])
	if not active.is_empty():
		var t := _lbl(active_box, Loc.t("contract_active"), 11, COL_FAINT, true)
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
	for c in active:
		var kind2 := str(c["kind"])
		var pid2 := str(c["product_id"])
		var nleft := int(c.get("nights_left", int(c["due_day"]) - day))
		var urgent := nleft <= 0
		var rowp := PanelContainer.new()
		rowp.add_theme_stylebox_override("panel", _sb(COL_INSET, Color(COL_RED, 0.6) if urgent else COL_BORDER, 8, 1, 8, 4))
		active_box.add_child(rowp)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 8)
		rowp.add_child(rh)
		var kc2 := _chip(rh, Loc.contract_line(kind2, "name"), _kind_color(kind2), Color(_kind_color(kind2), 0.4))
		kc2.size_flags_vertical = SIZE_SHRINK_CENTER
		var txt := "%s ×%d" % [Loc.product(pid2, "short_name", pid2), int(c["qty"])]
		var al := _lbl(rh, txt, 12, COL_TEXT, true)
		al.autowrap_mode = TextServer.AUTOWRAP_OFF
		al.size_flags_horizontal = SIZE_EXPAND_FILL
		var cd_txt := Loc.t("due_tonight") if urgent else "%s%d%s" % [Loc.t("nights_left"), nleft, Loc.t("nights_unit")]
		var cd := _lbl(rh, cd_txt, 12, COL_RED if urgent or nleft == 1 else COL_DIM, true)
		cd.autowrap_mode = TextServer.AUTOWRAP_OFF
	# vip promise reminder rides along with active contracts
	var promise = obs.get("vip_promise", null)
	if promise != null:
		var ppid := str(promise["product_id"])
		var prowp := PanelContainer.new()
		prowp.add_theme_stylebox_override("panel", _sb(COL_INSET, Color(COL_MAGENTA, 0.5), 8, 1, 8, 4))
		active_box.add_child(prowp)
		var prh := HBoxContainer.new()
		prh.add_theme_constant_override("separation", 8)
		prowp.add_child(prh)
		var pc := _chip(prh, Loc.visitor_line("vip", "name"), COL_MAGENTA, Color(COL_MAGENTA, 0.4))
		pc.size_flags_vertical = SIZE_SHRINK_CENTER
		var pl := _lbl(prh, "%s ×%d · %s" % [Loc.product(ppid, "short_name", ppid), int(promise["qty"]), Loc.t("due_tonight")], 12, COL_TEXT, true)
		pl.autowrap_mode = TextServer.AUTOWRAP_OFF


## Smuggle bay rows: icon + limit stepper + price + heat gain (§2.3).
func _refresh_smuggle(obs: Dictionary) -> void:
	for c in smuggle_box.get_children():
		c.queue_free()
	var offers: Array = obs.get("smuggle", [])
	if offers.is_empty():
		var l := _lbl(smuggle_box, Loc.sec("finale", "closed") if int(obs["day"]) >= int(obs["total_days"]) else "—", 11, COL_FAINT)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		smuggle_note.text = ""
		return
	var heat_add := 0
	for i in offers.size():
		var o: Dictionary = offers[i]
		var pid := str(o["product_id"])
		var q := int(smuggle_sel.get(pid, 0))
		heat_add += q * int(o["heat_per_unit"])
		var rowp := PanelContainer.new()
		rowp.add_theme_stylebox_override("panel", _sb(COL_INSET, Color(COL_RED, 0.55 if q > 0 else 0.3), 8, 1, 8, 2))
		smuggle_box.add_child(rowp)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 6)
		rowp.add_child(rh)
		var ic := TextureRect.new()
		ic.texture = _tex("res://assets/icons/product_%s.png" % pid)
		ic.custom_minimum_size = Vector2(22, 22)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.size_flags_vertical = SIZE_SHRINK_CENTER
		rh.add_child(ic)
		var nm := _lbl(rh, Loc.product(pid, "short_name", pid), 13, COL_TEXT, true)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.size_flags_vertical = SIZE_SHRINK_CENTER
		var sub := _lbl(rh, "%s%s · %s%d · %s%d" % [Loc.t("smuggle_price"), Loc.money(int(o["unit_price"])), Loc.t("limit_label"), int(o["limit"]), Loc.t("heat_plus"), int(o["heat_per_unit"])], 10, COL_FAINT)
		sub.autowrap_mode = TextServer.AUTOWRAP_OFF
		sub.size_flags_horizontal = SIZE_EXPAND_FILL
		sub.size_flags_vertical = SIZE_SHRINK_CENTER
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var oi := i
		var bminus := _stepper(rh, "−", adjust_smuggle.bind(oi, -1))
		bminus.modulate.a = 1.0
		var qv := _num(rh, str(q), 14, COL_RED if q > 0 else COL_FAINT, 26, HORIZONTAL_ALIGNMENT_CENTER)
		qv.size_flags_vertical = SIZE_SHRINK_CENTER
		var bplus := _stepper(rh, "＋", adjust_smuggle.bind(oi, 1))
		bplus.modulate.a = 1.0
	# footer spells the whole formula out with the SAME quote exports the top
	# capsule uses: 热度23 ×0.6事件 = 13.8%（地板6%） (§1)
	var iprob := float(obs["inspection_prob"])
	if _quote != null:
		iprob = float(_quote["inspection_prob"])
		smuggle_note.text = "%s%d ×%.1f%s = %.1f%%（%s%.0f%%）" % [
			Loc.sec("smuggle", "heat"), int(_quote["projected_heat"]),
			float(_quote["inspect_mult"]), Loc.t("insp_event_short"),
			iprob, Loc.t("insp_floor_short"), float(_quote["inspect_floor"])]
	else:
		smuggle_note.text = "%s %.1f%%" % [Loc.sec("smuggle", "inspection"), iprob]
	smuggle_note.add_theme_color_override("font_color", COL_RED if iprob >= 25.0 else COL_DIM)


## Dusk visitor card: named character, quoted offer, accept / decline (§2.5).
func _refresh_visitor(obs: Dictionary) -> void:
	var vis: Dictionary = obs.get("visitor", {})
	var has := not vis.is_empty()
	visitor_section.visible = has
	visitor_panel.visible = has
	if not has:
		return
	var kind := str(vis["kind"])
	visitor_name_l.text = "%s · %s" % [Loc.visitor_line(kind, "title"), Loc.visitor_line(kind, "name")]
	visitor_line_l.text = Loc.visitor_line(kind, "offer")
	match kind:
		"sweeper":
			visitor_num_l.text = "×%d · ≈ +%s" % [int(vis.get("units", 0)), Loc.money(int(vis.get("payout_est", 0)))]
		"informant":
			visitor_num_l.text = "−%s → %s −%d" % [Loc.money(int(vis.get("cost", 0))), Loc.sec("smuggle", "heat"), int(vis.get("heat_relief", 0))]
		"broker":
			visitor_num_l.text = "−%s → %s" % [Loc.money(int(vis.get("cost", 0))), Loc.t("rumor_certain")]
		"vip":
			var vpid := str(vis.get("product_id", ""))
			visitor_num_l.text = "%s ×%d · %s/%s · 明晚留 %d" % [Loc.product(vpid, "short_name", vpid), int(vis.get("qty", 0)), Loc.money(int(vis.get("unit_price", 0))), Loc.t("units_unit"), int(vis.get("promise_qty", 0))]
		"cameo":
			visitor_num_l.text = "+%s" % Loc.money(int(vis.get("tip", 0)))
	for c in visitor_btns.get_children():
		c.queue_free()
	var acc := _btn(visitor_btns, ("✓ " + Loc.t("visitor_accept")) if visitor_accept else Loc.t("visitor_accept"),
		Vector2(0, 30), COL_MAGENTA, visitor_accept, 12)
	acc.size_flags_horizontal = SIZE_EXPAND_FILL
	acc.pressed.connect(set_visitor.bind(true))
	var dec := _btn(visitor_btns, ("✓ " + Loc.t("visitor_decline")) if not visitor_accept else Loc.t("visitor_decline"),
		Vector2(0, 30), COL_DIM, not visitor_accept, 12)
	dec.size_flags_horizontal = SIZE_EXPAND_FILL
	dec.pressed.connect(set_visitor.bind(false))


## Route cards, nights 1/7/13 only — irreversible two-choice (§2.4, fix B9).
func _refresh_route(obs: Dictionary) -> void:
	var offer: Array = obs.get("route_offer", [])
	var has := not offer.is_empty()
	route_section.visible = has
	route_row.visible = has
	if not has:
		return
	var picked := route_index >= 0 and route_index < offer.size()
	for i in route_cards_ui.size():
		var pcard: Dictionary = route_cards_ui[i]
		var panel: PanelContainer = pcard["panel"]
		# once a card is picked the pair folds to a one-line summary (§6)
		if i >= offer.size() or (picked and i != route_index):
			panel.visible = false
			continue
		panel.visible = true
		var rt: Dictionary = offer[i]
		var rid := str(rt["id"])
		var rname := Loc.route(rid, "name", str(rt["name"]))
		pcard["name"].text = ("✓ %s · %s" % [rname, Loc.t("route_cancel")]) if picked else rname
		pcard["desc"].text = Loc.route(rid, "description", str(rt.get("description", "")))
		(pcard["desc"] as Control).visible = not picked
		panel.custom_minimum_size = Vector2(0, 30 if picked else 44)
		var sel := i == route_index
		# same margins + same min size in both states — only colors flip
		if sel:
			panel.add_theme_stylebox_override("panel", _sb(COL_LIME, COL_LIME.lightened(0.2), 10, 1, 10, 8))
			pcard["name"].add_theme_color_override("font_color", COL_INK)
			pcard["desc"].add_theme_color_override("font_color", Color(Color("#101322"), 0.75))
			var cl: Label = pcard["chip"].get_meta("label")
			cl.add_theme_color_override("font_color", COL_LIME)
			pcard["chip"].add_theme_stylebox_override("panel", _sb(COL_INK, COL_INK, 6, 1, 8, 2))
		else:
			panel.add_theme_stylebox_override("panel", _sb(COL_INSET, COL_BORDER_HI, 10, 1, 10, 8))
			pcard["name"].add_theme_color_override("font_color", COL_TEXT)
			pcard["desc"].add_theme_color_override("font_color", COL_DIM)
			var cl2: Label = pcard["chip"].get_meta("label")
			cl2.add_theme_color_override("font_color", COL_LIME)
			pcard["chip"].add_theme_stylebox_override("panel", _sb(COL_INSET, Color(COL_LIME, 0.4), 6, 1, 8, 2))


func _refresh_upgrade_favor(obs: Dictionary) -> void:
	var up_id = _upgrade_choices()[upgrade_index]
	if up_id == null:
		upg_name.text = Loc.t("upgrade_off")
		upg_sub.text = Loc.t("none_upgrade")
	else:
		var u: Dictionary = game.upgrades[up_id]
		var lv := int(game.state["upgrade_levels"][up_id])
		upg_name.text = Loc.upgrade(up_id, "name", u["name"])
		upg_sub.text = "Lv %s/%s · %s" % [lv, u["max_level"], Loc.money(game.upgrade_cost(up_id))]
	var favor := int(obs.get("favor", 0))
	var opts := _favor_options()
	if favor_index >= opts.size():
		favor_index = 0
	if favor <= 0:
		favor_name.text = Loc.t("favor_none")
		favor_sub.text = "0 / 3 · %s" % Loc.t("favor_empty_sub")
	else:
		favor_name.text = _favor_option_label(opts[favor_index])
		favor_sub.text = "%d / 3" % favor


## Risk ledger drawer refresh (§6): heat, debt, checkpoint, finale, score.
func _refresh_ledger() -> void:
	var obs := _obs
	if obs.is_empty():
		return
	var iprob := float(obs["inspection_prob"])
	if _quote != null:
		iprob = float(_quote["inspection_prob"])
		var hq := int(_quote["projected_heat"])
		ledger_kv["heat"].text = ("%d→%d / %d" % [int(obs["heat"]), hq, int(obs.get("heat_cap", 100))]) \
			if hq != int(obs["heat"]) else ("%d / %d" % [int(obs["heat"]), int(obs.get("heat_cap", 100))])
		# audited odds: base heat + tonight's cargo, event factor, floor, cap
		ledger_inspect_detail.text = "%s %d · %s +%d → %d\n%s ×%.1f · %s %.0f%% · %s %.0f%%" % [
			Loc.t("insp_base"), int(obs["heat"]), Loc.t("insp_extra"), int(_quote["heat_added"]), hq,
			Loc.t("insp_event"), float(_quote["inspect_mult"]),
			Loc.t("insp_floor"), float(_quote["inspect_floor"]), Loc.t("insp_cap"), float(_quote["inspect_cap"])]
	else:
		ledger_kv["heat"].text = "%d / %d" % [int(obs["heat"]), int(obs.get("heat_cap", 100))]
		ledger_inspect_detail.text = ""
	ledger_kv["inspect"].text = "%.1f%%" % iprob
	ledger_kv["smuggled"].text = "%d %s" % [int(obs.get("total_smuggled", 0)), Loc.t("units_unit")]
	ledger_kv["exposure"].text = Loc.money(int(_quote["contract_exposure"])) if _quote != null else "—"
	# debt
	var debt: Dictionary = obs.get("debt", {})
	var loans: Array = debt.get("loans", [])
	var lines: Array = []
	for l in loans:
		lines.append("%s %s ×%d%s" % [Loc.t("loan_per_night"), Loc.money(int(l["payment"])), int(l["remaining"]), Loc.t("nights_unit")])
	if lines.is_empty():
		lines.append(Loc.t("no_debt"))
	else:
		lines.append("%s：%s" % [Loc.t("debt_title"), Loc.money(int(debt.get("outstanding", 0)))])
	ledger_debt.text = "\n".join(lines)
	var avail := bool(debt.get("loan_available", false))
	loan_btn.disabled = not avail and not loan_take
	loan_btn.text = ("✓ " + Loc.t("loan_planned")) if loan_take else (Loc.t("take_loan") if avail else Loc.t("loan_na"))
	var streak := int(debt.get("negative_streak", 0))
	ledger_streak.visible = streak > 0
	ledger_streak.text = "⚠ %s %d%s — %s" % [Loc.t("neg_streak"), streak, Loc.t("nights_unit"), Loc.t("neg_streak_warn")]
	# checkpoint
	var cp: Dictionary = obs.get("checkpoint", {})
	if cp.is_empty():
		ledger_assess.text = Loc.t("assess_none")
	else:
		var cid := str(cp["id"])
		var parts: Array = ["%s · 夜%02d（%s%d%s）" % [Loc.checkpoint_line(cid, "name", cid), int(cp["day"]), Loc.t("nights_left"), int(cp["nights_left"]), Loc.t("nights_unit")]]
		parts.append("%s %s · %s %s" % [Loc.t("assess_net"), Loc.money(int(cp["net_target"])), Loc.t("now_net"), Loc.money(int(obs["net_worth"]))])
		if int(cp.get("heat_max", -1)) >= 0:
			parts.append("%s %d" % [Loc.t("heat_req"), int(cp["heat_max"])])
		ledger_assess.text = "\n".join(parts)
	# finale intel
	var fin: Dictionary = obs.get("finale_intel", {})
	var stage := str(fin.get("stage", "hidden"))
	var tags: Array = fin.get("tags", [])
	var tag_names: Array = []
	for t in tags:
		tag_names.append(Loc.rumor_tag(str(t)))
	match stage:
		"confirmed":
			ledger_finale.text = "%s\n· %s" % [Loc.sec("finale", "confirm_hint"), " / ".join(tag_names)]
		"tag":
			ledger_finale.text = "%s\n· %s" % [Loc.sec("finale", "tag_hint"), " / ".join(tag_names)]
		"domain":
			ledger_finale.text = "%s\n· %s" % [Loc.sec("finale", "domain_hint"), " / ".join(tag_names)]
		_:
			ledger_finale.text = Loc.t("finale_hidden")
	ledger_kv["net"].text = Loc.money(int(obs["net_worth"]))
	ledger_kv["score"].text = str(int(obs["score_estimate"]))


# ─── report / game over ──────────────────────────────────────────────────────

func _bill_row(label_txt: String, amount: int, color: Color, always: bool = false, prefix_plus: bool = false) -> void:
	if amount == 0 and not always:
		return
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bill_rows.add_child(h)
	var k := _lbl(h, label_txt, 12, COL_DIM)
	k.size_flags_horizontal = SIZE_EXPAND_FILL
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	var txt := Loc.money(amount)
	if prefix_plus and amount > 0:
		txt = "+" + txt
	var v := _lbl(h, txt, 13, color if amount != 0 else COL_FAINT, true)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func refresh_report() -> void:
	if report.is_empty():
		return
	var day := int(report["day"])
	var profit := int(report["profit"])
	report_title.text = "%s %02d · %s" % [Loc.t("night"), day, Loc.t("night_closed")]
	report_profit.text = ("+" if profit >= 0 else "") + Loc.money(profit)
	report_profit.add_theme_color_override("font_color", COL_MINT if profit >= 0 else COL_RED)
	var flavor_key := str(report.get("flavor", "sale_success"))
	var zh := Loc.flavor(flavor_key, day)
	report_flavor.text = zh if zh != "" else flavor_key
	metric_sales.text = Loc.money(int(report["revenue"]))
	metric_sold.text = "%s / %s" % [report["units_sold"], report["demand"]]
	metric_waste.text = str(report["units_spoiled"])
	metric_profit.text = Loc.money(profit)
	metric_profit.add_theme_color_override("font_color", COL_MINT if profit >= 0 else COL_RED)
	# inspection banner (§6) — big and red when customs strike
	var insp: Dictionary = report.get("inspection", {})
	var caught := bool(insp.get("occurred", false))
	inspect_panel.visible = caught
	clean_panel.visible = not caught and int(report.get("smuggled_units", 0)) > 0
	if caught:
		inspect_label.text = "⚠ %s — %s %d %s" % [Loc.sec("smuggle", "seized"), Loc.t("seized_units_label"), int(insp.get("seized_units", 0)), Loc.t("units_unit")]
		inspect_sub.text = Loc.sec("smuggle", "seized_line")
		inspect_amt.text = "−" + Loc.money(int(insp.get("fine", 0)))
	else:
		clean_label.text = "◈ " + Loc.sec("smuggle", "clean_pass")
	# contract settlement banner
	var settled: Array = report.get("contracts_settled", [])
	contract_panel.visible = not settled.is_empty()
	if not settled.is_empty():
		var okc := 0
		var badc := 0
		for s in settled:
			if bool(s.get("fulfilled", false)):
				okc += 1
			else:
				badc += 1
		var first: Dictionary = settled[0]
		var line := Loc.contract_line(str(first["kind"]), "fulfilled" if bool(first["fulfilled"]) else "breached")
		contract_label.text = "%s ✓%d · ✗%d — %s" % [Loc.t("contract_settle"), okc, badc, line]
		contract_label.add_theme_color_override("font_color", COL_GOLD if badc == 0 else COL_RED)
		var net := int(report.get("contract_revenue", 0)) - int(report.get("contract_penalty", 0))
		contract_amt.text = ("+" if net >= 0 else "") + Loc.money(net)
		contract_amt.add_theme_color_override("font_color", COL_GOLD if net >= 0 else COL_RED)
	# visitor result strip
	var vres: Dictionary = report.get("visitor", {})
	var pres: Dictionary = report.get("vip_promise", {})
	var vparts: Array = []
	if not vres.is_empty():
		var vkind := str(vres.get("kind", ""))
		var accepted := bool(vres.get("accepted", false))
		vparts.append("%s：%s" % [Loc.visitor_line(vkind, "name"), Loc.visitor_line(vkind, "accepted" if accepted else "declined")])
	if not pres.is_empty():
		vparts.append(Loc.visitor_line("vip", "kept" if bool(pres.get("kept", false)) else "broken"))
	visitor_res_panel.visible = not vparts.is_empty()
	if not vparts.is_empty():
		visitor_res_label.text = "  ".join(vparts)
	# checkpoint banner
	var cp: Dictionary = report.get("checkpoint", {})
	cp_panel.visible = not cp.is_empty()
	if not cp.is_empty():
		var cid := str(cp["id"])
		cp_label.text = Loc.checkpoint_line(cid, "passed" if bool(cp["passed"]) else "failed")
		cp_label.add_theme_color_override("font_color", COL_VIOLET if bool(cp["passed"]) else COL_RED)
	# milestones
	var achs: Array = report.get("achievements", [])
	if achs.is_empty():
		report_ach_panel.visible = false
	else:
		report_ach_panel.visible = true
		var names := ""
		for a in achs:
			if names != "":
				names += "、"
			names += Loc.achievement(str(a["id"]), "name", str(a["name"]))
		report_ach.text = "%s · %s" % [Loc.t("ach_unlock"), names]
	# product table — full width, name expands, numerics fixed right (fix B3)
	for c in report_products.get_children():
		c.queue_free()
	var prods: Dictionary = report["products"]
	var ri := 0
	for id in game.product_ids:
		var r: Dictionary = prods[id]
		var rowp := PanelContainer.new()
		var bgc := Color(COL_INSET, 0.9) if ri % 2 == 0 else Color(COL_PANEL_ALT, 0.6)
		rowp.add_theme_stylebox_override("panel", _sb(bgc, Color(0, 0, 0, 0), 6, 0, 10, 3))
		rowp.custom_minimum_size = Vector2(0, 30)
		rowp.size_flags_horizontal = SIZE_EXPAND_FILL
		report_products.add_child(rowp)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		rowp.add_child(row)
		var icon := TextureRect.new()
		icon.texture = _tex("res://assets/icons/product_%s.png" % id)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(icon)
		var sold := int(r["sold"])
		var demand := int(r["demand"])
		var shortage := maxi(0, demand - sold)
		var nm := _lbl(row, Loc.product(id, "name", id), 14, COL_TEXT if sold > 0 else COL_DIM, true)
		nm.size_flags_horizontal = SIZE_EXPAND_FILL
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var sd := _num(row, "%d / %d" % [sold, demand], 13, COL_TEXT if sold > 0 else COL_DIM, 90)
		sd.size_flags_vertical = SIZE_SHRINK_CENTER
		var so_cell := CenterContainer.new()
		so_cell.custom_minimum_size = Vector2(78, 0)
		row.add_child(so_cell)
		# stockout semantics split (fix B4): sold out = solid red chip;
		# never stocked = faint outlined chip; one column, one geometry
		if shortage > 0 and sold > 0:
			_chip(so_cell, "%s %s%d" % [Loc.t("sellout_chip"), Loc.t("stockout_short"), shortage], Color("#2A070F"), COL_RED.lightened(0.15), COL_RED)
		elif shortage > 0:
			_chip(so_cell, Loc.t("nostock_chip"), COL_FAINT, Color(COL_FAINT, 0.55), Color(0, 0, 0, 0))
		var rev := int(r["revenue"])
		var rl := _num(row, Loc.money(rev), 13, COL_MINT if rev > 0 else COL_FAINT, 90)
		rl.size_flags_vertical = SIZE_SHRINK_CENTER
		ri += 1
	# night bill (§6): contract income / breach fines / seizure / interest + rest
	for c in bill_rows.get_children():
		c.queue_free()
	var led: Dictionary = report.get("ledger", {})
	_bill_row(Loc.t("li_loan_in"), int(led.get("loan_received", 0)), COL_GOLD, false, true)
	_bill_row(Loc.t("li_deposit"), int(led.get("deposits", 0)), COL_GOLD, false, true)
	_bill_row(Loc.t("li_supply"), -int(led.get("procurement", 0)), COL_TEXT, true)
	_bill_row(Loc.t("li_smuggle"), -int(led.get("smuggle_cost", 0)), COL_RED)
	_bill_row(Loc.t("li_upgrade"), -int(led.get("upgrade_cost", 0)), COL_TEXT)
	_bill_row(Loc.t("li_restock"), -int(led.get("restock_cost", 0)), COL_TEXT)
	var vis_net := int(led.get("visitor_delta", 0)) + int(led.get("vip_promise_revenue", 0))
	_bill_row(Loc.t("li_visitor"), vis_net, COL_MAGENTA if vis_net != 0 else COL_FAINT, false, true)
	_bill_row(Loc.t("li_contract"), int(led.get("contract_revenue", 0)), COL_GOLD, true, true)
	_bill_row(Loc.t("li_penalty"), -int(led.get("contract_penalty", 0)), COL_RED, true)
	_bill_row(Loc.t("li_seized"), -int(led.get("inspection_fine", 0)), COL_RED, true)
	_bill_row(Loc.t("li_sales"), int(led.get("sales_revenue", 0)), COL_MINT, true, true)
	_bill_row(Loc.t("li_rent"), -int(led.get("rent", 0)), COL_TEXT, true)
	_bill_row(Loc.t("li_waste"), -int(led.get("waste_fee", 0)), COL_RED)
	_bill_row(Loc.t("li_loan_pay"), -int(led.get("loan_payment", 0)), COL_GOLD)
	_bill_row(Loc.t("li_interest"), -int(led.get("interest", 0)), COL_RED, true)
	_bill_row(Loc.t("li_subsidy"), int(led.get("checkpoint_subsidy", 0)), COL_VIOLET, false, true)
	# reputation delta (§7): integer headline in violet, kept OFF the money
	# column, with indented per-source attribution sub-rows from rep_breakdown
	var rd := float(report.get("reputation_delta", 0.0))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	bill_rows.add_child(rrow)
	var rk := _lbl(rrow, Loc.t("li_rep"), 12, COL_DIM)
	rk.autowrap_mode = TextServer.AUTOWRAP_OFF
	var rv := _lbl(rrow, _signed_int(int(round(rd))), 13, COL_VIOLET, true)
	rv.autowrap_mode = TextServer.AUTOWRAP_OFF
	var rbk: Dictionary = report.get("rep_breakdown", {})
	for entry in [["contract", "rep_src_contract"], ["inspection", "rep_src_inspect"],
			["vip", "rep_src_vip"], ["checkpoint", "rep_src_checkpoint"],
			["event", "rep_src_event"], ["service", "rep_src_service"],
			["stockout", "rep_src_stockout"], ["spoilage", "rep_src_spoil"]]:
		var amt := float(rbk.get(entry[0], 0.0))
		if absf(amt) < 0.05:
			continue
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		bill_rows.add_child(srow)
		var sk := _lbl(srow, "⌞ " + Loc.t(str(entry[1])), 11, COL_FAINT)
		sk.autowrap_mode = TextServer.AUTOWRAP_OFF
		var sv := _lbl(srow, "%+.1f" % amt, 11, Color(COL_VIOLET, 0.85), true)
		sv.autowrap_mode = TextServer.AUTOWRAP_OFF
	# divider + cash headline
	var sep := ColorRect.new()
	sep.color = Color(COL_BORDER_HI, 0.9)
	sep.custom_minimum_size = Vector2(0, 1)
	bill_rows.add_child(sep)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	bill_rows.add_child(crow)
	var ck := _lbl(crow, Loc.t("cash"), 13, COL_DIM)
	ck.size_flags_horizontal = SIZE_EXPAND_FILL
	ck.autowrap_mode = TextServer.AUTOWRAP_OFF
	var cv := _lbl(crow, Loc.money(int(report["cash_after"])), 20, COL_GOLD, true)
	cv.autowrap_mode = TextServer.AUTOWRAP_OFF
	cv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	report_prompt.text = Loc.t("hint_report_final") if game.state.get("done", false) else Loc.t("hint_report_next")
	# living strip resets to full brightness — focus rings only on demand (fix B8)
	if report_market.has_method("set_mode"):
		report_market.set_mode("living")
		if report_market.has_method("set_focus_group"):
			report_market.set_focus_group("")


## Ledger sign convention: +N for gains, −N for costs, ±0 for a clean zero.
func _signed_int(n: int) -> String:
	if n > 0:
		return "+%d" % n
	if n == 0:
		return "±0"
	return str(n)


func refresh_game_over() -> void:
	var t: Dictionary = game.terminal_summary()
	var ending := str(t.get("ending", "completed"))
	var liquidated := ending == "liquidated"
	# liquidation gets its own farewell (§6)
	final_title.text = Loc.ending(ending, "name", Loc.t("season_complete"))
	final_title.add_theme_color_override("font_color", COL_RED if liquidated else COL_GOLD)
	final_title.add_theme_color_override("font_shadow_color", Color(COL_RED if liquidated else COL_GOLD, 0.35))
	final_rank.text = Loc.rank(str(t["rank"]))
	final_score.text = "%s  %s" % [Loc.t("score"), t["score"]]
	var bd: Dictionary = t.get("score_breakdown", {})
	var fulfilled := int(t.get("contracts_fulfilled", 0))
	var breached := int(t.get("contracts_breached", 0))
	var vals := [
		[Loc.money(int(bd.get("cash", 0))), COL_GOLD],
		["+" + Loc.money(int(bd.get("inventory_liquidation", 0))), COL_TEXT],
		[Loc.money(int(bd.get("debt_penalty", 0))), COL_RED if int(bd.get("debt_penalty", 0)) < 0 else COL_DIM],
		["+%d" % int(bd.get("reputation_bonus", 0)), COL_VIOLET],
		["×%d · %s" % [fulfilled, _signed_int(int(bd.get("fulfill_bonus", 0)))], COL_MINT if fulfilled > 0 else COL_DIM],
		["×%d · %s" % [breached, _signed_int(int(bd.get("breach_penalty", 0)))], COL_RED if breached > 0 else COL_DIM],
		["+%d" % int(bd.get("ultimate_bonus", 0)) if int(bd.get("ultimate_bonus", 0)) > 0 else "—", COL_GOLD if int(bd.get("ultimate_bonus", 0)) > 0 else COL_FAINT],
		["%d%s · %d%s" % [int(t.get("seizures", 0)), Loc.t("times_unit"), int(t.get("units_seized", 0)), Loc.t("units_unit")], COL_RED if int(t.get("seizures", 0)) > 0 else COL_DIM],
		["%d%s" % [int(t.get("smuggled_units", 0)), Loc.t("units_unit")], COL_DIM],
		["%d / 3" % int(t.get("favor", 0)), COL_MINT],
		[str(int(t.get("score", 0))), COL_GOLD],
	]
	for i in final_ledger_rows.size():
		var entry: Array = vals[i]
		final_ledger_rows[i].text = str(entry[0])
		final_ledger_rows[i].add_theme_color_override("font_color", entry[1])
	if final_seed:
		final_seed.text = "%s  %04d" % [Loc.t("seed"), seed]
	final_flavor.text = Loc.ending(ending, "line", Loc.flavor("game_over", seed))


func _customer_tex(group_id: String) -> Texture2D:
	var map := {
		"dock_workers": "customer_dock", "transit_pilots": "customer_pilot",
		"star_tourists": "customer_tourist", "night_monks": "customer_monk",
		"scrap_traders": "customer_scrap", "luxe_envoys": "customer_luxe",
	}
	return _tex("res://assets/characters/%s.png" % map.get(group_id, "customer_dock"))


func _process(delta: float) -> void:
	_time += delta
	if title_market and title_market.has_method("tick") and mode == Mode.TITLE:
		title_market.tick(delta)
	if report_market and report_market.has_method("tick") and mode == Mode.REPORT:
		report_market.tick(delta)
	# CTA breathing pulse (spec §3.2)
	if mode == Mode.TITLE and not _cta_pulse.is_empty():
		var s := 10.0 + 6.0 * (0.5 + 0.5 * sin(_time * 2.4))
		for sbx in _cta_pulse:
			if sbx is StyleBoxFlat:
				sbx.shadow_size = int(s)
	# strategy column: show the fade + "▼ 更多" cue only while more content hides
	# below the fold (§6)
	if mode == Mode.PLAN and strategy_fade and strategy_scroll:
		var ssb := strategy_scroll.get_v_scroll_bar()
		strategy_fade.visible = ssb.visible and ssb.value + ssb.page < ssb.max_value - 4.0
	# toast expiry
	if mode == Mode.PLAN and toast != "" and _time >= toast_until:
		toast = ""
		refresh_plan()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: InputEventKey = event
	if k.keycode == KEY_ESCAPE:
		if help_open:
			help_open = false
			_refresh_help()
		elif ledger_open and mode == Mode.PLAN:
			toggle_ledger()
		else:
			get_tree().quit()
		return
	if k.keycode == KEY_H:
		help_open = not help_open
		if help_open:
			help_page = 0
		_refresh_help()
		return
	if help_open:
		if k.keycode in [KEY_LEFT, KEY_RIGHT]:
			help_page = 1 - help_page
			_refresh_help()
		return
	match mode:
		Mode.TITLE:
			if k.keycode in [KEY_SPACE, KEY_ENTER]:
				enter_plan()
		Mode.PLAN:
			if k.keycode == KEY_UP:
				select_product(selected_product - 1)
			elif k.keycode == KEY_DOWN:
				select_product(selected_product + 1)
			elif k.keycode == KEY_LEFT:
				adjust_order(-1)
			elif k.keycode == KEY_RIGHT:
				adjust_order(1)
			elif k.keycode == KEY_Z:
				adjust_price(-1)
			elif k.keycode == KEY_X:
				adjust_price(1)
			elif k.keycode == KEY_R:
				toggle_ledger()
			elif k.keycode == KEY_1:
				select_permit(0)
			elif k.keycode == KEY_2:
				select_permit(1)
			elif k.keycode == KEY_3:
				toggle_contract(0)
			elif k.keycode == KEY_4:
				toggle_contract(1)
			elif k.keycode == KEY_5:
				toggle_contract(2)
			elif k.keycode == KEY_V:
				set_visitor(not visitor_accept)
			elif k.keycode == KEY_B:
				cycle_upgrade()
			elif k.keycode == KEY_F:
				cycle_favor()
			elif k.keycode == KEY_L:
				toggle_loan()
			elif k.keycode in [KEY_SPACE, KEY_ENTER]:
				open_market()
		Mode.REPORT:
			if k.keycode in [KEY_SPACE, KEY_ENTER]:
				continue_from_report()
		Mode.GAME_OVER:
			if k.keycode == KEY_R:
				new_game(seed + 1)
				enter_plan()
			elif k.keycode == KEY_T:
				new_game(seed)
				show_mode(Mode.TITLE)
