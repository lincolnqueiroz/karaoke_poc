extends Control

signal back_requested
const Capture = preload("res://scripts/microphone_capture.gd")
const Trace = preload("res://scripts/microphone_trace.gd")
const Neon = preload("res://scripts/neon_theme.gd")
var device: String = "Default"
var gain_db: float = 12.0
var gate_db: float = -45.0
var threshold: float = 0.15
var microphone: Node
var trace: Control
var feedback: Label
var toggle: Button
var _started_at: int

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(Neon.background())
    var margin = MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "top", "right", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 32)
    add_child(margin)
    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 16)
    margin.add_child(box)
    var title = Label.new()
    title.text = "TESTAR MICROFONE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    Neon.title(title, Neon.GREEN)
    box.add_child(title)
    var hint = Label.new()
    hint.text = "Cante livremente. O traço verde mostra sua voz: grave embaixo, aguda em cima."
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(hint)
    var input = Label.new()
    input.text = "Microfone: %s · ganho: +%.0f dB" % [device, gain_db]
    input.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(input)
    trace = Trace.new()
    trace.custom_minimum_size.y = 220
    trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(trace)
    feedback = Label.new()
    feedback.custom_minimum_size.y = 48
    feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(feedback)
    var buttons = HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 16)
    box.add_child(buttons)
    toggle = Button.new()
    toggle.text = "DESATIVAR MICROFONE"
    toggle.custom_minimum_size.y = 52
    toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    buttons.add_child(toggle)
    toggle.pressed.connect(toggle_capture)
    var back = Button.new()
    back.text = "VOLTAR"
    back.custom_minimum_size.y = 52
    back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    buttons.add_child(back)
    back.pressed.connect(func():
        microphone.stop()
        back_requested.emit())
    microphone = Capture.new()
    microphone.input_gain_db = gain_db
    microphone.noise_gate_db = gate_db
    microphone.periodicity_threshold = threshold
    add_child(microphone)
    microphone.sample_ready.connect(receive)
    microphone.status_changed.connect(func(text): feedback.text = text)
    _started_at = Time.get_ticks_msec()
    start_capture()

func elapsed() -> float:
    return (Time.get_ticks_msec() - _started_at) / 1000.0

func _process(_delta: float) -> void:
    trace.advance(elapsed())

func start_capture() -> void:
    trace.clear()
    toggle.text = "DESATIVAR MICROFONE" if microphone.start(device) else "TENTAR NOVAMENTE"

func toggle_capture() -> void:
    if microphone.active:
        microphone.stop()
        trace.clear()
        feedback.text = "Microfone desligado."
        toggle.text = "ATIVAR MICROFONE"
    else:
        start_capture()

func receive(sample: Dictionary, age: float) -> void:
    trace.record(sample, elapsed() - age)
    if sample.frequency > 0:
        var midi = int(round(float(sample.midi)))
        var names = ["Dó", "Dó#", "Ré", "Ré#", "Mi", "Fá", "Fá#", "Sol", "Sol#", "Lá", "Lá#", "Si"]
        feedback.text = "Voz: %s%d · %.0f Hz · nível %.0f dB (com ganho)" % [names[posmod(midi, 12)], int(floor(midi / 12.0)) - 1, sample.frequency, sample.rms_db]
    elif sample.rms_db <= -119:
        feedback.text = "Sem sinal: confira o dispositivo e as permissões do microfone."
    elif sample.rms_db < microphone.noise_gate_db:
        feedback.text = "Entrada baixa · nível %.0f dB" % sample.rms_db
    else:
        feedback.text = "Entrada detectada, sem pitch estável · nível %.0f dB" % sample.rms_db
    if sample.rms_db > -3:
        feedback.text += " · nível alto: reduza o ganho"

func _exit_tree() -> void:
    if is_instance_valid(microphone):
        microphone.stop()
