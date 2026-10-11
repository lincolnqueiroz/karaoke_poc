extends Control

const LrcLyrics = preload("res://scripts/lrc_lyrics.gd")
const MicrophoneCapture = preload("res://scripts/microphone_capture.gd")
const SingingScore = preload("res://scripts/singing_score.gd")
const GameplayUI = preload("res://scripts/gameplay_ui.gd")
const COUNTDOWN_SOUND_PATH = "res://assets/audio/sfx/countdown.mp3"
signal menu_requested
signal preparation_started
signal countdown_started
var configured_input_device: String = "Default"
enum RoundState { PREPARE, COUNTDOWN, PLAYING, RESULT }
var round_state = RoundState.PLAYING
var gameplay_ui: GameplayUI
var song_title: String = "Karaoke"
var _countdown: float = 0.0
var _scored_round: bool = false
var note_style = GameplayUI.Neon.frame(Color("#35deff"), 0)

@export_file("*.json") var song_manifest: String = "res://demo/song.json"
@export_file("*.lrc") var lyrics_file: String = ""
@export_range(1.0, 20.0, 0.5) var window_seconds: float = 8.0
@export_range(0.1, 0.9, 0.05) var cursor_position: float = 0.25
## Positive values make notes reach the cursor earlier; negative values delay them.
@export_range(-0.5, 0.5, 0.01) var visual_offset_seconds: float = 0.0
## Additional input-device latency; positive values move captured pitch into the past.
@export_range(0.0, 0.5, 0.01) var microphone_latency_seconds: float = 0.0

var notes: Array = []
var pitch_min: float = 48.0
var pitch_max: float = 84.0
var song_duration: float = 0.0
var elapsed: float = 0.0
var audio_player: AudioStreamPlayer
var countdown_player: AudioStreamPlayer
var audio_loaded: bool = false
var output_latency: float = 0.0
var lyric_cues: Array = []
var lyrics_label: Label
var next_lyrics_label: Label
var microphone: MicrophoneCapture
var microphone_button: Button
var microphone_devices: OptionButton
var microphone_status: Label
var sung_pitch: Array = []
var voice_octaves: int = 0
var scorer = SingingScore.new()
var score_label: Label
var _end_wait: float = 0.0

func _ready() -> void:
    output_latency = AudioServer.get_output_latency()
    note_style.set_corner_radius_all(6)
    note_style.bg_color = Color("#167997")
    note_style.shadow_size = 5
    audio_player = get_node_or_null("Audio") as AudioStreamPlayer
    _setup_countdown_sound()
    lyrics_label = get_node_or_null("Lyrics") as Label
    next_lyrics_label = get_node_or_null("NextLyrics") as Label
    _load_song(song_manifest)
    scorer.configure(notes, song_duration, visual_offset_seconds)
    score_label = get_node_or_null("Score") as Label
    var reset_score = get_node_or_null("MicrophoneControls/ResetScore") as Button
    if reset_score != null:
        reset_score.pressed.connect(func(): scorer.reset(elapsed))
    _load_lyrics()
    _setup_microphone()
    gameplay_ui = GameplayUI.new()
    add_child(gameplay_ui)
    gameplay_ui.start_requested.connect(start_round)
    gameplay_ui.replay_requested.connect(prepare_round)
    gameplay_ui.restart_requested.connect(prepare_round)
    gameplay_ui.menu_requested.connect(func():
        countdown_player.stop()
        menu_requested.emit())
    prepare_round()
    set_process(true)

func _setup_countdown_sound() -> void:
    countdown_player = AudioStreamPlayer.new()
    countdown_player.name = "CountdownSound"
    countdown_player.bus = &"Effects"
    add_child(countdown_player)
    if not ResourceLoader.exists(COUNTDOWN_SOUND_PATH):
        push_warning("Efeito da contagem não encontrado: " + COUNTDOWN_SOUND_PATH)
        return
    var stream = load(COUNTDOWN_SOUND_PATH) as AudioStreamMP3
    if stream == null:
        push_warning("Não foi possível carregar o efeito da contagem: " + COUNTDOWN_SOUND_PATH)
        return
    stream = stream.duplicate() as AudioStreamMP3
    stream.loop = false
    countdown_player.stream = stream

func _exit_tree() -> void:
    if is_instance_valid(countdown_player):
        countdown_player.stop()

func prepare_round() -> void:
    if countdown_player != null:
        countdown_player.stop()
    if audio_player != null:
        audio_player.stop()
    elapsed = 0.0
    _end_wait = 0.0
    sung_pitch.clear()
    scorer = SingingScore.new()
    scorer.configure(notes, song_duration, visual_offset_seconds)
    round_state = RoundState.PREPARE
    if lyrics_label != null:
        lyrics_label.text = ""
    if next_lyrics_label != null:
        next_lyrics_label.text = ""
    if score_label != null:
        score_label.text = "Pronto para uma nova rodada"
    _set_round_controls(false)
    if gameplay_ui != null:
        gameplay_ui.prepare(song_title, song_duration > 0)
        gameplay_ui.preview.disabled = song_duration <= 0
    queue_redraw()
    preparation_started.emit()

func start_round(use_microphone: bool = true) -> void:
    if round_state != RoundState.PREPARE or song_duration <= 0:
        return
    if use_microphone:
        if microphone == null:
            return
        if not microphone.active:
            _toggle_microphone()
        if not microphone.active:
            return
        # Discard preparation audio before the timed round.
        microphone.discard_pending()
    elif microphone != null and microphone.active:
        _toggle_microphone()
    _scored_round = use_microphone
    if score_label != null:
        score_label.text = "Pontos 0.0 / 10.0" if use_microphone else "Modo acompanhamento · sem pontuação"
    scorer = SingingScore.new()
    scorer.configure(notes, song_duration, visual_offset_seconds)
    _countdown = 3.0
    round_state = RoundState.COUNTDOWN
    countdown_started.emit()
    if countdown_player != null and countdown_player.stream != null:
        countdown_player.play()
    _set_round_controls(true)
    if gameplay_ui != null:
        gameplay_ui.countdown(3)

func _set_round_controls(locked: bool) -> void:
    for path in ["MicrophoneControls/Octave", "MicrophoneControls/ResetScore"]:
        var button = get_node_or_null(path) as BaseButton
        if button != null:
            button.disabled = locked
    var reset = get_node_or_null("MicrophoneControls/ResetScore") as Control
    if reset != null:
        reset.hide()

func _finish_round() -> void:
    countdown_player.stop()
    scorer.advance(song_duration)
    round_state = RoundState.RESULT
    if microphone != null and microphone.active:
        _toggle_microphone()
    _set_round_controls(true)
    if gameplay_ui != null:
        gameplay_ui.finish(song_title, scorer.result(), _scored_round)

func _load_song(path: String) -> void:
    if not FileAccess.file_exists(path):
        push_error("Manifest not found: " + path)
        return
    var data = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(data) != TYPE_DICTIONARY or data.get("schema_version", "") != "1.0":
        push_error("Invalid or unsupported manifest")
        return
    notes = data.get("notes", [])
    _set_pitch_bounds()
    song_title = str(data.get("title", path.get_base_dir().get_file()))
    song_duration = float(data.get("duration_seconds", 0.0))
    var original_path: String = str(data.get("audio", {}).get("original", ""))
    if original_path != "" and audio_player != null:
        var full_path: String = path.get_base_dir().path_join(original_path)
        if FileAccess.file_exists(full_path):
            # Godot 4 supports runtime MP3 loading via AudioStreamMP3.load_from_file.
            var stream = AudioStreamMP3.load_from_file(full_path)
            if stream != null:
                audio_player.stream = stream
                audio_loaded = true
    queue_redraw()

func _load_lyrics() -> void:
    lyric_cues.clear()
    if lyrics_file.is_empty():
        return
    if not FileAccess.file_exists(lyrics_file):
        push_warning("Lyrics file not found: " + lyrics_file)
        return
    var result = LrcLyrics.parse(FileAccess.get_file_as_string(lyrics_file), song_duration)
    if not result.error.is_empty():
        push_error("Invalid LRC: " + str(result.error))
        return
    lyric_cues = result.cues

func _process(delta: float) -> void:
    if round_state == RoundState.PREPARE or round_state == RoundState.RESULT:
        return
    if round_state == RoundState.COUNTDOWN:
        _countdown -= delta
        if _countdown > 0:
            if gameplay_ui != null:
                gameplay_ui.countdown(int(ceil(_countdown)))
            return
        elapsed = 0.0
        # The final beep starts around 3 s; let its short tail finish over the song.
        sung_pitch.clear()
        if microphone != null:
            microphone.discard_pending()
        if _scored_round:
            scorer.reset(0.0)
        if audio_loaded and audio_player != null:
            audio_player.play(0.0)
        round_state = RoundState.PLAYING
        if gameplay_ui != null:
            gameplay_ui.playing(0.0)
        return
    if audio_loaded and audio_player != null:
        if audio_player.playing:
            _update_audio_clock(audio_player.get_playback_position(),
                                AudioServer.get_time_since_last_mix(), output_latency)
        else:
            elapsed = song_duration
    else:
        elapsed = minf(elapsed + delta, song_duration)
    if lyrics_label != null:
        var display = LrcLyrics.display_at(lyric_cues, elapsed)
        lyrics_label.text = display.current
        lyrics_label.modulate = Color("#a5b4fc") if display.preview else Color.WHITE
        if next_lyrics_label != null:
            next_lyrics_label.text = display.next
    while not sung_pitch.is_empty() and float(sung_pitch[0].time) < elapsed - window_seconds - 1:
        sung_pitch.pop_front()
    if elapsed >= song_duration:
        _end_wait += delta
    if scorer.started:
        # Leave time for the analysis window and device latency to deliver samples.
        var finalized = elapsed - 0.3 - microphone_latency_seconds
        if _end_wait >= 0.3 + microphone_latency_seconds:
            finalized = song_duration
        scorer.advance(finalized)
        if score_label != null:
            var score = scorer.result()
            score_label.text = "%s %s / 10.0 · Afinação %.0f%% · Canto %.0f%%" % [
                "Final" if finalized >= song_duration else "Pontos",
                gameplay_ui.score_text(score.points), score.accuracy, score.coverage]
    if gameplay_ui != null:
        gameplay_ui.playing(elapsed / maxf(song_duration, 0.001))
    if elapsed >= song_duration and _end_wait >= 0.3 + microphone_latency_seconds:
        _finish_round()
    queue_redraw()

func _setup_microphone() -> void:
    microphone = get_node_or_null("Microphone") as MicrophoneCapture
    microphone_button = get_node_or_null("MicrophoneControls/Toggle") as Button
    microphone_devices = get_node_or_null("MicrophoneControls/Devices") as OptionButton
    microphone_status = get_node_or_null("MicrophoneStatus") as Label
    if microphone == null or microphone_button == null or microphone_devices == null:
        return
    for device in AudioServer.get_input_device_list():
        microphone_devices.add_item(device)
    var selected_device = AudioServer.get_input_device_list().find(configured_input_device)
    if selected_device >= 0:
        microphone_devices.select(selected_device)
    else:
        microphone_devices.select(-1)
        _on_microphone_status("Microfone configurado indisponível. Escolha outro nas Configurações.")
    microphone_button.pressed.connect(_toggle_microphone)
    microphone.sample_ready.connect(_on_microphone_sample)
    microphone.status_changed.connect(_on_microphone_status)
    var gain_control = get_node_or_null("MicrophoneControls/Gain") as SpinBox
    if gain_control != null:
        gain_control.value = microphone.input_gain_db
        gain_control.value_changed.connect(func(value):
            microphone.input_gain_db = value)
    var octave_control = get_node_or_null("MicrophoneControls/Octave") as OptionButton
    if octave_control != null:
        octave_control.add_item("Oitava original", 0)
        octave_control.add_item("Voz grave (+1 oitava)", 1)
        octave_control.add_item("Voz aguda (-1 oitava)", 2)
        octave_control.item_selected.connect(func(index):
            voice_octaves = [0, 1, -1][index]
            queue_redraw())
    if AudioServer.get_driver_name() == "Dummy" or microphone_devices.item_count == 0:
        microphone_button.disabled = true
        _on_microphone_status("Microfone indisponível nesta sessão")

func _toggle_microphone() -> void:
    if microphone.active:
        microphone.stop()
        sung_pitch.clear()
        microphone_button.text = "Ativar microfone"
        microphone_devices.disabled = false
        _on_microphone_status("Microfone desligado")
    elif microphone_devices.selected >= 0:
        var device = microphone_devices.get_item_text(microphone_devices.selected)
        if microphone.start(device):
            if not scorer.started and round_state == RoundState.PLAYING and _scored_round:
                scorer.reset(elapsed)
            microphone_button.text = "Desativar microfone"
            microphone_devices.disabled = true

func _on_microphone_status(message: String) -> void:
    if microphone_status != null:
        microphone_status.text = message

func _on_microphone_sample(result: Dictionary, age_seconds: float) -> void:
    var time = elapsed - age_seconds - microphone_latency_seconds
    if round_state == RoundState.PLAYING:
        scorer.record(time, _display_voice_midi(float(result.midi)), result.frequency > 0)
        sung_pitch.append({"time": time, "midi": result.midi, "voiced": result.frequency > 0})
    while sung_pitch.size() > int(ceil(window_seconds / 0.05)) + 64:
        sung_pitch.pop_front()
    if result.frequency > 0:
        var midi = int(round(float(result.midi)))
        var names = ["Dó", "Dó#", "Ré", "Ré#", "Mi", "Fá", "Fá#", "Sol", "Sol#", "Lá", "Lá#", "Si"]
        _on_microphone_status("Voz: %s%d · %.0f Hz · nível %.0f dB (com ganho)" % [
            names[posmod(midi, 12)], int(floor(midi / 12.0)) - 1,
            result.frequency, result.rms_db])
    elif result.rms_db <= -119:
        _on_microphone_status("Sem sinal: confira o dispositivo e as permissões do microfone")
    elif result.rms_db < microphone.noise_gate_db:
        _on_microphone_status("Entrada baixa · nível %.0f dB" % result.rms_db)
    else:
        _on_microphone_status("Entrada detectada, sem pitch estável · nível %.0f dB" % result.rms_db)
    if result.rms_db > -3:
        _on_microphone_status(microphone_status.text + " · nível alto: reduza o ganho" if microphone_status != null else "Nível alto: reduza o ganho")

func _update_audio_clock(position: float, since_mix: float, latency: float) -> void:
    # Playback position advances in audio blocks. Interpolate between mixes and
    # subtract output latency to follow the sound reaching the speakers.
    var audible_time = clampf(position + since_mix - latency, 0.0, song_duration)
    # Thread timing can jitter slightly; never scroll backwards during playback.
    elapsed = maxf(elapsed, audible_time)

func _draw() -> void:
    var w = size.x
    var h = size.y
    draw_rect(Rect2(Vector2.ZERO, size), GameplayUI.Neon.BACKGROUND)
    if song_duration <= 0.0:
        return
    for midi in range(int(floor(pitch_min / 4)) * 4, int(ceil(pitch_max)) + 1, 4):
        var y = _pitch_y(float(midi), h)
        draw_line(Vector2(0, y), Vector2(w, y), Color("#1e3049"), 1.0)
    for item in notes:
        var start = float(item.get("start", 0.0))
        var duration = float(item.get("duration", 0.0))
        var midi = float(item.get("midi", 60))
        var rect = _note_rect(start, duration, midi)
        if rect.has_area():
            draw_style_box(note_style, rect)
    var cursor_x = size.x * clampf(cursor_position, 0.1, 0.9)
    draw_line(Vector2(cursor_x, 154), Vector2(cursor_x, h - 170), Color("#ffe16a", 0.14), 10.0)
    draw_line(Vector2(cursor_x, 154), Vector2(cursor_x, h - 170), Color("#fbbf24"), 3.0)
    _draw_sung_pitch()
    _draw_time_labels()

func _draw_sung_pitch() -> void:
    var previous: Dictionary = {}
    for point in sung_pitch:
        # Both live pitch and note offsets use the same display coordinates.
        var x = _time_to_x(float(point.time) + visual_offset_seconds)
        if not point.voiced or x < 0 or x > size.x:
            previous = {}
            continue
        var position = Vector2(x, _pitch_y(_display_voice_midi(float(point.midi)), size.y))
        if not previous.is_empty() and float(point.time) - float(previous.time) <= 0.15:
            draw_line(previous.position, position, Color("#4ade80"), 3.0)
        draw_circle(position, 3.0, Color("#4ade80"))
        previous = {"time": point.time, "position": position}

func _display_voice_midi(raw_midi: float) -> float:
    return raw_midi + 12 * voice_octaves

func _format_time(seconds: float, milliseconds: bool = true) -> String:
    var total_ms = int(round(maxf(seconds, 0.0) * 1000.0))
    var total_seconds = int(total_ms / 1000.0)
    var minutes = int(total_seconds / 60.0)
    var text = "%02d:%02d" % [minutes, total_seconds % 60]
    if milliseconds:
        text += ".%03d" % (total_ms % 1000)
    return text

func _draw_time_labels() -> void:
    var font: Font = get_theme_default_font()
    var text_color = Color("#e5e7eb")
    draw_rect(Rect2(0, 0, size.x, 40), GameplayUI.Neon.PANEL)
    var text = "Tempo %s / %s" % [_format_time(elapsed), _format_time(song_duration)]
    draw_string(font, Vector2(12, 27), text, HORIZONTAL_ALIGNMENT_LEFT,
                maxf(size.x - 24, 0), 20, text_color)

    draw_string(font, Vector2(230, 136), "Referência", HORIZONTAL_ALIGNMENT_LEFT,
                130, 16, Color("#67e8f9"))
    draw_string(font, Vector2(370, 136), "Sua voz", HORIZONTAL_ALIGNMENT_LEFT,
                130, 16, Color("#4ade80"))
    var footer_y = maxf(size.y - 32, 40)
    draw_rect(Rect2(0, footer_y, size.x, 32), GameplayUI.Neon.PANEL)
    # Reduce label density in a narrow viewport or a longer time window.
    var spacing = maxi(1, int(ceil(maxf(window_seconds, 0.1) * 65 / maxf(size.x, 1))))
    var start = maxf(0.0, _window_start())
    var end = minf(song_duration, _window_start() + maxf(window_seconds, 0.1))
    var tick = int(ceil(start / spacing)) * spacing
    while tick <= end:
        var x = _time_to_x(float(tick))
        var label = _format_time(float(tick), false)
        var width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
        draw_line(Vector2(x, footer_y), Vector2(x, footer_y + 5), text_color, 1)
        if size.x >= width:
            var label_x = clampf(x - width / 2, 0, size.x - width)
            draw_string(font, Vector2(label_x, footer_y + 23), label,
                        HORIZONTAL_ALIGNMENT_LEFT, width + 1, 14, text_color)
        tick += spacing

func _window_start() -> float:
    # Allow empty history at the beginning and empty future at the end so the
    # cursor remains fixed and notes never change speed near song boundaries.
    return (elapsed + visual_offset_seconds
            - maxf(window_seconds, 0.1) * clampf(cursor_position, 0.1, 0.9))

func _time_to_x(time_seconds: float) -> float:
    return (time_seconds - _window_start()) / maxf(window_seconds, 0.1) * size.x

func _note_rect(start: float, duration: float, midi: float) -> Rect2:
    var left = maxf(0.0, _time_to_x(start))
    var right = minf(size.x, _time_to_x(start + duration))
    if duration <= 0.0 or right <= left:
        return Rect2()
    return Rect2(left, _pitch_y(midi, size.y) - 6, right - left, 12)

func _pitch_y(midi: float, height: float) -> float:
    var top = minf(160, height * 0.4)
    var bottom_margin = 170.0 if not lyric_cues.is_empty() else 40.0
    var bottom = maxf(top, height - bottom_margin)
    return lerpf(bottom, top, clampf((midi - pitch_min) / (pitch_max - pitch_min), 0.0, 1.0))

func _set_pitch_bounds() -> void:
    pitch_min = 48.0
    pitch_max = 84.0
    for note in notes:
        pitch_min = minf(pitch_min, float(note.get("midi", 60)) - 2)
        pitch_max = maxf(pitch_max, float(note.get("midi", 60)) + 2)
