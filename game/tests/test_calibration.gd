extends SceneTree

const Calibration = preload("res://scripts/microphone_calibration.gd")
const Pitch = preload("res://scripts/live_pitch.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func samples(level: float, confidence: float, frequency: float = 110) -> Array:
    var values: Array = []
    for index in range(70):
        values.append({"rms_db": level, "confidence": confidence, "frequency": frequency})
    return values

func _initialize() -> void:
    call_deferred("verify")

func verify() -> void:
    var silence = samples(-65, 0, 0)
    var result = Calibration.evaluate(silence, samples(-38, 0.80))
    check(not result.has("error") and is_equal_approx(result.gain_db, 18), "Calibrate quiet low voice")
    check(result.threshold > 0.15 and result.threshold <= 0.30, "Bounded adaptation of periodicity")
    check(result.gate_db > -65 + result.gain_db, "Gate remains above measured noise")
    check(Calibration.evaluate([], []).has("error"), "Reject absent capture")
    check(Calibration.evaluate(silence, samples(-70, 0, 0)).has("error"), "Reject inaudible voice")
    check(Calibration.evaluate(samples(-40, 0, 0), samples(-35, 0.9)).has("error"), "Reject poor signal to noise")
    check(Calibration.evaluate(silence, samples(-30, 0, 0)).has("error"), "Gain cannot fix unpitched noise")
    check(Calibration.evaluate(samples(-65, 0.9), samples(-30, 0.9)).has("error"), "Reject tonal background")
    var random = RandomNumberGenerator.new()
    random.seed = 2026
    var noise = PackedFloat32Array()
    var low_voice = PackedFloat32Array()
    for index in range(1024):
        noise.append(random.randf_range(-0.2, 0.2))
        low_voice.append(0.2 * sin(TAU * 110 * index / 12000.0))
    check(Pitch.estimate(noise, 12000, -70, 0.30).frequency == 0, "Calibrated estimator rejects white noise")
    check(absf(Pitch.estimate(low_voice, 12000, -70, 0.30).frequency - 110) < 2, "Low voice remains in estimator range")
    var recovered = false
    for amplitude in [0.12, 0.16, 0.20, 0.24, 0.28]:
        random.seed = 19
        var noisy_voice = PackedFloat32Array()
        for index in range(1024):
            noisy_voice.append(low_voice[index] + random.randf_range(-amplitude, amplitude))
        var strict = Pitch.estimate(noisy_voice, 12000)
        var relaxed = Pitch.estimate(noisy_voice, 12000, -45, 0.30)
        if strict.frequency == 0 and absf(relaxed.frequency - 110) < 3:
            recovered = true
    check(recovered, "Bounded calibration recovers a noisy low tone rejected by the default threshold")
    var dialog = preload("res://scripts/calibration_dialog.gd").new()
    root.add_child(dialog)
    dialog.set_process(false)
    dialog.phase = "silence"
    dialog.remaining = 0.01
    dialog._process(0.02)
    check(not dialog.action.visible and not dialog.microphone.active, "Missing frames fail calibration and release capture")
    dialog.queue_free()
    await process_frame
    dialog = preload("res://scripts/calibration_dialog.gd").new()
    root.add_child(dialog)
    dialog.set_process(false)
    dialog.advance()
    dialog.remaining = 2.5
    for sample in silence:
        dialog.receive(sample, 0)
    dialog._process(3)
    check(dialog.action.text == "Medir voz (5 segundos)" and not dialog.action.disabled, "Silence completes before explicit voice measurement")
    dialog.advance()
    dialog.remaining = 4.5
    for sample in samples(-38, 0.80):
        dialog.receive(sample, 0)
    dialog._process(5)
    check(not dialog.profile.is_empty() and not dialog.microphone.active, "Voice measurement produces a profile and stops capture")
    var applied: Array = []
    dialog.calibrated.connect(func(profile): applied.append(profile))
    check(applied.is_empty(), "Measurement requires explicit application")
    dialog.advance()
    check(applied.size() == 1 and applied[0].gain_db == 18, "Apply emits successful calibration")
    await process_frame
    var menu = load("res://scenes/main_menu.tscn").instantiate()
    root.add_child(menu)
    result.device = "Default"
    menu.microphone_profile = result
    check(menu.save_settings("Default", result.gain_db, "user://calibration_test.cfg") == OK, "Persist calibration")
    var saved = ConfigFile.new()
    saved.load("user://calibration_test.cfg")
    check(saved.get_value("microphone", "calibration").threshold == result.threshold, "Persist sensitivity")
    menu.open_song({"manifest": "res://demo/song.json", "lyrics": ""})
    check(menu.player.microphone.periodicity_threshold == result.threshold and menu.player.microphone.noise_gate_db == result.gate_db, "Apply device calibration in gameplay")
    menu.return_to_menu()
    menu.input_device = "another device"
    menu.open_song({"manifest": "res://demo/song.json", "lyrics": ""})
    check(menu.player.microphone.periodicity_threshold == 0.15 and menu.player.microphone.noise_gate_db == -45, "Do not apply calibration to another device")
    menu.return_to_menu()
    DirAccess.remove_absolute("user://calibration_test.cfg")
    menu.queue_free()
    await process_frame
    print("Calibration checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
