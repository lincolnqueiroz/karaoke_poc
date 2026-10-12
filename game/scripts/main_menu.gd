extends Control

const Library = preload("res://scripts/song_library.gd")
const PlayerScene = preload("res://scenes/karaoke_player.tscn")
const Importer = preload("res://scripts/song_importer.gd")
const ImportPage = preload("res://scripts/import_page.gd")
const Neon = preload("res://scripts/neon_theme.gd")
var importer: Node
const SETTINGS_PATH = "user://settings.cfg"
const MENU_MUSIC_PATH = "res://assets/audio/music/menu.mp3"
var input_device: String = "Default"
var input_gain_db: float = 12.0
var microphone_profile: Dictionary = {}
var volumes: Dictionary = {"Master": 100.0, "Music": 100.0, "Effects": 100.0, "MenuMusic": 30.0}
var menu_music: AudioStreamPlayer
var song_preview: Node
var content: VBoxContainer
var menu_panel: CenterContainer
var player: Control
var status: Label

func _ready() -> void:
    importer = Importer.new()
    add_child(importer)
    get_tree().auto_accept_quit = false
    var settings = ConfigFile.new()
    var error = settings.load(SETTINGS_PATH)
    if error == OK:
        input_device = str(settings.get_value("microphone", "device", "Default"))
        var gain = settings.get_value("microphone", "gain_db", 12.0)
        if (gain is float or gain is int) and is_finite(float(gain)):
            input_gain_db = clampf(float(gain), 0, 30)
        var profile = settings.get_value("microphone", "calibration", {})
        if profile is Dictionary and profile.get("device", "") == input_device:
            var gate = profile.get("gate_db", null)
            var threshold = profile.get("threshold", null)
            if (gate is float or gate is int) and (threshold is float or threshold is int):
                if is_finite(float(gate)) and gate >= -70 and gate <= -20 and is_finite(float(threshold)) and threshold >= 0.15 and threshold <= 0.30:
                    microphone_profile = profile
    elif error != ERR_FILE_NOT_FOUND:
        push_warning("Não foi possível carregar as configurações: " + error_string(error))
    for bus in volumes:
        var value = settings.get_value("volume", bus, volumes[bus])
        if (value is float or value is int) and is_finite(float(value)):
            volumes[bus] = clampf(float(value), 0, 100)
        apply_volume(bus, volumes[bus])
    setup_menu_music()
    song_preview = preload("res://scripts/song_preview.gd").new()
    song_preview.menu_music = menu_music
    add_child(song_preview)
    add_child(Neon.background())
    theme = Neon.create(18)
    menu_panel = CenterContainer.new()
    menu_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(menu_panel)
    var panel = PanelContainer.new()
    panel.custom_minimum_size = Vector2(640, 500)
    panel.add_theme_stylebox_override("panel", Neon.frame(Color(Neon.CYAN, 0.48), 28))
    menu_panel.add_child(panel)
    content = VBoxContainer.new()
    content.add_theme_constant_override("separation", 16)
    panel.add_child(content)
    show_main()

func setup_menu_music() -> void:
    menu_music = AudioStreamPlayer.new()
    menu_music.name = "MenuMusic"
    menu_music.bus = &"MenuMusic"
    add_child(menu_music)
    if not ResourceLoader.exists(MENU_MUSIC_PATH):
        push_warning("Música de fundo não encontrada: " + MENU_MUSIC_PATH)
        return
    var stream = load(MENU_MUSIC_PATH) as AudioStreamMP3
    if stream == null:
        push_warning("Não foi possível carregar a música de fundo: " + MENU_MUSIC_PATH)
        return
    stream = stream.duplicate() as AudioStreamMP3
    stream.loop = true
    menu_music.stream = stream

func play_menu_music() -> void:
    if menu_music != null and menu_music.stream != null and not menu_music.playing and not menu_music.stream_paused:
        menu_music.play()

func _exit_tree() -> void:
    if is_instance_valid(song_preview):
        song_preview.stop(false)
    if is_instance_valid(menu_music):
        menu_music.stop()

func clear_page(title: String) -> void:
    if is_instance_valid(song_preview):
        song_preview.stop()
    content.alignment = BoxContainer.ALIGNMENT_CENTER if title == "KARAOKÊ" else BoxContainer.ALIGNMENT_BEGIN
    for child in content.get_children():
        content.remove_child(child)
        child.queue_free()
    var heading = Label.new()
    heading.text = title.to_upper()
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    Neon.title(heading, Neon.MAGENTA if title == "Configurações" else Neon.CYAN)
    content.add_child(heading)

func button(text: String, callback: Callable, parent: Node = null) -> Button:
    var control = Button.new()
    control.text = text.to_upper() if parent == null else text
    control.custom_minimum_size.y = 52
    control.pressed.connect(func():
        if not importer.busy:
            callback.call())
    (parent if parent != null else content).add_child(control)
    return control

func label(text: String, parent: Node = null) -> Label:
    var control = Label.new()
    control.text = text.to_upper() if parent != null else text
    if parent != null:
        control.add_theme_font_size_override("font_size", 15)
        control.add_theme_color_override("font_color", Neon.MUTED)
    control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    (parent if parent != null else content).add_child(control)
    return control

func show_main() -> void:
    play_menu_music()
    menu_panel.show()
    clear_page("KARAOKÊ")
    Neon.title(content.get_child(0), Neon.MAGENTA, 58)
    label("Sua voz, sua música. Escolha uma canção e comece a cantar.")
    var play = button("Jogar", show_songs)
    play.icon = Neon.icon("note")
    Neon.accent_button(play, Neon.CYAN)
    play.grab_focus()
    var settings_button = button("Configurações", show_settings)
    settings_button.icon = Neon.icon("settings")
    Neon.accent_button(settings_button, Neon.MAGENTA)
    var exit = button("Sair", func(): get_tree().quit())
    exit.icon = Neon.icon("power")
    Neon.accent_button(exit, Neon.YELLOW)

func show_songs() -> void:
    clear_page("Escolha sua música")
    var library = Library.discover(preload("res://scripts/runtime_paths.gd").library_roots())
    var scroll = ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.custom_minimum_size.y = 270
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content.add_child(scroll)
    var list = VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 10)
    scroll.add_child(list)
    for song in library.songs:
        var row = HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        list.add_child(row)
        var seconds = int(song.duration)
        var song_label = str(song.title)
        if not str(song.get("artist", "")).is_empty():
            song_label += " — " + str(song.artist)
        var song_button = button("%s  ·  %02d:%02d" % [song_label, int(seconds / 60.0), seconds % 60],
               func(): open_song(song), row)
        song_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        song_button.icon = Neon.icon("note")
        song_button.clip_text = true
        song_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        var preview_button = button("", func():
            if song_preview.manifest == song.manifest:
                song_preview.stop()
            else:
                var error = song_preview.start(song)
                status.text = error, row)
        preview_button.custom_minimum_size.x = 52
        preview_button.icon = Neon.icon("play")
        preview_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        preview_button.tooltip_text = "Ouvir 10 segundos a partir do meio da música"
        Neon.accent_button(preview_button, Neon.GREEN)
        var update_preview = func(active_manifest):
            if is_instance_valid(preview_button):
                var active = active_manifest == song.manifest
                preview_button.icon = Neon.icon("pause" if active else "play")
                preview_button.tooltip_text = "Interromper prévia" if active else "Ouvir 10 segundos a partir do meio da música"
        song_preview.changed.connect(update_preview)
        preview_button.tree_exiting.connect(func():
            if song_preview.changed.is_connected(update_preview):
                song_preview.changed.disconnect(update_preview))
    if library.songs.is_empty():
        label("Nenhuma música importada encontrada. Adicione a análise e o áudio à biblioteca local.")
    if not library.errors.is_empty():
        var warning = label("Algumas músicas não puderam ser carregadas. Passe o mouse aqui para detalhes.")
        warning.tooltip_text = "\n".join(library.errors)
    status = label("")
    button("Voltar", show_main)

    var import_button = button("Importar música", show_import)
    import_button.icon = Neon.icon("import")
    Neon.accent_button(import_button, Neon.GREEN)

func show_import() -> void:
    clear_page("Importar música")
    var page = ImportPage.new()
    page.importer = importer
    page.back_requested.connect(show_songs)
    page.completed.connect(func(message):
        show_songs()
        label(message))
    content.add_child(page)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if importer != null and importer.busy:
            importer.updated.emit({"message": "Aguarde a importação terminar antes de fechar o jogo."})
        else:
            get_tree().quit()

func show_settings() -> void:
    clear_page("Configurações")
    var columns = HBoxContainer.new()
    columns.add_theme_constant_override("separation", 28)
    content.add_child(columns)
    var microphone_settings = VBoxContainer.new()
    microphone_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    microphone_settings.add_theme_constant_override("separation", 12)
    columns.add_child(microphone_settings)
    var audio_settings = VBoxContainer.new()
    audio_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    audio_settings.add_theme_constant_override("separation", 8)
    columns.add_child(audio_settings)
    label("Microfone", microphone_settings)
    var devices = OptionButton.new()
    var available = AudioServer.get_input_device_list()
    for device in available:
        devices.add_item(device)
    var selected = available.find(input_device)
    devices.select(selected if selected >= 0 else 0)
    devices.disabled = available.is_empty() or AudioServer.get_driver_name() == "Dummy"
    devices.clip_text = true
    devices.fit_to_longest_item = false
    microphone_settings.add_child(devices)
    label("Ganho da entrada", microphone_settings)
    var gain = SpinBox.new()
    gain.min_value = 0
    gain.max_value = 30
    gain.value = input_gain_db
    gain.suffix = "dB"
    microphone_settings.add_child(gain)
    var calibrate = button("Calibrar microfone", func():
        var device = devices.get_item_text(devices.selected) if devices.selected >= 0 else "Default"
        var dialog = preload("res://scripts/calibration_dialog.gd").new()
        dialog.device = device
        dialog.theme = theme
        var resume_music = menu_music.playing
        menu_music.stop()
        add_child(dialog)
        dialog.tree_exited.connect(func():
            if resume_music:
                play_menu_music())
        dialog.calibrated.connect(func(profile):
            var previous = microphone_profile.duplicate()
            profile["device"] = device
            microphone_profile = profile
            var error = save_settings(device, profile.gain_db)
            if error == OK:
                gain.value = input_gain_db
                status.text = "Calibração aplicada e salva para este microfone."
            else:
                microphone_profile = previous
                status.text = "Não foi possível salvar a calibração: " + error_string(error))
        dialog.popup_centered(), microphone_settings)
    calibrate.disabled = devices.disabled
    var test_microphone = button("Testar microfone", func():
        var device = devices.get_item_text(devices.selected) if devices.selected >= 0 else "Default"
        open_microphone_test(device, gain.value), microphone_settings)
    test_microphone.name = "TestMicrophone"
    test_microphone.disabled = devices.disabled
    for entry in [["Master", "Volume geral"], ["Effects", "Volume dos efeitos"],
                  ["Music", "Volume da canção"], ["MenuMusic", "Música de fundo (menus)"]]:
        volume_control(audio_settings, entry[0], entry[1])
    status = label("O ganho amplifica voz e ruído. Use fones de ouvido.")
    if selected < 0:
        status.text = "Microfone salvo indisponível. Escolha outro dispositivo."
    button("Salvar configurações", func():
        var device = devices.get_item_text(devices.selected) if devices.selected >= 0 else "Default"
        var previous_profile = microphone_profile.duplicate()
        if device != input_device or not is_equal_approx(gain.value, input_gain_db):
            microphone_profile = {}
        var error = save_settings(device, gain.value)
        if error != OK:
            microphone_profile = previous_profile
            status.text = "Não foi possível salvar: " + error_string(error)
            return
        status.text = "Configurações salvas.")
    button("Voltar", show_main)

func open_microphone_test(device: String, gain: float) -> void:
    var test = preload("res://scripts/microphone_test.gd").new()
    test.device = device
    test.gain_db = gain
    if microphone_profile.get("device", "") == device and is_equal_approx(gain, input_gain_db):
        test.gate_db = microphone_profile.get("gate_db", -45.0)
        test.threshold = microphone_profile.get("threshold", 0.15)
    var resume_music = menu_music.playing
    menu_music.stop()
    menu_panel.hide()
    test.back_requested.connect(func():
        remove_child(test)
        test.queue_free()
        menu_panel.show()
        if resume_music:
            play_menu_music())
    add_child(test)

func save_settings(device: String, gain: float, path: String = SETTINGS_PATH) -> Error:
    if not is_finite(gain) or gain < 0 or gain > 30:
        return ERR_INVALID_PARAMETER
    var config = ConfigFile.new()
    config.set_value("microphone", "device", device)
    config.set_value("microphone", "gain_db", gain)
    config.set_value("microphone", "calibration", microphone_profile)
    for bus in volumes:
        config.set_value("volume", bus, volumes[bus])
    var error = config.save(path)
    if error == OK:
        input_device = device
        input_gain_db = gain
    return error

func apply_volume(bus: String, percentage: float) -> void:
    if not volumes.has(bus) or not is_finite(percentage):
        return
    volumes[bus] = clampf(percentage, 0, 100)
    var index = AudioServer.get_bus_index(bus)
    if index >= 0:
        AudioServer.set_bus_volume_linear(index, volumes[bus] / 100.0)
        AudioServer.set_bus_mute(index, volumes[bus] == 0)

func volume_control(parent: Node, bus: String, caption: String) -> void:
    label(caption, parent)
    var row = HBoxContainer.new()
    parent.add_child(row)
    var slider = HSlider.new()
    slider.name = bus + "Volume"
    slider.min_value = 0
    slider.max_value = 100
    slider.step = 1
    slider.value = volumes[bus]
    slider.custom_minimum_size = Vector2(160, 32)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    var value = Label.new()
    value.custom_minimum_size.x = 54
    value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value.text = "%d%%" % slider.value
    row.add_child(value)
    slider.value_changed.connect(func(percentage):
        apply_volume(bus, percentage)
        value.text = "%d%%" % percentage)

func open_song(song: Dictionary) -> void:
    song_preview.stop()
    if not FileAccess.file_exists(song.manifest):
        show_songs()
        label("A música selecionada não está mais disponível.")
        return
    player = PlayerScene.instantiate()
    player.song_manifest = song.manifest
    player.lyrics_file = song.lyrics
    player.configured_input_device = input_device
    player.get_node("Microphone").input_gain_db = input_gain_db
    if microphone_profile.get("device", "") == input_device:
        player.get_node("Microphone").noise_gate_db = microphone_profile.get("gate_db", -45.0)
        player.get_node("Microphone").periodicity_threshold = microphone_profile.get("threshold", 0.15)
    player.get_node("MicrophoneControls/Devices").hide()
    player.get_node("MicrophoneControls/Gain").hide()
    player.menu_requested.connect(return_to_menu)
    player.preparation_started.connect(play_menu_music)
    player.countdown_started.connect(menu_music.stop)
    menu_panel.hide()
    add_child(player)

func return_to_menu() -> void:
    if is_instance_valid(player):
        remove_child(player)
        player.queue_free()
    player = null
    show_main()
