extends Control
const Neon = preload("res://scripts/neon_theme.gd")

signal start_requested(use_microphone: bool)
signal replay_requested
signal restart_requested
signal menu_requested

var overlay: CenterContainer
var heading: Label
var description: Label
var final_score: Label
var primary: Button
var preview: Button
var restart: Button
var progress: ProgressBar
var stack: VBoxContainer

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    get_parent().theme = Neon.create()
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
    restart.text = "REINICIAR RODADA"
    restart.add_theme_font_size_override("font_size", 14)
    Neon.accent_button(restart, Neon.MAGENTA)
    restart.position = Vector2(12, 112)
    restart.pressed.connect(func(): restart_requested.emit())
    add_child(restart)
    var back = Button.new()
    back.text = "MENU PRINCIPAL"
    back.add_theme_font_size_override("font_size", 15)
    Neon.accent_button(back, Neon.YELLOW)
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
    panel.add_theme_stylebox_override("panel", Neon.frame(Color(Neon.CYAN, 0.55), 28))
    overlay.add_child(panel)
    stack = VBoxContainer.new()
    stack.add_theme_constant_override("separation", 18)
    panel.add_child(stack)
    heading = Label.new()
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    Neon.title(heading)
    stack.add_child(heading)
    final_score = Label.new()
    final_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    final_score.add_theme_font_size_override("font_size", 96)
    final_score.hide()
    stack.add_child(final_score)
    description = Label.new()
    description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    description.size_flags_vertical = Control.SIZE_EXPAND_FILL
    stack.add_child(description)
    primary = Button.new()
    Neon.accent_button(primary, Neon.GREEN)
    primary.custom_minimum_size.y = 48
    primary.pressed.connect(func():
        if primary.text == "JOGAR NOVAMENTE":
            replay_requested.emit()
        else:
            start_requested.emit(true))
    stack.add_child(primary)
    preview = Button.new()
    preview.text = "OUVIR E ACOMPANHAR SEM PONTUAR"
    preview.add_theme_font_size_override("font_size", 16)
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

static func score_text(points: float) -> String:
    return "%.1f" % (clampf(points, 0, 10000) / 1000.0)

static func score_color(points: float) -> Color:
    var fraction = clampf(points / 10000.0, 0, 1)
    var red = Color("#f87171")
    var yellow = Color("#facc15")
    var green = Color("#4ade80")
    return red.lerp(yellow, fraction * 2) if fraction <= 0.5 else yellow.lerp(green, (fraction - 0.5) * 2)

func prepare(title: String, available: bool) -> void:
    stack.alignment = BoxContainer.ALIGNMENT_BEGIN
    description.size_flags_vertical = Control.SIZE_EXPAND_FILL
    final_score.hide()
    overlay.show()
    restart.hide()
    progress.value = 0
    heading.text = "SUA PRÓXIMA MÚSICA"
    description.text = "%s\n\nEscolha a oitava adequada à sua voz.\nUse fones e cante seguindo as notas azuis." % title
    primary.text = "COMEÇAR A CANTAR"
    primary.visible = available
    preview.show()

func countdown(seconds: int) -> void:
    stack.alignment = BoxContainer.ALIGNMENT_CENTER
    description.size_flags_vertical = Control.SIZE_FILL
    final_score.hide()
    overlay.show()
    restart.hide()
    heading.text = str(seconds)
    description.text = "PREPARE SUA VOZ"
    primary.hide()
    preview.hide()

func playing(fraction: float) -> void:
    overlay.hide()
    restart.show()
    progress.value = fraction * 100

func finish(title: String, score: Dictionary, scored: bool) -> void:
    stack.alignment = BoxContainer.ALIGNMENT_BEGIN
    description.size_flags_vertical = Control.SIZE_EXPAND_FILL
    overlay.show()
    restart.hide()
    progress.value = 100
    heading.text = "RODADA CONCLUÍDA"
    final_score.visible = scored
    if scored:
        final_score.text = score_text(score.points)
        final_score.add_theme_color_override("font_color", score_color(score.points))
    description.text = "%s\n\nAfinação %.0f%%   ·   Canto %.0f%%" % [
        title, score.accuracy, score.coverage] if scored else title + "\n\nVocê acompanhou a música sem pontuação."
    primary.text = "JOGAR NOVAMENTE"
    primary.show()
    preview.hide()
