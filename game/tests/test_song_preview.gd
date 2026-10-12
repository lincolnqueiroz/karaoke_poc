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
    var preview = menu.song_preview
    check(preview.audio.bus == &"Music", "Preview uses song volume")
    check(not preview.start({"manifest": "user://missing-preview-song.json"}).is_empty(), "Missing manifest is explicit")
    if not FileAccess.file_exists(menu.MENU_MUSIC_PATH):
        print("Preview playback checks: SKIP (local menu MP3 not supplied)")
        menu.queue_free()
        await process_frame
        quit(0 if failures == 0 else 1)
        return
    var folder = "user://preview_test"
    DirAccess.make_dir_recursive_absolute(folder)
    var audio_path = folder.path_join("original.mp3")
    var file = FileAccess.open(audio_path, FileAccess.WRITE)
    file.store_buffer(FileAccess.get_file_as_bytes(menu.MENU_MUSIC_PATH))
    file.close()
    var song_path = folder.path_join("song.json")
    file = FileAccess.open(song_path, FileAccess.WRITE)
    file.store_string(JSON.stringify({"audio": {"original": "original.mp3"}}))
    file.close()
    var song = {"manifest": song_path}
    menu.menu_music.play(5.0)
    await create_timer(0.1).timeout
    var original_position = menu.menu_music.get_playback_position()
    check(preview.start(song).is_empty(), "Load preview MP3 at runtime")
    check(menu.menu_music.stream_paused, "Menu music pauses")
    var paused_position = menu.menu_music.get_playback_position()
    check(absf(paused_position - original_position) < 0.15, "Pause preserves menu playback position")
    var midpoint = preview.audio.stream.get_length() / 2.0
    check(absf(preview.audio.get_playback_position() - midpoint) < 0.15, "Preview starts at actual audio midpoint")
    check(is_equal_approx(preview.end_seconds, minf(midpoint + 10, preview.audio.stream.get_length())), "Preview endpoint is ten seconds or the end of short audio")
    await create_timer(0.15).timeout
    check(absf(menu.menu_music.get_playback_position() - paused_position) < 0.05, "Menu position does not advance during preview")
    check(preview.start(song).is_empty() and menu.menu_music.stream_paused, "Switching preview keeps menu paused")
    preview.stop()
    check(not preview.audio.playing and not menu.menu_music.stream_paused, "Manual stop resumes menu")
    check(absf(menu.menu_music.get_playback_position() - paused_position) < 0.15, "Manual stop does not restart menu music")
    preview.start(song)
    preview.audio.seek(preview.end_seconds)
    preview._process(0)
    check(preview.manifest.is_empty() and not menu.menu_music.stream_paused, "Playback endpoint automatically resumes menu")
    preview.start(song)
    preview.audio.finished.emit()
    check(preview.manifest.is_empty() and not menu.menu_music.stream_paused, "Natural audio finish resumes menu")
    preview.start(song)
    menu.show_settings()
    check(not preview.audio.playing and not menu.menu_music.stream_paused, "Leaving song selection interrupts preview")
    preview.start(song)
    var before_return = menu.menu_music.get_playback_position()
    menu.show_main()
    check(not preview.audio.playing and absf(menu.menu_music.get_playback_position() - before_return) < 0.15, "Returning to main menu preserves playback position")
    menu.menu_music.stop()
    preview.start(song)
    preview.stop()
    check(not menu.menu_music.playing, "Stopping preview does not start previously stopped menu music")
    menu.menu_music.play()
    menu.menu_music.stream_paused = true
    preview.start(song)
    preview.stop()
    check(menu.menu_music.stream_paused, "Preserve existing menu pause state")
    menu.menu_music.stream_paused = false
    DirAccess.remove_absolute(audio_path)
    DirAccess.remove_absolute(song_path)
    DirAccess.remove_absolute(folder)
    menu.queue_free()
    await process_frame
    await create_timer(0.1).timeout
    print("Song preview checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
