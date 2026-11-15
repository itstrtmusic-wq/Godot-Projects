extends Control

const BG = Color("10141b")
const PANEL = Color("171d26")
const BORDER = Color("2b3442")
const TEXT = Color("e8edf4")
const MUTED = Color("8c9aaf")
const ACCENT = Color("7ce4bf")
const COLORS = {"input": Color("7ce4bf"), "output": Color("7ce4bf"), "gain": Color("82b6ff"), "filter": Color("f3bd79"), "saturation": Color("c3a1f4")}
const Waveform = preload("res://scripts/waveform.gd")

var document = FoundryProject.new()
var graph: GraphEdit
var inspector: VBoxContainer
var palette_list: VBoxContainer
var project_label: Label
var saved_label: Label
var count_label: Label
var readiness: Label
var chain_label: Label
var log_view: RichTextLabel
var audition_button: Button
var meter: ProgressBar
var meter_label: Label
var preview: FoundryPreview
var save_dialog: FileDialog
var open_dialog: FileDialog
var export_dialog: FileDialog
var confirm: ConfirmationDialog
var selected_id = "n3"
var project_path = ""
var saved_snapshot = ""
var history: Array[String] = []
var future: Array[String] = []
var rebuilding = false
var plugin_settings = false
var pending_action: Callable
var last_edit_key = ""
var last_edit_time = 0

func _ready() -> void:
	get_tree().auto_accept_quit = false
	_install_theme()
	preview = FoundryPreview.new()
	add_child(preview)
	_build_ui()
	_build_dialogs()
	saved_snapshot = document.serialize()
	_refresh_graph()
	_refresh_inspector()
	_log("Workspace ready. Connect stereo modules, audition, then export JUCE source.", ACCENT)
	await get_tree().process_frame
	await get_tree().process_frame
	graph.scroll_offset = Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_guard_unsaved(func(): get_tree().quit())

func _style(color: Color, outline = Color.TRANSPARENT, radius = 8, padding = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = outline
	style.set_border_width_all(1 if outline.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _install_theme() -> void:
	var skin = Theme.new()
	skin.default_font_size = 14
	skin.set_color("font_color", "Label", TEXT)
	skin.set_color("font_color", "Button", TEXT)
	skin.set_color("font_hover_color", "Button", Color.WHITE)
	skin.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	for type in ["Button", "OptionButton"]:
		skin.set_stylebox("normal", type, _style(Color("222a36"), BORDER, 6, 10))
		skin.set_stylebox("hover", type, _style(Color("303b4b"), Color("526478"), 6, 10))
		skin.set_stylebox("pressed", type, _style(Color("344b49"), ACCENT, 6, 10))
		skin.set_stylebox("focus", type, _style(Color.TRANSPARENT, ACCENT, 6, 10))
		skin.set_stylebox("disabled", type, _style(Color("1b222c"), BORDER, 6, 10))
	for type in ["LineEdit", "TextEdit"]:
		skin.set_stylebox("normal", type, _style(BG, BORDER, 5, 10))
		skin.set_stylebox("focus", type, _style(BG, ACCENT, 5, 10))
		skin.set_color("font_color", type, TEXT)
		skin.set_color("font_placeholder_color", type, MUTED)
	skin.set_stylebox("panel", "PopupMenu", _style(PANEL, BORDER))
	skin.set_stylebox("panel", "Window", _style(PANEL, BORDER))
	skin.set_stylebox("panel", "AcceptDialog", _style(PANEL, BORDER))
	skin.set_stylebox("panel", "GraphEdit", _style(Color("121820"), BORDER, 0, 0))
	skin.set_color("grid_minor", "GraphEdit", Color("202a37"))
	skin.set_color("grid_major", "GraphEdit", Color("2d3848"))
	skin.set_color("activity", "GraphEdit", ACCENT)
	skin.set_stylebox("background", "ProgressBar", _style(BG, Color.TRANSPARENT, 3, 0))
	skin.set_stylebox("fill", "ProgressBar", _style(ACCENT, Color.TRANSPARENT, 3, 0))
	theme = skin

func _label(value: String, size_px = 14, color = TEXT) -> Label:
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label

func _button(value: String, action: Callable, primary = false) -> Button:
	var button = Button.new()
	button.text = value
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	if primary:
		button.add_theme_stylebox_override("normal", _style(ACCENT, ACCENT, 6, 11))
		button.add_theme_stylebox_override("hover", _style(ACCENT.lightened(0.12), ACCENT, 6, 11))
		button.add_theme_stylebox_override("pressed", _style(ACCENT.darkened(0.15), ACCENT, 6, 11))
		button.add_theme_color_override("font_color", BG)
		button.add_theme_color_override("font_hover_color", BG)
		button.add_theme_color_override("font_pressed_color", BG)
	return button

func _spacer(parent: Control) -> void:
	var space = Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(space)

func _gap(parent: Control, height = 10) -> void:
	var space = Control.new()
	space.custom_minimum_size.y = height
	parent.add_child(space)

func _box(parent: Control, color = PANEL, padding = 16) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(color, BORDER, 8, padding))
	parent.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box

func _wrapped(value: String, color = MUTED, font_size = 13) -> Label:
	var label = _label(value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _build_ui() -> void:
	var background = ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	layout.add_child(top)
	var icon = TextureRect.new()
	icon.texture = preload("res://assets/icon.svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(38, 38)
	top.add_child(icon)
	top.add_child(_label("SIGNAL FOUNDRY", 18))
	top.add_child(_label(" /  Visual plugin studio", 13, MUTED))
	_spacer(top)
	top.add_child(_button("New", func(): _guard_unsaved(_new_project)))
	top.add_child(_button("Open…", func(): _guard_unsaved(func(): open_dialog.popup_centered_ratio(0.7))))
	top.add_child(_button("Save", _save))
	top.add_child(_button("Export JUCE  ↗", _request_export, true))
	var heading = HBoxContainer.new()
	layout.add_child(heading)
	var titles = VBoxContainer.new()
	titles.add_theme_constant_override("separation", 4)
	heading.add_child(titles)
	titles.add_child(_label("WORKSPACE  /  STEREO EFFECT", 11, ACCENT))
	project_label = _label("Velvet Drive", 30)
	titles.add_child(project_label)
	_spacer(heading)
	var heading_right = VBoxContainer.new()
	heading_right.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_child(heading_right)
	saved_label = _label("Unsaved project", 12, MUTED)
	saved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading_right.add_child(saved_label)
	heading_right.add_child(_label("VST3  ·  Windows source target  ·  v0.1", 12, MUTED))
	var workspace = HBoxContainer.new()
	workspace.add_theme_constant_override("separation", 14)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(workspace)
	_build_palette(workspace)
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 12)
	workspace.add_child(center)
	_build_graph(center)
	_build_audition(center)
	_build_inspector(workspace)
	_build_status(layout)
	var footer = HBoxContainer.new()
	layout.add_child(footer)
	footer.add_child(_label("●  LOCAL WORKSPACE", 10, ACCENT))
	_spacer(footer)
	footer.add_child(_label("Ctrl+S  Save     Ctrl+Z  Undo     Ctrl+Shift+Z  Redo     Drag ports to connect", 11, MUTED))

func _build_palette(parent: Control) -> void:
	var box = _box(parent)
	box.get_parent().custom_minimum_size.x = 208
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("MODULE LIBRARY", 11, MUTED))
	box.add_child(_label("Build your signal", 19))
	box.add_child(_wrapped("Click to add a module.", MUTED, 12))
	var search = LineEdit.new()
	search.placeholder_text = "Search modules…"
	search.clear_button_enabled = true
	box.add_child(search)
	search.text_changed.connect(_filter_palette)
	palette_list = VBoxContainer.new()
	palette_list.add_theme_constant_override("separation", 10)
	box.add_child(palette_list)
	_filter_palette("")
	var expand = Control.new()
	expand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(expand)
	box.add_child(HSeparator.new())
	box.add_child(_label("STEREO IN → STEREO OUT", 10, ACCENT))
	box.add_child(_button("Plugin settings", func():
		plugin_settings = true
		_refresh_inspector()))

func _filter_palette(query: String) -> void:
	for child in palette_list.get_children():
		palette_list.remove_child(child)
		child.queue_free()
	for kind in ["input", "gain", "filter", "saturation", "output"]:
		var spec: Dictionary = FoundryProject.DEFINITIONS[kind]
		if not query.is_empty() and not (spec.name + " " + spec.description).to_lower().contains(query.to_lower()):
			continue
		var button = _button("", _add_node.bind(kind))
		button.custom_minimum_size = Vector2(174, 54)
		button.tooltip_text = spec.description
		palette_list.add_child(button)
		var content = VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 12
		content.offset_top = 5
		content.offset_right = -12
		content.offset_bottom = -5
		button.add_child(content)
		content.add_child(_label(spec.category + "                                      +", 10, COLORS[kind]))
		content.add_child(_label(spec.name, 14))

func _build_graph(parent: Control) -> void:
	var panel = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 8, 0))
	parent.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	var padding = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 12)
	box.add_child(padding)
	padding.add_child(toolbar)
	toolbar.add_child(_label("Signal graph", 15))
	count_label = _label("4 modules", 11, MUTED)
	toolbar.add_child(count_label)
	_spacer(toolbar)
	toolbar.add_child(_button("Undo", _undo))
	toolbar.add_child(_button("Redo", _redo))
	toolbar.add_child(_button("Arrange", _arrange))
	graph = GraphEdit.new()
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size.y = 300
	graph.minimap_enabled = false
	graph.right_disconnects = true
	graph.show_arrange_button = false
	graph.show_grid = true
	graph.snapping_distance = 20
	graph.zoom = 0.76
	graph.grid_pattern = GraphEdit.GRID_PATTERN_DOTS
	graph.connection_lines_curvature = 0.5
	graph.add_theme_constant_override("port_hotzone_inner_extent", 18)
	graph.add_theme_constant_override("port_hotzone_outer_extent", 18)
	box.add_child(graph)
	graph.connection_request.connect(_connect)
	graph.disconnection_request.connect(_disconnect)
	graph.node_selected.connect(func(node):
		selected_id = str(node.name)
		plugin_settings = false
		_refresh_inspector())
	graph.end_node_move.connect(_nodes_moved)
	graph.delete_nodes_request.connect(_delete_nodes)
	var hint = _label("  STEREO AUDIO     ●  Drag between ports to route    ·    Right-click a port to disconnect", 11, MUTED)
	hint.custom_minimum_size.y = 30
	box.add_child(hint)

func _build_audition(parent: Control) -> void:
	var box = _box(parent, PANEL, 14)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_label("REFERENCE AUDITION", 10, MUTED))
	_spacer(row)
	var frequencies = OptionButton.new()
	for frequency in [110, 220, 440, 880]:
		frequencies.add_item("%d Hz" % frequency, frequency)
	frequencies.select(1)
	frequencies.item_selected.connect(func(index): preview.frequency = frequencies.get_item_id(index))
	row.add_child(frequencies)
	audition_button = _button("▶  Audition", _toggle_audition)
	row.add_child(audition_button)
	var plot_row = HBoxContainer.new()
	plot_row.add_theme_constant_override("separation", 16)
	box.add_child(plot_row)
	var plot = Waveform.new()
	plot.preview = preview
	plot.custom_minimum_size.y = 62
	plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot_row.add_child(plot)
	var meter_box = VBoxContainer.new()
	meter_box.custom_minimum_size.x = 100
	plot_row.add_child(meter_box)
	meter_label = _label("−∞ dBFS", 16, ACCENT)
	meter_box.add_child(meter_label)
	meter = ProgressBar.new()
	meter.custom_minimum_size.y = 5
	meter.max_value = 1.0
	meter.show_percentage = false
	meter_box.add_child(meter)
	meter_box.add_child(_label("OUTPUT PEAK", 9, MUTED))
	box.add_child(_label("Harmonic tone · limited monitor output · design preview, not a JUCE host", 11, MUTED))

func _build_inspector(parent: Control) -> void:
	var box = _box(parent)
	box.get_parent().custom_minimum_size.x = 270
	box.get_parent().custom_minimum_size.y = 480
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	tabs.add_child(_button("Inspector", func():
		plugin_settings = false
		_refresh_inspector()))
	tabs.add_child(_button("Plugin", func():
		plugin_settings = true
		_refresh_inspector()))
	box.add_child(HSeparator.new())
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.custom_minimum_size.x = 234
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 10)
	scroll.add_child(inspector)

func _build_status(parent: Control) -> void:
	var box = _box(parent, PANEL, 14)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	readiness = _label("●  Ready to export", 14, ACCENT)
	column.add_child(readiness)
	chain_label = _label("", 12, MUTED)
	chain_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(chain_label)
	row.add_child(_button("Check graph", _check_graph))
	log_view = RichTextLabel.new()
	log_view.custom_minimum_size.y = 45
	log_view.bbcode_enabled = false
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(log_view)

func _build_dialogs() -> void:
	save_dialog = FileDialog.new()
	save_dialog.title = "Save Signal Foundry project"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.signal.json ; Signal Foundry project"])
	save_dialog.current_file = "Velvet Drive.signal.json"
	save_dialog.file_selected.connect(_save_to)
	add_child(save_dialog)
	open_dialog = FileDialog.new()
	open_dialog.title = "Open Signal Foundry project"
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.filters = save_dialog.filters
	open_dialog.file_selected.connect(_open_project)
	add_child(open_dialog)
	export_dialog = FileDialog.new()
	export_dialog.title = "Choose an empty folder for JUCE source (not a compiled VST3)"
	export_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.dir_selected.connect(_export_to)
	add_child(export_dialog)
	confirm = ConfirmationDialog.new()
	confirm.title = "Unsaved changes"
	confirm.dialog_text = "Discard unsaved changes to this project?\nUse Save first to keep your work."
	confirm.ok_button_text = "Discard changes"
	confirm.confirmed.connect(func():
		if pending_action.is_valid():
			pending_action.call())
	add_child(confirm)

func _refresh_graph() -> void:
	rebuilding = true
	var previous_scroll = graph.scroll_offset
	graph.clear_connections()
	for child in graph.get_children():
		if child is GraphNode:
			graph.remove_child(child)
			child.queue_free()
	for node in document.data.nodes:
		var item = GraphNode.new()
		item.name = node.id
		item.title = FoundryProject.DEFINITIONS[node.type].name
		item.position_offset = Vector2(node.position[0], node.position[1])
		item.custom_minimum_size = Vector2(224, 0)
		item.resizable = false
		var color: Color = COLORS[node.type]
		item.add_theme_stylebox_override("panel", _style(Color("202936"), BORDER, 8, 14))
		item.add_theme_stylebox_override("panel_selected", _style(Color("263242"), color, 8, 14))
		item.add_theme_stylebox_override("titlebar", _style(Color("293445"), BORDER, 8, 12))
		item.add_theme_stylebox_override("titlebar_selected", _style(Color("354356"), color, 8, 12))
		item.add_theme_color_override("title_color", TEXT)
		item.add_theme_font_size_override("title_font_size", 16)
		graph.add_child(item)
		item.add_child(_label(FoundryProject.DEFINITIONS[node.type].category + "  /  " + node.id.to_upper(), 11, color))
		var ports = HBoxContainer.new()
		ports.custom_minimum_size.y = 32
		if node.type != "input":
			ports.add_child(_label("IN", 10, MUTED))
		_spacer(ports)
		if node.type != "output":
			ports.add_child(_label("OUT", 10, MUTED))
		item.add_child(ports)
		item.set_slot(1, node.type != "input", 0, ACCENT, node.type != "output", 0, ACCENT)
		var summary = _label(_node_summary(node), 13, TEXT)
		summary.name = "Summary"
		item.add_child(summary)
		item.add_child(_label("STEREO  ·  32-BIT FLOAT", 10, MUTED))
		item.selected = node.id == selected_id
	for edge in document.data.connections:
		graph.connect_node(edge.from, 0, edge.to, 0)
	count_label.text = "%d modules" % document.data.nodes.size()
	graph.scroll_offset = previous_scroll
	graph.set_deferred("scroll_offset", previous_scroll)
	_restore_scroll.call_deferred(previous_scroll)
	rebuilding = false
	_update_state()

func _restore_scroll(value: Vector2) -> void:
	await get_tree().process_frame
	graph.scroll_offset = value

func _node_summary(node: Dictionary) -> String:
	match node.type:
		"input": return "DAW audio source"
		"output": return "Return to host"
		"gain": return "%+.1f dB" % node.params.gain_db
		"filter": return "%.0f Hz  ·  6 dB/oct" % node.params.cutoff
		"saturation": return "%.1f× drive  ·  %.0f%% mix" % [node.params.drive, node.params.mix * 100]
	return ""

func _refresh_inspector() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	if plugin_settings:
		_inspect_plugin()
		return
	var node = document.node_by_id(selected_id)
	if node.is_empty():
		inspector.add_child(_label("Select a module", 20))
		inspector.add_child(_wrapped("Click any node to edit its parameters and automation."))
		return
	var spec: Dictionary = FoundryProject.DEFINITIONS[node.type]
	inspector.add_child(_label(spec.category + "  /  " + node.id.to_upper(), 11, COLORS[node.type]))
	inspector.add_child(_label(spec.name, 21))
	inspector.add_child(_wrapped(spec.description))
	_gap(inspector, 8)
	if not spec.params.is_empty():
		inspector.add_child(_label("PARAMETERS", 10, MUTED))
	for key in spec.params:
		var parameter: Dictionary = spec.params[key]
		var row = HBoxContainer.new()
		inspector.add_child(row)
		row.add_child(_label(parameter.label, 14))
		_spacer(row)
		var value = SpinBox.new()
		value.custom_minimum_size.x = 120
		value.min_value = parameter.min
		value.max_value = parameter.max
		value.step = parameter.step
		value.value = node.params[key]
		value.suffix = parameter.unit
		row.add_child(value)
		var slider = HSlider.new()
		slider.min_value = parameter.min
		slider.max_value = parameter.max
		slider.step = parameter.step
		slider.value = node.params[key]
		slider.custom_minimum_size.y = 24
		if key == "cutoff":
			slider.exp_edit = true
		inspector.add_child(slider)
		slider.value_changed.connect(func(number):
			value.set_value_no_signal(number)
			_set_parameter(node.id, key, number))
		value.value_changed.connect(func(number):
			slider.set_value_no_signal(number)
			_set_parameter(node.id, key, number))
		var expose = CheckBox.new()
		expose.text = "Expose to DAW automation"
		expose.add_theme_font_size_override("font_size", 12)
		expose.button_pressed = node.exposed[key]
		expose.toggled.connect(func(enabled):
			_record()
			document.node_by_id(node.id).exposed[key] = enabled
			_update_state())
		inspector.add_child(expose)
		_gap(inspector, 8)
	inspector.add_child(HSeparator.new())
	inspector.add_child(_label("SIGNAL FORMAT", 10, MUTED))
	inspector.add_child(_wrapped("2 channels · floating point\nSample rate follows the host", TEXT, 13))
	if not spec.params.is_empty():
		_gap(inspector, 8)
		inspector.add_child(_wrapped("Exposed controls become plugin parameters. Unchecked values are baked into the exported DSP.", MUTED, 12))
	_gap(inspector, 12)
	inspector.add_child(_button("Remove module", func(): _delete_nodes([node.id])))

func _inspect_plugin() -> void:
	inspector.add_child(_label("EXPORT IDENTITY", 11, ACCENT))
	inspector.add_child(_label("Plugin settings", 21))
	inspector.add_child(_wrapped("Name your effect and set its host identity."))
	for pair in [["name", "Plugin name"], ["company", "Company"], ["manufacturer_code", "Manufacturer code"], ["plugin_code", "Plugin code"]]:
		inspector.add_child(_label(pair[1], 12, MUTED))
		var field = LineEdit.new()
		field.text = document.data.plugin[pair[0]]
		field.max_length = 4 if pair[0].ends_with("code") else 128
		inspector.add_child(field)
		# Commit immediately so Save/Export always uses the text currently visible.
		field.text_changed.connect(func(value):
			_record("plugin_" + pair[0])
			document.data.plugin[pair[0]] = value
			_update_state())
	inspector.add_child(_wrapped("Codes: 4 letters/digits, starting with a letter. Use unique codes before releasing a plugin.", MUTED, 12))
	inspector.add_child(HSeparator.new())
	inspector.add_child(_label("EXPORT TARGET", 10, MUTED))
	inspector.add_child(_wrapped("JUCE 8 · C++17 · VST3\nWindows x64 via Visual Studio 2022", TEXT, 13))
	inspector.add_child(_wrapped("Exports source, not a ready-to-load plugin. Compile on Windows, then validate in your DAW. JUCE licensing applies to distribution.", MUTED, 12))

func _set_parameter(id: String, key: String, value: float) -> void:
	_record(id + key)
	var node = document.node_by_id(id)
	node.params[key] = value
	var item = graph.get_node_or_null(NodePath(id + "/Summary"))
	if item != null:
		item.text = _node_summary(node)
	_update_state()

func _record(edit_key = "") -> void:
	var now = Time.get_ticks_msec()
	if edit_key.is_empty() or edit_key != last_edit_key or now - last_edit_time > 500:
		history.append(document.serialize())
		if history.size() > 80:
			history.pop_front()
	future.clear()
	last_edit_key = edit_key
	last_edit_time = now

func _undo() -> void:
	if history.is_empty():
		return
	future.append(document.serialize())
	document.load_json(history.pop_back())
	last_edit_key = ""
	_refresh_graph()
	_refresh_inspector()

func _redo() -> void:
	if future.is_empty():
		return
	history.append(document.serialize())
	document.load_json(future.pop_back())
	last_edit_key = ""
	_refresh_graph()
	_refresh_inspector()

func _add_node(kind: String) -> void:
	if kind in ["input", "output"]:
		for node in document.data.nodes:
			if node.type == kind:
				_log("Only one %s is allowed. Select the existing module." % FoundryProject.DEFINITIONS[kind].name, Color("f3bd79"))
				return
	if document.data.nodes.size() >= FoundryProject.MAX_NODES:
		_log("The 64-module project limit has been reached.", Color("f3bd79"))
		return
	_record()
	selected_id = document.add_node(kind, (graph.scroll_offset + graph.size * 0.4) / graph.zoom)
	plugin_settings = false
	_refresh_graph()
	_refresh_inspector()
	_log("Added %s. Connect it into the stereo chain." % FoundryProject.DEFINITIONS[kind].name)

func _connect(source: StringName, _source_port: int, destination: StringName, _destination_port: int) -> void:
	var before = document.serialize()
	var error = document.connect_nodes(str(source), str(destination))
	if not error.is_empty():
		_log(error, Color("f3bd79"))
		return
	history.append(before)
	if history.size() > 80:
		history.pop_front()
	future.clear()
	last_edit_key = ""
	_refresh_graph()

func _disconnect(source: StringName, _source_port: int, destination: StringName, _destination_port: int) -> void:
	_record()
	document.data.connections = document.data.connections.filter(func(edge): return not (edge.from == source and edge.to == destination))
	_refresh_graph()

func _delete_nodes(ids: Array) -> void:
	if ids.is_empty():
		return
	_record()
	for id in ids:
		document.remove_node(str(id))
	selected_id = ""
	_refresh_graph()
	_refresh_inspector()

func _nodes_moved() -> void:
	if rebuilding:
		return
	var positions = {}
	for node in document.data.nodes:
		var item = graph.get_node_or_null(NodePath(node.id))
		if item != null and item.position_offset != Vector2(node.position[0], node.position[1]):
			positions[node.id] = [item.position_offset.x, item.position_offset.y]
	if positions.is_empty():
		return
	_record()
	for id in positions:
		document.node_by_id(id).position = positions[id]
	_update_state()

func _arrange() -> void:
	_record()
	var ordered = document.ordered_nodes()
	for node in document.data.nodes:
		if not node in ordered:
			ordered.append(node)
	for i in ordered.size():
		ordered[i].position = [40 + i * 280, 150]
	graph.scroll_offset = Vector2.ZERO
	graph.zoom = clampf((graph.size.x - 50) / maxf(1, ordered.size() * 280), 0.3, 1.0)
	_refresh_graph()

func _update_state() -> void:
	project_label.text = document.data.plugin.name if not document.data.plugin.name.is_empty() else "Untitled effect"
	var dirty = document.serialize() != saved_snapshot
	saved_label.text = ("●  Unsaved changes" if dirty else "Saved locally") if not project_path.is_empty() else "●  Unsaved project"
	DisplayServer.window_set_title("%s%s — Signal Foundry" % ["*" if dirty else "", project_label.text])
	var errors = document.validate_graph()
	readiness.text = "●  Graph valid · source export available" if errors.is_empty() else "●  Graph needs attention"
	readiness.add_theme_color_override("font_color", ACCENT if errors.is_empty() else Color("f3bd79"))
	var names = PackedStringArray()
	for node in document.ordered_nodes():
		names.append(FoundryProject.DEFINITIONS[node.type].name)
	chain_label.text = "  →  ".join(names) if errors.is_empty() else errors[0]
	preview.configure(document)
	if not preview.active:
		audition_button.text = "▶  Audition"

func _toggle_audition() -> void:
	if preview.active:
		preview.stop()
		audition_button.text = "▶  Audition"
		return
	if not document.validate_graph().is_empty():
		_check_graph()
		return
	preview.configure(document)
	preview.start()
	audition_button.text = "■  Stop"

func _process(_delta: float) -> void:
	if preview == null or meter == null:
		return
	meter.value = preview.peak
	meter_label.text = "%.1f dBFS" % linear_to_db(preview.peak) if preview.peak > 0.00001 else "−∞ dBFS"
	meter_label.add_theme_color_override("font_color", Color("f3bd79") if preview.peak > 0.95 else ACCENT)

func _check_graph() -> void:
	var errors = document.validate_graph()
	if errors.is_empty():
		_log("PASS · All %d modules form one stereo chain. JUCE source export is available." % document.data.nodes.size(), ACCENT)
	else:
		for error in errors:
			_log(error, Color("f3bd79"))

func _log(message: String, color = MUTED) -> void:
	if log_view.get_line_count() > 120:
		log_view.clear()
	log_view.push_color(color)
	log_view.add_text(Time.get_time_string_from_system() + "  " + message + "\n")
	log_view.pop()

func _save() -> void:
	if project_path.is_empty():
		save_dialog.current_file = document.data.plugin.name.validate_filename() + ".signal.json"
		save_dialog.popup_centered_ratio(0.7)
	else:
		_save_to(project_path)

func _save_to(path: String) -> void:
	if not path.ends_with(".signal.json"):
		path += ".signal.json"
	var error = document.save_file(path)
	if not error.is_empty():
		_log(error, Color("f3bd79"))
		return
	project_path = path
	saved_snapshot = document.serialize()
	_update_state()
	_log("Saved " + path, ACCENT)

func _open_project(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_log("Could not open project: " + error_string(FileAccess.get_open_error()), Color("f3bd79"))
		return
	if file.get_length() > 2_000_000:
		file.close()
		_log("Project exceeds the 2 MB file limit.", Color("f3bd79"))
		return
	var error = document.load_json(file.get_as_text())
	file.close()
	if not error.is_empty():
		_log(error, Color("f3bd79"))
		return
	preview.stop()
	project_path = path
	saved_snapshot = document.serialize()
	history.clear()
	future.clear()
	last_edit_key = ""
	selected_id = ""
	_refresh_graph()
	_refresh_inspector()
	_log("Opened " + path, ACCENT)

func _new_project() -> void:
	preview.stop()
	document.reset()
	project_path = ""
	saved_snapshot = document.serialize()
	history.clear()
	future.clear()
	last_edit_key = ""
	selected_id = "n3"
	_refresh_graph()
	_refresh_inspector()
	_log("New Velvet Drive project.")

func _guard_unsaved(action: Callable) -> void:
	if document.serialize() != saved_snapshot:
		pending_action = action
		confirm.popup_centered()
	else:
		action.call()

func _request_export() -> void:
	if not document.validate_graph().is_empty():
		_check_graph()
		return
	export_dialog.popup_centered_ratio(0.7)

func _export_to(path: String) -> void:
	var error = JuceExporter.write_project(document, path)
	if not error.is_empty():
		_log(error, Color("f3bd79"))
		return
	_log("Exported JUCE source to " + path + ". On Windows run build-windows.ps1 to compile VST3.", ACCENT)
	var dialog = AcceptDialog.new()
	dialog.title = "JUCE source exported"
	dialog.dialog_text = "Source exported to:\n%s\n\nOn Windows, install Visual Studio 2022 C++ tools, CMake and Git.\nRun build-windows.ps1 in the exported folder.\n\nThis export is source code, not a compiled VST3.\nSee the exported README for build and licensing details." % path
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_S: _save()
			KEY_O: _guard_unsaved(func(): open_dialog.popup_centered_ratio(0.7))
			KEY_Z:
				if event.shift_pressed: _redo()
				else: _undo()
			KEY_Y: _redo()
			_: return
		get_viewport().set_input_as_handled()
