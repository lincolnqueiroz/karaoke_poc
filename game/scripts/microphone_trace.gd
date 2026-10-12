extends Control

const Neon = preload("res://scripts/neon_theme.gd")
const WINDOW_SECONDS = 8.0
var points: Array = []
var elapsed: float = 0.0

func record(sample: Dictionary, time: float) -> void:
    points.append({"time": time, "midi": float(sample.midi), "voiced": sample.frequency > 0})
    while points.size() > 256:
        points.pop_front()
    queue_redraw()

func advance(time: float) -> void:
    elapsed = time
    while not points.is_empty() and float(points[0].time) < elapsed - WINDOW_SECONDS:
        points.pop_front()
    queue_redraw()

func clear() -> void:
    points.clear()
    queue_redraw()

func position_for(time: float, midi: float) -> Vector2:
    var left = 64.0
    var width = maxf(1, size.x - left - 24)
    return Vector2(left + width * (0.90 + (time - elapsed) / WINDOW_SECONDS),
        lerpf(size.y - 24, 24, clampf((midi - 36) / 48.0, 0, 1)))

func _draw() -> void:
    draw_style_box(Neon.frame(Color(Neon.GREEN, 0.5)), Rect2(Vector2.ZERO, size))
    var font = get_theme_default_font()
    for midi in range(36, 85, 12):
        var y = position_for(elapsed, midi).y
        draw_line(Vector2(60, y), Vector2(size.x - 24, y), Color(Neon.MUTED, 0.16), 1)
        draw_string(font, Vector2(12, y + 5), "Dó%d" % (int(midi / 12.0) - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Neon.MUTED)
    var cursor = position_for(elapsed, 60).x
    draw_line(Vector2(cursor, 24), Vector2(cursor, size.y - 24), Color(Neon.GREEN, 0.3), 2)
    var previous: Dictionary = {}
    for point in points:
        var position = position_for(point.time, point.midi)
        if not point.voiced or position.x < 64 or position.x > size.x - 24:
            previous = {}
            continue
        if not previous.is_empty() and point.time - previous.time <= 0.2:
            draw_line(previous.position, position, Color(Neon.GREEN, 0.15), 10, true)
            draw_line(previous.position, position, Neon.GREEN, 3, true)
        draw_circle(position, 3, Neon.GREEN)
        previous = {"time": point.time, "position": position}
