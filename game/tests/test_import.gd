extends SceneTree

const Importer = preload("res://scripts/song_importer.gd")
class FakeImporter extends Importer:
    var fail: bool = false
    func execute_process(_python: String, _args: PackedStringArray) -> Dictionary:
        if fail:
            return {"code": 1, "output": "Simulated failure"}
        var file = FileAccess.open(status_path, FileAccess.WRITE)
        file.store_string(JSON.stringify({"state": "complete", "progress": 1,
            "message": "Complete"}))
        file.close()
        return {"code": 0, "output": ""}

var failures: int = 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func _initialize() -> void:
    call_deferred("verify")

func verify() -> void:
    var args = Importer.arguments("C:/music/a & b.mp3", "C:/music/verse.lrc", "cpu",
        false, false, "C:/ffmpeg/bin", "C:/job.json")
    check(args[2] == "C:/music/a & b.mp3", "Paths remain separate subprocess arguments")
    check("--without-separation" in args and "--allow-model-download" not in args,
          "Model downloads require explicit option")
    var service = FakeImporter.new()
    root.add_child(service)
    var reports: Array = []
    service.finished.connect(func(ok, state): reports.append({"ok": ok, "state": state}))
    var source = "user://test_import_source.mp3"
    var file = FileAccess.open(source, FileAccess.WRITE)
    file.store_string("fake")
    file.close()
    var jobs = Importer.project_root().path_join("workspace/import-jobs")
    DirAccess.make_dir_recursive_absolute(jobs)
    check(service.start(OS.get_executable_path(), ProjectSettings.globalize_path(source), "", "cpu", false, false, "") == OK,
          "Starts asynchronous worker")
    check(service.start("missing", "missing", "", "cpu", false, false, "") == ERR_BUSY,
          "Rejects concurrent imports")
    for frame in range(100):
        await process_frame
        if not service.busy:
            break
    check(not service.busy and reports.size() == 1 and reports[0].ok,
          "Successful worker completion updates UI")
    DirAccess.remove_absolute(service.status_path)
    service.fail = true
    service.start(OS.get_executable_path(), ProjectSettings.globalize_path(source), "", "cpu", false, false, "")
    for frame in range(100):
        await process_frame
        if not service.busy:
            break
    check(reports.size() == 2 and not reports[1].ok and reports[1].state.message.contains("Simulated failure"),
          "Subprocess failure is explicit")
    service.queue_free()
    DirAccess.remove_absolute(source)
    var menu = load("res://scenes/main_menu.tscn").instantiate()
    root.add_child(menu)
    menu.show_import()
    var page = menu.content.get_child(1)
    check(not page.downloads.button_pressed and page.separate.button_pressed,
          "Import form defaults to separation with cached weights")
    page.begin()
    check(page.status.text.contains("título") and not menu.importer.busy,
          "Title is required before launching analysis")
    page.title_field.text = "Título"
    page.artist_field.text = "Artista"
    page.lyrics_mode.select(1)
    page.change_lyrics_mode(1)
    check(page.local_box.visible and not page.online_box.visible, "Local LRC mode is exclusive")
    page.lyrics_mode.select(2)
    page.change_lyrics_mode(2)
    check(not page.local_box.visible and page.online_box.visible, "Online LRC mode is exclusive")
    page.on_candidates([{"id": 1, "title": "Título", "artist": "Artista", "album": "Álbum", "duration": 10,
        "lrc": "[00:01] Teste"}])
    page.select_lyrics(1)
    check(page.selected_lyrics.id == 1 and page.preview.text.contains("Teste"), "Preview selected synchronized lyrics")
    page.artist_field.text = "Outro artista"
    page.artist_field.text_changed.emit(page.artist_field.text)
    check(page.selected_lyrics.is_empty() and page.preview.text.is_empty(), "Changing query invalidates lyrics")
    page.begin()
    check(page.status.text.contains("selecione") and not menu.importer.busy,
          "Online mode requires a selected lyric, never falls back to local file")
    var titled_args = Importer.arguments("song.mp3", "", "cpu", false, false, "", "job.json", "", "Título & teste", "Artista")
    check(titled_args[titled_args.find("--title") + 1] == "Título & teste" and "--artist" in titled_args,
          "Pass title and artist as distinct arguments")
    page.back_requested.emit()
    check(menu.content.get_child(0).text == "Escolha sua música", "Back returns to selector")
    menu.queue_free()
    await process_frame
    print("Import checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
