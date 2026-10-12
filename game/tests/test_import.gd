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
    check(args[args.find("--suite") + 1] == "suite_1", "Default suite reaches analyzer")
    var suite_args = Importer.arguments("song.mp3", "", "cpu", false, false, "", "job.json", "", "", "", "future_suite")
    check(suite_args[suite_args.find("--suite") + 1] == "future_suite", "Selected suite reaches analyzer unchanged")
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
    if OS.is_debug_build():
        check(page.analysis_suite != null and page.analysis_suite.get_item_metadata(0) == "suite_1",
              "Debug import offers preserved suite 1")
        page.separate.button_pressed = false
        page.analysis_suite.select(1)
        page.update_suite_controls()
        check(page.analysis_suite.get_item_metadata(1) == "suite_2" and page.separate.button_pressed and page.separate.disabled,
              "Suite 2 requires vocal separation")
        page.analysis_suite.select(0)
        page.update_suite_controls()
        check(not page.separate.disabled, "Suite 1 allows optional separation again")
        page.analysis_suite.select(2)
        page.update_suite_controls()
        check(page.analysis_suite.get_item_metadata(2) == "suite_3" and not page.separate.disabled,
              "Suite 3 is selectable with optional separation")
        page.analysis_suite.select(3)
        page.update_suite_controls()
        check(page.analysis_suite.get_item_metadata(3) == "suite_4" and not page.separate.disabled,
              "Suite 4 offers HPSS with optional separation")
        page.analysis_suite.select(4)
        page.update_suite_controls()
        check(page.analysis_suite.get_item_metadata(4) == "suite_5" and page.separate.disabled and page.separate.button_pressed,
              "Suite 5 requires accompaniment and vocal stems")
        page.analysis_suite.select(5)
        page.update_suite_controls()
        check(page.analysis_suite.get_item_metadata(5) == "suite_6" and page.separate.disabled and page.separate.button_pressed,
              "Suite 6 requires adjusted Demucs separation")
        page.analysis_suite.select(6)
        page.update_suite_controls()
        check(page.analysis_suite.get_item_metadata(6) == "suite_7" and not page.separate.disabled,
              "Suite 7 offers HPSS and aggressive absolute gate with optional separation")
        page.analysis_suite.select(7)
        page.update_suite_controls()
        check(page.analysis_suite.get_item_metadata(7) == "suite_8" and not page.separate.disabled,
              "Suite 8 offers postprocessing with optional separation")
    else:
        check(page.analysis_suite == null, "Release hides experimental selection")
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
    check(menu.content.get_child(0).text == "ESCOLHA SUA MÚSICA", "Back returns to selector")
    menu.queue_free()
    await process_frame
    await create_timer(0.5).timeout # Let the audio mixer release menu music.
    print("Import checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
