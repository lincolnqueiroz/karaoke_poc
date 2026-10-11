extends SceneTree

const Library = preload("res://scripts/song_library.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func _initialize() -> void:
    call_deferred("verify")

func verify() -> void:
    var folder = "user://library_test"
    DirAccess.make_dir_recursive_absolute(folder.path_join("sample/lyrics"))
    var audio = FileAccess.open(folder.path_join("sample/original.mp3"), FileAccess.WRITE)
    audio.store_string("fake audio for discovery only")
    audio.close()
    var lyrics = FileAccess.open(folder.path_join("sample/lyrics/sample.lrc"), FileAccess.WRITE)
    lyrics.store_string("[00:01] Verse")
    lyrics.close()
    var manifest = FileAccess.open(folder.path_join("sample/song.json"), FileAccess.WRITE)
    manifest.store_string(JSON.stringify({"schema_version": "1.0", "title": "Test song",
        "duration_seconds": 10, "audio": {"original": "original.mp3"}, "notes": []}))
    manifest.close()
    var metadata = FileAccess.open(folder.path_join("sample/metadata.json"), FileAccess.WRITE)
    metadata.store_string(JSON.stringify({"artist": "Test artist"}))
    metadata.close()
    var library = Library.discover([folder, folder])
    check(library.songs.size() == 1, "Discover imported songs without duplicate copies")
    check(library.songs[0].lyrics.ends_with("sample.lrc"), "Associate local LRC")
    check(library.songs[0].artist == "Test artist", "Read optional artist without changing the manifest")
    DirAccess.remove_absolute(folder.path_join("sample/original.mp3"))
    var missing = Library.discover([folder])
    check(missing.songs.is_empty() and missing.errors.size() == 1, "Missing audio is reported")
    DirAccess.remove_absolute(folder.path_join("sample/song.json"))
    DirAccess.remove_absolute(folder.path_join("sample/metadata.json"))
    DirAccess.remove_absolute(folder.path_join("sample/lyrics/sample.lrc"))
    DirAccess.remove_absolute(folder.path_join("sample/lyrics"))
    DirAccess.remove_absolute(folder.path_join("sample"))
    DirAccess.remove_absolute(folder)
    var menu = load("res://scenes/main_menu.tscn").instantiate()
    root.add_child(menu)
    check(menu.content.get_child(2).text == "Jogar", "Main menu contains Play")
    menu.show_settings()
    check(menu.content.get_child(0).text == "Configurações", "Settings navigation")
    check(menu.save_settings("Default", 18, "user://test_settings.cfg") == OK,
          "Settings save successfully")
    var saved = ConfigFile.new()
    check(saved.load("user://test_settings.cfg") == OK and saved.get_value("microphone", "gain_db") == 18,
          "Saved settings persist locally")
    DirAccess.remove_absolute("user://test_settings.cfg")
    menu.show_songs()
    var actual = Library.discover(["res://demo", ProjectSettings.globalize_path("res://").path_join("../workspace/songs").simplify_path()])
    print("Local imported songs: ", actual.songs.map(func(song): return song.title))
    check(menu.content.get_child(0).text == "Escolha sua música", "Song selector navigation")
    menu.input_gain_db = 18
    menu.open_song({"manifest": "res://demo/song.json", "lyrics": ""})
    check(is_instance_valid(menu.player) and not menu.menu_panel.visible,
          "Selecting song opens karaoke")
    check(menu.player.microphone.input_gain_db == 18, "Global gain applies to karaoke")
    check(not menu.player.get_node("MicrophoneControls/Gain").visible,
          "Global settings are removed from player controls")
    menu.player.menu_requested.emit()
    check(menu.player == null and menu.menu_panel.visible, "Return to main menu")
    menu.queue_free()
    await process_frame
    print("Menu checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
