extends RefCounted

static func discover(roots: Array) -> Dictionary:
    var songs: Array = []
    var errors: Array = []
    var seen: Dictionary = {}
    for root in roots:
        var directory = DirAccess.open(str(root))
        if directory == null:
            continue
        var folders: Array = [str(root)]
        for child in directory.get_directories():
            folders.append(str(root).path_join(child))
        folders.sort()
        for folder in folders:
            var manifest = str(folder).path_join("song.json")
            if not FileAccess.file_exists(manifest):
                continue
            var data = JSON.parse_string(FileAccess.get_file_as_string(manifest))
            if not data is Dictionary or data.get("schema_version", "") != "1.0":
                errors.append("Manifesto inválido: " + manifest)
                continue
            var audio = data.get("audio", {})
            if not audio is Dictionary:
                errors.append("Áudio inválido: " + manifest)
                continue
            var original = str(audio.get("original", ""))
            if original.is_empty():
                continue # The committed silent synthetic demo is not an imported song.
            var duration = data.get("duration_seconds", 0)
            if (not duration is float and not duration is int) or not is_finite(float(duration)) or float(duration) <= 0 or not data.get("notes", null) is Array:
                errors.append("Dados inválidos: " + manifest)
                continue
            if not FileAccess.file_exists(str(folder).path_join(original)):
                errors.append("Áudio não encontrado: " + manifest)
                continue
            var valid_notes = true
            for note in data.notes:
                if not note is Dictionary:
                    valid_notes = false
                    break
                for key in ["start", "duration", "midi"]:
                    var value = note.get(key, null)
                    if (not value is float and not value is int) or not is_finite(float(value)):
                        valid_notes = false
                        break
                if not valid_notes:
                    break
                if float(note.start) < 0 or float(note.duration) <= 0 or float(note.start) + float(note.duration) > float(duration) + 0.001 or float(note.midi) < 0 or float(note.midi) > 127:
                    valid_notes = false
                    break
            if not valid_notes:
                errors.append("Notas inválidas: " + manifest)
                continue
            var id = str(folder).get_file()
            if seen.has(id):
                continue # Prefer the playable game copy over its workspace source.
            seen[id] = true
            var lyrics: String = ""
            var lyric_dir = str(folder).path_join("lyrics")
            var directory_lyrics = DirAccess.open(lyric_dir)
            if directory_lyrics != null:
                var files = directory_lyrics.get_files()
                files.sort()
                for filename in files:
                    if filename.get_extension().to_lower() == "lrc":
                        lyrics = lyric_dir.path_join(filename)
                        if filename.get_basename() == id:
                            break
            var artist: String = ""
            var metadata_path = str(folder).path_join("metadata.json")
            if FileAccess.file_exists(metadata_path):
                var metadata = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
                if metadata is Dictionary and metadata.get("artist", null) is String:
                    artist = metadata.artist.strip_edges()
            songs.append({"manifest": manifest, "lyrics": lyrics, "artist": artist,
                          "title": str(data.get("title", id)), "duration": float(duration)})
    songs.sort_custom(func(a, b): return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
    return {"songs": songs, "errors": errors}
