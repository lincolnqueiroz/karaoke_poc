extends VBoxContainer

signal back_requested
signal completed(message: String)
const Importer = preload("res://scripts/song_importer.gd")
const Lrclib = preload("res://scripts/lrclib_client.gd")
const Lyrics = preload("res://scripts/lrc_lyrics.gd")
var importer: Node
var source: LineEdit
var lyrics: LineEdit
var python: LineEdit
var ffmpeg: LineEdit
var separate: CheckBox
var downloads: CheckBox
var device: OptionButton
var progress: ProgressBar
var status: Label
var launch: Button
var back: Button
var fields: VBoxContainer
var title_field: LineEdit
var artist_field: LineEdit
var lyrics_mode: OptionButton
var local_box: VBoxContainer
var online_box: VBoxContainer
var search_button: Button
var results: OptionButton
var preview: TextEdit
var lyric_status: Label
var online_client: Node
var candidates: Array = []
var selected_lyrics: Dictionary = {}
var temporary_lrc: String = ""
var importing: bool = false

func _ready() -> void:
    add_theme_constant_override("separation", 12)
    var scroll = ScrollContainer.new()
    scroll.custom_minimum_size.y = 260
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(scroll)
    fields = VBoxContainer.new()
    fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    fields.add_theme_constant_override("separation", 10)
    scroll.add_child(fields)
    source = file_field(fields, "MP3", "*.mp3 ; Áudio MP3")
    title_field = text_field("Título (obrigatório)")
    artist_field = text_field("Artista (opcional)")
    lyrics_mode = OptionButton.new()
    lyrics_mode.add_item("Sem letra")
    lyrics_mode.add_item("Importar arquivo LRC")
    lyrics_mode.add_item("Buscar letra online — LRCLIB")
    fields.add_child(lyrics_mode)
    local_box = VBoxContainer.new()
    fields.add_child(local_box)
    lyrics = file_field(local_box, "Letra LRC", "*.lrc ; Letra sincronizada")
    online_box = VBoxContainer.new()
    online_box.add_theme_constant_override("separation", 8)
    fields.add_child(online_box)
    search_button = Button.new()
    search_button.text = "Buscar pelo título e artista"
    search_button.pressed.connect(search_lyrics)
    online_box.add_child(search_button)
    results = OptionButton.new()
    results.clip_text = true
    results.item_selected.connect(select_lyrics)
    online_box.add_child(results)
    lyric_status = Label.new()
    lyric_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    lyric_status.text = "A busca usa título e artista. O áudio não é enviado. Escolha a mesma gravação."
    online_box.add_child(lyric_status)
    preview = TextEdit.new()
    preview.editable = false
    preview.custom_minimum_size.y = 130
    online_box.add_child(preview)
    online_client = Lrclib.new()
    add_child(online_client)
    online_client.received.connect(on_candidates)
    online_client.failed.connect(on_lyrics_error)
    lyrics_mode.item_selected.connect(change_lyrics_mode)
    for field in [title_field, artist_field, source]:
        field.text_changed.connect(func(_text): invalidate_online())
    change_lyrics_mode(0)
    if OS.has_feature("editor"):
        python = file_field(fields, "Python do venv", "*.exe ; Executável Python")
        python.text = Importer.Paths.analyzer()
        ffmpeg = file_field(fields, "Pasta FFmpeg (opcional se estiver no PATH)", "", true)
    separate = CheckBox.new()
    separate.text = "Separar voz com Demucs (recomendado)"
    separate.button_pressed = true
    fields.add_child(separate)
    device = OptionButton.new()
    device.add_item("GPU NVIDIA (CUDA)")
    device.add_item("CPU")
    fields.add_child(device)
    separate.toggled.connect(func(enabled): device.disabled = not enabled)
    downloads = CheckBox.new()
    downloads.text = "Permitir baixar pesos oficiais do Demucs se necessário"
    fields.add_child(downloads)
    progress = ProgressBar.new()
    progress.show_percentage = false
    progress.custom_minimum_size.y = 10
    add_child(progress)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status.text = "Selecione um MP3 que você tenha autorização para usar. A análise pode levar vários minutos."
    add_child(status)
    launch = Button.new()
    launch.text = "Importar música"
    launch.custom_minimum_size.y = 48
    launch.pressed.connect(begin)
    add_child(launch)
    back = Button.new()
    back.text = "Voltar"
    back.pressed.connect(func(): back_requested.emit())
    add_child(back)
    importer.updated.connect(on_update)
    importer.finished.connect(on_finish)

func file_field(parent: Node, title: String, filter: String, folder: bool = false) -> LineEdit:
    var caption = Label.new()
    caption.text = title
    parent.add_child(caption)
    var row = HBoxContainer.new()
    parent.add_child(row)
    var field = LineEdit.new()
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(field)
    var choose = Button.new()
    choose.text = "Escolher"
    row.add_child(choose)
    choose.pressed.connect(func():
        var dialog = FileDialog.new()
        dialog.access = FileDialog.ACCESS_FILESYSTEM
        dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if folder else FileDialog.FILE_MODE_OPEN_FILE
        if not folder:
            dialog.filters = PackedStringArray([filter])
        dialog.file_selected.connect(func(path): field.text = path; field.text_changed.emit(path); dialog.queue_free())
        dialog.dir_selected.connect(func(path): field.text = path; field.text_changed.emit(path); dialog.queue_free())
        dialog.canceled.connect(func(): dialog.queue_free())
        add_child(dialog)
        dialog.popup_centered(Vector2i(900, 560)))
    return field

func begin() -> void:
    if title_field.text.strip_edges().is_empty():
        status.text = "Informe o título da música."
        title_field.grab_focus()
        return
    if title_field.text.strip_edges().length() > 200 or artist_field.text.strip_edges().length() > 200:
        status.text = "Título e artista devem ter no máximo 200 caracteres."
        return
    if importing or online_client.waiting:
        return
    var selected_path: String = ""
    if lyrics_mode.selected == 1:
        selected_path = lyrics.text.strip_edges()
        if selected_path.is_empty():
            status.text = "Selecione o arquivo LRC ou escolha Sem letra."
            return
    elif lyrics_mode.selected == 2:
        if selected_lyrics.is_empty():
            status.text = "Busque e selecione uma letra sincronizada para importar."
            return
        if not FileAccess.file_exists(source.text.strip_edges()) or source.text.strip_edges().get_extension().to_lower() != "mp3":
            status.text = "Selecione um MP3 existente."
            return
        var audio = AudioStreamMP3.load_from_file(source.text.strip_edges())
        if audio == null:
            status.text = "Não foi possível ler o MP3 selecionado."
            return
        var validation = Lyrics.parse(str(selected_lyrics.lrc), audio.get_length())
        if not validation.error.is_empty() or validation.cues.is_empty():
            status.text = "A letra selecionada não tem versos válidos para este MP3. Escolha outro resultado."
            return
        var jobs = Importer.Paths.data_root().path_join("import-jobs")
        var directory_error = DirAccess.make_dir_recursive_absolute(jobs)
        if directory_error != OK:
            status.text = "Não foi possível preparar a letra: " + error_string(directory_error)
            return
        temporary_lrc = jobs.path_join("lyrics_%s_%s.lrc" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
        var file = FileAccess.open(temporary_lrc, FileAccess.WRITE)
        if file == null:
            status.text = "Não foi possível salvar a letra online."
            temporary_lrc = ""
            return
        file.store_string("[re:LRCLIB https://lrclib.net/api/get/%d]\n" % int(selected_lyrics.id) + str(selected_lyrics.lrc))
        file.close()
        selected_path = temporary_lrc
    var executable = python.text.strip_edges() if python != null else Importer.Paths.analyzer()
    var tools = ffmpeg.text.strip_edges() if ffmpeg != null else Importer.Paths.ffmpeg()
    var error = importer.start(executable, source.text.strip_edges(),
        selected_path, "cuda" if device.selected == 0 else "cpu",
        separate.button_pressed, downloads.button_pressed, tools,
        title_field.text.strip_edges(), artist_field.text.strip_edges())
    if error != OK:
        status.text = "Confira os arquivos selecionados e a instalação do analisador: " + error_string(error)
        cleanup_lyrics()
        return
    importing = true
    launch.disabled = true
    back.disabled = true
    lock_fields(true)
    status.text = "Preparando a importação…"
    progress.value = 0

func on_update(state: Dictionary) -> void:
    progress.value = float(state.get("progress", 0)) * 100
    status.text = str(state.get("message", "Analisando…"))

func on_finish(success: bool, state: Dictionary) -> void:
    importing = false
    cleanup_lyrics()
    launch.disabled = false
    back.disabled = false
    lock_fields(false)
    on_update(state)
    if success:
        completed.emit(str(state.get("message", "Música importada.")))
    else:
        status.tooltip_text = str(state.get("diagnostics", ""))

func lock_fields(locked: bool) -> void:
    for node in fields.find_children("*", "", true, false):
        if node is BaseButton:
            node.disabled = locked
        elif node is LineEdit:
            node.editable = not locked
    if not locked:
        device.disabled = not separate.button_pressed
        preview.editable = false
        results.disabled = candidates.is_empty()

func text_field(caption_text: String) -> LineEdit:
    var caption = Label.new()
    caption.text = caption_text
    fields.add_child(caption)
    var field = LineEdit.new()
    fields.add_child(field)
    return field

func change_lyrics_mode(mode: int) -> void:
    local_box.visible = mode == 1
    online_box.visible = mode == 2
    invalidate_online()

func invalidate_online() -> void:
    if online_client == null:
        return
    online_client.cancel()
    candidates.clear()
    selected_lyrics.clear()
    results.clear()
    results.disabled = true
    preview.text = ""
    search_button.disabled = importing
    if launch != null:
        launch.disabled = importing
    lyric_status.text = "Busque e selecione a gravação correspondente ao seu MP3."

func search_lyrics() -> void:
    invalidate_online()
    var error = online_client.search(title_field.text, artist_field.text)
    if error == OK:
        search_button.disabled = true
        launch.disabled = true
        lyric_status.text = "Buscando letras sincronizadas no LRCLIB…"

func on_candidates(records: Array) -> void:
    search_button.disabled = false
    launch.disabled = false
    candidates = records
    results.clear()
    results.add_item("Selecione uma letra sincronizada")
    for record in records:
        var seconds = int(record.duration)
        results.add_item("%s — %s · %s · %02d:%02d" % [record.title, record.artist, record.album, int(seconds / 60.0), seconds % 60])
    results.disabled = records.is_empty()
    lyric_status.text = "Nenhuma letra sincronizada válida encontrada. Use um LRC local ou importe sem letra." if records.is_empty() else "Escolha a versão correta e confira a prévia abaixo."

func select_lyrics(index: int) -> void:
    selected_lyrics.clear()
    preview.text = ""
    if index <= 0 or index > candidates.size():
        return
    selected_lyrics = candidates[index - 1].duplicate(true)
    preview.text = str(selected_lyrics.lrc)
    lyric_status.text = "Letra selecionada. Versões ao vivo e remixes podem ter tempos diferentes."
    var path = source.text.strip_edges()
    if FileAccess.file_exists(path) and path.get_extension().to_lower() == "mp3":
        var audio = AudioStreamMP3.load_from_file(path)
        if audio != null:
            var difference = absf(audio.get_length() - float(selected_lyrics.duration))
            if difference > 2.0:
                lyric_status.text = "A duração difere do seu MP3 em %.1f s. Confira se é a mesma gravação antes de importar." % difference

func on_lyrics_error(message: String) -> void:
    search_button.disabled = false
    launch.disabled = false
    lyric_status.text = message

func cleanup_lyrics() -> void:
    if not temporary_lrc.is_empty():
        DirAccess.remove_absolute(temporary_lrc)
        temporary_lrc = ""

func _exit_tree() -> void:
    if online_client != null:
        online_client.cancel()
    # The menu prevents leaving during analysis; preserve an in-use input otherwise.
    if not importing:
        cleanup_lyrics()
