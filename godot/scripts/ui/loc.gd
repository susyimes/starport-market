class_name Loc
extends RefCounted
## Display localization. Default language is Chinese (zh).

static var _root: Dictionary = {}
static var _loaded: bool = false
static var language: String = "zh"


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if language != "zh":
		return
	var path := "res://data/loc_zh.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		_root = data


static func t(key: String, fallback: String = "") -> String:
	ensure()
	var ui: Dictionary = _root.get("ui", {})
	if ui.has(key):
		return str(ui[key])
	return fallback if fallback != "" else key


static func product(id: String, field: String, fallback: String) -> String:
	return _lookup("products", id, field, fallback)


static func group(id: String, field: String, fallback: String) -> String:
	return _lookup("customer_groups", id, field, fallback)


static func event(id: String, field: String, fallback: String) -> String:
	return _lookup("events", id, field, fallback)


static func upgrade(id: String, field: String, fallback: String) -> String:
	return _lookup("upgrades", id, field, fallback)


static func campaign(id: String, field: String, fallback: String) -> String:
	return _lookup("campaigns", id, field, fallback)


static func permit(id: String, field: String, fallback: String) -> String:
	return _lookup("permits", id, field, fallback)


static func achievement(id: String, field: String, fallback: String) -> String:
	return _lookup("achievements", id, field, fallback)


static func route(id: String, field: String, fallback: String = "") -> String:
	return _lookup("routes", id, field, fallback if fallback != "" else id)


static func visitor_line(kind: String, field: String, fallback: String = "") -> String:
	return _lookup("visitors", kind, field, fallback if fallback != "" else kind)


static func contract_line(kind: String, field: String, fallback: String = "") -> String:
	return _lookup("contracts", kind, field, fallback if fallback != "" else kind)


static func ending(id: String, field: String, fallback: String = "") -> String:
	return _lookup("endings", id, field, fallback if fallback != "" else id)


static func checkpoint_line(id: String, field: String, fallback: String = "") -> String:
	return _lookup("checkpoints", id, field, fallback if fallback != "" else id)


## Flat lookup inside a top-level section, e.g. sec("smuggle", "title").
static func sec(section: String, key: String, fallback: String = "") -> String:
	ensure()
	var s: Dictionary = _root.get(section, {})
	if s.has(key) and typeof(s[key]) != TYPE_DICTIONARY:
		return str(s[key])
	return fallback if fallback != "" else key


static func rumor_tag(tag: String) -> String:
	ensure()
	var tags: Dictionary = _root.get("rumor_tags", {})
	return str(tags.get(tag, tag))


static func rank(english: String) -> String:
	ensure()
	var ranks: Dictionary = _root.get("ranks", {})
	return str(ranks.get(english, english))


static func tip(index: int) -> String:
	ensure()
	var tips: Array = _root.get("tips", [])
	if tips.is_empty():
		return ""
	return str(tips[posmod(index, tips.size())])


static func flavor(group_key: String, seed_index: int) -> String:
	ensure()
	var flav: Dictionary = _root.get("flavor", {})
	var arr: Array = flav.get(group_key, [])
	if arr.is_empty():
		return ""
	return str(arr[posmod(seed_index, arr.size())])


static func _lookup(section: String, id: String, field: String, fallback: String) -> String:
	ensure()
	var sec_d: Dictionary = _root.get(section, {})
	var item = sec_d.get(id, {})
	if typeof(item) == TYPE_DICTIONARY and (item as Dictionary).has(field):
		return str(item[field])
	return fallback


static func money(value: int) -> String:
	if value < 0:
		return "-$%d" % absi(value)
	return "$%d" % value
