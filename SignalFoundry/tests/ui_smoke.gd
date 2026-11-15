extends SceneTree

var failures = 0
var checks = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Load the real scene and exercise its controls and signal handlers.
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	for i in 4:
		await process_frame
	var spins = app.inspector.find_children("*", "SpinBox", true, false)
	if spins.is_empty():
		printerr("FAIL: Inspector did not initialize")
		quit(1)
		return
	spins[0].value = 3.5
	check(app.document.node_by_id("n3").params.drive == 3.5, "Inspector controls update document")
	app._undo()
	check(app.document.node_by_id("n3").params.drive == 2.5, "Inspector edit undoes")
	app.palette_list.get_child(2).pressed.emit()
	check(app.document.data.nodes.size() == 5 and not app.document.validate_graph().is_empty(), "Palette adds a disconnected filter")
	app._undo()
	check(app.document.data.nodes.size() == 4 and app.document.validate_graph().is_empty(), "Add-node undo restores chain")
	app.graph.disconnection_request.emit("n2", 0, "n3", 0)
	check(not app.document.validate_graph().is_empty(), "Disconnect updates model")
	app.graph.connection_request.emit("n2", 0, "n3", 0)
	check(app.document.validate_graph().is_empty(), "Connect updates model")
	app._set_parameter("n2", "gain_db", -12.0)
	check(app.document.node_by_id("n2").params.gain_db == -12.0, "Parameter changes")
	app._undo()
	check(app.document.node_by_id("n2").params.gain_db == -6.0, "Parameter undo")
	app._redo()
	check(app.document.node_by_id("n2").params.gain_db == -12.0, "Parameter redo")
	app._undo()
	app._toggle_audition()
	await create_timer(0.2).timeout
	check(app.preview.active and app.preview.peak > 0.0, "Audition produces audio frames")
	for sample in app.preview.trace:
		if not is_finite(sample):
			check(false, "Audition output must be finite")
			break
	app.graph.disconnection_request.emit("n2", 0, "n3", 0)
	check(not app.preview.active, "Invalid graph automatically stops audition")
	app._undo()
	app._toggle_audition()
	app._toggle_audition()
	check(not app.preview.active, "Audition stops")
	app.selected_id = "n3"
	app._refresh_inspector()
	app._check_graph()
	for i in 3:
		await process_frame
	for item in app.graph.get_children():
		if item is GraphNode:
			check(item.position.y >= 0.0 and item.position.y < app.graph.size.y, "Starter node visible: " + str(item.name))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path = OS.get_cache_dir().path_join("signal-foundry.png")
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--screenshot="):
				path = argument.trim_prefix("--screenshot=")
		check(root.get_texture().get_image().save_png(path) == OK, "Screenshot saved")
	print("UI smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
