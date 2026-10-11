extends SceneTree

var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func _initialize() -> void:
    call_deferred("verify")

func verify() -> void:
    var scene = load("res://scenes/karaoke_player.tscn").instantiate()
    scene.song_manifest = "res://demo/song.json"
    scene.lyrics_file = ""
    root.add_child(scene)
    scene.set_process(false)
    check(scene.round_state == scene.RoundState.PREPARE and scene.elapsed == 0,
          "Scene waits for player instead of autoplay")
    check(scene.gameplay_ui.overlay.visible and not scene.audio_player.playing,
          "Preparation overlay visible and audio stopped")
    scene._process(1)
    check(scene.elapsed == 0, "Preparation does not advance song time")
    scene.voice_octaves = 1
    scene.microphone.input_gain_db = 15
    scene.start_round(false)
    check(scene.round_state == scene.RoundState.COUNTDOWN, "Start launches countdown")
    scene._process(2)
    check(scene.elapsed == 0 and not scene.scorer.started, "Countdown does not score")
    scene._process(1)
    check(scene.round_state == scene.RoundState.PLAYING, "Countdown starts round")
    check(not scene.gameplay_ui.overlay.visible, "Round reveals timeline")
    scene._process(8)
    check(scene.round_state == scene.RoundState.RESULT, "Song end shows result")
    check(scene.gameplay_ui.description.text.contains("sem pontuação"), "Preview is not a zero-score performance")
    scene.prepare_round()
    check(scene.elapsed == 0 and scene.scorer.total == 0 and scene.sung_pitch.is_empty(),
          "Replay clears time, score and trace")
    check(scene.voice_octaves == 1 and scene.microphone.input_gain_db == 15,
          "Replay preserves voice settings")
    scene.start_round(false)
    scene._scored_round = true # Simulated capture; never opens real hardware.
    scene._process(3)
    scene._process(2)
    check(scene.scorer.started and scene.scorer.total > 0, "Scored round includes silence from beginning")
    scene._process(6)
    check(scene.round_state == scene.RoundState.RESULT and scene.scorer.result().points == 0,
          "Scored result finalizes missing vocals")
    var points = scene.scorer.result().points
    scene._process(10)
    check(scene.scorer.result().points == points, "Result freezes evaluation")
    scene.queue_free()
    await process_frame
    print("Gameplay checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
