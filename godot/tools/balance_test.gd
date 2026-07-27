extends SceneTree
## Headless balance harness for gameplay v3: 3 deterministic bot strategies
## x 200 seeds, full 18-night seasons. Reports a compact JSON summary.
## This tool only measures — no tuning happens here.

const SEEDS := 200
const STRATEGIES := ["conservative", "balanced", "greedy"]


func base_action(g: MarketGame) -> Dictionary:
	var a := {
		"orders": {}, "prices": {}, "upgrade": null,
		"contracts_accept": [], "smuggle": {}, "visitor": false,
		"route_card": null, "favor_use": null, "loan": false,
	}
	for id in g.product_ids:
		a["orders"][id] = 0
		a["prices"][id] = int(g.products[id]["base_price"])
	return a


func check_ledger(r: Dictionary) -> bool:
	var l: Dictionary = r["ledger"]
	var expect := int(r["cash_before"]) + int(l["loan_received"]) + int(l["deposits"]) \
		- int(l["procurement"]) - int(l["smuggle_cost"]) - int(l["upgrade_cost"]) - int(l["restock_cost"]) \
		+ int(l["visitor_delta"]) + int(l["vip_promise_revenue"]) - int(l["inspection_fine"]) \
		+ int(l["contract_revenue"]) - int(l["contract_penalty"]) + int(l["sales_revenue"]) \
		- int(l["rent"]) - int(l["waste_fee"]) - int(l["loan_payment"]) - int(l["interest"]) \
		+ int(l["checkpoint_subsidy"])
	return expect == int(r["cash_after"])


func bot_action(g: MarketGame, strat: String) -> Dictionary:
	var obs: Dictionary = g.observation()
	var d := int(obs["day"])
	var td := int(obs["total_days"])
	var a := base_action(g)
	var cap_room := maxi(0, maxi(int(obs["capacity"]), int(obs["inventory_used"])) - int(obs["inventory_used"]))
	var budget := int(obs["cash"]) - 10
	# route cards
	var ro: Array = obs["route_offer"]
	if ro.size() > 0:
		var want := {}
		match strat:
			"conservative":
				want = {"official_license": 1, "cold_pact": 1, "vip_list": 1}
			"balanced":
				want = {"official_license": 1, "dock_broker": 1, "customs_insider": 1}
			"greedy":
				want = {"gray_route": 1, "dock_broker": 1, "customs_insider": 1}
		for opt in ro:
			if want.has(str(opt["id"])):
				a["route_card"] = str(opt["id"])
	# loan
	if bool(obs["debt"]["loan_available"]):
		a["loan"] = true
		budget += 150
	# prices
	var price_mult := 1.0
	if strat == "balanced":
		price_mult = 1.1
	elif strat == "greedy":
		price_mult = 1.25
	for id in g.product_ids:
		a["prices"][id] = maxi(1, int(round(int(g.products[id]["base_price"]) * price_mult)))
	# contracts
	var board: Array = obs["contracts"]["board"]
	var accepted_due_today := {}
	for c in board:
		var kind := str(c["kind"])
		var pid := str(c["product_id"])
		var have := int(obs["products"][pid]["inventory"]["units"])
		var take := false
		match strat:
			"conservative":
				take = kind == "spot" and int(c["qty"]) <= 8
			"balanced":
				take = (kind == "spot" and int(c["qty"]) <= 10) or (kind == "bulk" and int(c["qty"]) <= 14)
			"greedy":
				take = true
		if take and d >= td and int(c["due_day"]) == td and strat != "greedy" and have < int(c["qty"]):
			take = false
		if take and kind == "spot" and d >= 15 and d < td:
			for ac in obs["contracts"]["active"]:
				if int(ac["due_day"]) >= td and str(ac["product_id"]) == pid:
					take = false
		if take:
			(a["contracts_accept"] as Array).append(str(c["id"]))
			budget += int(c["deposit"])
			if int(c["due_day"]) == d:
				accepted_due_today[pid] = int(accepted_due_today.get(pid, 0)) + int(c["qty"])
	# pre-buy for future contracts FIRST (the finale wholesale closes, so night-18 dues need stock early)
	if d < td:
		for c in obs["contracts"]["active"]:
			var due := int(c["due_day"])
			if due <= d:
				continue
			var lead := due - d
			if not (strat == "greedy" or lead <= 2 or due >= td):
				continue
			var pid3 := str(c["product_id"])
			var p3: Dictionary = obs["products"][pid3]
			var life3 = p3["shelf_life"]
			if life3 != null and int(life3) < lead + 1:
				continue
			var have3 := int(p3["inventory"]["units"]) + int(a["orders"][pid3])
			var buffer := 6 if due >= td else 0
			var need3 := maxi(0, int(c["qty"]) + buffer - have3)
			var uc3 := int(p3["unit_cost_today"])
			if due >= td and d >= due - 3:
				a["prices"][pid3] = int(g.price_bounds(pid3).y)
			need3 = mini(need3, cap_room)
			need3 = mini(need3, maxi(0, int(floor(budget / float(uc3)))))
			if need3 > 0:
				a["orders"][pid3] = int(a["orders"][pid3]) + need3
				cap_room -= need3
				budget -= need3 * uc3
	# cover contracts due today
	var due_need := {}
	for c in obs["contracts"]["active"]:
		if int(c["due_day"]) == d:
			due_need[str(c["product_id"])] = int(due_need.get(str(c["product_id"]), 0)) + int(c["qty"])
	for pid in accepted_due_today:
		due_need[pid] = int(due_need.get(pid, 0)) + int(accepted_due_today[pid])
	if d < td:
		for pid in due_need:
			var have2 := int(obs["products"][pid]["inventory"]["units"])
			var need := maxi(0, int(due_need[pid]) - have2)
			need = mini(need, cap_room)
			var uc := int(obs["products"][pid]["unit_cost_today"])
			need = mini(need, maxi(0, int(floor(budget / float(uc)))))
			if need > 0:
				a["orders"][pid] = int(a["orders"][pid]) + need
				cap_room -= need
				budget -= need * uc
	# smuggle
	if d < td:
		var offers: Array = obs["smuggle"]
		if strat == "balanced" and int(obs["heat"]) < 25 and offers.size() > 0:
			var o: Dictionary = offers[0]
			var q := mini(4, int(o["limit"]))
			q = mini(q, cap_room)
			q = mini(q, maxi(0, int(floor(budget / float(int(o["unit_price"]))))))
			if q > 0:
				a["smuggle"][str(o["product_id"])] = q
				cap_room -= q
				budget -= q * int(o["unit_price"])
		elif strat == "greedy":
			for o in offers:
				var q2 := mini(int(o["limit"]), cap_room)
				q2 = mini(q2, maxi(0, int(floor(budget / float(int(o["unit_price"]))))))
				if q2 > 0:
					a["smuggle"][str(o["product_id"])] = q2
					cap_room -= q2
					budget -= q2 * int(o["unit_price"])
	# walk-in stocking / finale hoard
	if d < td:
		var hoard := d >= 15
		var theme_tags: Array = (obs["finale_intel"] as Dictionary).get("tags", [])
		for id in g.product_ids:
			var p: Dictionary = obs["products"][id]
			var uc2 := int(p["unit_cost_today"])
			var target := 0
			if hoard:
				var life = p["shelf_life"]
				var durable: bool = life == null or int(life) > td - d
				var themed := false
				for t in p["tags"]:
					if t in theme_tags:
						themed = true
				if themed and durable:
					target = 14 if strat == "greedy" else 8
				elif durable and strat == "greedy" and d >= 16:
					target = 5
				elif durable and d >= 16:
					target = 3
			else:
				var fc: Dictionary = p["forecast"]
				target = int(round((int(fc["low"]) + int(fc["high"])) * 0.5))
				if strat == "conservative":
					target = int(round(target * 0.9))
				if uc2 > int(g.products[id]["base_price"]):
					target = 0
			var order := maxi(0, target - int(p["inventory"]["units"]) - int(a["orders"][id]))
			order = mini(order, cap_room)
			order = mini(order, maxi(0, int(floor(budget / float(uc2)))))
			if order > 0:
				a["orders"][id] = int(a["orders"][id]) + order
				cap_room -= order
				budget -= order * uc2
	# upgrades
	var lv: Dictionary = obs["upgrade_levels"]
	var pick := ""
	match strat:
		"conservative":
			if int(lv["cold_rack"]) < 2 and budget > 90:
				pick = "cold_rack"
			elif int(lv["freshness_seal"]) < 1 and budget > 120:
				pick = "freshness_seal"
		"balanced":
			if int(lv["bargain_terminal"]) < 2 and budget > 90:
				pick = "bargain_terminal"
			elif int(lv["cold_rack"]) < 2 and budget > 110:
				pick = "cold_rack"
			elif int(lv["intel_antenna"]) < 1 and budget > 130:
				pick = "intel_antenna"
		"greedy":
			if int(lv["cold_rack"]) < 2 and budget > 80:
				pick = "cold_rack"
			elif int(lv["bargain_terminal"]) < 2 and budget > 100:
				pick = "bargain_terminal"
	if pick != "" and budget >= g.upgrade_cost(pick):
		a["upgrade"] = pick
	# visitor
	var vis: Dictionary = obs["visitor"]
	if not vis.is_empty() and str(vis["kind"]) == "sweeper" and d == td and due_need.size() > 0:
		a["visitor"] = false
	elif not vis.is_empty():
		var kind := str(vis["kind"])
		match strat:
			"conservative":
				a["visitor"] = kind in ["sweeper", "cameo"]
			"balanced":
				a["visitor"] = true
			"greedy":
				a["visitor"] = kind != "broker"
	# favor
	if int(obs["favor"]) > 0 and d >= 13 and d < td:
		a["favor_use"] = {"type": "rent_free"}
	return a


func percentile(sorted_vals: Array, p: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx := int(floor(p * (sorted_vals.size() - 1)))
	return float(sorted_vals[idx])


func _init() -> void:
	print("BALANCE_START seeds=", SEEDS)
	var t0 := Time.get_ticks_msec()
	var summary := {}
	var means := {}
	var surv_means := {}
	for strat in STRATEGIES:
		var scores: Array = []
		var bankrupts := 0
		var fulfilled := 0
		var breached := 0
		var seizures := 0
		var ledger_violations := 0
		var action_fails := 0
		var nights_total := 0
		var ultimates := 0
		var surv_scores: Array = []
		var profit_sum := {}
		var profit_cnt := {}
		var insp_nights := 0
		var insp_zero_nights := 0
		var insp_cap_nights := 0
		var runs_all_zero_insp := 0
		var runs_all_cap_insp := 0
		for seed in range(1, SEEDS + 1):
			var g := MarketGame.new(seed)
			var guard := 0
			var run_had_insp := false
			var run_cap_nights := 0
			while not g.state.get("done", false) and guard < 20:
				var st = g.try_step(bot_action(g, strat))
				if st == null:
					action_fails += 1
					st = g.try_step(base_action(g))
				if st == null:
					print("STEP_DEAD strat=", strat, " seed=", seed, " day=", g.state["day"], " err=", g.last_error)
					break
				if not check_ledger(st["report"]):
					ledger_violations += 1
				var rp: Dictionary = st["report"]
				var dd := int(rp["day"])
				profit_sum[dd] = float(profit_sum.get(dd, 0.0)) + float(rp["profit"])
				profit_cnt[dd] = int(profit_cnt.get(dd, 0)) + 1
				var ip := float((rp["inspection"] as Dictionary)["prob"])
				insp_nights += 1
				if ip <= 0.01:
					insp_zero_nights += 1
				else:
					run_had_insp = true
				if ip >= 79.9:
					insp_cap_nights += 1
					run_cap_nights += 1
				guard += 1
			nights_total += guard
			if not run_had_insp:
				runs_all_zero_insp += 1
			if guard > 0 and run_cap_nights >= guard:
				runs_all_cap_insp += 1
			var ts: Dictionary = g.terminal_summary()
			scores.append(int(ts["score"]))
			if str(ts.get("ending", "")) == "liquidated":
				bankrupts += 1
			else:
				surv_scores.append(int(ts["score"]))
			fulfilled += int(ts["contracts_fulfilled"])
			breached += int(ts["contracts_breached"])
			seizures += int(ts["seizures"])
			if bool(g.state["stats"].get("ultimate_fulfilled", false)):
				ultimates += 1
		scores.sort()
		var mean := 0.0
		for s in scores:
			mean += float(s)
		mean /= float(scores.size())
		means[strat] = mean
		var surv_mean := 0.0
		for s in surv_scores:
			surv_mean += float(s)
		surv_mean /= float(maxi(1, surv_scores.size()))
		surv_means[strat] = surv_mean
		var night_profit: Array = []
		for dd in range(1, 19):
			var cnt := int(profit_cnt.get(dd, 0))
			night_profit.append(snappedf(float(profit_sum.get(dd, 0.0)) / float(maxi(1, cnt)), 0.1))
		var finale_avg := float(night_profit[17])
		var best_other := -999999.0
		for i in range(0, 17):
			best_other = maxf(best_other, float(night_profit[i]))
		var denom := maxi(1, fulfilled + breached)
		summary[strat] = {
			"score_mean_surv": snappedf(surv_mean, 0.1),
			"finale_profit_avg": snappedf(finale_avg, 0.1),
			"best_other_night_avg": snappedf(best_other, 0.1),
			"finale_is_best_night": finale_avg > best_other,
			"night_profit": night_profit,
			"insp_zero_night_rate": snappedf(float(insp_zero_nights) / float(maxi(1, insp_nights)), 0.001),
			"insp_cap_night_rate": snappedf(float(insp_cap_nights) / float(maxi(1, insp_nights)), 0.001),
			"runs_all_zero_inspection": runs_all_zero_insp,
			"runs_all_cap_inspection": runs_all_cap_insp,
			"runs": SEEDS,
			"bankrupt_rate": snappedf(float(bankrupts) / float(SEEDS), 0.001),
			"score_mean": snappedf(mean, 0.1),
			"score_p50": percentile(scores, 0.5),
			"score_p90": percentile(scores, 0.9),
			"score_min": float(scores[0]),
			"score_max": float(scores[-1]),
			"contract_fulfill_rate": snappedf(float(fulfilled) / float(denom), 0.001),
			"contracts_fulfilled_avg": snappedf(float(fulfilled) / float(SEEDS), 0.01),
			"contracts_breached_avg": snappedf(float(breached) / float(SEEDS), 0.01),
			"seizures_avg": snappedf(float(seizures) / float(SEEDS), 0.01),
			"ultimate_fulfilled": ultimates,
			"avg_nights": snappedf(float(nights_total) / float(SEEDS), 0.01),
			"ledger_violations": ledger_violations,
			"action_fallbacks": action_fails,
		}
		print("STRAT_DONE ", strat, " mean=", snappedf(mean, 0.1), " bankrupt=", summary[strat]["bankrupt_rate"])
	var out := {
		"seeds_per_strategy": SEEDS,
		"strategies": summary,
		"balanced_minus_conservative_mean": snappedf(float(means["balanced"]) - float(means["conservative"]), 0.1),
		"degenerate_conservative_dominates": float(means["conservative"]) >= float(means["balanced"]),
		"greedy_surv_mean_is_top": float(surv_means["greedy"]) > float(surv_means["balanced"]) \
			and float(surv_means["greedy"]) > float(surv_means["conservative"]),
		"elapsed_ms": Time.get_ticks_msec() - t0,
	}
	print("BALANCE_JSON ", JSON.stringify(out))
	quit(0)
