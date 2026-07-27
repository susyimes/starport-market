extends SceneTree
## Windowed screenshot tour for gameplay v3:
## title → night-1 plan (route card + contract + smuggle armed) → open market →
## settlement report → fast-forward nights (keep smuggling / contracting so heat
## and active contracts build up) → richest plan shot → play out → game over.
## Outputs the canonical four: shot_title / shot_plan / shot_report / shot_gameover.
## Run: godot_console --path godot -s res://tools/screenshot.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	await _frames(12)
	await _shot("title")

	# field guide overlay, both pages
	ui.help_open = true
	ui.help_page = 0
	ui._refresh_help()
	await _frames(4)
	await _shot("help")
	ui.help_page = 1
	ui._refresh_help()
	await _frames(2)
	await _shot("help2")
	ui.help_open = false
	ui._refresh_help()
	await _frames(2)

	# night 1: route card + accepted contract + smuggle units all visible
	ui.enter_plan()
	await _frames(4)
	_plan_night(ui, true)
	await _frames(2)
	ui.open_market()
	await _frames(20)
	await _shot("report")

	# fast-forward to night 7 (route night), building heat / contracts via the UI API
	var guard := 0
	while not ui.game.state.get("done", false) and int(ui.game.observation()["day"]) < 7 and guard < 10:
		ui.continue_from_report()
		await _frames(1)
		_plan_night(ui, false)
		ui.open_market()
		await _frames(2)
		guard += 1

	# richest plan screenshot: route cards + heat + rumors + contracts + smuggle
	if not ui.game.state.get("done", false):
		ui.continue_from_report()
		await _frames(2)
		_plan_night(ui, false)
		await _frames(240)   # let any "can't afford" toast from the top-up expire
	await _shot("plan")

	# play the season out
	if ui.mode == ui.Mode.PLAN:
		ui.open_market()
		await _frames(2)
	guard = 0
	while not ui.game.state.get("done", false) and guard < 25:
		ui.continue_from_report()
		await _frames(1)
		ui.open_market()
		await _frames(1)
		guard += 1
	ui.continue_from_report()
	await _frames(6)
	await _shot("gameover")
	print("SHOTS_DONE")
	quit(0)


## Drive one planning phase through the public UI API only.
func _plan_night(ui, first_night: bool) -> void:
	var obs: Dictionary = ui.game.observation()
	# route card: gray route on night 1 (extra smuggle line), otherwise slot 1
	var routes: Array = obs.get("route_offer", [])
	if routes.size() > 0:
		ui.select_permit(1 if first_night else 0)
	# accept the first spot contract and stock up for it (keeps reputation up);
	# also take one bulk card when offered so an active countdown shows later
	var board: Array = (obs.get("contracts", {}) as Dictionary).get("board", [])
	for bi in board.size():
		var card: Dictionary = board[bi]
		var kind := str(card["kind"])
		if kind == "spot":
			ui.toggle_contract(bi)
			var cidx: int = ui.game.product_ids.find(str(card["product_id"]))
			if cidx >= 0:
				ui.select_product(cidx)
				for i in int(card["qty"]):
					ui.adjust_order(1)
			break
	for bi in board.size():
		if str(board[bi]["kind"]) == "bulk":
			ui.toggle_contract(bi)
			break
	# smuggle a handful of units from the first bay line BEFORE the greedy
	# top-up drains the wallet — heat has to build across the season
	var offers: Array = obs.get("smuggle", [])
	if offers.size() > 0:
		for i in 4:
			ui.adjust_smuggle(0, 1)
	# greedy top-up across the shelf: adjust_order reverts by itself once cash
	# or capacity runs out, so this simply fills what the plan can afford
	for pi in ui.game.product_ids.size():
		ui.select_product(pi)
		for i in 4:
			ui.adjust_order(1)
	ui.select_product(0)
	# take the dusk visitor's deal when one shows up
	if not (obs.get("visitor", {}) as Dictionary).is_empty():
		ui.set_visitor(true)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://.preview/shot_%s.png" % name)
	print("SHOT ", name)
