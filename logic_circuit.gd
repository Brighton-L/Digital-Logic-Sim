class_name LogicCircuit
extends RefCounted

const SEGMENTS := ["7SEG_a", "7SEG_b", "7SEG_c", "7SEG_d", "7SEG_e", "7SEG_f", "7SEG_g"]
const MAX_ITERATIONS := 30
const MAX_DEPTH := 10

var gates: Array[Dictionary] = []
var connections: Array[Dictionary] = []
var custom_gates: Array[Dictionary] = []
var inputs: Array[bool] = [false]
var outputs: Array[bool] = [false]
var states: Dictionary = {}
var background_color := Color(0.8, 0.2, 0.3)
var gate_color := Color(0.2, 0.969, 0.365)
var curved_wires := false
var clock_high := false
var project_id := ""
var project_name := ""

func _init() -> void:
	_sync_io()

static func key(gate_id: String, port: String) -> String:
	return gate_id + "_" + port

static func new_id() -> String:
	return str(ResourceUID.create_id())

static func display_port(path: String, segment: String) -> String:
	return "DISPLAY_" + path + "_" + segment

static func display_paths(model: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	for gate in model.get("internalGates", []):
		if gate.get("type", "") == "7SEG":
			paths.append(str(gate["id"]))
		elif gate.get("type", "") == "COMPOSITE":
			for child_path in display_paths(gate.get("composite", {})):
				paths.append(str(gate["id"]) + "/" + child_path)
	return paths

static func ports(gate: Dictionary) -> Dictionary:
	match gate.get("type", ""):
		"AND": return {"inputs": ["AND_left_top", "AND_left_bottom"], "outputs": ["AND_right"]}
		"NOT": return {"inputs": ["NOT_left"], "outputs": ["NOT_right"]}
		"CLK": return {"inputs": [], "outputs": ["CLK_out"]}
		"7SEG": return {"inputs": SEGMENTS.duplicate(), "outputs": []}
		"COMPOSITE":
			var model: Dictionary = gate.get("composite", {})
			return {"inputs": model.get("inputIDs", []), "outputs": model.get("outputIDs", [])}
	return {"inputs": [], "outputs": []}

func add_gate(type: String, at: Vector2, composite: Dictionary = {}) -> Dictionary:
	var gate := {"id": new_id(), "type": type, "x": at.x, "y": at.y}
	if type == "COMPOSITE":
		gate["composite"] = composite.duplicate(true)
	gates.append(gate)
	for port in ports(gate)["inputs"] + ports(gate)["outputs"]:
		states[key(gate["id"], port)] = false
	return gate

func remove_gate(gate_id: String) -> void:
	gates = gates.filter(func(g: Dictionary) -> bool: return g["id"] != gate_id)
	connections = connections.filter(func(c: Dictionary) -> bool: return c["fromGate"] != gate_id and c["toGate"] != gate_id)
	for state_key in states.keys():
		if String(state_key).begins_with(gate_id + "_"):
			states.erase(state_key)
	simulate()

func connect_ports(from_gate: String, from_port: String, to_gate: String, to_port: String) -> bool:
	if from_gate == to_gate and from_port == to_port:
		return false
	var from_key := key(from_gate, from_port) if not from_gate.begins_with("INPUT_") else from_gate + "_input"
	var to_key := key(to_gate, to_port) if not to_gate.begins_with("OUTPUT_") else to_gate + "_output"
	for connection in connections:
		if connection["fromNub"] == from_key and connection["toNub"] == to_key:
			return false
	# An input port has one driver. Replace its previous wire.
	connections = connections.filter(func(c: Dictionary) -> bool: return c["toNub"] != to_key)
	connections.append({"id": new_id(), "fromGate": from_gate, "fromNub": from_key, "toGate": to_gate, "toNub": to_key})
	simulate()
	return true

func set_input(index: int, value: bool) -> void:
	if index < 0 or index >= inputs.size():
		return
	inputs[index] = value
	states["INPUT_%d_input" % index] = value
	simulate()

func resize_inputs(count: int) -> void:
	count = clampi(count, 1, 18)
	inputs.resize(count)
	for i in range(count):
		states["INPUT_%d_input" % i] = inputs[i]
	_clean_io_connections()
	simulate()

func resize_outputs(count: int) -> void:
	count = clampi(count, 1, 18)
	outputs.resize(count)
	for i in range(count):
		states["OUTPUT_%d_output" % i] = false
	_clean_io_connections()
	simulate()

func _sync_io() -> void:
	for i in range(inputs.size()):
		states["INPUT_%d_input" % i] = inputs[i]
	for i in range(outputs.size()):
		states["OUTPUT_%d_output" % i] = outputs[i]

func _clean_io_connections() -> void:
	var allowed: Dictionary = {}
	for i in range(inputs.size()):
		allowed["INPUT_%d" % i] = true
	for i in range(outputs.size()):
		allowed["OUTPUT_%d" % i] = true
	connections = connections.filter(func(c: Dictionary) -> bool:
		return (not String(c["fromGate"]).begins_with("INPUT_") or allowed.has(c["fromGate"])) and (not String(c["toGate"]).begins_with("OUTPUT_") or allowed.has(c["toGate"]))
	)
	for state_key in states.keys():
		if String(state_key).begins_with("INPUT_") or String(state_key).begins_with("OUTPUT_"):
			states.erase(state_key)
	_sync_io()

func tick_clocks() -> void:
	clock_high = not clock_high
	simulate()

func simulate() -> void:
	# Rebuild driven inputs so deleting a wire cannot leave a stale high signal.
	for gate in gates:
		var gate_ports: Dictionary = ports(gate)
		for port in gate_ports["inputs"] + gate_ports["outputs"]:
			states[key(gate["id"], port)] = false
		if gate["type"] == "COMPOSITE" and gate.get("composite", {}).get("contains7Segment", false):
			for path in display_paths(gate.get("composite", {})):
				for segment in SEGMENTS:
					states[key(gate["id"], display_port(path, segment))] = false
			for segment in SEGMENTS:
				states[key(gate["id"], segment)] = false
	for i in range(outputs.size()):
		states["OUTPUT_%d_output" % i] = false
	for i in range(inputs.size()):
		states["INPUT_%d_input" % i] = inputs[i]
	states = _settle(gates, connections, states, 0, clock_high)
	for i in range(inputs.size()):
		states["INPUT_%d_input" % i] = inputs[i]
	for i in range(outputs.size()):
		outputs[i] = states.get("OUTPUT_%d_output" % i, false)

static func _settle(local_gates: Array, local_connections: Array, initial: Dictionary, depth: int, clock_value: bool) -> Dictionary:
	if depth > MAX_DEPTH:
		return initial.duplicate()
	var current := initial.duplicate()
	for _step in range(MAX_ITERATIONS):
		var next := current.duplicate()
		for gate in local_gates:
			var id: String = gate.get("id", "")
			match gate.get("type", ""):
				"AND": next[key(id, "AND_right")] = bool(current.get(key(id, "AND_left_top"), false)) and bool(current.get(key(id, "AND_left_bottom"), false))
				"NOT": next[key(id, "NOT_right")] = not bool(current.get(key(id, "NOT_left"), false))
				"CLK": next[key(id, "CLK_out")] = clock_value
				"COMPOSITE":
					var model: Dictionary = gate.get("composite", {})
					var external: Dictionary = {}
					for port in model.get("inputIDs", []):
						external[port] = current.get(key(id, port), false)
					var result := simulate_composite(model, external, depth + 1, clock_value)
					for port in model.get("outputIDs", []):
						next[key(id, port)] = result.get(port, false)
					if model.get("contains7Segment", false):
						for path in display_paths(model):
							for segment in SEGMENTS:
								next[key(id, display_port(path, segment))] = result.get(display_port(path, segment), false)
						for segment in SEGMENTS:
							next[key(id, segment)] = result.get(segment, false)
		for connection in local_connections:
			next[connection["toNub"]] = next.get(connection["fromNub"], false)
		if next == current:
			break
		current = next
	return current

static func simulate_composite(model: Dictionary, external: Dictionary, depth: int = 0, clock_value: bool = false) -> Dictionary:
	if depth > MAX_DEPTH:
		return {}
	var internal: Dictionary = model.get("initialNubStates", {}).duplicate(true)
	for port in model.get("inputIDs", []):
		internal[port] = external.get(port, false)
	var result := _settle(model.get("internalGates", []), model.get("internalConnections", []), internal, depth, clock_value)
	var outputs_found: Dictionary = {}
	for port in model.get("outputIDs", []):
		outputs_found[port] = result.get(port, false)
	if model.get("contains7Segment", false):
		for gate in model.get("internalGates", []):
			var gate_id: String = str(gate["id"])
			if gate.get("type", "") == "7SEG":
				for segment in SEGMENTS:
					outputs_found[display_port(gate_id, segment)] = result.get(key(gate_id, segment), false)
			elif gate.get("type", "") == "COMPOSITE":
				for child_path in display_paths(gate.get("composite", {})):
					for segment in SEGMENTS:
						outputs_found[display_port(gate_id + "/" + child_path, segment)] = result.get(key(gate_id, display_port(child_path, segment)), false)
		var paths := display_paths(model)
		if not paths.is_empty():
			for segment in SEGMENTS:
				outputs_found[segment] = outputs_found.get(display_port(paths[0], segment), false)
	return outputs_found

func encapsulate(name: String, color: Color = Color(0.2, 0.969, 0.365)) -> bool:
	if name.strip_edges().is_empty() or gates.is_empty():
		return false
	var input_ids: Array[String] = []
	var output_ids: Array[String] = []
	for i in range(inputs.size()):
		var port := "INPUT_%d_input" % i
		if connections.any(func(c: Dictionary) -> bool: return c["fromNub"] == port):
			input_ids.append(port)
	for i in range(outputs.size()):
		var port := "OUTPUT_%d_output" % i
		if connections.any(func(c: Dictionary) -> bool: return c["toNub"] == port):
			output_ids.append(port)
	if input_ids.is_empty() and output_ids.is_empty():
		return false
	var has_segment := gates.any(func(g: Dictionary) -> bool: return g["type"] == "7SEG" or (g["type"] == "COMPOSITE" and g.get("composite", {}).get("contains7Segment", false)))
	var model := {"name": name.strip_edges(), "color": color.to_html(), "inputIDs": input_ids, "outputIDs": output_ids, "contains7Segment": has_segment, "internalGates": gates.duplicate(true), "internalConnections": connections.duplicate(true), "initialNubStates": states.duplicate(true)}
	custom_gates.append(model.duplicate(true))
	gates.clear()
	connections.clear()
	states.clear()
	_sync_io()
	add_gate("COMPOSITE", Vector2(480, 320), model)
	simulate()
	return true

func to_dict() -> Dictionary:
	return {"id": project_id, "name": project_name, "gates": gates.duplicate(true), "connections": connections.duplicate(true), "customGates": custom_gates.duplicate(true), "inputStates": inputs.duplicate(), "outputStates": outputs.duplicate(), "nubStates": states.duplicate(true), "colorR": background_color.r, "colorG": background_color.g, "colorB": background_color.b, "gateColor": gate_color.to_html(), "useCurvedLines": curved_wires, "clockHigh": clock_high}

func load_dict(data: Dictionary) -> void:
	project_id = str(data.get("id", ""))
	project_name = str(data.get("name", ""))
	gates.assign(data.get("gates", []))
	connections.assign(data.get("connections", []))
	custom_gates.assign(data.get("customGates", []))
	inputs.assign(data.get("inputStates", [false]))
	outputs.assign(data.get("outputStates", [false]))
	states = data.get("nubStates", {}).duplicate(true)
	background_color = Color(float(data.get("colorR", 0.8)), float(data.get("colorG", 0.2)), float(data.get("colorB", 0.3)))
	gate_color = Color.html(str(data.get("gateColor", "34f75d")))
	curved_wires = data.get("useCurvedLines", false)
	clock_high = bool(data.get("clockHigh", false))
	_sync_io()
	simulate()
