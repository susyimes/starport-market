class_name MarketGame
extends RefCounted
## Deterministic economy for gameplay v3 "Undertow Night Market".
## All rules live here; all numbers live in data/content.json.
## UI must only call try_quote_action / try_step / observation / terminal_summary.
## Determinism: every roll goes through stable_rng(label, day).

const STATE_VERSION := 3

var content: Dictionary
var products: Dictionary = {}
var events: Dictionary = {}
var groups: Dictionary = {}
var upgrades: Dictionary = {}
var routes: Dictionary = {}
var route_slots: Dictionary = {}
var game_cfg: Dictionary = {}
var heat_cfg: Dictionary = {}
var contracts_cfg: Dictionary = {}
var visitors_cfg: Dictionary = {}
var rent_cfg: Dictionary = {}
var checkpoints_cfg: Array = []
var loans_cfg: Dictionary = {}
var finale_cfg: Dictionary = {}
var score_cfg: Dictionary = {}
var memory_cfg: Dictionary = {}
var favor_cfg: Dictionary = {}
var wave_cfg: Dictionary = {}
var rep_cfg: Dictionary = {}
var product_ids: Array = []
var state: Dictionary = {}
var last_error: String = ""

const FAVOR_TYPES := ["contract_waive", "rent_free", "restock"]


func _init(seed: int = 7, content_pack: Dictionary = {}) -> void:
	content = content_pack if not content_pack.is_empty() else ContentLoader.load_pack()
	for p in content.get("products", []):
		products[p["id"]] = p
	for e in content.get("events", []):
		events[e["id"]] = e
	for g in content.get("customer_groups", []):
		groups[g["id"]] = g
	for u in content.get("upgrades", []):
		upgrades[u["id"]] = u
	route_slots = content.get("routes", {})
	for slot in route_slots:
		for opt in route_slots[slot]:
			routes[opt["id"]] = opt
	game_cfg = content.get("game", {})
	heat_cfg = content.get("heat", {})
	contracts_cfg = content.get("contracts", {})
	visitors_cfg = content.get("visitors", {})
	rent_cfg = content.get("rent_curve", {})
	checkpoints_cfg = content.get("checkpoints", [])
	loans_cfg = content.get("loans", {})
	finale_cfg = content.get("finale", {})
	score_cfg = content.get("score", {})
	memory_cfg = content.get("price_memory", {})
	favor_cfg = content.get("favor", {})
	wave_cfg = content.get("market_wave", {})
	rep_cfg = content.get("reputation", {})
	product_ids = products.keys()
	product_ids.sort()
	state = _new_state(seed)


func _phase_for(day: int) -> int:
	if day <= 6:
		return 0
	elif day <= 12:
		return 1
	return 2


func _new_state(seed: int) -> Dictionary:
	var total_days := int(game_cfg.get("total_days", 18))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5A172026
	var event_items: Array = content.get("events", [])
	var finale_event := str(finale_cfg.get("event_id", event_items[0]["id"]))
	var event_schedule: Array = []
	for day in range(1, total_days + 1):
		if day == total_days:
			event_schedule.append(finale_event)
			continue
		var phase := _phase_for(day)
		var weights: Array = []
		for e in event_items:
			var pw: Array = e.get("phase_weights", [])
			var w := int(pw[phase]) if pw.size() > phase else maxi(0, int(e.get("weight", 1)))
			weights.append(w)
		var selected: Dictionary = _weighted_choice(rng, event_items, weights)
		var tries := 0
		while event_schedule.size() > 0 and str(event_schedule[-1]) == str(selected["id"]) and tries < 6:
			selected = _weighted_choice(rng, event_items, weights)
			tries += 1
		event_schedule.append(selected["id"])
	var group_items: Array = content.get("customer_groups", [])
	var group_schedule: Array = []
	for _i in total_days:
		group_schedule.append(group_items[rng.randi() % group_items.size()]["id"])
	var themes: Array = finale_cfg.get("themes", [{"tag": "sweet", "decoy": "glow"}])
	var theme: Dictionary = themes[rng.randi() % themes.size()]
	var inv := {}
	var prices := {}
	for id in product_ids:
		inv[id] = []
		prices[id] = int(products[id]["base_price"])
	var levels := {}
	for id in upgrades.keys():
		levels[id] = 0
	return {
		"version": STATE_VERSION,
		"seed": seed,
		"day": 1,
		"total_days": total_days,
		"cash": int(game_cfg.get("start_cash", 120)),
		"reputation": float(game_cfg.get("start_reputation", 50)),
		"inventory": inv,
		"prices": prices,
		"upgrade_levels": levels,
		"event_schedule": event_schedule,
		"group_schedule": group_schedule,
		"heat": 0,
		"total_smuggled": 0,
		"active_contracts": [],
		"route_cards": {"n1": null, "n7": null, "n13": null},
		"price_memory": {},
		"favor": 0,
		"loans": [],
		"negative_streak": 0,
		"vip_promise": null,
		"certain_rumor_day": 0,
		"checkpoints": {"cp1": null, "cp2": null},
		"finale_theme": {"tag": str(theme.get("tag", "sweet")), "decoy": str(theme.get("decoy", "glow"))},
		"history": [],
		"completed_achievements": [],
		"stats": {
			"perfect_service_days": 0, "no_waste_days": 0,
			"contracts_fulfilled": 0, "contracts_breached": 0,
			"seizures": 0, "units_seized": 0, "smuggled_units": 0,
			"loans_taken": 0, "favor_gained": 0, "favor_used": 0,
			"ultimate_fulfilled": false,
		},
		"totals": {
			"revenue": 0, "contract_revenue": 0, "deposits": 0,
			"procurement": 0, "smuggle_cost": 0, "upgrades": 0, "restock_cost": 0,
			"rent": 0, "waste_fees": 0, "interest": 0, "fines": 0, "penalties": 0,
			"loan_payments": 0, "loan_received": 0, "visitor_net": 0, "subsidies": 0,
			"units_sold": 0, "units_spoiled": 0, "stockouts": 0,
		},
		"done": false,
		"ending": null,
	}


func _weighted_choice(rng: RandomNumberGenerator, items: Array, weights: Array) -> Dictionary:
	var total := 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return items[0]
	var roll := rng.randi() % total
	var acc := 0
	for i in items.size():
		acc += int(weights[i])
		if roll < acc:
			return items[i]
	return items[-1]


# ---------------------------------------------------------------- basics

func day_value() -> int:
	return int(state["day"])


func cash_value() -> int:
	return int(state["cash"])


func reputation_value() -> float:
	return float(state["reputation"])


func favor_value() -> int:
	return int(state["favor"])


func heat_value() -> int:
	return int(state["heat"])


func event_at(day: int = -1) -> Dictionary:
	var d := day if day > 0 else day_value()
	var idx := clampi(d - 1, 0, int(state["total_days"]) - 1)
	return events[str(state["event_schedule"][idx])]


func group_at(day: int = -1) -> Dictionary:
	var d := day if day > 0 else day_value()
	var idx := clampi(d - 1, 0, int(state["total_days"]) - 1)
	return groups[str(state["group_schedule"][idx])]


func inventory_count(product_id: String = "") -> int:
	var inv: Dictionary = state["inventory"]
	if product_id != "":
		var s := 0
		for b in inv.get(product_id, []):
			s += int(b.get("quantity", 0))
		return s
	var total := 0
	for id in product_ids:
		total += inventory_count(id)
	return total


func hot_count() -> int:
	var n := 0
	var inv: Dictionary = state["inventory"]
	for id in product_ids:
		for b in inv[id]:
			if b.get("hot", false):
				n += int(b.get("quantity", 0))
	return n


func hot_value() -> int:
	var v := 0
	var inv: Dictionary = state["inventory"]
	for id in product_ids:
		for b in inv[id]:
			if b.get("hot", false):
				v += int(b.get("quantity", 0)) * int(b.get("unit_cost", 0))
	return v


func expiring_units(product_id: String = "") -> int:
	var n := 0
	var inv: Dictionary = state["inventory"]
	for id in product_ids:
		if product_id != "" and id != product_id:
			continue
		for b in inv[id]:
			var dl = b.get("days_left", null)
			if dl != null and int(dl) == 1:
				n += int(b.get("quantity", 0))
	return n


func levels_with(upgrade_id: String = "") -> Dictionary:
	var levels := {}
	for k in state["upgrade_levels"]:
		levels[k] = int(state["upgrade_levels"][k])
	if upgrade_id != "":
		levels[upgrade_id] = int(levels.get(upgrade_id, 0)) + 1
	return levels


func effect_sum(key: String, levels: Dictionary = {}) -> float:
	if levels.is_empty():
		levels = levels_with()
	var total := 0.0
	for uid in levels:
		if not upgrades.has(uid):
			continue
		var eff: Dictionary = upgrades[uid].get("effects", {})
		if eff.has(key):
			total += float(eff[key]) * int(levels[uid])
	return total


func intel_level() -> int:
	return int(round(effect_sum("intel_level")))


func upgrade_cost(upgrade_id: String) -> int:
	var item: Dictionary = upgrades[upgrade_id]
	var level := int(state["upgrade_levels"][upgrade_id])
	if level >= int(item["max_level"]):
		return 999999
	return int(ceil(float(item["base_cost"]) * pow(float(item["cost_growth"]), level)))


# ---------------------------------------------------------------- routes

func _route_effect(key: String, def: Variant) -> Variant:
	var cards: Dictionary = state["route_cards"]
	for slot in cards:
		var rid = cards[slot]
		if rid == null:
			continue
		var eff: Dictionary = (routes.get(str(rid), {}) as Dictionary).get("effects", {})
		if eff.has(key):
			return eff[key]
	return def


func _route_tag_demand(product: Dictionary) -> float:
	var m := 1.0
	var cards: Dictionary = state["route_cards"]
	for slot in cards:
		var rid = cards[slot]
		if rid == null:
			continue
		var eff: Dictionary = (routes.get(str(rid), {}) as Dictionary).get("effects", {})
		m *= _tag_mult(product, eff.get("tag_demand", {}))
	return m


func route_offer_for(day: int = -1) -> Array:
	var d := day if day > 0 else day_value()
	var slot := ""
	if d == 1:
		slot = "n1"
	elif d == 7:
		slot = "n7"
	elif d == 13:
		slot = "n13"
	if slot == "" or state["route_cards"][slot] != null:
		return []
	return (route_slots.get(slot, []) as Array).duplicate(true)


func _route_slot_for(route_id: String) -> String:
	for slot in route_slots:
		for opt in route_slots[slot]:
			if str(opt["id"]) == route_id:
				return slot
	return ""


# ---------------------------------------------------------------- capacity / shelf / cost

func capacity(levels: Dictionary = {}, day: int = -1) -> int:
	if levels.is_empty():
		levels = levels_with()
	var d := day if day > 0 else day_value()
	var effects: Dictionary = event_at(d).get("effects", {})
	var cap := int(game_cfg.get("base_capacity", 26))
	cap += int(round(effect_sum("capacity_delta", levels)))
	cap += int(effects.get("capacity_delta", 0))
	if d == int(state["total_days"]):
		cap += int(finale_cfg.get("capacity_bonus", 8))
		if state["checkpoints"].get("cp2") == true:
			cap += int(_cp_cfg("cp2").get("capacity_reward", 2))
	return maxi(1, cap)


func shelf_life(product_id: String, levels: Dictionary = {}) -> Variant:
	if levels.is_empty():
		levels = levels_with()
	var bas = products[product_id].get("shelf_life", null)
	if bas == null:
		return null
	var bonus := int(round(effect_sum("shelf_life_bonus", levels)))
	bonus += int(_route_effect("shelf_life_bonus", 0))
	return int(bas) + bonus


func _tag_mult(product: Dictionary, mapping: Dictionary) -> float:
	var m := 1.0
	for tag in product.get("tags", []):
		if mapping.has(tag):
			m *= float(mapping[tag])
	return m


func market_factor(product_id: String, day: int = -1) -> float:
	var rng := stable_rng("market:" + product_id, day)
	var lo := float(wave_cfg.get("min", 0.85))
	var hi := float(wave_cfg.get("max", 1.2))
	return lo + rng.randf() * (hi - lo)


func _squeeze_factor(day: int) -> float:
	var squeeze: Dictionary = finale_cfg.get("supply_squeeze", {})
	return float(squeeze.get(str(day), 1.0))


func unit_cost(product_id: String, levels: Dictionary = {}, day: int = -1, with_route_discount: bool = true) -> int:
	var d := day if day > 0 else day_value()
	var product: Dictionary = products[product_id]
	var effects: Dictionary = event_at(d).get("effects", {})
	var factor := float(effects.get("cost_all", 1.0))
	factor *= _tag_mult(product, effects.get("cost_tags", {}))
	factor = clampf(factor, 0.45, 2.5)
	var cost := float(product["base_cost"]) * factor * market_factor(product_id, d) * _squeeze_factor(d)
	if with_route_discount:
		cost *= 1.0 - clampf(float(_route_effect("order_discount", 0.0)), 0.0, 0.35)
	return maxi(1, int(ceil(cost)))


func market_closed(day: int = -1) -> bool:
	var d := day if day > 0 else day_value()
	return d >= int(finale_cfg.get("close_day", 18))


func price_bounds(product_id: String) -> Vector2i:
	var p: Dictionary = products[product_id]
	@warning_ignore("integer_division")
	return Vector2i(maxi(1, int(p["base_cost"]) / 2), int(p["base_price"]) * 3)


func stable_rng(label: String, day: int = -1) -> RandomNumberGenerator:
	var d := day if day > 0 else day_value()
	var payload := "%s:%s:%s" % [state["seed"], d, label]
	var h := payload.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = h if h != 0 else 1
	return rng


# ---------------------------------------------------------------- smuggling & heat

func _heat_cap() -> int:
	return mini(int(heat_cfg.get("max", 100)), int(_route_effect("heat_cap", int(heat_cfg.get("max", 100)))))


func _add_heat(amount: int) -> void:
	state["heat"] = clampi(int(state["heat"]) + amount, 0, _heat_cap())


func smuggle_offers(day: int = -1) -> Array:
	var d := day if day > 0 else day_value()
	if market_closed(d):
		return []
	var rng := stable_rng("smuggle", d)
	var cmin := int(heat_cfg.get("offer_count_min", 2))
	var cmax := int(heat_cfg.get("offer_count_max", 3))
	var count := cmin + (rng.randi() % maxi(1, cmax - cmin + 1))
	count += int(_route_effect("smuggle_slots", 0))
	count = mini(count, product_ids.size())
	var pool: Array = product_ids.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var qmin := int(heat_cfg.get("offer_qty_min", 6))
	var qmax := int(heat_cfg.get("offer_qty_max", 10))
	var pmin := float(heat_cfg.get("price_min", 0.55))
	var pmax := float(heat_cfg.get("price_max", 0.65))
	var offers: Array = []
	for i in count:
		var pid: String = pool[i]
		var limit := qmin + (rng.randi() % maxi(1, qmax - qmin + 1))
		var rate := pmin + rng.randf() * (pmax - pmin)
		rate -= float(_route_effect("smuggle_discount", 0.0))
		var base := unit_cost(pid, {}, d, false)
		offers.append({
			"product_id": pid,
			"limit": limit,
			"unit_price": maxi(1, int(ceil(base * rate))),
			"heat_per_unit": int(heat_cfg.get("per_unit", 2)),
		})
	return offers


func inspection_prob(extra_heat: int = 0, extra_units: int = 0, day: int = -1) -> float:
	var d := day if day > 0 else day_value()
	var h := clampi(int(state["heat"]) + extra_heat, 0, _heat_cap())
	if h <= 0 and hot_count() == 0 and extra_units == 0:
		return 0.0
	var total_units := int(state["total_smuggled"]) + extra_units
	@warning_ignore("integer_division")
	var floor_p := float(heat_cfg.get("floor_base", 6)) + float(total_units / maxi(1, int(heat_cfg.get("floor_per_units", 12))))
	var mult := float(event_at(d).get("inspect_mult", 1.0))
	mult *= float(_route_effect("inspect_prob_mult", 1.0))
	var prob := float(h) * mult
	prob = clampf(prob, floor_p, float(heat_cfg.get("prob_cap", 80)))
	return round(prob * 10.0) / 10.0


# ---------------------------------------------------------------- rumors

func _rumor_pair(target_day: int) -> Array:
	var true_id := str(state["event_schedule"][target_day - 1])
	var rng := stable_rng("rumor", target_day)
	var real_prob := 0.55 + rng.randf() * 0.3
	var finale_event := str(finale_cfg.get("event_id", ""))
	var pool: Array = []
	for e in content.get("events", []):
		var eid := str(e["id"])
		if eid != true_id and eid != finale_event:
			pool.append(eid)
	var decoy: String = pool[rng.randi() % pool.size()]
	var fuzz := (rng.randf() - 0.5) * 0.3
	var swap := rng.randf() < 0.5
	var certain := int(state["certain_rumor_day"]) == target_day
	var shown := real_prob
	if not certain and intel_level() < 1:
		shown = clampf(real_prob + fuzz, 0.05, 0.95)
	if certain:
		shown = 1.0
	var a := {"event_id": true_id, "prob": int(round(shown * 100.0))}
	var b := {"event_id": decoy, "prob": 100 - int(a["prob"])}
	if swap and not certain:
		return [b, a]
	return [a, b]


func rumors_for(day: int = -1) -> Dictionary:
	var d := day if day > 0 else day_value()
	var td := int(state["total_days"])
	var res := {"tomorrow": [], "later_hint": "", "later": [], "certain": false}
	if d + 1 <= td:
		res["tomorrow"] = _rumor_pair(d + 1)
		res["certain"] = int(state["certain_rumor_day"]) == d + 1
	if d + 2 <= td:
		var e2: Dictionary = events[str(state["event_schedule"][d + 1])]
		res["later_hint"] = str(e2.get("rumor_tag", ""))
		if intel_level() >= 2:
			res["later"] = _rumor_pair(d + 2)
	return res


# ---------------------------------------------------------------- contracts

func _contract_price_bonus() -> float:
	var bonus := 1.0 + effect_sum("contract_bonus")
	bonus *= float(_route_effect("contract_price_mult", 1.0))
	return bonus


func _theme_product() -> String:
	var tag := str(state["finale_theme"]["tag"])
	var best := ""
	var best_price := -1
	for id in product_ids:
		var p: Dictionary = products[id]
		if tag in (p.get("tags", []) as Array):
			if int(p["base_price"]) > best_price:
				best_price = int(p["base_price"])
				best = id
	if best == "":
		best = product_ids[0]
	return best


func contracts_board(day: int = -1) -> Array:
	var d := day if day > 0 else day_value()
	if state.get("done", false):
		return []
	var rng := stable_rng("board", d)
	var bonus := _contract_price_bonus()
	var cards: Array = []
	var slots := int(contracts_cfg.get("board_size", 2)) + int(_route_effect("contract_extra_card", 0))
	var ult: Dictionary = contracts_cfg.get("ultimate", {})
	if d == int(ult.get("day", 15)):
		cards.append(_ultimate_card(rng, bonus, d))
	var bulk: Dictionary = contracts_cfg.get("bulk", {})
	var i := cards.size()
	while i < slots:
		var eligible: bool = d >= int(bulk.get("min_day", 5)) and d <= int(bulk.get("max_day", 16)) \
			and reputation_value() >= float(bulk.get("rep_min", 55))
		var roll := rng.randf()
		if eligible and roll < float(bulk.get("board_chance", 0.45)):
			cards.append(_bulk_card(rng, bonus, d, i))
		else:
			cards.append(_spot_card(rng, bonus, d, i))
		i += 1
	return cards


func _spot_card(rng: RandomNumberGenerator, bonus: float, d: int, idx: int) -> Dictionary:
	var cfg: Dictionary = contracts_cfg.get("spot", {})
	var pid: String = product_ids[rng.randi() % product_ids.size()]
	var qty := int(round(float(cfg.get("qty_base", 3)) + float(cfg.get("qty_per_day", 0.4)) * d))
	qty += rng.randi_range(-int(cfg.get("qty_variance", 2)), int(cfg.get("qty_variance", 2)))
	qty = maxi(int(cfg.get("qty_min", 2)), qty)
	var unit := maxi(1, int(ceil(float(products[pid]["base_price"]) * float(cfg.get("price_mult", 1.7)) * bonus)))
	var total := qty * unit
	return {
		"id": "d%d_%d" % [d, idx], "kind": "spot", "product_id": pid,
		"qty": qty, "unit_price": unit, "total": total, "deposit": 0, "due_day": d,
		"penalty": int(ceil(total * float(cfg.get("penalty_rate", 0.3)))),
		"rep_penalty": float(cfg.get("rep_penalty", 4)), "rep_reward": float(cfg.get("rep_reward", 2)),
		"favor_reward": 0, "score_bonus": 0,
	}


func _bulk_card(rng: RandomNumberGenerator, bonus: float, d: int, idx: int) -> Dictionary:
	var cfg: Dictionary = contracts_cfg.get("bulk", {})
	var pid: String = product_ids[rng.randi() % product_ids.size()]
	var qmin := int(cfg.get("qty_min", 10))
	var qmax := int(cfg.get("qty_max", 18))
	var qty := qmin + (rng.randi() % maxi(1, qmax - qmin + 1))
	var due := d + int(cfg.get("due_min", 2)) + (rng.randi() % maxi(1, int(cfg.get("due_max", 3)) - int(cfg.get("due_min", 2)) + 1))
	due = mini(due, int(state["total_days"]))
	var unit := maxi(1, int(ceil(float(products[pid]["base_price"]) * float(cfg.get("price_mult", 2.0)) * bonus)))
	var total := qty * unit
	var deposit := int(round(total * float(cfg.get("deposit_rate", 0.3))))
	return {
		"id": "d%d_%d" % [d, idx], "kind": "bulk", "product_id": pid,
		"qty": qty, "unit_price": unit, "total": total, "deposit": deposit, "due_day": due,
		"penalty": int(round(deposit * float(cfg.get("penalty_deposit_mult", 1.5)))),
		"rep_penalty": float(cfg.get("rep_penalty", 8)), "rep_reward": float(cfg.get("rep_reward", 5)),
		"favor_reward": int(cfg.get("favor_reward", 1)), "score_bonus": 0,
	}


func _ultimate_card(rng: RandomNumberGenerator, bonus: float, d: int) -> Dictionary:
	var cfg: Dictionary = contracts_cfg.get("ultimate", {})
	var pid := _theme_product()
	var qmin := int(cfg.get("qty_min", 18))
	var qmax := int(cfg.get("qty_max", 22))
	var qty := qmin + (rng.randi() % maxi(1, qmax - qmin + 1))
	var unit := maxi(1, int(ceil(float(products[pid]["base_price"]) * float(cfg.get("price_mult", 2.4)) * bonus)))
	var total := qty * unit
	var deposit := int(round(total * float(cfg.get("deposit_rate", 0.4))))
	return {
		"id": "d%d_ult" % d, "kind": "ultimate", "product_id": pid,
		"qty": qty, "unit_price": unit, "total": total, "deposit": deposit,
		"due_day": int(cfg.get("due_day", 18)),
		"penalty": int(round(deposit * float(cfg.get("penalty_deposit_mult", 2.0)))),
		"rep_penalty": float(cfg.get("rep_penalty", 12)), "rep_reward": float(cfg.get("rep_reward", 0)),
		"favor_reward": 0, "score_bonus": int(cfg.get("score_bonus", 150)),
	}


# ---------------------------------------------------------------- visitors

func visitor_for(day: int = -1) -> Dictionary:
	var d := day if day > 0 else day_value()
	if state.get("done", false):
		return {}
	# 1. sweeper — enough stock dies after tonight
	var sw: Dictionary = visitors_cfg.get("sweeper", {})
	var exp_total := expiring_units()
	if exp_total >= int(sw.get("min_expiring", 4)):
		var rate := float(sw.get("price_rate", 0.55))
		var payout := 0
		var per := {}
		for id in product_ids:
			var u := expiring_units(id)
			if u > 0:
				per[id] = u
				payout += u * maxi(1, int(ceil(float(state["prices"][id]) * rate)))
		return {"kind": "sweeper", "units": exp_total, "per_product": per, "payout_est": payout, "rate": rate}
	# 2. informant — heat runs high
	var inf: Dictionary = visitors_cfg.get("informant", {})
	if heat_value() >= int(inf.get("heat_min", 40)):
		var cost := int(ceil(float(inf.get("base_cost", 12)) + heat_value() * float(inf.get("cost_per_heat", 0.5))))
		return {"kind": "informant", "cost": cost, "heat_relief": int(inf.get("heat_relief", 25))}
	# 3. broker — tight rumor, cash on hand (certainty lands on next planning's "tomorrow")
	var br: Dictionary = visitors_cfg.get("broker", {})
	if d + 2 <= int(state["total_days"]) and int(state["certain_rumor_day"]) != d + 2 and cash_value() >= int(br.get("cost", 18)):
		var pair := _rumor_pair(d + 1)
		if pair.size() == 2:
			var gap: int = absi(int(pair[0]["prob"]) - int(pair[1]["prob"]))
			if gap <= int(br.get("prob_gap_max", 30)):
				return {"kind": "broker", "cost": int(br.get("cost", 18))}
	# 4. vip — reputation and luxury stock
	var vip: Dictionary = visitors_cfg.get("vip", {})
	if reputation_value() >= float(vip.get("rep_min", 65)):
		var tags: Array = vip.get("tags", ["luxury", "premium"])
		var best := ""
		var best_units := 0
		for id in product_ids:
			var p: Dictionary = products[id]
			var has_tag := false
			for t in p.get("tags", []):
				if t in tags:
					has_tag = true
					break
			if has_tag and inventory_count(id) > best_units:
				best_units = inventory_count(id)
				best = id
		if best != "" and best_units >= int(vip.get("stock_min", 2)):
			return {
				"kind": "vip", "product_id": best,
				"qty": mini(int(vip.get("buy_limit", 4)), best_units),
				"unit_price": maxi(1, int(ceil(float(state["prices"][best]) * float(vip.get("price_mult", 2.0))))),
				"promise_qty": int(vip.get("promise_qty", 3)),
			}
	# cameo — pure flavor
	var rng := stable_rng("visitor", d)
	if rng.randf() < float(visitors_cfg.get("cameo_chance", 0.25)):
		var tmin := int(visitors_cfg.get("cameo_tip_min", 2))
		var tmax := int(visitors_cfg.get("cameo_tip_max", 6))
		return {"kind": "cameo", "tip": tmin + (rng.randi() % maxi(1, tmax - tmin + 1))}
	return {}


# ---------------------------------------------------------------- demand

func demand_for(product_id: String, price: int, include_noise: bool = true, levels: Dictionary = {}) -> int:
	if levels.is_empty():
		levels = levels_with()
	var product: Dictionary = products[product_id]
	var group: Dictionary = group_at()
	var effects: Dictionary = event_at().get("effects", {})
	var base := float(product["base_demand"])
	base *= float(effects.get("demand_all", 1.0))
	base *= _tag_mult(product, effects.get("demand_tags", {}))
	if day_value() == int(state["total_days"]):
		base *= float(finale_cfg.get("demand_all", 2.2))
		if str(state["finale_theme"]["tag"]) in (product.get("tags", []) as Array):
			base *= float(finale_cfg.get("theme_mult", 2.5))
	var pref: Array = group.get("preferred_tags", [])
	var match_count := 0
	for t in product.get("tags", []):
		if t in pref:
			match_count += 1
	base *= 1.0 + float(game_cfg.get("group_pref_bonus", 0.18)) * match_count
	var sens := float(group.get("price_sensitivity", 1.0))
	var ratio := float(price) / maxf(1.0, float(product["base_price"]))
	base *= pow(maxf(0.35, 2.0 - ratio), sens * float(game_cfg.get("price_elasticity_pow", 0.55)))
	base *= _route_tag_demand(product)
	base *= 1.0 + (reputation_value() - 50.0) * float(rep_cfg.get("demand_per_point", 0.006))
	base *= float((state["price_memory"] as Dictionary).get(product_id, 1.0))
	if include_noise:
		var noise := float(game_cfg.get("demand_noise", 0.12))
		var rng := stable_rng("demand:" + product_id)
		base *= rng.randf_range(1.0 - noise, 1.0 + noise)
	return maxi(0, int(round(base)))


func demand_forecast(product_id: String, price: int) -> Dictionary:
	var mid := demand_for(product_id, price, false)
	var uncertainty := 0.18
	return {
		"at_price": price,
		"low": maxi(0, int(floor(mid * (1.0 - uncertainty)))),
		"high": maxi(0, int(ceil(mid * (1.0 + uncertainty)))),
	}


# ---------------------------------------------------------------- money helpers

func rent_for(day: int = -1) -> int:
	var d := day if day > 0 else day_value()
	if d == int(state["total_days"]):
		var fee := float(finale_cfg.get("stall_fee", 50))
		var cp2 = state["checkpoints"].get("cp2")
		var cfg := _cp_cfg("cp2")
		if cp2 == true:
			fee *= float(cfg.get("stall_fee_mult_pass", 0.5))
		elif cp2 == false:
			fee *= float(cfg.get("stall_fee_mult_fail", 1.5))
		return int(round(fee))
	var rent := 0
	for act in rent_cfg.get("acts", []):
		if d >= int(act["from"]) and d <= int(act["to"]):
			rent = int(act["rent"])
			break
	var cp2_day := int(_cp_cfg("cp2").get("day", 12))
	if state["checkpoints"].get("cp1") == false and d > int(_cp_cfg("cp1").get("day", 6)) and d <= cp2_day:
		rent += int(rent_cfg.get("fail_bump", 6))
	return rent


func _cp_cfg(id: String) -> Dictionary:
	for c in checkpoints_cfg:
		if str(c.get("id", "")) == id:
			return c
	return {}


func inventory_value() -> int:
	var v := 0
	for id in product_ids:
		v += inventory_count(id) * int(products[id]["base_cost"])
	return v


func liquidation_value() -> int:
	return int(floor(inventory_value() * float(score_cfg.get("inventory_rate", 0.5))))


func outstanding_debt() -> int:
	var total := 0.0
	for loan in state["loans"]:
		var nights := maxi(1, int(loan.get("nights", 8)))
		total += float(loan.get("amount", 0)) * float(loan.get("remaining", 0)) / float(nights)
	return int(round(total))


func net_worth() -> int:
	return cash_value() + liquidation_value() - outstanding_debt()


func current_score() -> int:
	var stats: Dictionary = state["stats"]
	var score := cash_value() + liquidation_value()
	score -= int(round(outstanding_debt() * float(score_cfg.get("debt_mult", 1.5))))
	score += int(round(reputation_value() * float(score_cfg.get("rep_mult", 5))))
	score += int(stats["contracts_fulfilled"]) * int(score_cfg.get("fulfill_mult", 10))
	score -= int(stats["contracts_breached"]) * int(score_cfg.get("breach_mult", 20))
	if stats.get("ultimate_fulfilled", false):
		score += int((contracts_cfg.get("ultimate", {}) as Dictionary).get("score_bonus", 150))
	return score


func _add_rep(delta: float) -> void:
	state["reputation"] = clampf(round((reputation_value() + delta) * 100.0) / 100.0, 0.0, 100.0)


func _add_favor(n: int) -> void:
	var cap := int(favor_cfg.get("max", 3))
	var before := favor_value()
	state["favor"] = clampi(before + n, 0, cap)
	if n > 0:
		state["stats"]["favor_gained"] = int(state["stats"]["favor_gained"]) + maxi(0, favor_value() - before)


func loan_available() -> bool:
	return cash_value() < int(loans_cfg.get("unlock_below", 30)) \
		and (state["loans"] as Array).size() < int(loans_cfg.get("max_loans", 2))


# ---------------------------------------------------------------- inventory ops

func _take_units(product_id: String, qty: int) -> void:
	var left := qty
	var inv: Dictionary = state["inventory"]
	var new_batches: Array = []
	for b in inv[product_id]:
		if left <= 0:
			new_batches.append(b)
			continue
		var q := int(b["quantity"])
		var take := mini(q, left)
		q -= take
		left -= take
		if q > 0:
			var nb: Dictionary = b.duplicate()
			nb["quantity"] = q
			new_batches.append(nb)
	inv[product_id] = new_batches


func _seize_hot() -> int:
	var seized := 0
	var inv: Dictionary = state["inventory"]
	for id in product_ids:
		var kept: Array = []
		for b in inv[id]:
			if b.get("hot", false):
				seized += int(b["quantity"])
			else:
				kept.append(b)
		inv[id] = kept
	return seized


func _remove_expiring() -> Dictionary:
	var removed := {}
	var inv: Dictionary = state["inventory"]
	for id in product_ids:
		var kept: Array = []
		var n := 0
		for b in inv[id]:
			var dl = b.get("days_left", null)
			if dl != null and int(dl) == 1:
				n += int(b["quantity"])
			else:
				kept.append(b)
		inv[id] = kept
		if n > 0:
			removed[id] = n
	return removed


func _add_batch(product_id: String, qty: int, life: Variant, hot: bool, cost: int) -> void:
	if qty <= 0:
		return
	var inv: Dictionary = state["inventory"]
	var batches: Array = inv[product_id]
	batches.append({"quantity": qty, "days_left": life, "hot": hot, "unit_cost": cost})
	inv[product_id] = batches


# ---------------------------------------------------------------- action normalization

func _normalize_action(action: Dictionary) -> Dictionary:
	var raw_orders: Dictionary = action.get("orders", {})
	var raw_prices: Dictionary = action.get("prices", {})
	var orders := {}
	var prices := {}
	var current: Dictionary = state["prices"]
	var closed := market_closed()
	for id in product_ids:
		var q := int(raw_orders.get(id, 0))
		var p := int(raw_prices.get(id, current[id]))
		if q < 0 or q > 99:
			last_error = "order for %s must be 0..99" % id
			return {}
		if closed and q > 0:
			last_error = "wholesale market is closed on the final night"
			return {}
		var bounds := price_bounds(id)
		if p < bounds.x or p > bounds.y:
			last_error = "price for %s out of bounds" % id
			return {}
		orders[id] = q
		prices[id] = p
	var upgrade = action.get("upgrade", null)
	if upgrade == "" or upgrade == "none":
		upgrade = null
	if upgrade != null:
		if not upgrades.has(str(upgrade)):
			last_error = "unknown upgrade"
			return {}
		if int(state["upgrade_levels"][str(upgrade)]) >= int(upgrades[str(upgrade)]["max_level"]):
			last_error = "upgrade maxed"
			return {}
	# contracts
	var board := contracts_board()
	var board_ids := {}
	for c in board:
		board_ids[str(c["id"])] = c
	var accepts: Array = []
	for cid in action.get("contracts_accept", []):
		var s := str(cid)
		if not board_ids.has(s):
			last_error = "contract %s not on tonight's board" % s
			return {}
		if not (s in accepts):
			accepts.append(s)
	# smuggle
	var offers := smuggle_offers()
	var offer_map := {}
	for o in offers:
		offer_map[str(o["product_id"])] = o
	var smuggle := {}
	for pid in action.get("smuggle", {}):
		var q2 := int(action["smuggle"][pid])
		if q2 <= 0:
			continue
		if not offer_map.has(str(pid)):
			last_error = "smuggle offer for %s not available tonight" % pid
			return {}
		if q2 > int(offer_map[str(pid)]["limit"]):
			last_error = "smuggle qty for %s exceeds limit" % pid
			return {}
		smuggle[str(pid)] = q2
	# visitor
	var visitor := bool(action.get("visitor", false))
	if visitor_for().is_empty():
		visitor = false
	# route card
	var route = action.get("route_card", null)
	if route == "" or route == "none":
		route = null
	if route != null:
		var offered := false
		for opt in route_offer_for():
			if str(opt["id"]) == str(route):
				offered = true
				break
		if not offered:
			last_error = "route card not offered tonight"
			return {}
	# favor use
	var favor_use = action.get("favor_use", null)
	if favor_use != null and (typeof(favor_use) != TYPE_DICTIONARY or (favor_use as Dictionary).is_empty()):
		favor_use = null
	if favor_use != null:
		var ftype := str(favor_use.get("type", ""))
		if not (ftype in FAVOR_TYPES):
			last_error = "unknown favor_use type"
			return {}
		if favor_value() < 1:
			last_error = "no favor points"
			return {}
		if ftype == "restock":
			var fpid := str(favor_use.get("product_id", favor_use.get("pid", "")))
			if not products.has(fpid):
				last_error = "favor restock needs a valid product_id"
				return {}
			if closed:
				last_error = "cannot restock on the final night"
				return {}
			favor_use = {"type": ftype, "product_id": fpid}
		else:
			favor_use = {"type": ftype}
	# loan
	var loan := bool(action.get("loan", false))
	if loan and not loan_available():
		last_error = "loan not available"
		return {}
	return {
		"orders": orders, "prices": prices, "upgrade": upgrade,
		"contracts_accept": accepts, "smuggle": smuggle, "visitor": visitor,
		"route_card": route, "favor_use": favor_use, "loan": loan,
	}


# ---------------------------------------------------------------- quote

func try_quote_action(action: Dictionary) -> Variant:
	last_error = ""
	var n := _normalize_action(action)
	if n.is_empty():
		return null
	var d := day_value()
	var upgrade_id = n["upgrade"]
	var levels := levels_with(str(upgrade_id) if upgrade_id != null else "")
	var orders: Dictionary = n["orders"]
	var unit_costs := {}
	var procurement := 0
	for id in product_ids:
		var c := unit_cost(id, levels)
		unit_costs[id] = c
		procurement += int(orders[id]) * c
	# smuggle
	var offers := smuggle_offers()
	var offer_map := {}
	for o in offers:
		offer_map[str(o["product_id"])] = o
	var smuggle_cost := 0
	var smuggle_units := 0
	for pid in n["smuggle"]:
		var q := int(n["smuggle"][pid])
		smuggle_cost += q * int(offer_map[pid]["unit_price"])
		smuggle_units += q
	# favor restock
	var restock_cost := 0
	var restock_units := 0
	var fu = n["favor_use"]
	if fu != null and str(fu.get("type", "")) == "restock":
		restock_units = int(favor_cfg.get("restock_qty", 5))
		restock_cost = restock_units * int(products[str(fu["product_id"])]["base_cost"])
	var upgrade_cost_v := upgrade_cost(str(upgrade_id)) if upgrade_id != null else 0
	# contracts accepted tonight
	var board := contracts_board()
	var board_map := {}
	for c in board:
		board_map[str(c["id"])] = c
	var deposits := 0
	var accepted_cards: Array = []
	for cid in n["contracts_accept"]:
		var card: Dictionary = board_map[cid]
		accepted_cards.append(card)
		deposits += int(card["deposit"])
	var loan_amount := int(loans_cfg.get("amount", 150)) if n["loan"] else 0
	var total_spend := procurement + smuggle_cost + upgrade_cost_v + restock_cost
	var available := cash_value() + loan_amount + deposits
	if total_spend > 0 and total_spend > available:
		last_error = "cannot afford plan: costs %d, available %d" % [total_spend, available]
		return null
	# capacity
	var projected := inventory_count() + smuggle_units + restock_units
	for id in product_ids:
		projected += int(orders[id])
	var cap := capacity(levels)
	var cap_limit := maxi(inventory_count(), cap)
	if projected > cap_limit:
		last_error = "capacity exceeded: %d / %d" % [projected, cap]
		return null
	# contracts due tonight (already active + accepted tonight)
	var due_tonight: Array = []
	for c in state["active_contracts"]:
		if int(c["due_day"]) == d:
			due_tonight.append(c)
	for c in accepted_cards:
		if int(c["due_day"]) == d:
			due_tonight.append(c)
	var due_qty := {}
	var due_revenue := 0
	var due_penalty := 0
	for c in due_tonight:
		var pid2 := str(c["product_id"])
		due_qty[pid2] = int(due_qty.get(pid2, 0)) + int(c["qty"])
		due_revenue += int(c["total"]) - int(c["deposit"])
		due_penalty += int(c["penalty"])
	# walk-in forecast, after reserving due-contract stock
	var prices: Dictionary = n["prices"]
	var forecasts := {}
	var est_low := 0
	var est_high := 0
	for id in product_ids:
		var fc := demand_forecast(id, int(prices[id]))
		forecasts[id] = fc
		var have := inventory_count(id) + int(orders[id]) + int(n["smuggle"].get(id, 0))
		if fu != null and str(fu.get("type", "")) == "restock" and str(fu.get("product_id", "")) == id:
			have += restock_units
		have = maxi(0, have - int(due_qty.get(id, 0)))
		est_low += mini(have, int(fc["low"])) * int(prices[id])
		est_high += mini(have, int(fc["high"])) * int(prices[id])
	# risk
	var extra_heat := smuggle_units * int(heat_cfg.get("per_unit", 2))
	var iprob := inspection_prob(extra_heat, smuggle_units)
	var projected_heat := clampi(heat_value() + extra_heat, 0, _heat_cap())
	var exposure := due_penalty
	for c in state["active_contracts"]:
		if int(c["due_day"]) != d:
			exposure += int(c["penalty"])
	for c in accepted_cards:
		if int(c["due_day"]) != d:
			exposure += int(c["penalty"])
	# visitor delta (estimate)
	var visitor := visitor_for()
	var visitor_best := 0
	var visitor_worst := 0
	if n["visitor"] and not visitor.is_empty():
		match str(visitor["kind"]):
			"sweeper":
				visitor_best = int(visitor.get("payout_est", 0))
				visitor_worst = visitor_best
			"informant":
				visitor_best = -int(visitor.get("cost", 0))
				visitor_worst = visitor_best
			"broker":
				visitor_best = -int(visitor.get("cost", 0))
				visitor_worst = visitor_best
			"vip":
				visitor_best = int(visitor.get("qty", 0)) * int(visitor.get("unit_price", 0))
				visitor_worst = visitor_best
			"cameo":
				visitor_best = int(visitor.get("tip", 0))
				visitor_worst = visitor_best
	var rent := rent_for(d)
	if fu != null and str(fu.get("type", "")) == "rent_free":
		rent = 0
	var best_case := -total_spend + deposits + est_high + due_revenue + visitor_best - rent
	var worst_inspect := 0
	if iprob > 0.0:
		worst_inspect = projected_heat * int(heat_cfg.get("fine_per_heat", 1)) + hot_value() + smuggle_cost
	# worst-case due penalty (export only, §4): contracts whose quantity is fully
	# covered by reserved CLEAN stock (non-hot — hot batches can be seized in the
	# worst case) cannot breach, so their penalty never lands in the worst case.
	# Coverage walks due_tonight in settlement order, mirroring try_step.
	var clean_have := {}
	for id in product_ids:
		var nh := 0
		for b in (state["inventory"] as Dictionary)[id]:
			if not b.get("hot", false):
				nh += int(b.get("quantity", 0))
		nh += int(orders[id])
		if fu != null and str(fu.get("type", "")) == "restock" and str(fu.get("product_id", "")) == id:
			nh += restock_units
		clean_have[id] = nh
	var worst_due_penalty := 0
	for c in due_tonight:
		var pidw := str(c["product_id"])
		var qw := int(c["qty"])
		if int(clean_have[pidw]) >= qw:
			clean_have[pidw] = int(clean_have[pidw]) - qw
		else:
			worst_due_penalty += int(c["penalty"])
	var worst_case := -total_spend + deposits + est_low + visitor_worst - rent - worst_inspect - worst_due_penalty
	# inspection decomposition for the UI (export only — mirrors inspection_prob)
	@warning_ignore("integer_division")
	var insp_floor := float(heat_cfg.get("floor_base", 6)) + float((int(state["total_smuggled"]) + smuggle_units) / maxi(1, int(heat_cfg.get("floor_per_units", 12))))
	var insp_mult := float(event_at(d).get("inspect_mult", 1.0)) * float(_route_effect("inspect_prob_mult", 1.0))
	return {
		"unit_costs": unit_costs,
		"procurement": procurement,
		"smuggle_cost": smuggle_cost,
		"smuggle_units": smuggle_units,
		"restock_cost": restock_cost,
		"upgrade_cost": upgrade_cost_v,
		"total_spend": total_spend,
		"deposits": deposits,
		"loan_amount": loan_amount,
		"projected_units": projected,
		"projected_capacity": cap,
		"demand_forecasts": forecasts,
		"estimated_revenue": {"low": est_low, "high": est_high},
		"contract_due_revenue": due_revenue,
		"inspection_prob": iprob,
		"best_case": best_case,
		"worst_case": worst_case,
		"contract_exposure": exposure,
		# worst-case audit trail + projected risk (export only, §7 只增不改)
		"worst_inspect": worst_inspect,
		"due_penalty": due_penalty,
		"worst_due_penalty": worst_due_penalty,
		"rent": rent,
		"projected_heat": projected_heat,
		"heat_added": extra_heat,
		"inspect_floor": insp_floor,
		"inspect_mult": insp_mult,
		"inspect_cap": float(heat_cfg.get("prob_cap", 80)),
	}


# ---------------------------------------------------------------- step

func try_step(action: Dictionary) -> Variant:
	last_error = ""
	if state.get("done", false):
		last_error = "episode already finished"
		return null
	# capture planning-time offers before any mutation
	var board := contracts_board()
	var visitor_offer := visitor_for()
	var smug_offers := smuggle_offers()
	var quote = try_quote_action(action)
	if quote == null:
		return null
	var n := _normalize_action(action)
	var current_day := day_value()
	var cash_before := cash_value()
	var rep_before := reputation_value()
	var upgrade_id = n["upgrade"]
	var levels := levels_with(str(upgrade_id) if upgrade_id != null else "")
	var fu = n["favor_use"]
	# ---- planning application ----
	var loan_received := 0
	if n["loan"]:
		loan_received = int(loans_cfg.get("amount", 150))
		state["cash"] = cash_value() + loan_received
		var loans: Array = state["loans"]
		loans.append({
			"amount": loan_received,
			"payment": int(loans_cfg.get("payment", 25)),
			"nights": int(loans_cfg.get("nights", 8)),
			"remaining": int(loans_cfg.get("nights", 8)),
		})
		state["stats"]["loans_taken"] = int(state["stats"]["loans_taken"]) + 1
	for id in product_ids:
		state["prices"][id] = int(n["prices"][id])
	# route card (applies immediately)
	if n["route_card"] != null:
		var slot := _route_slot_for(str(n["route_card"]))
		if slot != "":
			state["route_cards"][slot] = str(n["route_card"])
			state["heat"] = clampi(heat_value(), 0, _heat_cap())
	# upgrade
	if upgrade_id != null:
		state["upgrade_levels"][str(upgrade_id)] = int(state["upgrade_levels"][str(upgrade_id)]) + 1
	# official procurement
	for id in product_ids:
		var qty := int(n["orders"][id])
		if qty > 0:
			_add_batch(id, qty, shelf_life(id, levels), false, int(quote["unit_costs"][id]))
	# smuggle procurement
	var offer_map := {}
	for o in smug_offers:
		offer_map[str(o["product_id"])] = o
	var smuggled_units := 0
	for pid in n["smuggle"]:
		var q := int(n["smuggle"][pid])
		_add_batch(pid, q, shelf_life(pid, levels), true, int(offer_map[pid]["unit_price"]))
		smuggled_units += q
	if smuggled_units > 0:
		_add_heat(smuggled_units * int(heat_cfg.get("per_unit", 2)))
		state["total_smuggled"] = int(state["total_smuggled"]) + smuggled_units
		state["stats"]["smuggled_units"] = int(state["stats"]["smuggled_units"]) + smuggled_units
	# favor spend (rent_free / restock consumed now; contract_waive armed)
	var waive_armed := false
	var rent_waived := false
	if fu != null:
		match str(fu["type"]):
			"restock":
				var fpid := str(fu["product_id"])
				_add_batch(fpid, int(favor_cfg.get("restock_qty", 5)), shelf_life(fpid, levels), false, int(products[fpid]["base_cost"]))
				state["favor"] = favor_value() - 1
				state["stats"]["favor_used"] = int(state["stats"]["favor_used"]) + 1
			"rent_free":
				rent_waived = true
				state["favor"] = favor_value() - 1
				state["stats"]["favor_used"] = int(state["stats"]["favor_used"]) + 1
			"contract_waive":
				waive_armed = true
	state["cash"] = cash_value() - int(quote["total_spend"])
	# contract acceptance (deposits in)
	var board_map := {}
	for c in board:
		board_map[str(c["id"])] = c
	var accepted: Array = []
	var deposits := 0
	for cid in n["contracts_accept"]:
		var card: Dictionary = (board_map[cid] as Dictionary).duplicate(true)
		card["accepted_day"] = current_day
		(state["active_contracts"] as Array).append(card)
		deposits += int(card["deposit"])
		accepted.append(card)
	if deposits > 0:
		state["cash"] = cash_value() + deposits
	# ---- settlement ----
	# reputation attribution (export only, §7): every _add_rep below also logs
	# its amount here — the calculation itself is untouched.
	var rep_break := {
		"contract": 0.0, "inspection": 0.0, "vip": 0.0, "checkpoint": 0.0,
		"event": 0.0, "service": 0.0, "stockout": 0.0, "spoilage": 0.0,
	}
	# a) vip promise from last night, then tonight's visitor
	var vip_promise_result := {}
	var promise = state["vip_promise"]
	if promise != null and int(promise["due_day"]) == current_day:
		var ppid := str(promise["product_id"])
		var pqty := int(promise["qty"])
		var vcfg: Dictionary = visitors_cfg.get("vip", {})
		if inventory_count(ppid) >= pqty:
			_take_units(ppid, pqty)
			var prev := pqty * maxi(1, int(ceil(float(state["prices"][ppid]) * float(vcfg.get("price_mult", 2.0)))))
			state["cash"] = cash_value() + prev
			_add_favor(int(vcfg.get("promise_favor_reward", 1)))
			vip_promise_result = {"kept": true, "product_id": ppid, "qty": pqty, "revenue": prev}
		else:
			_add_rep(-float(vcfg.get("promise_rep_penalty", 3)))
			rep_break["vip"] -= float(vcfg.get("promise_rep_penalty", 3))
			vip_promise_result = {"kept": false, "product_id": ppid, "qty": pqty, "revenue": 0}
		state["vip_promise"] = null
	var visitor_result := {}
	var visitor_delta := 0
	if n["visitor"] and not visitor_offer.is_empty():
		match str(visitor_offer["kind"]):
			"sweeper":
				var removed := _remove_expiring()
				var rate := float(visitor_offer.get("rate", 0.55))
				var payout := 0
				var units := 0
				for pid2 in removed:
					var u := int(removed[pid2])
					units += u
					payout += u * maxi(1, int(ceil(float(state["prices"][pid2]) * rate)))
				state["cash"] = cash_value() + payout
				visitor_delta = payout
				visitor_result = {"kind": "sweeper", "accepted": true, "units": units, "payout": payout, "per_product": removed}
			"informant":
				var cost := int(visitor_offer["cost"])
				state["cash"] = cash_value() - cost
				state["heat"] = maxi(0, heat_value() - int(visitor_offer["heat_relief"]))
				visitor_delta = -cost
				visitor_result = {"kind": "informant", "accepted": true, "cost": cost, "heat_after": heat_value()}
			"broker":
				var cost2 := int(visitor_offer["cost"])
				state["cash"] = cash_value() - cost2
				state["certain_rumor_day"] = current_day + 2
				visitor_delta = -cost2
				visitor_result = {"kind": "broker", "accepted": true, "cost": cost2}
			"vip":
				var vpid := str(visitor_offer["product_id"])
				var vqty := mini(int(visitor_offer["qty"]), inventory_count(vpid))
				_take_units(vpid, vqty)
				var vrev := vqty * int(visitor_offer["unit_price"])
				state["cash"] = cash_value() + vrev
				state["vip_promise"] = {
					"product_id": vpid, "qty": int(visitor_offer["promise_qty"]),
					"due_day": current_day + 1,
				}
				visitor_delta = vrev
				visitor_result = {"kind": "vip", "accepted": true, "qty": vqty, "revenue": vrev, "promise_qty": int(visitor_offer["promise_qty"])}
			"cameo":
				var tip := int(visitor_offer["tip"])
				state["cash"] = cash_value() + tip
				visitor_delta = tip
				visitor_result = {"kind": "cameo", "accepted": true, "tip": tip}
	elif not visitor_offer.is_empty():
		visitor_result = {"kind": str(visitor_offer["kind"]), "accepted": false}
	# b) inspection
	var inspection := {"occurred": false, "prob": inspection_prob(), "seized_units": 0, "fine": 0}
	if hot_count() > 0 and float(inspection["prob"]) > 0.0:
		var roll := stable_rng("inspect", current_day).randf() * 100.0
		if roll < float(inspection["prob"]):
			var seized := _seize_hot()
			var fine := heat_value() * int(heat_cfg.get("fine_per_heat", 1))
			state["cash"] = cash_value() - fine
			_add_rep(-float(heat_cfg.get("seize_rep_penalty", 5)))
			rep_break["inspection"] -= float(heat_cfg.get("seize_rep_penalty", 5))
			@warning_ignore("integer_division")
			state["heat"] = heat_value() / 2
			state["stats"]["seizures"] = int(state["stats"]["seizures"]) + 1
			state["stats"]["units_seized"] = int(state["stats"]["units_seized"]) + seized
			inspection = {"occurred": true, "prob": inspection["prob"], "seized_units": seized, "fine": fine}
	# c) contract delivery (before walk-in crowd)
	var contract_results: Array = []
	var contract_revenue := 0
	var contract_penalty := 0
	var waive_used := false
	var remaining_contracts: Array = []
	for c in state["active_contracts"]:
		if int(c["due_day"]) != current_day:
			remaining_contracts.append(c)
			continue
		var cpid := str(c["product_id"])
		var cqty := int(c["qty"])
		if inventory_count(cpid) >= cqty:
			_take_units(cpid, cqty)
			var pay := int(c["total"]) - int(c["deposit"])
			state["cash"] = cash_value() + pay
			contract_revenue += pay
			_add_rep(float(c["rep_reward"]))
			rep_break["contract"] += float(c["rep_reward"])
			if int(c["favor_reward"]) > 0:
				_add_favor(int(c["favor_reward"]))
			state["stats"]["contracts_fulfilled"] = int(state["stats"]["contracts_fulfilled"]) + 1
			if str(c["kind"]) == "ultimate":
				state["stats"]["ultimate_fulfilled"] = true
			contract_results.append({"id": c["id"], "kind": c["kind"], "product_id": cpid, "qty": cqty, "fulfilled": true, "revenue": pay, "penalty": 0, "waived": false})
		else:
			var pen := int(c["penalty"])
			var waived := false
			if waive_armed and not waive_used:
				waive_used = true
				waived = true
				state["favor"] = favor_value() - 1
				state["stats"]["favor_used"] = int(state["stats"]["favor_used"]) + 1
			else:
				state["cash"] = cash_value() - pen
				contract_penalty += pen
				_add_rep(-float(c["rep_penalty"]))
				rep_break["contract"] -= float(c["rep_penalty"])
			state["stats"]["contracts_breached"] = int(state["stats"]["contracts_breached"]) + 1
			contract_results.append({"id": c["id"], "kind": c["kind"], "product_id": cpid, "qty": cqty, "fulfilled": false, "revenue": 0, "penalty": 0 if waived else pen, "waived": waived})
	state["active_contracts"] = remaining_contracts
	# d) walk-in sales
	var product_results := {}
	var total_sold := 0
	var total_demand := 0
	var total_revenue := 0
	var stockouts := 0
	var group := group_at()
	for id in product_ids:
		var price := int(n["prices"][id])
		var demand := demand_for(id, price, true, levels)
		var have := inventory_count(id)
		var sold := mini(have, demand)
		_take_units(id, sold)
		var stockout := sold < demand and demand > 0
		if stockout:
			stockouts += 1
		var revenue := sold * price
		total_sold += sold
		total_demand += demand
		total_revenue += revenue
		product_results[id] = {
			"sold": sold, "demand": demand, "revenue": revenue,
			"remaining": inventory_count(id), "stockout": stockout,
		}
	state["cash"] = cash_value() + total_revenue
	# e) spoilage
	var inv: Dictionary = state["inventory"]
	var spoiled_total := 0
	var spoilage := {}
	for id in product_ids:
		var kept: Array = []
		var spoiled_q := 0
		for b in inv[id]:
			var dl = b.get("days_left", null)
			if dl == null:
				kept.append(b)
				continue
			var days := int(dl) - 1
			if days <= 0:
				spoiled_q += int(b["quantity"])
			else:
				var nb: Dictionary = b.duplicate()
				nb["days_left"] = days
				kept.append(nb)
		inv[id] = kept
		if spoiled_q > 0:
			spoilage[id] = spoiled_q
			spoiled_total += spoiled_q
	var waste_fee := int(round(spoiled_total * float(game_cfg.get("waste_fee", 1)) * float(_route_effect("waste_fee_mult", 1.0))))
	state["cash"] = cash_value() - waste_fee
	# f) rent + loan payments + interest
	var rent := 0 if rent_waived else rent_for(current_day)
	state["cash"] = cash_value() - rent
	var loan_paid := 0
	for loan in state["loans"]:
		if int(loan["remaining"]) > 0:
			loan_paid += int(loan["payment"])
			loan["remaining"] = int(loan["remaining"]) - 1
	if loan_paid > 0:
		state["cash"] = cash_value() - loan_paid
	var interest := 0
	if cash_value() < 0:
		interest = int(ceil(-cash_value() * float(loans_cfg.get("negative_interest", 0.2))))
		state["cash"] = cash_value() - interest
	# g) heat decay
	var heat_before_decay := heat_value()
	var decay := int(ceil(heat_before_decay * float(heat_cfg.get("decay_rate", 0.22))))
	if heat_before_decay >= int(heat_cfg.get("decay_min", 4)):
		decay = maxi(decay, int(heat_cfg.get("decay_min", 4)))
	state["heat"] = maxi(0, heat_before_decay - decay)
	# h) reputation from service
	var fulfillment := 1.0 if total_demand == 0 else float(total_sold) / float(total_demand)
	var rep_delta := (fulfillment - 0.75) * 8.0
	rep_break["service"] = (fulfillment - 0.75) * 8.0
	if stockouts > 0:
		rep_delta -= stockouts * 0.8
		rep_break["stockout"] = -stockouts * 0.8
	if spoiled_total > 0:
		rep_delta -= spoiled_total * 0.15
		rep_break["spoilage"] = -spoiled_total * 0.15
	rep_delta += float(event_at().get("effects", {}).get("reputation_delta", 0))
	rep_break["event"] = float(event_at().get("effects", {}).get("reputation_delta", 0))
	_add_rep(rep_delta)
	# i) checkpoint
	var checkpoint_result := {}
	var subsidy := 0
	for cp in checkpoints_cfg:
		if int(cp.get("day", -1)) != current_day:
			continue
		var cid := str(cp["id"])
		var net_now := net_worth()
		var passed := net_now >= int(cp.get("net_target", 0))
		if cp.has("heat_max") and heat_value() >= int(cp["heat_max"]):
			passed = false
		state["checkpoints"][cid] = passed
		if passed:
			subsidy = int(cp.get("subsidy", 0)) + int(_route_effect("checkpoint_bonus", 0))
			if subsidy > 0:
				state["cash"] = cash_value() + subsidy
			_add_rep(float(cp.get("rep_reward", 0)))
			rep_break["checkpoint"] += float(cp.get("rep_reward", 0))
			_add_favor(int(cp.get("favor_reward", 0)))
		checkpoint_result = {"id": cid, "passed": passed, "net_worth": net_now, "target": int(cp.get("net_target", 0)), "subsidy": subsidy}
	# price memory for tomorrow
	var mem := {}
	for id in product_ids:
		var ratio := float(n["prices"][id]) / maxf(1.0, float(products[id]["base_price"]))
		if ratio >= float(memory_cfg.get("high_ratio", 1.5)):
			mem[id] = float(memory_cfg.get("high_mult", 0.85))
		elif ratio <= float(memory_cfg.get("low_ratio", 0.95)):
			mem[id] = float(memory_cfg.get("low_mult", 1.06))
	state["price_memory"] = mem
	# j) net worth / bankruptcy / season end
	var net_after := net_worth()
	if net_after < 0:
		state["negative_streak"] = int(state["negative_streak"]) + 1
	else:
		state["negative_streak"] = 0
	if int(state["negative_streak"]) >= int(loans_cfg.get("bankrupt_streak", 3)):
		state["done"] = true
		state["ending"] = "liquidated"
	elif current_day >= int(state["total_days"]):
		state["done"] = true
		state["ending"] = "completed"
	# totals
	var totals: Dictionary = state["totals"]
	totals["revenue"] = int(totals["revenue"]) + total_revenue
	totals["contract_revenue"] = int(totals["contract_revenue"]) + contract_revenue
	totals["deposits"] = int(totals["deposits"]) + deposits
	totals["procurement"] = int(totals["procurement"]) + int(quote["procurement"])
	totals["smuggle_cost"] = int(totals["smuggle_cost"]) + int(quote["smuggle_cost"])
	totals["upgrades"] = int(totals["upgrades"]) + int(quote["upgrade_cost"])
	totals["restock_cost"] = int(totals["restock_cost"]) + int(quote["restock_cost"])
	totals["rent"] = int(totals["rent"]) + rent
	totals["waste_fees"] = int(totals["waste_fees"]) + waste_fee
	totals["interest"] = int(totals["interest"]) + interest
	totals["fines"] = int(totals["fines"]) + int(inspection["fine"])
	totals["penalties"] = int(totals["penalties"]) + contract_penalty
	totals["loan_payments"] = int(totals["loan_payments"]) + loan_paid
	totals["loan_received"] = int(totals["loan_received"]) + loan_received
	totals["visitor_net"] = int(totals["visitor_net"]) + visitor_delta + int(vip_promise_result.get("revenue", 0))
	totals["subsidies"] = int(totals["subsidies"]) + subsidy
	totals["units_sold"] = int(totals["units_sold"]) + total_sold
	totals["units_spoiled"] = int(totals["units_spoiled"]) + spoiled_total
	totals["stockouts"] = int(totals["stockouts"]) + stockouts
	var stats: Dictionary = state["stats"]
	if fulfillment >= 0.98:
		stats["perfect_service_days"] = int(stats["perfect_service_days"]) + 1
	if spoiled_total == 0:
		stats["no_waste_days"] = int(stats["no_waste_days"]) + 1
	var unlocked := _check_achievements()
	var flavor_key := "sale_success"
	if str(state.get("ending", "")) == "liquidated":
		flavor_key = "liquidated"
	elif inspection["occurred"]:
		flavor_key = "seized"
	elif contract_penalty > 0:
		flavor_key = "contract_breach"
	elif contract_revenue > 0:
		flavor_key = "contract"
	elif spoiled_total > 0:
		flavor_key = "spoilage"
	elif stockouts >= 3:
		flavor_key = "stockout"
	elif smuggled_units > 0:
		flavor_key = "smuggle"
	var rep_export := {}
	for rk in rep_break:
		rep_export[rk] = round(float(rep_break[rk]) * 10.0) / 10.0
	var ledger := {
		"loan_received": loan_received,
		"deposits": deposits,
		"procurement": int(quote["procurement"]),
		"smuggle_cost": int(quote["smuggle_cost"]),
		"upgrade_cost": int(quote["upgrade_cost"]),
		"restock_cost": int(quote["restock_cost"]),
		"visitor_delta": visitor_delta,
		"vip_promise_revenue": int(vip_promise_result.get("revenue", 0)),
		"inspection_fine": int(inspection["fine"]),
		"contract_revenue": contract_revenue,
		"contract_penalty": contract_penalty,
		"sales_revenue": total_revenue,
		"rent": rent,
		"waste_fee": waste_fee,
		"loan_payment": loan_paid,
		"interest": interest,
		"checkpoint_subsidy": subsidy,
	}
	var report := {
		"day": current_day,
		"event": event_at(current_day)["id"],
		"event_name": event_at(current_day)["name"],
		"customer_group": group["id"],
		"customer_name": group["name"],
		"upgrade": upgrade_id,
		"route_card": n["route_card"],
		"loan": n["loan"],
		"favor_use": fu,
		"contracts_accepted": accepted.duplicate(true),
		"contracts_settled": contract_results,
		"visitor": visitor_result,
		"vip_promise": vip_promise_result,
		"inspection": inspection,
		"products": product_results,
		"demand": total_demand,
		"units_sold": total_sold,
		"stockouts": stockouts,
		"spoilage": spoilage,
		"units_spoiled": spoiled_total,
		"revenue": total_revenue,
		"contract_revenue": contract_revenue,
		"contract_penalty": contract_penalty,
		"deposits": deposits,
		"procurement": int(quote["procurement"]),
		"smuggle_cost": int(quote["smuggle_cost"]),
		"smuggled_units": smuggled_units,
		"upgrade_cost": int(quote["upgrade_cost"]),
		"rent": rent,
		"waste_fee": waste_fee,
		"interest": interest,
		"loan_payment": loan_paid,
		"checkpoint": checkpoint_result,
		"heat_after": heat_value(),
		"favor_after": favor_value(),
		"net_worth": net_after,
		"score_estimate": current_score(),
		"ledger": ledger,
		"profit": cash_value() - cash_before,
		"cash_before": cash_before,
		"cash_after": cash_value(),
		"reputation_delta": round((reputation_value() - rep_before) * 10.0) / 10.0,
		"rep_breakdown": rep_export,
		"reputation_after": reputation_value(),
		"fulfillment": round(fulfillment * 1000.0) / 1000.0,
		"achievements": unlocked,
		"flavor": flavor_key,
	}
	(state["history"] as Array).append(report.duplicate(true))
	if not state["done"]:
		state["day"] = current_day + 1
	return {"report": report, "observation": observation(), "terminated": state["done"]}


# ---------------------------------------------------------------- achievements (pure badges)

func _check_achievements() -> Array:
	var unlocked: Array = []
	var done: Array = state["completed_achievements"]
	var totals: Dictionary = state["totals"]
	var stats: Dictionary = state["stats"]
	for a in content.get("achievements", []):
		var id: String = a["id"]
		if id in done:
			continue
		var metric: String = a["metric"]
		var target := int(a["target"])
		var value := 0
		match metric:
			"total_units_sold":
				value = int(totals["units_sold"])
			"total_revenue":
				value = int(totals["revenue"])
			"cash":
				value = cash_value()
			"reputation":
				value = int(reputation_value())
			"upgrade_levels":
				var s := 0
				for k in state["upgrade_levels"]:
					s += int(state["upgrade_levels"][k])
				value = s
			"perfect_service_days":
				value = int(stats["perfect_service_days"])
			"no_waste_days":
				value = int(stats["no_waste_days"])
			"contracts_fulfilled":
				value = int(stats["contracts_fulfilled"])
			"smuggled_units":
				value = int(stats["smuggled_units"])
			"total_units_spoiled":
				if not state["done"]:
					continue
				value = int(totals["units_spoiled"])
			_:
				continue
		var ok := false
		if metric == "total_units_spoiled":
			ok = value == target and state["done"]
		else:
			ok = value >= target
		if ok:
			done.append(id)
			unlocked.append({"id": id, "name": a["name"]})
	return unlocked


# ---------------------------------------------------------------- observation

func observation() -> Dictionary:
	var d := day_value()
	var trend_window := int(wave_cfg.get("trend_window", 5))
	var prods := {}
	var trend := {}
	for id in product_ids:
		var p: Dictionary = products[id]
		var price := int(state["prices"][id])
		var hot_units := 0
		for b in state["inventory"][id]:
			if b.get("hot", false):
				hot_units += int(b["quantity"])
		# perishable batch summary (export only): units per days_left, ascending
		var batch_agg := {}
		for b in state["inventory"][id]:
			var bdl = b.get("days_left", null)
			if bdl == null:
				continue
			batch_agg[int(bdl)] = int(batch_agg.get(int(bdl), 0)) + int(b["quantity"])
		var batch_days := batch_agg.keys()
		batch_days.sort()
		var batch_view: Array = []
		for bd in batch_days:
			batch_view.append({"days_left": int(bd), "units": int(batch_agg[bd])})
		prods[id] = {
			"id": id,
			"name": p["name"],
			"short_name": p["short_name"],
			"description": p["description"],
			"tags": p["tags"],
			"price": price,
			"unit_cost_today": unit_cost(id),
			"shelf_life": shelf_life(id),
			"inventory": {
				"units": inventory_count(id), "hot": hot_units, "expiring": expiring_units(id),
				"batches": batch_view,
				"min_days_left": int(batch_view[0]["days_left"]) if not batch_view.is_empty() else -1,
				"min_days_units": int(batch_view[0]["units"]) if not batch_view.is_empty() else 0,
			},
			"forecast": demand_forecast(id, price),
			"price_memory": float((state["price_memory"] as Dictionary).get(id, 1.0)),
		}
		var series: Array = []
		for td in range(maxi(1, d - trend_window + 1), d + 1):
			series.append(round(market_factor(id, td) * 100.0) / 100.0)
		trend[id] = series
	var ev := event_at()
	var gr := group_at()
	var active: Array = []
	for c in state["active_contracts"]:
		var cc: Dictionary = (c as Dictionary).duplicate(true)
		cc["nights_left"] = int(c["due_day"]) - d
		active.append(cc)
	var next_cp := {}
	for cp in checkpoints_cfg:
		if int(cp.get("day", 0)) >= d and state["checkpoints"].get(str(cp["id"])) == null:
			next_cp = {
				"id": str(cp["id"]), "day": int(cp["day"]),
				"net_target": int(cp.get("net_target", 0)),
				"heat_max": int(cp.get("heat_max", -1)),
				"nights_left": int(cp["day"]) - d,
			}
			break
	var theme: Dictionary = state["finale_theme"]
	var finale_intel := {"stage": "hidden", "tags": []}
	if d >= int(finale_cfg.get("confirm_day", 17)):
		finale_intel = {"stage": "confirmed", "tags": [str(theme["tag"])]}
	elif d >= int(finale_cfg.get("reveal_tag_day", 15)):
		finale_intel = {"stage": "tag", "tags": [str(theme["tag"])]}
	elif d >= int(finale_cfg.get("reveal_domain_day", 12)):
		finale_intel = {"stage": "domain", "tags": [str(theme["tag"]), str(theme["decoy"])]}
	var loans_view: Array = []
	for loan in state["loans"]:
		loans_view.append({"payment": int(loan["payment"]), "remaining": int(loan["remaining"])})
	return {
		"day": d,
		"total_days": state["total_days"],
		"cash": cash_value(),
		"reputation": reputation_value(),
		"capacity": capacity(),
		"inventory_used": inventory_count(),
		"done": state["done"],
		"market": {
			"event": {"id": ev["id"], "name": ev["name"], "headline": ev.get("headline", ""), "description": ev.get("description", "")},
			"customer_group": {"id": gr["id"], "name": gr["name"], "leader": gr.get("leader", ""), "preferred_tags": gr.get("preferred_tags", [])},
		},
		"products": prods,
		"market_trend": trend,
		"upgrade_levels": state["upgrade_levels"].duplicate(),
		"rumors": rumors_for(),
		"heat": heat_value(),
		"heat_cap": _heat_cap(),
		"total_smuggled": int(state["total_smuggled"]),
		"inspection_prob": inspection_prob(),
		"smuggle": smuggle_offers(),
		"contracts": {"board": contracts_board(), "active": active},
		"visitor": visitor_for(),
		"route_offer": route_offer_for(),
		"route_cards": (state["route_cards"] as Dictionary).duplicate(),
		"favor": favor_value(),
		"debt": {
			"loans": loans_view,
			"outstanding": outstanding_debt(),
			"negative_streak": int(state["negative_streak"]),
			"loan_available": loan_available(),
		},
		"checkpoint": next_cp,
		"finale_intel": finale_intel,
		"vip_promise": (state["vip_promise"] as Dictionary).duplicate(true) if state["vip_promise"] != null else null,
		"rent_tonight": rent_for(),
		"net_worth": net_worth(),
		"score_estimate": current_score(),
	}


# ---------------------------------------------------------------- terminal

func terminal_summary() -> Dictionary:
	var stats: Dictionary = state["stats"]
	var score := current_score()
	var rank := "SPACE DEBRIS"
	for r in score_cfg.get("ranks", []):
		if score >= int(r.get("min", 0)):
			rank = str(r.get("id", rank))
			break
	var ult_bonus := 0
	if stats.get("ultimate_fulfilled", false):
		ult_bonus = int((contracts_cfg.get("ultimate", {}) as Dictionary).get("score_bonus", 150))
	var breakdown := {
		"cash": cash_value(),
		"inventory_liquidation": liquidation_value(),
		"debt_penalty": -int(round(outstanding_debt() * float(score_cfg.get("debt_mult", 1.5)))),
		"reputation_bonus": int(round(reputation_value() * float(score_cfg.get("rep_mult", 5)))),
		"fulfill_bonus": int(stats["contracts_fulfilled"]) * int(score_cfg.get("fulfill_mult", 10)),
		"breach_penalty": -int(stats["contracts_breached"]) * int(score_cfg.get("breach_mult", 20)),
		"ultimate_bonus": ult_bonus,
	}
	return {
		"rank": rank,
		"score": score,
		"score_breakdown": breakdown,
		"cash": cash_value(),
		"reputation": reputation_value(),
		"totals": state["totals"].duplicate(),
		"upgrade_levels": state["upgrade_levels"].duplicate(),
		"contracts_fulfilled": int(stats["contracts_fulfilled"]),
		"contracts_breached": int(stats["contracts_breached"]),
		"seizures": int(stats["seizures"]),
		"units_seized": int(stats["units_seized"]),
		"smuggled_units": int(stats["smuggled_units"]),
		"loans_taken": int(stats["loans_taken"]),
		"favor": favor_value(),
		"route_cards": (state["route_cards"] as Dictionary).duplicate(),
		"achievements_completed": (state["completed_achievements"] as Array).size(),
		"achievements_total": (content.get("achievements", []) as Array).size(),
		"flavor": "game_over",
		"ending": state.get("ending", null),
	}
