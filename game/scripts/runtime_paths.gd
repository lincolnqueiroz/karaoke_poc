extends RefCounted

static func development_root() -> String:
    return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()

static func data_root() -> String:
    return development_root().path_join("workspace") if OS.has_feature("editor") else ProjectSettings.globalize_path("user://")

static func bundle_root() -> String:
    return OS.get_executable_path().get_base_dir()

static func analyzer() -> String:
    return development_root().path_join("analyzer/.venv/Scripts/python.exe") if OS.has_feature("editor") else bundle_root().path_join("analyzer/karaoke-analyzer.exe")

static func ffmpeg() -> String:
    return "" if OS.has_feature("editor") else bundle_root().path_join("tools/ffmpeg")

static func library_roots() -> Array:
    return ["res://demo", data_root().path_join("songs")]
