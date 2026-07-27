extends SceneTree
## Headless logic smoke for gameplay v3 "Undertow Night Market".
## Covers: determinism (same seed twice), nightly cash-flow identity,
## contract lifecycle, hot-only seizure, closed market on night 18,
## checkpoint nights, visitor branches, favor bounds, loans,
## bankruptcy ("liquidated"), full-season autoplay, loc pack sections.

var ok := true


func expect(cond: bool, label: String) -> void:
	if not cond:
		ok = false
		print("FAIL ", label)


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
	var expect_cash := int(r["cash_before"]) + int(l["loan_received"]) + int(l["deposits"]) \
		- int(l["procurement"]) - int(l["smuggle_cost"]) - int(l["upgrade_cost"]) - int(l["restock_cost"]) \
		+ int(l["visitor_delta"]) + int(l["vip_promise_revenue"]) - int(l["inspection_fine"]) \
		+ int(l["contract_revenue"]) - int(l["contract_penalty"]) + int(l["sales_revenue"]) \
		- int(l["rent"]) - int(l["waste_fee"]) - int(l["loan_payment"]) - int(l["interest"]) \
		+ int(l["checkpoint_subsidy"])
	if expect_cash != int(r["cash_after"]):
		print("LEDGER_MISMATCH day=", r["day"], " expect=", expect_cash, " got=", r["cash_after"], " ledger=", JSON.stringify(l))
		return false
	return true


func scripted_action(g: MarketGame) -> Dictionary:
	var obs: Dictionary = g.observation()
	var a := base_action(g)
	var d := int(obs["day"])
	if d < int(obs["total_days"]):
		for id in ["ion_soda", "star_donut", "meteor_popcorn"]:
			a["orders"][id] = 2
	for c in obs["contracts"]["board"]:
		if str(c["kind"]) == "spot" and int(c["qty"]) <= 6:
			a["contracts_accept"] = [str(c["id"])]
			var pid := str(c["product_id"])
			if d < int(obs["total_days"]):
				a["orders"][pid] = int(a["orders"].get(pid, 0)) + int(c["qty"])
			break
	if d % 3 == 2 and (obs["smuggle"] as Array).size() > 0:
		var o: Dictionary = obs["smuggle"][0]
		a["smuggle"][str(o["product_id"])] = mini(2, int(o["limit"]))
	a["visitor"] = true
	var ro: Array = obs["route_offer"]
	if ro.size() > 0:
		a["route_card"] = str(ro[0]["id"])
	if bool(obs["debt"]["loan_available"]):
		a["loan"] = true
	return a


func run_season(seed: int) -> Array:
	var g := MarketGame.new(seed)
	var reports: Array = []
	var guard := 0
	while not g.state.get("done", false) and guard < 25:
		var a := scripted_action(g)
		var st = g.try_step(a)
		if st == null:
			st = g.try_step(base_action(g))
		if st == null:
			print("SEASON_STEP_FAIL seed=", seed, " day=", g.state["day"], " err=", g.last_error)
			ok = false
			break
		var r: Dictionary = st["report"]
		expect(check_ledger(r), "ledger seed=%d day=%d" % [seed, int(r["day"])])
		reports.append(JSON.stringify(r))
		guard += 1
	return reports


func _init() -> void:
	print("SMOKE_START v3")

	# --- determinism: same seed, two full scripted seasons, identical reports ---
	var run1 := run_season(42)
	var run2 := run_season(42)
	expect(run1.size() == run2.size() and run1.size() > 0, "determinism run length")
	for i in run1.size():
		if str(run1[i]) != str(run2[i]):
			expect(false, "determinism night %d" % (i + 1))
			break
	print("DET_NIGHTS ", run1.size())

	# --- full season autoplay finishes: done=true within 18 nights ---
	var gfull := MarketGame.new(11)
	var nights := 0
	while not gfull.state.get("done", false) and nights < 25:
		var st = gfull.try_step(scripted_action(gfull))
		if st == null:
			st = gfull.try_step(base_action(gfull))
		expect(st != null, "autoplay step day=%d err=%s" % [int(gfull.state["day"]), gfull.last_error])
		if st == null:
			break
		expect(check_ledger(st["report"]), "autoplay ledger day=%d" % int(st["report"]["day"]))
		nights += 1
	expect(bool(gfull.state.get("done", false)), "autoplay done")
	expect(nights <= 18, "autoplay <= 18 nights")
	print("AUTOPLAY nights=", nights, " ending=", gfull.state.get("ending"), " score=", gfull.current_score())

	# --- observation & quote interface fields (spec §7) ---
	var gi := MarketGame.new(7)
	var obs: Dictionary = gi.observation()
	for key in ["rumors", "heat", "inspection_prob", "contracts", "visitor", "route_offer",
			"favor", "debt", "checkpoint", "finale_intel", "score_estimate", "market_trend", "smuggle", "net_worth"]:
		expect(obs.has(key), "observation field %s" % key)
	expect((obs["rumors"]["tomorrow"] as Array).size() == 2, "rumor two candidates")
	expect((obs["route_offer"] as Array).size() == 2, "route offer night 1")
	var q = gi.try_quote_action(base_action(gi))
	expect(q != null, "quote base action")
	if q != null:
		for key in ["best_case", "worst_case", "inspection_prob", "contract_exposure"]:
			expect((q as Dictionary).has(key), "quote field %s" % key)

	# --- spot contract: fulfilled ---
	var gs := MarketGame.new(5)
	var board: Array = gs.contracts_board()
	expect(board.size() >= 2, "board size >= 2")
	var spot: Dictionary = {}
	for c in board:
		if str(c["kind"]) == "spot":
			spot = c
			break
	expect(not spot.is_empty(), "spot card on night 1")
	if not spot.is_empty():
		var a := base_action(gs)
		a["contracts_accept"] = [str(spot["id"])]
		a["orders"][str(spot["product_id"])] = int(spot["qty"])
		var st = gs.try_step(a)
		expect(st != null, "spot step: %s" % gs.last_error)
		if st != null:
			var r: Dictionary = st["report"]
			expect(check_ledger(r), "spot ledger")
			var settled: Array = r["contracts_settled"]
			expect(settled.size() == 1 and bool(settled[0]["fulfilled"]), "spot fulfilled")
			expect(int(settled[0]["revenue"]) == int(spot["total"]), "spot revenue = total (deposit 0)")

	# --- spot contract: breach (no stock) ---
	var gb := MarketGame.new(3)
	var board_b: Array = gb.contracts_board()
	var spot_b: Dictionary = {}
	for c in board_b:
		if str(c["kind"]) == "spot":
			spot_b = c
			break
	if not spot_b.is_empty():
		var ab := base_action(gb)
		ab["contracts_accept"] = [str(spot_b["id"])]
		var rep_before := gb.reputation_value()
		var stb = gb.try_step(ab)
		expect(stb != null, "breach step")
		if stb != null:
			var rb: Dictionary = stb["report"]
			expect(check_ledger(rb), "breach ledger")
			var sb: Array = rb["contracts_settled"]
			expect(sb.size() == 1 and not bool(sb[0]["fulfilled"]), "spot breached")
			expect(int(sb[0]["penalty"]) == int(spot_b["penalty"]), "breach penalty amount")
			expect(gb.reputation_value() < rep_before, "breach rep down")

	# --- bulk contract lifecycle: deposit on accept, payout on due night ---
	var bulk_done := false
	for s in range(1, 80):
		var gk := MarketGame.new(s)
		gk.state["day"] = 6
		gk.state["reputation"] = 70.0
		gk.state["cash"] = 600
		var bulk: Dictionary = {}
		for c in gk.contracts_board():
			if str(c["kind"]) == "bulk":
				bulk = c
				break
		if bulk.is_empty():
			continue
		var ak := base_action(gk)
		ak["contracts_accept"] = [str(bulk["id"])]
		var cash0 := gk.cash_value()
		var stk = gk.try_step(ak)
		expect(stk != null, "bulk accept step: %s" % gk.last_error)
		if stk == null:
			break
		expect(int(stk["report"]["deposits"]) == int(bulk["deposit"]), "bulk deposit received")
		expect((gk.state["active_contracts"] as Array).size() == 1, "bulk active")
		while int(gk.state["day"]) < int(bulk["due_day"]):
			var mid := base_action(gk)
			if int(gk.state["day"]) == int(bulk["due_day"]):
				break
			if gk.try_step(mid) == null:
				expect(false, "bulk mid step: %s" % gk.last_error)
				break
		var due_a := base_action(gk)
		var pid := str(bulk["product_id"])
		var need := int(bulk["qty"]) - gk.inventory_count(pid)
		if need > 0:
			due_a["orders"][pid] = need
		var favor0 := gk.favor_value()
		var std = gk.try_step(due_a)
		expect(std != null, "bulk due step: %s" % gk.last_error)
		if std != null:
			var found := false
			for e in std["report"]["contracts_settled"]:
				if str(e["id"]) == str(bulk["id"]):
					found = true
					expect(bool(e["fulfilled"]), "bulk fulfilled")
					expect(int(e["revenue"]) == int(bulk["total"]) - int(bulk["deposit"]), "bulk pays remainder")
			expect(found, "bulk settled on due night")
			expect(gk.favor_value() == mini(3, favor0 + 1), "bulk favor +1")
			expect(check_ledger(std["report"]), "bulk ledger")
		bulk_done = true
		break
	expect(bulk_done, "bulk lifecycle exercised")

	# --- ultimate card exists on night 15 ---
	var gu := MarketGame.new(9)
	gu.state["day"] = 15
	var has_ult := false
	for c in gu.contracts_board():
		if str(c["kind"]) == "ultimate":
			has_ult = true
			expect(int(c["due_day"]) == 18, "ultimate due night 18")
	expect(has_ult, "ultimate on night 15")

	# --- inspection seizes only hot batches ---
	var seize_seen := false
	for s in range(1, 60):
		var gh := MarketGame.new(s)
		gh.state["heat"] = 90
		var offers: Array = gh.smuggle_offers()
		if offers.is_empty():
			continue
		var o: Dictionary = offers[0]
		if str(o["product_id"]) == "meteor_popcorn":
			continue
		var units := int(o["limit"])
		var ah := base_action(gh)
		ah["smuggle"][str(o["product_id"])] = units
		ah["orders"]["meteor_popcorn"] = 3
		var prob := gh.inspection_prob(units * 2, units)
		var roll := gh.stable_rng("inspect", 1).randf() * 100.0
		var will_hit := roll < prob
		var sth = gh.try_step(ah)
		if sth == null:
			continue
		var rh: Dictionary = sth["report"]
		expect(check_ledger(rh), "inspection ledger seed=%d" % s)
		expect(bool(rh["inspection"]["occurred"]) == will_hit, "inspection roll matches")
		if will_hit:
			expect(int(rh["inspection"]["seized_units"]) == units, "seized only hot units")
			expect(int(rh["inspection"]["fine"]) > 0, "seizure fine")
			var pr: Dictionary = rh["products"]["meteor_popcorn"]
			expect(int(pr["sold"]) + int(pr["remaining"]) == 3, "clean batch untouched by seizure")
			expect(gh.hot_count() == 0, "no hot stock left")
			seize_seen = true
			break
	expect(seize_seen, "seizure branch exercised")

	# --- night 18: wholesale closed ---
	var g18 := MarketGame.new(7)
	g18.state["day"] = 18
	expect((g18.smuggle_offers() as Array).is_empty(), "no smuggle offers night 18")
	var a18 := base_action(g18)
	a18["orders"]["ion_soda"] = 1
	expect(g18.try_step(a18) == null, "orders rejected night 18")
	var st18 = g18.try_step(base_action(g18))
	expect(st18 != null, "night 18 sell-only step")
	if st18 != null:
		expect(bool(st18["terminated"]), "season ends night 18")
		expect(str(g18.state["ending"]) == "completed", "ending completed")
		expect(check_ledger(st18["report"]), "night 18 ledger")

	# --- checkpoint nights judged (from scripted season reports) ---
	var gcp := MarketGame.new(42)
	var cp1_seen := false
	var cp2_seen := false
	while not gcp.state.get("done", false):
		var stc = gcp.try_step(scripted_action(gcp))
		if stc == null:
			stc = gcp.try_step(base_action(gcp))
		if stc == null:
			break
		var rc: Dictionary = stc["report"]
		if not (rc["checkpoint"] as Dictionary).is_empty():
			var cp: Dictionary = rc["checkpoint"]
			if str(cp["id"]) == "cp1":
				cp1_seen = true
				expect(int(rc["day"]) == 6, "cp1 on night 6")
				var pass_expect: bool = int(cp["net_worth"]) >= int(cp["target"])
				expect(bool(cp["passed"]) == pass_expect, "cp1 verdict matches net worth")
			elif str(cp["id"]) == "cp2":
				cp2_seen = true
				expect(int(rc["day"]) == 12, "cp2 on night 12")
	expect(cp1_seen and cp2_seen, "both checkpoints judged")

	# --- visitor: sweeper (expiring stock) ---
	var gv := MarketGame.new(13)
	gv.state["inventory"]["star_donut"] = [{"quantity": 5, "days_left": 1, "hot": false, "unit_cost": 4}]
	var vis: Dictionary = gv.visitor_for()
	expect(str(vis.get("kind", "")) == "sweeper", "sweeper triggers on expiring stock")
	var av := base_action(gv)
	av["visitor"] = true
	var stv = gv.try_step(av)
	expect(stv != null, "sweeper step")
	if stv != null:
		var rv: Dictionary = stv["report"]
		expect(check_ledger(rv), "sweeper ledger")
		expect(int(rv["visitor"]["units"]) == 5, "sweeper takes all expiring")
		expect(int(rv["visitor"]["payout"]) == 5 * int(ceil(8 * 0.55)), "sweeper pays 55%")
		expect(int(rv["products"]["star_donut"]["sold"]) == 0, "swept goods skip walk-in sales")

	# --- visitor: informant (high heat) ---
	var gvi := MarketGame.new(13)
	gvi.state["heat"] = 45
	var vi: Dictionary = gvi.visitor_for()
	expect(str(vi.get("kind", "")) == "informant", "informant triggers on heat>=40")
	var avi := base_action(gvi)
	avi["visitor"] = true
	var stvi = gvi.try_step(avi)
	if stvi != null:
		expect(check_ledger(stvi["report"]), "informant ledger")
		expect(int(stvi["report"]["visitor"]["cost"]) == int(ceil(12.0 + 45 * 0.5)), "informant cost formula")
	else:
		expect(false, "informant step")

	# --- visitor: broker makes tomorrow's rumor certain ---
	var broker_seen := false
	for s in range(1, 120):
		var gbk := MarketGame.new(s)
		var vb: Dictionary = gbk.visitor_for()
		if str(vb.get("kind", "")) != "broker":
			continue
		var abk := base_action(gbk)
		abk["visitor"] = true
		var stbk = gbk.try_step(abk)
		if stbk == null:
			continue
		expect(check_ledger(stbk["report"]), "broker ledger")
		var ru: Dictionary = gbk.rumors_for()
		expect(bool(ru["certain"]), "broker rumor certain")
		expect(int(ru["tomorrow"][0]["prob"]) == 100, "certain rumor 100%")
		broker_seen = true
		break
	expect(broker_seen, "broker branch exercised")

	# --- visitor: vip buy + promise kept next night (+favor) ---
	var vip_seen := false
	for s in range(1, 120):
		var gvp := MarketGame.new(s)
		gvp.state["reputation"] = 70.0
		gvp.state["inventory"]["orbit_plush"] = [{"quantity": 12, "days_left": null, "hot": false, "unit_cost": 12}]
		var vv: Dictionary = gvp.visitor_for()
		if str(vv.get("kind", "")) != "vip":
			continue
		var avp := base_action(gvp)
		avp["visitor"] = true
		var stvp = gvp.try_step(avp)
		if stvp == null:
			continue
		expect(check_ledger(stvp["report"]), "vip ledger")
		expect(int(stvp["report"]["visitor"]["revenue"]) == int(vv["qty"]) * int(vv["unit_price"]), "vip pays 2x")
		expect(gvp.state["vip_promise"] != null, "vip promise recorded")
		var favor0 := gvp.favor_value()
		var stp2 = gvp.try_step(base_action(gvp))
		expect(stp2 != null, "vip promise night")
		if stp2 != null:
			expect(check_ledger(stp2["report"]), "vip promise ledger")
			var vres: Dictionary = stp2["report"]["vip_promise"]
			expect(bool(vres.get("kept", false)), "vip promise kept")
			expect(gvp.favor_value() == mini(3, favor0 + 1), "vip promise favor +1")
		vip_seen = true
		break
	expect(vip_seen, "vip branch exercised")

	# --- favor boundaries ---
	var gf := MarketGame.new(7)
	var af := base_action(gf)
	af["favor_use"] = {"type": "rent_free"}
	expect(gf.try_step(af) == null, "favor_use rejected at 0 favor")
	gf.state["favor"] = 1
	var stf = gf.try_step(af)
	expect(stf != null, "favor rent_free step")
	if stf != null:
		expect(int(stf["report"]["rent"]) == 0, "rent waived")
		expect(gf.favor_value() == 0, "favor consumed")
		expect(check_ledger(stf["report"]), "favor ledger")
	gf._add_favor(9)
	expect(gf.favor_value() == 3, "favor capped at 3")

	# --- loan: receive, then nightly payment ---
	var gl := MarketGame.new(7)
	gl.state["cash"] = 20
	var al := base_action(gl)
	al["loan"] = true
	var stl = gl.try_step(al)
	expect(stl != null, "loan step")
	if stl != null:
		expect(int(stl["report"]["ledger"]["loan_received"]) == 150, "loan received 150")
		expect(int(stl["report"]["loan_payment"]) == 25, "loan payment starts same night")
		expect(check_ledger(stl["report"]), "loan ledger")
		var stl2 = gl.try_step(base_action(gl))
		if stl2 != null:
			expect(int(stl2["report"]["loan_payment"]) == 25, "loan payment night 2")
			expect(check_ledger(stl2["report"]), "loan ledger 2")
	expect(gl.outstanding_debt() > 0, "outstanding debt tracked")

	# --- bankruptcy: 3 negative-net nights -> liquidated ---
	var gx := MarketGame.new(7)
	gx.state["cash"] = -500
	for i in 3:
		var stx = gx.try_step(base_action(gx))
		expect(stx != null, "bankrupt step %d" % i)
		if stx == null:
			break
		expect(check_ledger(stx["report"]), "bankrupt ledger %d" % i)
	expect(bool(gx.state.get("done", false)), "bankrupt done")
	expect(str(gx.state.get("ending", "")) == "liquidated", "ending liquidated")
	expect(str(gx.terminal_summary()["ending"]) == "liquidated", "terminal ending liquidated")

	# --- terminal summary shape ---
	var ts: Dictionary = gfull.terminal_summary()
	for key in ["rank", "score", "score_breakdown", "contracts_fulfilled", "contracts_breached", "seizures", "ending"]:
		expect(ts.has(key), "terminal field %s" % key)

	# --- loc pack: v3 sections + named characters ---
	var f := FileAccess.open("res://data/loc_zh.json", FileAccess.READ)
	var loc = JSON.parse_string(f.get_as_text())
	expect(typeof(loc) == TYPE_DICTIONARY, "loc parses")
	if typeof(loc) == TYPE_DICTIONARY:
		for sec in ["routes", "visitors", "contracts", "moneylender", "endings", "checkpoints", "smuggle", "finale", "favor", "rumor_tags"]:
			expect((loc as Dictionary).has(sec), "loc section %s" % sec)
		expect(str(loc["visitors"]["informant"]["name"]) == "缉私线人·三只手", "informant named")
		expect(str(loc["moneylender"]["name"]).contains("半两"), "moneylender named")
		expect(str(loc["customer_groups"]["dock_workers"]["leader"]).contains("铁砂"), "group leader named")
	expect(Loc.t("app_title") == "星港市集", "Loc app title")

	print("SMOKE_", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
