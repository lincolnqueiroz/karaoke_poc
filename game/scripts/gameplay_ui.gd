extends Control

signal start_requested(use_microphone: bool)
signal replay_requested
signal restart_requested
signal menu_requested

var overlay: CenterContainer
var heading: Label
var description: Label
var primary: Button
var preview: Button
var restart: Button
var progress: ProgressBar

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var ui_theme = Theme.new()
    ui_theme.default_font_size = 18
    var normal = card(Color("#17243b"), Color("#334764"))
    var hover = card(Color("#233e59"), Color("#38bdf8"))
    for kind in ["Button", "OptionButton", "SpinBox"]:
        ui_theme.set_stylebox("normal", kind, normal)
        ui_theme.set_stylebox("hover", kind, hover)
        ui_theme.set_stylebox("pressed", kind, hover)
        ui_theme.set_stylebox("focus", kind, hover)
    get_parent().theme = ui_theme
    progress = ProgressBar.new()
    progress.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    progress.offset_top = 36
    progress.offset_bottom = 40
    progress.show_percentage = false
    progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # Button padding would force this four-pixel bar to expand into the controls.
    progress.add_theme_stylebox_override("background", card(Color("#17243b"), Color.TRANSPARENT, 0))
    progress.add_theme_stylebox_override("fill", card(Color("#22d3ee"), Color.TRANSPARENT, 0))
    add_child(progress)
    restart = Button.new()
    restart.text = "Reiniciar rodada"
    restart.position = Vector2(12, 112)
    restart.pressed.connect(func(): restart_requested.emit())
    add_child(restart)
    var back = Button.new()
    back.text = "Menu principal"
    back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    back.offset_left = -190
    back.offset_right = -12
    back.offset_top = 112
    back.offset_bottom = 150
    back.pressed.connect(func(): menu_requested.emit())
    add_child(back)
    overlay = CenterContainer.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.offset_top = 160
    add_child(overlay)
    var panel = PanelContainer.new()
    panel.custom_minimum_size = Vector2(560, 330)
    panel.add_theme_stylebox_override("panel", card(Color("#101e34"), Color("#30516b"), 28))
    overlay.add_child(panel)
    var stack = VBoxContainer.new()
    stack.add_theme_constant_override("separation", 18)
    panel.add_child(stack)
    heading = Label.new()
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 36)
    heading.add_theme_color_override("font_color", Color("#67e8f9"))
    stack.add_child(heading)
    description = Label.new()
    description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    description.size_flags_vertical = Control.SIZE_EXPAND_FILL
    stack.add_child(description)
    primary = Button.new()
    primary.custom_minimum_size.y = 48
    primary.pressed.connect(func():
        if primary.text == "Jogar novamente":
            replay_requested.emit()
        else:
            start_requested.emit(true))
    stack.add_child(primary)
    preview = Button.new()
    preview.text = "Ouvir e acompanhar sem pontuar"
    preview.pressed.connect(func(): start_requested.emit(false))
    stack.add_child(preview)

static func card(color: Color, border: Color = Color.TRANSPARENT, padding: int = 10) -> StyleBoxFlat:
    var box = StyleBoxFlat.new()
    box.bg_color = color
    box.border_color = border
    box.set_border_width_all(1)
    box.set_corner_radius_all(12)
    box.content_margin_left = padding
    box.content_margin_right = padding
    box.content_margin_top = padding
    box.content_margin_bottom = padding
    return box

func prepare(title: String, available: bool) -> void:
    overlay.show()
    restart.hide()
    progress.value = 0
    heading.text = "Sua próxima música"
    description.text = "%s\n\nEscolha a oitava adequada à sua voz.\nUse fones e cante seguindo as notas azuis." % title
    primary.text = "Começar a cantar"
    primary.visible = available
    preview.show()

func countdown(seconds: int) -> void:
    overlay.show()
    restart.hide()
    heading.text = str(seconds)
    description.text = "Prepare sua voz"
    primary.hide()
    preview.hide()

func playing(fraction: float) -> void:
    overlay.hide()
    restart.show()
    progress.value = fraction * 100

func finish(title: String, score: Dictionary, scored: bool) -> void:
    overlay.show()
    restart.hide()
    progress.value = 100
    heading.text = "Rodada concluída"
    description.text = "%s\n\n%05d / 10000 pontos\nAfinação %.0f%%   ·   Canto %.0f%%" % [
        title, score.points, score.accuracy, score.coverage] if scored else title + "\n\nVocê acompanhou a música sem pontuação."
    primary.text = "Jogar novamente"
    primary.show()
    preview.hide()
