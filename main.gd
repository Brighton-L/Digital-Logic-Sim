extends Control

const Circuit = preload("res://logic_circuit.gd")
const PROJECT_DIR := "user://projects"
const ON_COLOR := Color(1.0, 0.27, 0.28)
const OFF_COLOR := Color(0.12, 0.14, 0.19)
const TEXT_COLOR := Color(0.95, 0.97, 1.0)

var circuit = Circuit.new()
var port_positions: Dictionary = {}
var port_directions: Dictionary = {}
var selected_port := ""
var pointer_position := Vector2.ZERO
var dragging_gate := ""
var drag_offset := Vector2.ZERO
var right_held := false
var zoom := 1.0
var last_save := 0.0
var canvas: Control
var top_background: ColorRect
var bottom_background: ColorRect
var gate_bar: HBoxContainer
var save_dialog: ConfirmationDialog
var projects_dialog: AcceptDialog
var settings_dialog: AcceptDialog
var name_edit: LineEdit
var settings_color_picker: ColorPickerButton
var settings_curved: CheckBox

func _ready() -> void:
	_build_ui()
	_refresh_custom_buttons()
	_refresh_theme()
	var clock := Timer.new()
	clock.wait_time = 1.0
	clock.autostart = true
	clock.timeout.connect(func() -> void:
		circuit.tick_clocks()
		canvas.queue_redraw()
	)
	add_child(clock)
	var autosave := Timer.new()
	autosave.wait_time = 10.0
	autosave.autostart = true
	autosave.timeout.connect(func() -> void:
		if not circuit.project_id.is_empty():
			_save_current()
	)
	add_child(autosave)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.15, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	top_background = ColorRect.new()
	top_background.anchor_right = 1.0
	top_background.offset_bottom = 62
	top_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_background)
	var top := HBoxContainer.new()
	top.anchor_right = 1.0
	top.offset_left = 12
	top.offset_top = 8
	top.offset_right = -12
	top.offset_bottom = 54
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	_button(top, "Projects", _show_projects)
	_button(top, "Save Project", _show_save)
	_button(top, "Create Gate", _show_create_gate)
	_button(top, "Settings", _show_settings)
	canvas = Control.new()
	canvas.anchor_right = 1.0
	canvas.anchor_bottom = 1.0
	canvas.offset_top = 62
	canvas.offset_bottom = -92
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_on_canvas_input)
	canvas.resized.connect(func() -> void: canvas.queue_redraw())
	add_child(canvas)
	bottom_background = ColorRect.new()
	bottom_background.anchor_top = 1.0
	bottom_background.anchor_right = 1.0
	bottom_background.anchor_bottom = 1.0
	bottom_background.offset_top = -92
	bottom_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_background)
	var scroller := ScrollContainer.new()
	scroller.anchor_top = 1.0
	scroller.anchor_right = 1.0
	scroller.anchor_bottom = 1.0
	scroller.offset_left = 12
	scroller.offset_top = -82
	scroller.offset_right = -12
	scroller.offset_bottom = -5
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroller)
	gate_bar = HBoxContainer.new()
	gate_bar.add_theme_constant_override("separation", 10)
	scroller.add_child(gate_bar)
	for type in ["AND", "NOT", "CLK", "7SEG"]:
		var gate_type: String = type
		var button := _button(gate_bar, "7-Segment" if type == "7SEG" else type, func() -> void:
			circuit.add_gate(gate_type, Vector2(canvas.size.x * 0.5, canvas.size.y * 0.5))
			circuit.simulate()
			canvas.queue_redraw()
		)
		_style_gate_button(button, _gate_color_for_type(type))
	_make_dialogs()

func _button(parent: Node, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _draw_canvas() -> void:
	port_positions.clear()
	port_directions.clear()
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), circuit.background_color.lightened(0.35))
	var bar_color: Color = _bar_color()
	canvas.draw_rect(Rect2(0, 0, 100, canvas.size.y), bar_color)
	canvas.draw_rect(Rect2(canvas.size.x - 100, 0, 100, canvas.size.y), bar_color)
	_draw_io_controls(28.0)
	_draw_io_controls(canvas.size.x - 72.0)
	for i in range(circuit.inputs.size()):
		var p := Vector2(132, _io_y(i, circuit.inputs.size()))
		var bulb := Vector2(84, p.y)
		var id := "INPUT_%d_input" % i
		port_positions[id] = p
		port_directions[id] = "output"
		canvas.draw_rect(Rect2(bulb.x, p.y - 15, p.x - bulb.x, 30), Color.BLACK)
		canvas.draw_circle(bulb, 20, ON_COLOR if circuit.inputs[i] else Color.BLACK)
		_draw_port(id, p)
	for i in range(circuit.outputs.size()):
		var p := Vector2(canvas.size.x - 132, _io_y(i, circuit.outputs.size()))
		var bulb := Vector2(canvas.size.x - 84, p.y)
		var id := "OUTPUT_%d_output" % i
		port_positions[id] = p
		port_directions[id] = "input"
		canvas.draw_rect(Rect2(p.x, p.y - 15, bulb.x - p.x, 30), Color.BLACK)
		canvas.draw_circle(bulb, 20, ON_COLOR if circuit.outputs[i] else Color.BLACK)
		_draw_port(id, p)
	for gate in circuit.gates:
		_draw_gate(gate)
	for connection in circuit.connections:
		var a: Vector2 = port_positions.get(connection["fromNub"], Vector2.ZERO)
		var b: Vector2 = port_positions.get(connection["toNub"], Vector2.ZERO)
		if not port_positions.has(connection["fromNub"]) or not port_positions.has(connection["toNub"]):
			continue
		_draw_wire(a, b, ON_COLOR if circuit.states.get(connection["fromNub"], false) else OFF_COLOR)
	if not selected_port.is_empty() and port_positions.has(selected_port):
		var start: Vector2 = port_positions[selected_port]
		if port_directions[selected_port] == "input":
			_draw_wire(pointer_position, start, ON_COLOR if circuit.states.get(selected_port, false) else OFF_COLOR)
		else:
			_draw_wire(start, pointer_position, ON_COLOR if circuit.states.get(selected_port, false) else OFF_COLOR)

func _draw_io_controls(start_x: float) -> void:
	for i in range(2):
		var center := Vector2(start_x + i * 42.0, 28)
		canvas.draw_circle(center, 15, Color.BLACK)
		var symbol := "+" if i == 0 else "−"
		canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-5, 6), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

func _draw_wire(a: Vector2, b: Vector2, color: Color) -> void:
	if circuit.curved_wires:
		canvas.draw_polyline(_wire_points(a, b), color, 2.5, true)
	else:
		canvas.draw_line(a, b, color, 2.5, true)

func _wire_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var curve := PackedVector2Array()
	var control := minf(80.0, a.distance_to(b) * 0.4)
	for step in range(17):
		var t := step / 16.0
		var u := 1.0 - t
		curve.append(u * u * u * a + 3 * u * u * t * (a + Vector2(control, 0)) + 3 * u * t * t * (b - Vector2(control, 0)) + t * t * t * b)
	return curve

func _io_y(i: int, count: int) -> float:
	return 62.0 + (i + 1) * (canvas.size.y - 110.0) / (count + 1.0)

func _draw_gate(gate: Dictionary) -> void:
	var pos := Vector2(float(gate.get("x", 0)), float(gate.get("y", 0)))
	var type: String = gate.get("type", "")
	var size := _gate_size(gate)
	var rect := Rect2(pos - size * 0.5, size)
	var color: Color = Color.html(str(gate.get("composite", {}).get("color", circuit.gate_color.to_html()))) if type == "COMPOSITE" else _gate_color_for_type(type)
	canvas.draw_rect(rect, color)
	canvas.draw_rect(rect, Color(0.08, 0.1, 0.15), false, 2.0)
	var title: String = gate.get("composite", {}).get("name", "Custom") if type == "COMPOSITE" else type
	canvas.draw_string(ThemeDB.fallback_font, pos + Vector2(-size.x * 0.5 + 12, -size.y * 0.5 + 22), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 15, TEXT_COLOR)
	var ports: Dictionary = Circuit.ports(gate)
	var ins: Array = ports["inputs"]
	var outs: Array = ports["outputs"]
	for i in range(ins.size()):
		var id := Circuit.key(gate["id"], ins[i])
		var p := Vector2(rect.position.x, rect.position.y + size.y * (i + 1) / (ins.size() + 1))
		port_positions[id] = p
		port_directions[id] = "input"
		_draw_port(id, p)
	for i in range(outs.size()):
		var id := Circuit.key(gate["id"], outs[i])
		var p := Vector2(rect.end.x, rect.position.y + size.y * (i + 1) / (outs.size() + 1))
		port_positions[id] = p
		port_directions[id] = "output"
		_draw_port(id, p)
	if type == "7SEG":
		_draw_segments(gate["id"], Rect2(rect.position + Vector2(44, 36), Vector2(size.x - 57, size.y - 47)))
	elif type == "COMPOSITE":
		var paths := Circuit.display_paths(gate.get("composite", {}))
		var mini_size := Vector2(28, 38) * zoom
		var gap := 7.0 * zoom
		var columns: int = mini(4, paths.size())
		var grid_width := columns * mini_size.x + maxi(0, columns - 1) * gap
		var start_x := rect.position.x + (rect.size.x - grid_width) * 0.5
		for i in range(paths.size()):
			var mini_pos := Vector2(start_x + (i % 4) * (mini_size.x + gap), rect.position.y + 31 * zoom + int(i / 4.0) * 47 * zoom)
			canvas.draw_rect(Rect2(mini_pos - Vector2(2, 2) * zoom, mini_size + Vector2(4, 4) * zoom), Color(0.1, 0.12, 0.16, 0.6))
			_draw_segments(gate["id"], Rect2(mini_pos, mini_size), paths[i])

func _gate_size(gate: Dictionary) -> Vector2:
	match gate.get("type", ""):
		"7SEG": return Vector2(155, 235) * zoom
		"COMPOSITE":
			var ports: Dictionary = Circuit.ports(gate)
			var count: int = maxi(ports["inputs"].size(), ports["outputs"].size())
			var display_count: int = Circuit.display_paths(gate.get("composite", {})).size()
			var rows: int = int(ceil(display_count / 4.0))
			return Vector2(155, maxi(maxi(80, 48 + count * 21), 36 + rows * 47)) * zoom
	return Vector2(110, 58) * zoom

func _draw_port(id: String, pos: Vector2) -> void:
	canvas.draw_circle(pos, 8, ON_COLOR if circuit.states.get(id, false) else OFF_COLOR)

func _draw_segments(gate_id: String, rect: Rect2, path: String = "") -> void:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var thick := maxf(2.0, minf(w, h) * 0.11)
	var pad := w * 0.16
	var top_half := (h - 3 * thick) * 0.5
	var bars := {
		"7SEG_a": Rect2(x + pad, y, w - 2 * pad, thick),
		"7SEG_b": Rect2(x + w - thick, y + thick, thick, top_half),
		"7SEG_c": Rect2(x + w - thick, y + h * 0.5 + thick * 0.5, thick, top_half),
		"7SEG_d": Rect2(x + pad, y + h - thick, w - 2 * pad, thick),
		"7SEG_e": Rect2(x, y + h * 0.5 + thick * 0.5, thick, top_half),
		"7SEG_f": Rect2(x, y + thick, thick, top_half),
		"7SEG_g": Rect2(x + pad, y + h * 0.5 - thick * 0.5, w - 2 * pad, thick)
	}
	for segment in Circuit.SEGMENTS:
		var state_port: String = Circuit.display_port(path, segment) if not path.is_empty() else segment
		canvas.draw_rect(bars[segment], ON_COLOR if circuit.states.get(Circuit.key(gate_id, state_port), false) else Color(0.36, 0.36, 0.4))

func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		pointer_position = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = minf(2.0, zoom * 1.1)
			canvas.queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = maxf(0.5, zoom / 1.1)
			canvas.queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_press(event.position)
			else:
				dragging_gate = ""
		if event.button_index == MOUSE_BUTTON_RIGHT:
			right_held = event.pressed
			if right_held:
				selected_port = ""
				_erase_at(event.position)
	elif event is InputEventMouseMotion:
		pointer_position = event.position
		if right_held:
			_erase_at(event.position)
		elif not dragging_gate.is_empty():
			for gate in circuit.gates:
				if gate["id"] == dragging_gate:
					var new_pos: Vector2 = event.position + drag_offset
					gate["x"] = clampf(new_pos.x, 170, canvas.size.x - 170)
					gate["y"] = clampf(new_pos.y, 45, canvas.size.y - 45)
					canvas.queue_redraw()
					break
		elif not selected_port.is_empty():
			canvas.queue_redraw()

func _handle_press(pos: Vector2) -> void:
	for i in range(2):
		if pos.distance_to(Vector2(28 + i * 42, 28)) <= 16:
			circuit.resize_inputs(circuit.inputs.size() + (1 if i == 0 else -1))
			canvas.queue_redraw()
			return
		if pos.distance_to(Vector2(canvas.size.x - 72 + i * 42, 28)) <= 16:
			circuit.resize_outputs(circuit.outputs.size() + (1 if i == 0 else -1))
			canvas.queue_redraw()
			return
	for id in port_positions:
		if pos.distance_to(port_positions[id]) <= 13:
			_select_port(id)
			return
	for i in range(circuit.inputs.size()):
		if pos.distance_to(Vector2(84, _io_y(i, circuit.inputs.size()))) <= 21:
			circuit.set_input(i, not circuit.inputs[i])
			canvas.queue_redraw()
			return
	for gate in circuit.gates:
		if Rect2(Vector2(gate["x"], gate["y"]) - _gate_size(gate) * 0.5, _gate_size(gate)).has_point(pos):
			dragging_gate = gate["id"]
			drag_offset = Vector2(gate["x"], gate["y"]) - pos
			return
	selected_port = ""
	canvas.queue_redraw()

func _erase_at(pos: Vector2) -> void:
	for gate in circuit.gates.duplicate():
		if Rect2(Vector2(gate["x"], gate["y"]) - _gate_size(gate) * 0.5, _gate_size(gate)).has_point(pos):
			circuit.remove_gate(gate["id"])
			canvas.queue_redraw()
			return
	for connection in circuit.connections.duplicate():
		if _wire_hit(connection, pos):
			circuit.connections.erase(connection)
			circuit.simulate()
			canvas.queue_redraw()
			return

func _select_port(id: String) -> void:
	if selected_port.is_empty():
		selected_port = id
	elif selected_port == id:
		selected_port = ""
	else:
		var source := selected_port if port_directions[selected_port] == "output" else id
		var target := id if source == selected_port else selected_port
		if port_directions[source] == "output" and port_directions[target] == "input":
			var source_gate := _gate_from_port(source)
			var target_gate := _gate_from_port(target)
			circuit.connect_ports(source_gate, _port_suffix(source, source_gate), target_gate, _port_suffix(target, target_gate))
		selected_port = ""
	canvas.queue_redraw()

func _gate_from_port(port: String) -> String:
	if port.begins_with("INPUT_") or port.begins_with("OUTPUT_"):
		return port.substr(0, port.rfind("_"))
	for gate in circuit.gates:
		if port.begins_with(gate["id"] + "_"):
			return gate["id"]
	return ""

func _port_suffix(port: String, gate_id: String) -> String:
	return port.trim_prefix(gate_id + "_")

func _wire_hit(connection: Dictionary, pos: Vector2) -> bool:
	if not port_positions.has(connection["fromNub"]) or not port_positions.has(connection["toNub"]):
		return false
	var a: Vector2 = port_positions[connection["fromNub"]]
	var b: Vector2 = port_positions[connection["toNub"]]
	var points := _wire_points(a, b) if circuit.curved_wires else PackedVector2Array([a, b])
	for i in range(points.size() - 1):
		if Geometry2D.get_closest_point_to_segment(pos, points[i], points[i + 1]).distance_to(pos) < 9:
			return true
	return false

func _make_dialogs() -> void:
	save_dialog = ConfirmationDialog.new()
	save_dialog.title = "Save Project"
	var save_box := VBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Project name"
	save_box.add_child(name_edit)
	save_dialog.add_child(save_box)
	save_dialog.confirmed.connect(func() -> void:
		if not name_edit.text.strip_edges().is_empty():
			circuit.project_name = name_edit.text.strip_edges()
			if circuit.project_id.is_empty(): circuit.project_id = Circuit.new_id()
			_save_current()
	)
	add_child(save_dialog)
	projects_dialog = AcceptDialog.new()
	projects_dialog.title = "Projects"
	add_child(projects_dialog)
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = "Settings"
	var settings_box := VBoxContainer.new()
	settings_box.custom_minimum_size = Vector2(360, 0)
	settings_box.add_child(_heading("Background color"))
	settings_color_picker = ColorPickerButton.new()
	settings_color_picker.color = circuit.background_color
	settings_color_picker.color_changed.connect(func(color: Color) -> void: circuit.background_color = color; _refresh_theme())
	settings_box.add_child(settings_color_picker)
	settings_curved = CheckBox.new()
	settings_curved.text = "Use curved wires"
	settings_curved.toggled.connect(func(value: bool) -> void: circuit.curved_wires = value; canvas.queue_redraw())
	settings_box.add_child(settings_curved)
	settings_dialog.add_child(settings_box)
	add_child(settings_dialog)

func _heading(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label

func _show_save() -> void:
	name_edit.text = circuit.project_name
	save_dialog.popup_centered(Vector2i(380, 150))

func _show_projects() -> void:
	for child in projects_dialog.get_children():
		if child is VBoxContainer:
			child.queue_free()
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(390, 0)
	_button(list, "New Project", func() -> void:
		circuit = Circuit.new()
		_refresh_custom_buttons()
		_refresh_theme()
		projects_dialog.hide()
	)
	var directory := DirAccess.open(PROJECT_DIR)
	if directory:
		for filename in directory.get_files():
			if not filename.ends_with(".json"): continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROJECT_DIR.path_join(filename)))
			if data is Dictionary:
				var path := PROJECT_DIR.path_join(filename)
				var row := HBoxContainer.new()
				list.add_child(row)
				_button(row, str(data.get("name", "Untitled")), func() -> void:
					_load_project(path)
					projects_dialog.hide()
				)
				_button(row, "Delete", func() -> void:
					DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
					_show_projects()
				)
	projects_dialog.add_child(list)
	projects_dialog.popup_centered(Vector2i(430, 400))

func _show_create_gate() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Create Gate"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(350, 0)
	var input := LineEdit.new()
	input.placeholder_text = "Gate name"
	box.add_child(input)
	box.add_child(_heading("Gate color"))
	var color_picker := ColorPickerButton.new()
	color_picker.color = circuit.gate_color
	box.add_child(color_picker)
	dialog.add_child(box)
	dialog.confirmed.connect(func() -> void:
		if circuit.encapsulate(input.text, color_picker.color):
			circuit.gate_color = color_picker.color
			_refresh_custom_buttons()
			canvas.queue_redraw()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(390, 190))

func _show_settings() -> void:
	settings_color_picker.color = circuit.background_color
	settings_curved.button_pressed = circuit.curved_wires
	settings_dialog.popup_centered(Vector2i(420, 240))

func _refresh_custom_buttons() -> void:
	for child in gate_bar.get_children():
		if child.has_meta("custom_gate_button"):
			child.queue_free()
	for model in circuit.custom_gates:
		var saved_model: Dictionary = model
		var button := _button(gate_bar, str(model.get("name", "Custom")), func() -> void:
			circuit.add_gate("COMPOSITE", Vector2(canvas.size.x * 0.5, canvas.size.y * 0.5), saved_model)
			canvas.queue_redraw()
		)
		button.set_meta("custom_gate_button", true)
		_style_gate_button(button, Color.html(str(model.get("color", circuit.gate_color.to_html()))))

func _bar_color() -> Color:
	return circuit.background_color.lightened(0.22)

func _refresh_theme() -> void:
	top_background.color = _bar_color()
	bottom_background.color = _bar_color()
	canvas.queue_redraw()

func _gate_color_for_type(type: String) -> Color:
	match type:
		"CLK": return Color(0.96, 0.53, 0.17)
		"7SEG": return Color(0.18, 0.21, 0.28)
	return Color(0.22, 0.45, 0.82)

func _style_gate_button(button: Button, color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(7)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.15)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.17)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

func _save_current() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROJECT_DIR))
	var path := PROJECT_DIR.path_join(circuit.project_id + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(circuit.to_dict(), "\t"))
		file.close()
		last_save = Time.get_unix_time_from_system()

func _load_project(path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		circuit.load_dict(data)
		_refresh_custom_buttons()
		_refresh_theme()
