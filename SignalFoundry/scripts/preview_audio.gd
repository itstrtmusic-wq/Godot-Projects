class_name FoundryPreview
extends Node

const RATE = 44100.0
var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var chain: Array = []
var phase = 0.0
var frequency = 220.0
var peak = 0.0
var active = false
var lowpass_states: Dictionary = {}
var ramp = 0.0
var trace = PackedFloat32Array()
var topology = ""

func _ready() -> void:
	player = AudioStreamPlayer.new()
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = RATE
	generator.buffer_length = 0.08
	player.stream = generator
	add_child(player)

func configure(project: FoundryProject) -> void:
	chain = project.ordered_nodes().duplicate(true)
	var new_topology = JSON.stringify(project.data.connections)
	if new_topology != topology:
		lowpass_states.clear()
		topology = new_topology
	if not project.validate_graph().is_empty():
		stop()

func start() -> void:
	phase = 0.0
	ramp = 0.0
	lowpass_states.clear()
	player.play()
	playback = player.get_stream_playback()
	active = true

func stop() -> void:
	active = false
	peak = 0.0
	if player != null:
		player.stop()
	playback = null

func _process(_delta: float) -> void:
	if not active or playback == null:
		return
	# Prepare once per buffer. This audition is a reference tone, not a JUCE host.
	var stages = []
	for node in chain:
		match node.type:
			"gain": stages.append(["gain", db_to_linear(node.params.gain_db)])
			"filter": stages.append(["filter", exp(-TAU * minf(node.params.cutoff, RATE * 0.49) / RATE), node.id])
			"saturation": stages.append(["saturation", node.params.drive, node.params.mix, tanh(node.params.drive)])
	var buffer = PackedVector2Array()
	var available = mini(playback.get_frames_available(), 4096)
	buffer.resize(available)
	peak *= 0.9
	for i in available:
		# -18 dBFS input with a little harmonic content, for filter/saturation audition.
		var sample = (sin(phase) + 0.25 * sin(phase * 3.0)) * 0.1
		phase = fmod(phase + TAU * frequency / RATE, TAU)
		for stage in stages:
			match stage[0]:
				"gain": sample *= stage[1]
				"filter":
					sample = (1.0 - stage[1]) * sample + stage[1] * lowpass_states.get(stage[2], 0.0)
					lowpass_states[stage[2]] = sample
				"saturation": sample += stage[2] * (tanh(stage[1] * sample) / stage[3] - sample)
		ramp = minf(1.0, ramp + 1.0 / (RATE * 0.02))
		sample *= ramp
		peak = maxf(peak, absf(sample))
		# Audition limiter only. Exported effects do not hard-clip their output.
		buffer[i] = Vector2.ONE * clampf(sample, -0.95, 0.95)
	playback.push_buffer(buffer)
	if available >= 256:
		trace.resize(256)
		for i in 256:
			trace[i] = buffer[i].x
