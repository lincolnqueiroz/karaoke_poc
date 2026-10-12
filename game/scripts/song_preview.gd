extends Node

signal changed(manifest: String)
const LENGTH_SECONDS = 10.0
var menu_music: AudioStreamPlayer
var audio: AudioStreamPlayer
var manifest: String = ""
var end_seconds: float = 0.0
var _restore_menu: bool = false

func _ready() -> void:
    audio = AudioStreamPlayer.new()
    audio.bus = &"Music"
    add_child(audio)
    audio.finished.connect(stop)

func start(song: Dictionary) -> String:
    var path = str(song.get("manifest", ""))
    if not FileAccess.file_exists(path):
        return "A música não está mais disponível."
    var data = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not data is Dictionary or not data.get("audio", null) is Dictionary:
        return "Manifesto de música inválido."
    var original = str(data.audio.get("original", ""))
    if original.is_empty():
        return "Esta música não possui áudio para a prévia."
    var full_path = path.get_base_dir().path_join(original)
    if not FileAccess.file_exists(full_path):
        return "Áudio da música não encontrado."
    var stream = AudioStreamMP3.load_from_file(full_path)
    if stream == null or not is_finite(stream.get_length()) or stream.get_length() <= 0:
        return "Não foi possível carregar o MP3 para a prévia."
    stream.loop = false
    if manifest.is_empty():
        _restore_menu = is_instance_valid(menu_music) and menu_music.playing and not menu_music.stream_paused
        if _restore_menu:
            menu_music.stream_paused = true
    audio.stop()
    audio.stream = stream
    manifest = path
    var start_seconds = stream.get_length() / 2.0
    end_seconds = minf(start_seconds + LENGTH_SECONDS, stream.get_length())
    audio.play(start_seconds)
    changed.emit(manifest)
    return ""

func stop(restore_menu: bool = true) -> void:
    if is_instance_valid(audio):
        audio.stop()
        audio.stream = null
    manifest = ""
    if restore_menu and _restore_menu and is_instance_valid(menu_music):
        menu_music.stream_paused = false
    _restore_menu = false
    changed.emit("")

func _process(_delta: float) -> void:
    if not manifest.is_empty() and audio.get_playback_position() >= end_seconds:
        stop()

func _exit_tree() -> void:
    stop(false)
