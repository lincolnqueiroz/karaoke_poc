extends Node

const Paths = preload("res://scripts/runtime_paths.gd")

signal updated(status: Dictionary)
signal finished(success: bool, status: Dictionary)
var busy: bool = false
var worker: Thread
var status_path: String
var _last_status: String = ""
var library_root: String = ""

static func project_root() -> String:
    return Paths.development_root()

static func arguments(source: String, lyrics: String, device: String, separate: bool,
                      download: bool, ffmpeg: String, status_file: String,
                      output_root: String = "", title: String = "", artist: String = "", suite: String = "suite_1") -> PackedStringArray:
    var args = PackedStringArray()
    if OS.has_feature("editor"):
        args.append_array(["-m", "karaoke_analyzer.song_import"])
    args.append_array([source,
        "--output-root", output_root if not output_root.is_empty() else Paths.data_root().path_join("songs"), "--status", status_file,
        "--data-root", Paths.data_root(), "--device", device, "--suite", suite])
    if not lyrics.is_empty():
        args.append_array(["--lyrics", lyrics])
    if not separate:
        args.append("--without-separation")
    if download:
        args.append("--allow-model-download")
    if not ffmpeg.is_empty():
        args.append_array(["--ffmpeg-location", ffmpeg])
    if not title.is_empty():
        args.append_array(["--title", title.strip_edges()])
    if not artist.is_empty():
        args.append_array(["--artist", artist.strip_edges()])
    return args

func start(python: String, source: String, lyrics: String, device: String,
           separate: bool, download: bool, ffmpeg: String,
           title: String = "", artist: String = "", suite: String = "suite_1") -> Error:
    if busy:
        return ERR_BUSY
    if not FileAccess.file_exists(python) or not FileAccess.file_exists(source):
        return ERR_FILE_NOT_FOUND
    if source.get_extension().to_lower() != "mp3":
        return ERR_INVALID_PARAMETER
    if not lyrics.is_empty() and (not FileAccess.file_exists(lyrics) or lyrics.get_extension().to_lower() != "lrc"):
        return ERR_INVALID_PARAMETER
    if not ffmpeg.is_empty() and not DirAccess.dir_exists_absolute(ffmpeg):
        return ERR_FILE_NOT_FOUND
    var jobs = Paths.data_root().path_join("import-jobs")
    var directory_error = DirAccess.make_dir_recursive_absolute(jobs)
    if directory_error != OK:
        return directory_error
    status_path = jobs.path_join("%s_%s.json" % [
        Time.get_unix_time_from_system(), Time.get_ticks_usec()])
    var args = arguments(source, lyrics, device, separate, download, ffmpeg, status_path, library_root, title, artist, suite)
    worker = Thread.new()
    busy = true
    _last_status = ""
    var error = worker.start(func(): return execute_process(python, args))
    if error != OK:
        busy = false
        worker = null
    return error

func execute_process(python: String, args: PackedStringArray) -> Dictionary:
    var output: Array = []
    var code = OS.execute(python, args, output, true, false)
    return {"code": code, "output": "\n".join(output)}

func _process(_delta: float) -> void:
    if not busy:
        return
    var state: Dictionary = {}
    if FileAccess.file_exists(status_path):
        var raw = FileAccess.get_file_as_string(status_path)
        var parsed = JSON.parse_string(raw)
        if parsed is Dictionary:
            state = parsed
            if raw != _last_status:
                _last_status = raw
                updated.emit(state)
    if not worker.is_alive():
        var result = worker.wait_to_finish()
        # Read again after joining: the worker may have published status during this frame.
        if FileAccess.file_exists(status_path):
            var final_state = JSON.parse_string(FileAccess.get_file_as_string(status_path))
            if final_state is Dictionary:
                state = final_state
        worker = null
        busy = false
        var success = result.code == 0 and state.get("state", "") == "complete"
        if not success and state.get("state", "") != "error":
            state = {"state": "error", "message": "Falha ao executar o analisador (código %s). %s" % [result.code, str(result.output).right(3000)]}
        finished.emit(success, state)

func _exit_tree() -> void:
    if worker != null and worker.is_started():
        worker.wait_to_finish()
