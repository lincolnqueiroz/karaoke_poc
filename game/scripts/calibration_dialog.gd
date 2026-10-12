extends Window

signal calibrated(profile: Dictionary)
const Capture = preload("res://scripts/microphone_capture.gd")
const Calibration = preload("res://scripts/microphone_calibration.gd")
var device: String = "Default"
var microphone: Node
var message: Label
var action: Button
var phase: String = ""
var remaining: float = 0
var silence: Array = []
var voice: Array = []
var profile: Dictionary = {}

func _ready() -> void:
    title = "Calibrar microfone"
    size = Vector2i(540, 300)
    unresizable = true
    exclusive = true
    var margin = MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "top", "right", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 24)
    add_child(margin)
    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 16)
    margin.add_child(box)
    message = Label.new()
    message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    message.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(message)
    action = Button.new()
    action.text = "Medir silêncio (3 segundos)"
    action.custom_minimum_size.y = 44
    box.add_child(action)
    var cancel = Button.new()
    cancel.text = "Fechar"
    box.add_child(cancel)
    cancel.pressed.connect(queue_free)
    close_requested.connect(queue_free)
    action.pressed.connect(advance)
    microphone = Capture.new()
    microphone.input_gain_db = 0
    microphone.noise_gate_db = -80
    microphone.periodicity_threshold = 0.30
    add_child(microphone)
    microphone.sample_ready.connect(receive)
    microphone.status_changed.connect(func(text): message.text = text)
    if microphone.start(device):
        message.text = "Fique em silêncio para medir o ruído. Depois, sustente uma vogal no seu tom habitual, inclusive grave. Não é necessário cantar agudo."
    else:
        action.disabled = true

func advance() -> void:
    if not profile.is_empty():
        calibrated.emit(profile)
        queue_free()
        return
    phase = "silence" if silence.is_empty() else "voice"
    remaining = 3.5 if phase == "silence" else 5.5
    microphone.discard_pending()
    action.disabled = true

func receive(sample: Dictionary, _age: float) -> void:
    var duration = 3.0 if phase == "silence" else 5.0
    if remaining <= 0 or remaining > duration:
        return
    (silence if phase == "silence" else voice).append(sample)

func _process(delta: float) -> void:
    if remaining <= 0:
        return
    remaining = maxf(0, remaining - delta)
    message.text = ("Fique em silêncio" if phase == "silence" else "Sustente “aaa” no seu tom confortável") + " · %d s" % int(ceil(remaining))
    if remaining > 0:
        return
    if phase == "silence":
        if silence.size() < 20:
            microphone.stop()
            message.text = "Entrada insuficiente. Confira o dispositivo e tente novamente."
            action.hide()
            return
        action.text = "Medir voz (5 segundos)"
        message.text = "Agora sustente uma vogal no seu tom habitual. Clique quando estiver pronto."
    else:
        microphone.stop()
        profile = Calibration.evaluate(silence, voice)
        if profile.has("error"):
            message.text = profile.error
            profile.clear()
            action.hide()
        else:
            message.text = "Calibração concluída. Ganho: +%.0f dB · limiar: %.0f dB.\nClique para aplicar e salvar as configurações." % [profile.gain_db, profile.gate_db]
            action.text = "Aplicar calibração"
    action.disabled = false

func _exit_tree() -> void:
    if is_instance_valid(microphone):
        microphone.stop()
