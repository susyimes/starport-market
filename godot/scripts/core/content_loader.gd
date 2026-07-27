class_name ContentLoader
extends RefCounted
## Loads shared content pack (same IDs as starport_market/data/content.json).

static func load_pack() -> Dictionary:
	var path := "res://data/content.json"
	if not FileAccess.file_exists(path):
		push_error("Missing content.json")
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("content.json parse failed")
		return {}
	_validate(data)
	return data


static func _validate(data: Dictionary) -> void:
	assert((data.get("products", []) as Array).size() == 8, "products")
	assert((data.get("customer_groups", []) as Array).size() == 6, "customer_groups")
	assert((data.get("events", []) as Array).size() == 13, "events")
	assert((data.get("upgrades", []) as Array).size() == 4, "upgrades")
	for key in ["game", "rent_curve", "heat", "contracts", "visitors", "routes", "loans", "finale", "score", "price_memory", "favor"]:
		assert(data.has(key), key)
	assert((data.get("checkpoints", []) as Array).size() == 2, "checkpoints")
	assert(((data.get("routes", {}) as Dictionary).keys() as Array).size() == 3, "route slots")
