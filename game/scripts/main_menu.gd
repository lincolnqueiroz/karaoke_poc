extends Control

const Library = preload("res://scripts/song_library.gd")
const UI = preload("res://scripts/gameplay_ui.gd")
const PlayerScene = preload("res://scenes/karaoke_player.tscn")
const Importer = preload("res://scripts/song_importer.gd")
const ImportPage = preload("res://scripts/import_page.gd")
var importer: Node
const SETTINGS_PATH = "user://settings.cfg"
var input_device: String = "Default"
var input_gain_db: float = 12.0
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
    elif error != ERR_FILE_NOT_FOUND:
        push_warning("Não foi possível carregar as configurações: " + error_string(error))
    var background = ColorRect.new()
    background.color = Color("#080f1e")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    theme = Theme.new()
    theme.default_font_size = 20
    for kind in ["Button", "OptionButton"]:
        theme.set_stylebox("normal", kind, UI.card(Color("#17243b"), Color("#334764"), 14))
        theme.set_stylebox("hover", kind, UI.card(Color("#233e59"), Color("#38bdf8"), 14))
        theme.set_stylebox("pressed", kind, UI.card(Color("#233e59"), Color("#38bdf8"), 14))
        theme.set_stylebox("focus", kind, UI.card(Color("#233e59"), Color("#38bdf8"), 14))
    menu_panel = CenterContainer.new()
    menu_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(menu_panel)
    var panel = PanelContainer.new()
    panel.custom_minimum_size = Vector2(640, 500)
    panel.add_theme_stylebox_override("panel", UI.card(Color("#101e34"), Color("#30516b"), 28))
    menu_panel.add_child(panel)
    content = VBoxContainer.new()
    content.add_theme_constant_override("separation", 16)
    panel.add_child(content)
    show_main()

func clear_page(title: String) -> void:
    for child in content.get_children():
        content.remove_child(child)
        child.queue_free()
    var heading = Label.new()
    heading.text = title
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 36)
    heading.add_theme_color_override("font_color", Color("#67e8f9"))
    content.add_child(heading)

func button(text: String, callback: Callable, parent: Node = null) -> Button:
    var control = Button.new()
    control.text = text
    control.custom_minimum_size.y = 52
    control.pressed.connect(callback)
    (parent if parent != null else content).add_child(control)
    return control

func label(text: String) -> Label:
    var control = Label.new()
    control.text = text
    control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(control)
    return control

func show_main() -> void:
    menu_panel.show()
    clear_page("KARAOKE")
    label("Sua voz, sua música. Escolha uma canção e comece a cantar.")
    button("Jogar", show_songs).grab_focus()
    button("Configurações", show_settings)
    button("Sair", func(): get_tree().quit())

func show_songs() -> void:
    clear_page("Escolha sua música")
    var library = Library.discover(preload("res://scripts/runtime_paths.gd").library_roots())
    var scroll = ScrollContainer.new()
    scroll.custom_minimum_size.y = 270
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content.add_child(scroll)
    var list = VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 10)
    scroll.add_child(list)
    for song in library.songs:
        var seconds = int(song.duration)
        var song_label = str(song.title)
        if not str(song.get("artist", "")).is_empty():
            song_label += " — " + str(song.artist)
        button("%s  ·  %02d:%02d" % [song_label, int(seconds / 60.0), seconds % 60],
               func(): open_song(song), list)
    if library.songs.is_empty():
        label("Nenhuma música importada encontrada. Adicione a análise e o áudio à biblioteca local.")
    if not library.errors.is_empty():
        var warning = label("Algumas músicas não puderam ser carregadas. Passe o mouse aqui para detalhes.")
        warning.tooltip_text = "\n".join(library.errors)
    button("Voltar", show_main)

    button("Importar música", show_import)

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
    label("Microfone")
    var devices = OptionButton.new()
    var available = AudioServer.get_input_device_list()
    for device in available:
        devices.add_item(device)
    var selected = available.find(input_device)
    devices.select(selected if selected >= 0 else 0)
    devices.disabled = available.is_empty() or AudioServer.get_driver_name() == "Dummy"
    content.add_child(devices)
    label("Ganho da entrada")
    var gain = SpinBox.new()
    gain.min_value = 0
    gain.max_value = 30
    gain.value = input_gain_db
    gain.suffix = "dB"
    content.add_child(gain)
    status = label("O ganho amplifica voz e ruído. Use fones de ouvido.")
    if selected < 0:
        status.text = "Microfone salvo indisponível. Escolha outro dispositivo."
    button("Salvar configurações", func():
        var device = devices.get_item_text(devices.selected) if devices.selected >= 0 else "Default"
        var error = save_settings(device, gain.value)
        if error != OK:
            status.text = "Não foi possível salvar: " + error_string(error)
            return
        status.text = "Configurações salvas.")
    button("Voltar", show_main)

func save_settings(device: String, gain: float, path: String = SETTINGS_PATH) -> Error:
    if not is_finite(gain) or gain < 0 or gain > 30:
        return ERR_INVALID_PARAMETER
    var config = ConfigFile.new()
    config.set_value("microphone", "device", device)
    config.set_value("microphone", "gain_db", gain)
    var error = config.save(path)
    if error == OK:
        input_device = device
        input_gain_db = gain
    return error

func open_song(song: Dictionary) -> void:
    if not FileAccess.file_exists(song.manifest):
        show_songs()
        label("A música selecionada não está mais disponível.")
        return
    player = PlayerScene.instantiate()
    player.song_manifest = song.manifest
    player.lyrics_file = song.lyrics
    player.configured_input_device = input_device
    player.get_node("Microphone").input_gain_db = input_gain_db
    player.get_node("MicrophoneControls/Devices").hide()
    player.get_node("MicrophoneControls/Gain").hide()
    player.menu_requested.connect(return_to_menu)
    menu_panel.hide()
    add_child(player)

func return_to_menu() -> void:
    if is_instance_valid(player):
        remove_child(player)
        player.queue_free()
    player = null
    show_main()
