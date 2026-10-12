extends Node

signal sample_ready(result: Dictionary, age_seconds: float)
signal status_changed(message: String)

const Pitch = preload("res://scripts/live_pitch.gd")
const WINDOW = 1024
@export_range(-70, -20, 1) var noise_gate_db: float = -45.0
## Software gain before the gate and pitch estimator; does not change Windows settings.
@export_range(0, 30, 1) var input_gain_db: float = 12.0
var periodicity_threshold: float = 0.15

var active: bool = false
var capture: AudioEffectCapture
var input_player: AudioStreamPlayer
var bus_name: String
var _samples = PackedFloat32Array()
var _group_sum: float = 0.0
var _group_count: int = 0
var _since_analysis: int = 0
var _sample_rate: float = 0.0
var _factor: int = 1
var _no_frames_seconds: float = 0.0
var _discarded: int = 0
var _owns_input: bool = false

func start(device: String = "Default") -> bool:
    stop()
    if AudioServer.get_driver_name() == "Dummy":
        status_changed.emit("Microfone indisponível no modo headless")
        return false
    if not ProjectSettings.get_setting("audio/driver/enable_input", false):
        status_changed.emit("Entrada de áudio desativada no projeto")
        return false
    if device not in AudioServer.get_input_device_list():
        status_changed.emit("Dispositivo de entrada não encontrado")
        return false
    AudioServer.input_device = device
    var input_error = AudioServer.set_input_device_active(true)
    if input_error != OK:
        AudioServer.set_input_device_active(false)
        status_changed.emit("Não foi possível abrir o microfone: %s. Confira as permissões do Windows." % error_string(input_error))
        return false
    _owns_input = true
    bus_name = "Microphone_%s" % get_instance_id()
    AudioServer.add_bus()
    var index = AudioServer.bus_count - 1
    AudioServer.set_bus_name(index, bus_name)
    AudioServer.set_bus_send(index, "Master")
    AudioServer.set_bus_volume_linear(index, 0.0)
    capture = AudioEffectCapture.new()
    capture.buffer_length = 0.5
    AudioServer.add_bus_effect(index, capture)
    input_player = AudioStreamPlayer.new()
    input_player.stream = AudioStreamMicrophone.new()
    input_player.bus = bus_name
    add_child(input_player)
    _sample_rate = AudioServer.get_mix_rate()
    _factor = maxi(1, int(round(_sample_rate / 12000.0)))
    active = true
    input_player.play()
    status_changed.emit("Microfone ativo: cante para testar")
    return true

func stop() -> void:
    active = false
    if is_instance_valid(input_player):
        input_player.stop()
        input_player.queue_free()
    input_player = null
    if _owns_input:
        AudioServer.set_input_device_active(false)
        _owns_input = false
    var index = AudioServer.get_bus_index(bus_name) if not bus_name.is_empty() else -1
    if index >= 0:
        AudioServer.remove_bus(index)
    capture = null
    bus_name = ""
    _samples.clear()
    _group_count = 0
    _group_sum = 0
    _since_analysis = 0
    _no_frames_seconds = 0
    _discarded = 0

func _exit_tree() -> void:
    stop()

func discard_pending() -> void:
    _samples.clear()
    _group_sum = 0.0
    _group_count = 0
    _since_analysis = 0
    if capture != null:
        capture.clear_buffer()

func _process(delta: float) -> void:
    if not active or capture == null:
        return
    var available = capture.get_frames_available()
    if available == 0:
        _no_frames_seconds += delta
        if _no_frames_seconds >= 2.0:
            status_changed.emit("Sem entrada: confira o dispositivo e a permissão do Windows")
            sample_ready.emit({"frequency": 0.0, "midi": 0.0, "confidence": 0.0,
                               "rms_db": -120.0}, 0.0)
            _no_frames_seconds = 0
        return
    _no_frames_seconds = 0
    var frames = capture.get_buffer(available)
    var discarded = capture.get_discarded_frames()
    if discarded > _discarded:
        _samples.clear()
        _group_count = 0
        _group_sum = 0
        _since_analysis = 0
        status_changed.emit("Entrada atrasada: amostras perdidas; reduza a carga do sistema")
        _discarded = discarded
    consume_frames(frames, _sample_rate)

func consume_frames(frames: PackedVector2Array, rate: float) -> void:
    if frames.is_empty() or rate <= 0:
        return
    var factor = maxi(1, int(round(rate / 12000.0)))
    if rate != _sample_rate or factor != _factor:
        _samples.clear()
        _group_count = 0
        _group_sum = 0
        _since_analysis = 0
        _sample_rate = rate
        _factor = factor
    # Select the stronger channel, avoiding cancellation or an unused mic channel.
    var left_power: float = 0.0
    var right_power: float = 0.0
    for frame in frames:
        left_power += frame.x * frame.x
        right_power += frame.y * frame.y
    var gain = db_to_linear(input_gain_db)
    for frame in frames:
        _group_sum += (frame.x if left_power >= right_power else frame.y) * gain
        _group_count += 1
        if _group_count == _factor:
            _samples.append(_group_sum / _factor)
            _group_sum = 0
            _group_count = 0
            _since_analysis += 1
    if _samples.size() > WINDOW:
        _samples = _samples.slice(_samples.size() - WINDOW)
    var effective_rate = rate / _factor
    if _samples.size() < WINDOW or _since_analysis < effective_rate * 0.05:
        return
    _since_analysis = 0
    var result = Pitch.estimate(_samples, effective_rate, noise_gate_db, periodicity_threshold)
    sample_ready.emit(result, WINDOW / (2.0 * effective_rate))
