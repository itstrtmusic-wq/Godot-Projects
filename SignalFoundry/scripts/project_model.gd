class_name FoundryProject
extends RefCounted

const SCHEMA_VERSION = 1
const MAX_NODES = 64
const DEFINITIONS = {
	"input": {"name": "Audio Input", "category": "I/O", "description": "Stereo audio from your DAW.", "params": {}},
	"gain": {"name": "Gain", "category": "LEVEL", "description": "Clean, automatable stereo gain.", "params": {
		"gain_db": {"label": "Gain", "min": -60.0, "max": 12.0, "default": -6.0, "step": 0.1, "unit": "dB"}}},
	"filter": {"name": "Low-pass Filter", "category": "FILTER", "description": "One-pole low-pass. Warm and simple.", "params": {
		"cutoff": {"label": "Cutoff", "min": 20.0, "max": 20000.0, "default": 4000.0, "step": 1.0, "unit": "Hz"}}},
	"saturation": {"name": "Saturation", "category": "COLOR", "description": "Normalized tanh waveshaping with dry/wet.", "params": {
		"drive": {"label": "Drive", "min": 1.0, "max": 20.0, "default": 2.5, "step": 0.1, "unit": "×"},
		"mix": {"label": "Mix", "min": 0.0, "max": 1.0, "default": 0.5, "step": 0.01, "unit": ""}}},
	"output": {"name": "Audio Output", "category": "I/O", "description": "Stereo output back to your DAW.", "params": {}}
}

var data: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	data = {"schema_version": SCHEMA_VERSION, "next_node_id": 1, "plugin": {"name": "Velvet Drive", "company": "Your Studio", "manufacturer_code": "Ystd", "plugin_code": "Vlvt"}, "nodes": [], "connections": []}
	var input_id = add_node("input", Vector2(50, 150))
	var gain_id = add_node("gain", Vector2(330, 150))
	var sat_id = add_node("saturation", Vector2(610, 150))
	var output_id = add_node("output", Vector2(890, 150))
	data.connections = [{"from": input_id, "to": gain_id}, {"from": gain_id, "to": sat_id}, {"from": sat_id, "to": output_id}]

func add_node(kind: String, position: Vector2) -> String:
	if not DEFINITIONS.has(kind) or data.nodes.size() >= MAX_NODES or data.next_node_id >= 1000000000:
		return ""
	if kind in ["input", "output"]:
		for node in data.nodes:
			if node.type == kind:
				return ""
	var index = int(data.next_node_id)
	while not node_by_id("n%d" % index).is_empty():
		index += 1
	data.next_node_id = index + 1
	var id = "n%d" % index
	var parameters = {}
	var exposed = {}
	for key in DEFINITIONS[kind].params:
		parameters[key] = DEFINITIONS[kind].params[key].default
		exposed[key] = true
	data.nodes.append({"id": id, "type": kind, "position": [position.x, position.y], "params": parameters, "exposed": exposed})
	return id

func node_by_id(id: String) -> Dictionary:
	for node in data.nodes:
		if node.id == id:
			return node
	return {}

func remove_node(id: String) -> void:
	data.nodes = data.nodes.filter(func(n): return n.id != id)
	data.connections = data.connections.filter(func(c): return c.from != id and c.to != id)

func connect_nodes(source: String, destination: String) -> String:
	var a = node_by_id(source)
	var b = node_by_id(destination)
	if a.is_empty() or b.is_empty():
		return "The connection references a missing node."
	if source == destination or a.type == "output" or b.type == "input":
		return "Connect an output port to another node's input."
	for edge in data.connections:
		if edge.from == source or edge.to == destination:
			return "This version supports one stereo chain. Disconnect the occupied port first."
	# Follow the destination before adding the edge, so even disconnected cycles are rejected.
	var cursor = destination
	var seen = {}
	while not seen.has(cursor):
		if cursor == source:
			return "Feedback loops are not supported."
		seen[cursor] = true
		var next = ""
		for edge in data.connections:
			if edge.from == cursor:
				next = edge.to
		if next.is_empty():
			break
		cursor = next
	data.connections.append({"from": source, "to": destination})
	return ""

func ordered_nodes() -> Array:
	var result = []
	var current = ""
	for node in data.nodes:
		if node.type == "input":
			current = node.id
	var visited = {}
	while not current.is_empty() and not visited.has(current):
		visited[current] = true
		var node = node_by_id(current)
		if node.is_empty():
			break
		result.append(node)
		var next = ""
		for edge in data.connections:
			if edge.from == current:
				next = edge.to
		current = next
	return result

func validate_graph() -> PackedStringArray:
	var errors = PackedStringArray()
	var chain = ordered_nodes()
	if chain.is_empty() or chain[0].type != "input":
		errors.append("Add an Audio Input node.")
	if chain.is_empty() or chain[-1].type != "output":
		errors.append("Connect a complete chain from Audio Input to Audio Output.")
	if chain.size() != data.nodes.size():
		errors.append("Every node must belong to the stereo chain. Connect or remove unused nodes.")
	if data.plugin.name.strip_edges().is_empty():
		errors.append("Give your plugin a name in Plugin settings.")
	elif RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$").search(data.plugin.name) == null or data.plugin.name.ends_with(".") or data.plugin.name.ends_with(" "):
		errors.append("Plugin name: use 1–64 letters, digits, spaces, dots, hyphens or underscores; start with a letter/digit and end without a dot/space.")
	if RegEx.create_from_string("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$").search(data.plugin.name.get_slice(".", 0).to_upper()) != null:
		errors.append("Choose a plugin name that is not a reserved Windows filename.")
	if data.plugin.company.strip_edges().is_empty():
		errors.append("Give your plugin a company name in Plugin settings.")
	for character in data.plugin.company:
		if character.unicode_at(0) < 32:
			errors.append("Company name cannot contain control characters.")
			break
	var code_regex = RegEx.create_from_string("^[A-Za-z][A-Za-z0-9]{3}$")
	for key in ["manufacturer_code", "plugin_code"]:
		if code_regex.search(data.plugin[key]) == null:
			errors.append("%s must be four ASCII letters/digits, starting with a letter." % key.capitalize())
	return errors

func serialize() -> String:
	return JSON.stringify(data, "\t", true, true)

func load_json(content: String) -> String:
	if content.length() > 2_000_000:
		return "Project exceeds the 2 MB file limit."
	var json = JSON.new()
	if json.parse(content) != OK:
		return "Invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
	var error = validate_document(json.data)
	if not error.is_empty():
		return error
	# Work on a candidate: never mutate a document when loading fails.
	var candidate = FoundryProject.new()
	candidate.data = json.data.duplicate(true)
	candidate.data.schema_version = SCHEMA_VERSION
	candidate.data.next_node_id = int(candidate.data.get("next_node_id", 1))
	for node in candidate.data.nodes:
		candidate.data.next_node_id = maxi(candidate.data.next_node_id, int(node.id.trim_prefix("n")) + 1)
	var connections: Array = candidate.data.connections.duplicate(true)
	candidate.data.connections = []
	for edge in connections:
		error = candidate.connect_nodes(edge.from, edge.to)
		if not error.is_empty():
			return error
	data = candidate.data
	return ""

static func validate_document(value: Variant) -> String:
	if not value is Dictionary or value.get("schema_version") != SCHEMA_VERSION:
		return "Unsupported project format. Expected Signal Foundry schema 1."
	if value.has("next_node_id") and (not _number(value.next_node_id) or value.next_node_id < 1 or value.next_node_id > 1000000000 or value.next_node_id != floor(value.next_node_id)):
		return "Invalid node ID counter."
	if not value.get("plugin") is Dictionary:
		return "Missing plugin settings."
	for key in ["name", "company", "manufacturer_code", "plugin_code"]:
		if not value.plugin.get(key) is String or value.plugin[key].length() > 128:
			return "Invalid plugin setting: " + key
	if not value.get("nodes") is Array or not value.get("connections") is Array:
		return "Nodes and connections must be arrays."
	if value.nodes.size() > MAX_NODES or value.connections.size() > MAX_NODES:
		return "Project exceeds the 64-node limit."
	var ids = {}
	var counts = {"input": 0, "output": 0}
	for node in value.nodes:
		if not node is Dictionary or not node.get("id") is String or not node.get("type") is String:
			return "Invalid node."
		if RegEx.create_from_string("^n[1-9][0-9]{0,8}$").search(node.id) == null or ids.has(node.id) or not DEFINITIONS.has(node.type):
			return "Unknown node type, invalid ID, or duplicate ID."
		ids[node.id] = true
		if counts.has(node.type):
			counts[node.type] += 1
			if counts[node.type] > 1:
				return "Only one input and one output are supported."
		if not node.get("position") is Array or node.position.size() != 2:
			return "Invalid node position."
		for coordinate in node.position:
			if not _number(coordinate) or absf(coordinate) > 100000:
				return "Invalid node position."
		if not node.get("params") is Dictionary or not node.get("exposed") is Dictionary:
			return "Invalid node parameters."
		var spec: Dictionary = DEFINITIONS[node.type].params
		if node.params.size() != spec.size() or node.exposed.size() != spec.size():
			return "Unexpected or missing node parameters."
		for key in spec:
			var parameter = node.params.get(key)
			if not _number(parameter) or parameter < spec[key].min or parameter > spec[key].max or not node.exposed.get(key) is bool:
				return "Invalid parameter: " + key
	for edge in value.connections:
		if not edge is Dictionary or not edge.get("from") is String or not edge.get("to") is String:
			return "Invalid connection."
		if not ids.has(edge.from) or not ids.has(edge.to):
			return "Connection references a missing node."
	return ""

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func save_file(path: String) -> String:
	var nonce = Crypto.new().generate_random_bytes(8).hex_encode()
	var temporary = path + ".tmp-" + nonce
	var backup = path + ".bak-" + nonce
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not write the project: " + error_string(FileAccess.get_open_error())
	file.store_string(serialize())
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		return "Project write failed: " + error_string(write_error)
	var exists = FileAccess.file_exists(path)
	if exists and DirAccess.rename_absolute(path, backup) != OK:
		return "Could not preserve the existing project. Check file permissions."
	if DirAccess.rename_absolute(temporary, path) != OK:
		if exists:
			DirAccess.rename_absolute(backup, path)
		return "Could not finish saving the project."
	if exists:
		DirAccess.remove_absolute(backup)
	return ""
