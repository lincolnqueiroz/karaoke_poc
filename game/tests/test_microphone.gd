extends SceneTree

const Pitch = preload("res://scripts/live_pitch.gd")
const Capture = preload("res://scripts/microphone_capture.gd")
const Player = preload("res://scripts/karaoke_player.gd")
var failures: int = 0

func check(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error(description)

func tone(frequency: float, rate: float, amplitude: float = 0.2) -> PackedFloat32Array:
    var samples = PackedFloat32Array()
    for index in range(1024):
        samples.append(amplitude * sin(TAU * frequency * index / rate))
    return samples

func _initialize() -> void:
    call_deferred("verify")

func verify() -> void:
    var began = Time.get_ticks_usec()
    for rate in [11025.0, 12000.0]:
        for frequency in [65.4, 82.4, 110.0, 220.0, 440.0, 880.0]:
            var result = Pitch.estimate(tone(frequency, rate), rate)
            check(absf(float(result.frequency) - frequency) / frequency < 0.01,
                  "Frequency accuracy: %.1f Hz at %.0f Hz" % [frequency, rate])
    print("Synthetic estimates took (ms): ", (Time.get_ticks_usec() - began) / 1000.0)
    check(Pitch.estimate(tone(440, 12000, 0), 12000).frequency == 0, "Silence rejected")
    check(Pitch.estimate(tone(440, 12000, 0.001), 12000).frequency == 0, "Noise gate")
    var dc = tone(220, 12000)
    for index in range(dc.size()):
        dc[index] += 0.4 + 0.05 * sin(TAU * 440 * index / 12000)
    check(absf(float(Pitch.estimate(dc, 12000).frequency) - 220) < 2,
          "DC offset and harmonics")
    var random = RandomNumberGenerator.new()
    random.seed = 42
    var noise = PackedFloat32Array()
    for index in range(1024):
        noise.append(random.randf_range(-0.2, 0.2))
    check(Pitch.estimate(noise, 12000).frequency == 0, "Unpitched noise rejected")

    var service = Capture.new()
    var reports: Array = []
    service.sample_ready.connect(func(result, age): reports.append({"result": result, "age": age}))
    var frames = PackedVector2Array()
    for index in range(4800):
        var value = 0.2 * sin(TAU * 440 * index / 48000)
        frames.append(Vector2(value, -value))
    # Exercise resampling across arbitrary chunk boundaries and opposite stereo phase.
    service.consume_frames(frames.slice(0, 777), 48000)
    service.consume_frames(frames.slice(777), 48000)
    check(reports.size() == 1 and absf(float(reports[0].result.frequency) - 440) < 2,
          "Streaming chunks and stereo input")
    check(is_equal_approx(float(reports[0].age), 1024.0 / 24000), "Window center age")
    service.stop()
    check(service._samples.is_empty() and not service.active, "Stop clears input state")
    service.free()

    var quiet = Capture.new()
    var quiet_reports: Array = []
    quiet.sample_ready.connect(func(result, _age): quiet_reports.append(result))
    var quiet_frames = PackedVector2Array()
    for index in range(4800):
        var value = 0.002 * sin(TAU * 220 * index / 48000)
        quiet_frames.append(Vector2(value, value))
    quiet.input_gain_db = 0
    quiet.consume_frames(quiet_frames, 48000)
    check(quiet_reports[-1].frequency == 0, "Quiet voice below gate without gain")
    var raw_level = float(quiet_reports[-1].rms_db)
    quiet.stop()
    quiet.input_gain_db = 12
    quiet.consume_frames(quiet_frames, 48000)
    check(absf(float(quiet_reports[-1].frequency) - 220) < 2,
          "Gain makes quiet voice pass the gate without changing pitch")
    check(absf(float(quiet_reports[-1].rms_db) - raw_level - 12) < 0.1,
          "Gain increases measured level by 12 dB")
    quiet.stop()
    quiet.consume_frames(PackedVector2Array([Vector2.ZERO]), 48000)
    check(quiet_reports.size() == 2, "Short silence does not produce a pitch")
    quiet.free()

    var view = Player.new()
    view.microphone = Capture.new()
    view.microphone_status = Label.new()
    view.elapsed = 12.0
    view.microphone_latency_seconds = 0.02
    view._on_microphone_sample({"frequency": 440.0, "midi": 69.0,
                               "confidence": 1.0, "rms_db": -20.0}, 0.04)
    check(is_equal_approx(float(view.sung_pitch[0].time), 11.94),
          "Live pitch compensates window age and input latency")
    check(view.sung_pitch[0].voiced and view.microphone_status.text.contains("440"),
          "Live pitch updates trace and status")
    view.voice_octaves = 1
    check(view._display_voice_midi(57.25) == 69.25,
          "Lower octave preserves detuning when displayed against reference")
    check(view.sung_pitch[0].midi == 69.0, "Octave display preserves raw pitch")
    view.voice_octaves = -1
    check(view._display_voice_midi(81.25) == 69.25, "Higher octave display")
    for index in range(300):
        view._on_microphone_sample({"frequency": 0.0, "midi": 0.0,
                                   "confidence": 0.0, "rms_db": -120.0}, 0.0)
    check(view.sung_pitch.size() <= 224 and not view.sung_pitch[-1].voiced,
          "Silence breaks trace and history remains bounded")
    view.microphone.free()
    view.microphone_status.free()
    view.free()

    if AudioServer.get_driver_name() == "Dummy":
        print("Audio bus integration: SKIP (Dummy driver; use --audio-driver WASAPI)")
        print("Microphone synthetic checks: ", "PASS" if failures == 0 else "FAIL")
        quit(0 if failures == 0 else 1)
        return

    # Test capture routing with generated audio, without opening a real microphone.
    var index = AudioServer.bus_count
    AudioServer.add_bus()
    AudioServer.set_bus_name(index, "SyntheticMicTest")
    AudioServer.set_bus_volume_linear(index, 0.0)
    var effect = AudioEffectCapture.new()
    effect.buffer_length = 0.5
    AudioServer.add_bus_effect(index, effect)
    var player = AudioStreamPlayer.new()
    var generator = AudioStreamGenerator.new()
    generator.mix_rate = AudioServer.get_mix_rate()
    generator.buffer_length = 0.5
    player.stream = generator
    player.bus = "SyntheticMicTest"
    root.add_child(player)
    player.play()
    var playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
    var synthetic = PackedVector2Array()
    for sample in range(int(generator.mix_rate * 0.4)):
        var value = 0.2 * sin(TAU * 440 * sample / generator.mix_rate)
        synthetic.append(Vector2(value, value))
    check(playback.push_buffer(synthetic), "Generated input buffer accepted")
    await create_timer(0.2).timeout
    var captured = effect.get_buffer(effect.get_frames_available())
    var peak: float = 0
    for frame in captured:
        peak = maxf(peak, absf(frame.x))
    print("Captured synthetic frames: ", captured.size(), " peak: ", peak)
    check(peak > 0.1 and AudioServer.get_bus_volume_linear(index) == 0,
          "Silent bus still captures PCM")
    player.stop()
    player.queue_free()
    await process_frame
    AudioServer.remove_bus(index)
    print("Microphone synthetic checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
