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
    var has_menu_music = ResourceLoader.exists(menu.MENU_MUSIC_PATH)
    if has_menu_music:
        check(menu.menu_music.playing and menu.menu_music.stream is AudioStreamMP3
              and menu.menu_music.stream.loop, "Menu music starts and loops")
    check(menu.menu_music.bus == &"MenuMusic", "Background music uses its own audio channel")
    check(menu.content.get_child(2).text == "JOGAR", "Main menu contains Play")
    check(menu.content.get_child(0).text == "KARAOKÊ", "Neon menu displays the brand")
    menu.importer.busy = true
    menu.content.get_child(2).pressed.emit()
    check(menu.content.get_child(0).text == "KARAOKÊ", "Navigation cannot interrupt an import")
    menu.importer.busy = false
    menu.content.get_child(2).pressed.emit()
    check(menu.content.get_child(0).text == "ESCOLHA SUA MÚSICA", "Play opens the song library")
    menu.show_settings()
    check(menu.content.get_child(0).text == "CONFIGURAÇÕES", "Settings navigation")
    var master = menu.content.find_child("MasterVolume", true, false)
    var music = menu.content.find_child("MusicVolume", true, false)
    var effects = menu.content.find_child("EffectsVolume", true, false)
    var background_music = menu.content.find_child("MenuMusicVolume", true, false)
    master.value = 60
    music.value = 35
    effects.value = 0
    check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Master")), 0.6)
          and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.35),
          "Sliders apply master and music volumes independently")
    check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "Zero effects volume is silent")
    effects.value = 40
    background_music.value = 20
    check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("MenuMusic")), 0.2)
          and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.35),
          "Menu music volume is independent of the song volume")
    if has_menu_music:
        check(menu.menu_music.playing, "Navigating settings keeps the background music playing")
    check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "Raising volume restores the effects channel")
    check(menu.input_gain_db != 0, "Playback volume does not alter microphone gain")
    root.size = Vector2i(1100, 640)
    for frame in range(8):
        await process_frame
    var back = menu.content.get_child(menu.content.get_child_count() - 1)
    check(back.get_global_rect().end.y <= 640 and menu.content.get_global_rect().end.x <= 1100,
          "Settings controls fit the minimum window size")
    check(menu.save_settings("Default", 18, "user://test_settings.cfg") == OK,
          "Settings save successfully")
    var saved = ConfigFile.new()
    check(saved.load("user://test_settings.cfg") == OK and saved.get_value("microphone", "gain_db") == 18,
          "Saved settings persist locally")
    check(saved.get_value("volume", "Master") == 60 and saved.get_value("volume", "Music") == 35
          and saved.get_value("volume", "Effects") == 40, "All three volume settings persist")
    check(saved.get_value("volume", "MenuMusic") == 20, "Menu music volume persists")
    DirAccess.remove_absolute("user://test_settings.cfg")
    menu.show_songs()
    if has_menu_music:
        check(menu.menu_music.playing, "Song selector keeps the background music playing")
    var actual = Library.discover(["res://demo", ProjectSettings.globalize_path("res://").path_join("../workspace/songs").simplify_path()])
    print("Local imported songs: ", actual.songs.map(func(song): return song.title))
    check(menu.content.get_child(0).text == "ESCOLHA SUA MÚSICA", "Song selector navigation")
    menu.input_gain_db = 18
    menu.open_song({"manifest": "res://demo/song.json", "lyrics": ""})
    if has_menu_music:
        check(menu.menu_music.playing, "Entering the waiting room keeps menu music playing")
    check(is_instance_valid(menu.player) and not menu.menu_panel.visible,
          "Selecting song opens karaoke")
    check(menu.player.microphone.input_gain_db == 18, "Global gain applies to karaoke")
    check(menu.player.audio_player.bus == &"Music", "Song playback uses the music volume channel")
    check(not menu.player.get_node("MicrophoneControls/Gain").visible,
          "Global settings are removed from player controls")
    menu.player.set_process(false)
    menu.player.start_round(false)
    check(not menu.menu_music.playing, "Starting countdown stops the menu music")
    menu.player._process(3)
    check(not menu.menu_music.playing, "Menu music stays stopped during singing")
    menu.player._process(8)
    check(not menu.menu_music.playing, "Menu music stays stopped during results")
    menu.player.prepare_round()
    if has_menu_music:
        check(menu.menu_music.playing, "Replay preparation restores menu music")
    menu.player.menu_requested.emit()
    check(menu.player == null and menu.menu_panel.visible, "Return to main menu")
    if has_menu_music:
        check(menu.menu_music.playing, "Returning from karaoke restarts background music")
    for bus in menu.volumes:
        menu.apply_volume(bus, 100)
    menu.queue_free()
    await process_frame
    await create_timer(0.1).timeout # Let the audio mixer release stopped MP3 playbacks.
    print("Menu checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
