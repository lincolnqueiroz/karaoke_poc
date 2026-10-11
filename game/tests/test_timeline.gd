extends SceneTree

var failures: int = 0

func check(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error(description)

func _initialize() -> void:
    var player = load("res://scripts/karaoke_player.gd").new()
    player.size = Vector2(800, 400)
    player.window_seconds = 8.0
    player.cursor_position = 0.25

    # At the start: two seconds of empty history and six seconds of future.
    player.elapsed = 0.0
    check(is_equal_approx(player._time_to_x(0.0), 200), "Cursor at start")
    check(is_equal_approx(player._time_to_x(6.0), 800), "Future edge")
    var first = player._note_rect(3.0, 1.0, 69)
    check(is_equal_approx(first.position.x, 500), "Note start position")
    check(is_equal_approx(first.size.x, 100), "One-second note width")

    player.elapsed = 1.0
    var moved = player._note_rect(3.0, 1.0, 69)
    check(is_equal_approx(moved.position.x, first.position.x - 100), "Scroll speed")
    check(is_equal_approx(player._time_to_x(1.0), 200), "Fixed cursor")

    player.elapsed = 10.0
    var left = player._note_rect(7.0, 2.0, 69)
    var right = player._note_rect(15.0, 2.0, 69)
    check(is_equal_approx(left.position.x, 0) and is_equal_approx(left.size.x, 100),
          "Left edge clipping")
    check(is_equal_approx(right.position.x, 700) and is_equal_approx(right.size.x, 100),
          "Right edge clipping")
    check(not player._note_rect(0.0, 1.0, 69).has_area(), "Past notes excluded")
    check(not player._note_rect(17.0, 1.0, 69).has_area(), "Future notes excluded")
    check(not player._note_rect(10.0, 0.0, 69).has_area(), "Zero duration excluded")
    check(is_equal_approx(player._note_rect(0.0, 20.0, 69).size.x, 800),
          "Sustained note crossing both edges")

    player.song_duration = 273.4267
    player.elapsed = player.song_duration
    check(is_equal_approx(player._time_to_x(player.elapsed), 200), "Fixed cursor at end")
    player.size.x = 1600
    check(is_equal_approx(player._time_to_x(player.elapsed), 400), "Resize")
    check(is_equal_approx(player._note_rect(player.elapsed, 1.0, 69).size.x, 200),
          "Scaled duration after resize")
    player.window_seconds = 4.0
    check(is_equal_approx(player._note_rect(player.elapsed, 1.0, 69).size.x, 400),
          "Configurable time window")

    player.elapsed = 0.0
    player._update_audio_clock(0.0, 0.01, 0.05)
    check(is_equal_approx(player.elapsed, 0), "Startup latency clamps to zero")
    player._update_audio_clock(10.0, 0.02, 0.05)
    check(is_equal_approx(player.elapsed, 9.97), "Audible clock compensates mix and latency")
    player._update_audio_clock(10.0, 0.03, 0.05)
    check(is_equal_approx(player.elapsed, 9.98), "Clock advances between audio blocks")
    player._update_audio_clock(9.99, 0.02, 0.05)
    check(is_equal_approx(player.elapsed, 9.98), "Clock ignores backwards jitter")
    player._update_audio_clock(1000.0, 0.02, 0.05)
    check(is_equal_approx(player.elapsed, player.song_duration), "Clock clamps at song end")

    player.elapsed = 0.9
    player.visual_offset_seconds = 0.1
    check(is_equal_approx(player._time_to_x(1.0), 400), "Positive offset advances notes")
    player.visual_offset_seconds = -0.1
    check(player._time_to_x(1.0) > 400, "Negative offset delays notes")
    check(is_equal_approx(player.elapsed, 0.9), "Offset does not alter the audio clock")
    player.notes = [{"midi": 45}]
    player._set_pitch_bounds()
    check(player.pitch_min == 43 and player._pitch_y(45, 720) > player._pitch_y(48, 720),
          "Lower reference pitches have distinct visible rows")
    player.free()
    print("Timeline checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
