extends SceneTree

var checks = 0
var failures = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var project = FoundryProject.new()
	check(project.validate_graph().is_empty(), "Starter graph is valid")
	check(project.ordered_nodes().size() == 4, "Starter chain contains four ordered nodes")
	var original = project.serialize()
	check(project.load_json(original).is_empty(), "JSON round-trip")
	check(project.serialize() == original, "Round-trip preserves parameters, IDs and positions")
	check(project.add_node("input", Vector2.ZERO).is_empty(), "Duplicate input rejected")
	check(project.add_node("unknown", Vector2.ZERO).is_empty(), "Unknown module rejected")
	check(not project.connect_nodes("n2", "n2").is_empty(), "Self connection rejected")
	check(not project.connect_nodes("n1", "n3").is_empty(), "Occupied output rejected")
	check(not project.connect_nodes("n4", "n2").is_empty(), "Audio output cannot be a source")
	check(not project.connect_nodes("n2", "n1").is_empty(), "Audio input cannot be a destination")
	var identity = FoundryProject.new()
	identity.remove_node("n2")
	check(identity.add_node("gain", Vector2.ZERO) != "n2", "Deleted node IDs are not reused for automation")
	var filter_id = project.add_node("filter", Vector2(300, 400))
	check(not project.validate_graph().is_empty(), "Disconnected node blocks export")
	check(JuceExporter.generate(project).has("error"), "Exporter rejects incomplete graph")
	project.data.connections = project.data.connections.filter(func(edge): return edge.from != "n2")
	check(project.connect_nodes("n2", filter_id).is_empty(), "Connect gain to filter")
	check(project.connect_nodes(filter_id, "n3").is_empty(), "Connect filter to saturation")
	check(project.validate_graph().is_empty(), "Extended graph is valid")
	var cycle = FoundryProject.new()
	cycle.data.connections.clear()
	check(cycle.connect_nodes("n2", "n3").is_empty(), "Disconnected fragment allowed")
	check(not cycle.connect_nodes("n3", "n2").is_empty(), "Disconnected cycle rejected")
	var malformed: Array = ["{", "null", "[]", "{}"]
	for value in malformed:
		var before = project.serialize()
		check(not project.load_json(value).is_empty(), "Malformed document rejected: " + value)
		check(project.serialize() == before, "Failed load leaves active project intact")
	var corruptions: Array[Callable] = [
		func(d): d.schema_version = 99,
		func(d): d.nodes[0].id = "../../bad",
		func(d): d.nodes[1].id = d.nodes[0].id,
		func(d): d.nodes[1].params.gain_db = 900,
		func(d): d.nodes[1].params.gain_db = "loud",
		func(d): d.nodes[1].exposed.gain_db = "yes",
		func(d): d.nodes[1].params.extra = 0,
		func(d): d.nodes[1].position = [0],
		func(d): d.nodes[1].position = ["x", 0],
		func(d): d.connections[0].to = "n900",
		func(d): d.connections.append({"from": "n2", "to": "n3"}),
		func(d): d.plugin.name = 17,
	]
	for corrupt in corruptions:
		var bad: Dictionary = JSON.parse_string(original)
		corrupt.call(bad)
		check(not project.load_json(JSON.stringify(bad)).is_empty(), "Invalid schema or topology rejected")
	var exported = JuceExporter.generate(project)
	check(exported.has("files") and exported.files.size() == 7, "All seven source export artifacts generated")
	check(exported.files["Source/GeneratedDSP.h"].contains("filter"), "Filter emitted into DSP")
	check(exported.files["Source/PluginProcessor.cpp"].contains('ParameterID{"n2_gain_db", 1}'), "Stable automation ID")
	project.node_by_id("n2").exposed.gain_db = false
	var fixed = JuceExporter.generate(project)
	check(not fixed.files["Source/PluginProcessor.cpp"].contains('ParameterID{"n2_gain_db", 1}'), "Unexposed parameter not published to host")
	check(fixed.files["Source/GeneratedDSP.h"].contains("n2_gain_db"), "Unexposed parameter remains in DSP")
	project.node_by_id("n2").exposed.gain_db = true
	project.data.plugin.name = "../../escape"
	check(not project.validate_graph().is_empty(), "Unsafe plugin filename rejected")
	project.data.plugin.name = "Velvet Drive"
	project.data.plugin.name = "CON"
	check(not project.validate_graph().is_empty(), "Reserved Windows filename rejected")
	project.data.plugin.name = "Velvet Drive"
	project.data.plugin.plugin_code = "!bad"
	check(not project.validate_graph().is_empty(), "Invalid plugin code rejected")
	project.data.plugin.plugin_code = "Vlvt"
	check(JuceExporter.cmake_string("A $B; \"C\"").contains("\\$"), "CMake variable expansion escaped")
	var test_directory = OS.get_cache_dir().path_join("signal-foundry-tests")
	DirAccess.make_dir_recursive_absolute(test_directory)
	var save_path = test_directory.path_join("foundry-test.signal.json")
	check(project.save_file(save_path).is_empty(), "Project saves to disk")
	check(project.save_file(save_path).is_empty(), "Project safely replaces previous save")
	var loaded = FoundryProject.new()
	check(loaded.load_json(FileAccess.get_file_as_string(save_path)).is_empty(), "Saved file loads")
	check(loaded.serialize() == project.serialize(), "Disk round-trip is lossless")
	var export_root = test_directory.path_join("export-" + str(Time.get_ticks_usec()))
	check(JuceExporter.write_project(project, export_root).is_empty(), "Source export writes files")
	check(not JuceExporter.write_project(project, export_root).is_empty(), "Export never overwrites an existing folder")
	for relative in exported.files:
		check(FileAccess.file_exists(export_root.path_join(relative)), "Export exists: " + relative)
	# Stable path supplied by the caller for compiling this run's emitted C++.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--export-to="):
			var target = argument.trim_prefix("--export-to=")
			check(JuceExporter.write_project(project, target).is_empty(), "Build fixture export: " + target)
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
