extends SceneTree

const Lrc = preload("res://scripts/lrc_lyrics.gd")
var failures: int = 0

func check(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error(description)

func _initialize() -> void:
    var result = Lrc.parse("\ufeff[ar:Test]\r\n[00:02.50] First\n[00:05.125][00:10] Second\n[00:08]\n", 15)
    check(result.error.is_empty(), "Metadata, BOM, CRLF and multiple tags")
    check(result.cues.size() == 4, "Repeated verses sorted")
    check(Lrc.text_at(result.cues, 2.49) == "", "Before first verse")
    check(Lrc.text_at(result.cues, 2.5) == "First", "Exact onset")
    check(Lrc.text_at(result.cues, 5.125) == "Second", "Next verse boundary")
    check(Lrc.text_at(result.cues, 9) == "", "Empty cue clears instrumental gap")
    check(Lrc.text_at(result.cues, 14) == "Second", "Last verse ends at song end")
    check(Lrc.text_at(result.cues, 15) == "", "After song end")
    check(Lrc.display_at(result.cues, 1.49).current == "", "No premature preview")
    check(Lrc.display_at(result.cues, 1.5).current == "First", "First verse one second early")
    check(Lrc.display_at(result.cues, 1.5).preview, "First verse marked as preview")
    var preview = Lrc.display_at(result.cues, 4.125)
    check(preview.current == "First" and preview.next == "Second",
          "Keep active verse while next appears below one second early")
    var transition = Lrc.display_at(result.cues, 5.125)
    check(transition.current == "Second" and transition.next == "" and not transition.preview,
          "Next verse moves up at exact onset")
    check(Lrc.display_at(result.cues, 8.5).current == "", "Instrumental gap stays empty")
    check(Lrc.display_at(result.cues, 9).current == "Second", "Preview after empty cue")
    check(Lrc.display_at(result.cues, 15).current == "", "Clear both lines at song end")
    var offset = Lrc.parse("[00:02] First\n[offset:100]", 10)
    check(is_equal_approx(offset.cues[0].start, 1.9), "Global positive offset advances lyrics")
    check(not Lrc.parse("[00:60] Bad", 80).error.is_empty(), "Invalid seconds")
    check(not Lrc.parse("", 80).error.is_empty(), "Empty file")
    check(not Lrc.parse("[00:01] <00:01.2>Word", 80).error.is_empty(), "Unsupported word timing")
    check(not Lrc.parse("[01:00] Beyond end", 30).error.is_empty(), "Beyond song duration")
    check(not Lrc.parse("untimed", 30).error.is_empty(), "Untimed content")
    var player = load("res://scripts/karaoke_player.gd").new()
    var label = Label.new()
    var next_label = Label.new()
    player.lyrics_label = label
    player.next_lyrics_label = next_label
    player.lyric_cues = result.cues
    player.song_duration = 15
    player.elapsed = 5.1
    player.visual_offset_seconds = 0.1
    player._process(0.0)
    check(label.text == "First", "Lyrics use audio clock, not note offset")
    check(next_label.text == "Second", "Player renders upcoming verse")
    player.elapsed = 5.125
    player._process(0.0)
    check(label.text == "Second" and next_label.text == "", "Player promotes verse at boundary")
    label.free()
    next_label.free()
    player.free()
    print("Lyrics checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
