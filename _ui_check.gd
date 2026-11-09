extends SceneTree
func _initialize() -> void:
	call_deferred("check")
func check() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	assert(scene.top_background.color == scene.bottom_background.color)
	assert(scene.gate_bar.get_child_count() == 4)
	assert(scene.settings_dialog.get_children().size() > 0)
	assert(scene.get_node_or_null("Delete") == null)
	var canvas = scene.canvas
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(28, 28)
	canvas.gui_input.emit(click)
	assert(scene.circuit.inputs.size() == 2)
	click.position = Vector2(84, scene._io_y(0, 2))
	canvas.gui_input.emit(click)
	assert(scene.circuit.inputs[0])
	var gate = scene.circuit.add_gate("AND", Vector2(400, 250))
	var erase = InputEventMouseButton.new()
	erase.button_index = MOUSE_BUTTON_RIGHT
	erase.pressed = true
	erase.position = Vector2(400, 250)
	canvas.gui_input.emit(erase)
	assert(scene.circuit.gates.is_empty())
	var display_a = scene.circuit.add_gate("7SEG", Vector2.ZERO)
	var display_b = scene.circuit.add_gate("7SEG", Vector2.ZERO)
	scene.circuit.connect_ports("INPUT_0", "input", display_a["id"], "7SEG_a")
	scene.circuit.connect_ports("INPUT_1", "input", display_b["id"], "7SEG_b")
	assert(scene.circuit.encapsulate("Two displays"))
	var composite = scene.circuit.gates[0]
	assert(scene._gate_size(composite).y < scene._gate_size(display_a).y)
	assert(scene._gate_size(composite).y < scene._gate_size(display_b).y)
	print("UI_CHECK_OK")
	quit()
