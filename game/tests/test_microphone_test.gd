extends SceneTree

var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func _initialize() -> void:
    call_deferred("verify")

func verify() -> void:
    var menu = load("res://scenes/main_menu.tscn").instantiate()
    root.add_child(menu)
    menu.show_settings()
    check(menu.content.find_child("TestMicrophone", true, false) != null, "Settings expose microphone test")
    menu.input_gain_db = 18
    menu.microphone_profile = {"device": "Default", "gate_db": -40.0, "threshold": 0.24}
    var was_playing = menu.menu_music.playing
    menu.open_microphone_test("Default", 18)
    var test = menu.get_child(menu.get_child_count() - 1)
    check(not menu.menu_panel.visible and not menu.menu_music.playing, "Free singing pauses menu music")
    check(test.microphone.input_gain_db == 18 and test.microphone.noise_gate_db == -40
        and test.microphone.periodicity_threshold == 0.24, "Use selected gain and device calibration")
    check(menu.player == null, "No song or scoring session is required")
    test.set_process(false)
    var sample = {"frequency": 110.0, "midi": 45.0, "confidence": 0.9, "rms_db": -20.0}
    test.receive(sample, 0.04)
    check(test.trace.points.size() == 1 and test.trace.points[0].voiced, "Voiced samples populate green trace")
    check("110 Hz" in test.feedback.text and "Lá2" in test.feedback.text, "Show real pitch and input level")
    var quiet = {"frequency": 0.0, "midi": 0.0, "confidence": 0.0, "rms_db": -60.0}
    test.receive(quiet, 0)
    check(not test.trace.points[1].voiced and "Entrada baixa" in test.feedback.text, "Silence breaks the trace")
    for index in range(400):
        test.trace.record(sample, index * 0.05)
    check(test.trace.points.size() <= 256, "Trace history has bounded memory")
    test.trace.advance(30)
    check(test.trace.points.is_empty(), "Old samples disappear during silence")
    check(test.trace.position_for(30, 45).y > test.trace.position_for(30, 81).y, "Low pitch below high pitch")
    root.size = Vector2i(1100, 640)
    for frame in range(6):
        await process_frame
    check(test.toggle.get_global_rect().end.y <= 640, "Test controls fit the minimum window")
    var microphone = test.microphone
    test.back_requested.emit()
    check(menu.menu_panel.visible and not microphone.active, "Returning restores settings and releases capture")
    check(menu.menu_music.playing == was_playing, "Restore previous music state")
    await process_frame
    menu.open_microphone_test("Default", 20)
    test = menu.get_child(menu.get_child_count() - 1)
    check(test.microphone.noise_gate_db == -45 and test.microphone.periodicity_threshold == 0.15, "Edited gain uses default settings until recalibrated")
    test.back_requested.emit()
    await process_frame
    menu.queue_free()
    await process_frame
    print("Microphone free singing checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
