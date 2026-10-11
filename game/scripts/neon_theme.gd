extends RefCounted

const BACKGROUND = Color("#060914")
const PANEL = Color("#0d1428")
const CYAN = Color("#35deff")
const MAGENTA = Color("#ff55cc")
const YELLOW = Color("#ffe16a")
const GREEN = Color("#64f5a6")
const TEXT = Color("#f0f5ff")
const MUTED = Color("#a5b4d2")
const MENU_BACKGROUND_PATH = "res://assets/images/backgrounds/menu.jpg"

static func frame(accent: Color, padding: int = 12, luminous: bool = true) -> StyleBoxFlat:
    var box = StyleBoxFlat.new()
    box.bg_color = PANEL
    box.border_color = accent
    box.set_border_width_all(1)
    box.set_corner_radius_all(10)
    box.content_margin_left = padding
    box.content_margin_right = padding
    box.content_margin_top = padding
    box.content_margin_bottom = padding
    if luminous:
        box.shadow_color = Color(accent, 0.22)
        box.shadow_size = 8
    return box

static func create(font_size: int = 18) -> Theme:
    var result = Theme.new()
    result.default_font_size = font_size
    result.set_color("font_color", "Label", TEXT)
    for kind in ["Button", "OptionButton"]:
        result.set_stylebox("normal", kind, frame(Color(CYAN, 0.48)))
        result.set_stylebox("hover", kind, frame(CYAN))
        var pressed = frame(MAGENTA)
        pressed.bg_color = Color("#251333")
        result.set_stylebox("pressed", kind, pressed)
        var focus = frame(YELLOW, 0, false)
        focus.draw_center = false
        focus.set_border_width_all(2)
        result.set_stylebox("focus", kind, focus)
        result.set_stylebox("disabled", kind, frame(Color("#29364e"), 12, false))
        result.set_color("font_color", kind, TEXT)
        result.set_color("font_hover_color", kind, CYAN)
        result.set_color("font_pressed_color", kind, MAGENTA)
        result.set_color("font_disabled_color", kind, Color("#74829e"))
    for kind in ["LineEdit", "TextEdit"]:
        result.set_stylebox("normal", kind, frame(Color("#34466b"), 10, false))
        var focused = frame(CYAN, 0)
        focused.draw_center = false
        result.set_stylebox("focus", kind, focused)
        result.set_color("font_color", kind, TEXT)
        result.set_color("caret_color", kind, CYAN)
        result.set_color("selection_color", kind, Color("#573569"))
    result.set_color("font_color", "CheckBox", TEXT)
    result.set_color("font_hover_color", "CheckBox", CYAN)
    result.set_stylebox("panel", "PopupMenu", frame(MAGENTA))
    result.set_color("font_color", "PopupMenu", TEXT)
    result.set_color("font_hover_color", "PopupMenu", CYAN)
    result.set_stylebox("hover", "PopupMenu", frame(Color(CYAN, 0.4), 6, false))
    result.set_stylebox("background", "ProgressBar", frame(Color("#24344f"), 0, false))
    var fill = frame(CYAN, 0, false)
    fill.bg_color = CYAN
    result.set_stylebox("fill", "ProgressBar", fill)
    result.set_stylebox("slider", "HSlider", frame(Color("#34466b"), 2, false))
    var track = frame(MAGENTA, 2, false)
    track.bg_color = MAGENTA
    result.set_stylebox("grabber_area", "HSlider", track)
    result.set_stylebox("grabber_area_highlight", "HSlider", track)
    return result

static func accent_button(button: Button, accent: Color) -> void:
    button.add_theme_stylebox_override("normal", frame(Color(accent, 0.62)))
    var hover = frame(accent)
    hover.bg_color = PANEL.lerp(accent, 0.10)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_color_override("font_color", accent)
    button.add_theme_color_override("font_hover_color", TEXT)
    button.add_theme_color_override("icon_normal_color", accent)
    button.add_theme_color_override("icon_hover_color", TEXT)

static func title(label: Label, accent: Color = CYAN, font_size: int = 36) -> void:
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", TEXT)
    label.add_theme_color_override("font_outline_color", Color(accent, 0.6))
    label.add_theme_constant_override("outline_size", 2)
    label.add_theme_color_override("font_shadow_color", Color(accent, 0.35))
    label.add_theme_constant_override("shadow_outline_size", 6)
    label.add_theme_constant_override("shadow_offset_x", 0)
    label.add_theme_constant_override("shadow_offset_y", 0)

static func icon(kind: String) -> Texture2D:
    var paths = {
        "note": '<path d="M9 17V5l11-2v12M9 8l11-2"/><ellipse cx="6" cy="17" rx="3" ry="2"/><ellipse cx="17" cy="15" rx="3" ry="2"/>',
        "settings": '<path d="M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1Z"/><circle cx="12" cy="12" r="3"/>',
        "power": '<path d="M12 2v9M6 5a9 9 0 1 0 12 0"/>',
        "home": '<path d="m3 11 9-8 9 8M5 10v11h14V10M10 21v-7h4v7"/>',
        "import": '<path d="M12 16V3m-5 5 5-5 5 5M4 15v6h16v-6"/>',
        "trophy": '<path d="M7 3h10v7a5 5 0 0 1-10 0ZM7 5H3v3a4 4 0 0 0 4 4m10-7h4v3a4 4 0 0 1-4 4m-5 3v6m-4 0h8"/>',
    }
    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="white" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % paths.get(kind, paths.note)
    var source = Image.new()
    source.load_svg_from_string(svg)
    return ImageTexture.create_from_image(source)

static func background() -> Control:
    if ResourceLoader.exists(MENU_BACKGROUND_PATH):
        var texture = load(MENU_BACKGROUND_PATH) as Texture2D
        if texture != null:
            var image = TextureRect.new()
            image.name = "MenuBackground"
            image.texture = texture
            image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
            image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
            image.mouse_filter = Control.MOUSE_FILTER_IGNORE
            var shade = ColorRect.new()
            shade.color = Color(BACKGROUND, 0.22)
            shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
            shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
            image.add_child(shade)
            return image
        push_warning("Não foi possível carregar o fundo dos menus: " + MENU_BACKGROUND_PATH)
    var rect = ColorRect.new()
    rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var shader = Shader.new()
    shader.code = """shader_type canvas_item;
render_mode unshaded;
void fragment() {
    vec2 uv = UV;
    vec3 base = vec3(0.0235, 0.0353, 0.0784);
    float blue = exp(-5.5 * length((uv - vec2(0.10, 0.22)) * vec2(1.0, 1.3)));
    float pink = exp(-6.0 * length((uv - vec2(0.94, 0.76)) * vec2(1.0, 1.3)));
    base += vec3(0.02, 0.13, 0.22) * blue + vec3(0.16, 0.02, 0.13) * pink;
    COLOR = vec4(base, 1.0);
}
"""
    var material = ShaderMaterial.new()
    material.shader = shader
    rect.material = material
    return rect
