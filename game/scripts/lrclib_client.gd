extends Node

signal received(records: Array)
signal failed(message: String)
const Lyrics = preload("res://scripts/lrc_lyrics.gd")
const BASE_URL = "https://lrclib.net/api/search"
var client_contact: String = str(ProjectSettings.get_setting("lyrics/lrclib/client_contact", ""))
var http: HTTPRequest
var waiting: bool = false
var next_request_ms: int = 0

func _ready() -> void:
    http = HTTPRequest.new()
    http.timeout = 20.0
    http.body_size_limit = 2 * 1024 * 1024
    add_child(http)
    http.request_completed.connect(on_response)

static func search_url(title: String, artist: String) -> String:
    var url = BASE_URL + "?track_name=" + title.strip_edges().uri_encode()
    if not artist.strip_edges().is_empty():
        url += "&artist_name=" + artist.strip_edges().uri_encode()
    return url

func search(title: String, artist: String) -> Error:
    if waiting:
        return ERR_BUSY
    if title.strip_edges().is_empty():
        failed.emit("Informe o título para buscar a letra.")
        return ERR_INVALID_PARAMETER
    if client_contact.strip_edges().is_empty():
        failed.emit("Configure a URL do projeto ou e-mail de contato do aplicativo para acessar o LRCLIB.")
        return ERR_UNCONFIGURED
    if client_contact.contains("\n") or client_contact.contains("\r"):
        failed.emit("Identificação inválida do aplicativo LRCLIB.")
        return ERR_INVALID_PARAMETER
    if Time.get_ticks_msec() < next_request_ms:
        failed.emit("Aguarde %d segundos antes de buscar novamente." % int(ceil((next_request_ms - Time.get_ticks_msec()) / 1000.0)))
        return ERR_BUSY
    waiting = true
    var error = send_request(search_url(title, artist), PackedStringArray([
        "Accept: application/json", "User-Agent: KaraokePoC/0.1 (%s)" % client_contact.strip_edges()]))
    if error != OK:
        waiting = false
        failed.emit("Não foi possível iniciar a busca de letras: " + error_string(error))
    return error

func send_request(url: String, headers: PackedStringArray) -> Error:
    return http.request(url, headers)

func cancel() -> void:
    if waiting:
        http.cancel_request()
        waiting = false
        next_request_ms = maxi(next_request_ms, Time.get_ticks_msec() + 300)

static func retry_seconds(headers: PackedStringArray, now: float) -> float:
    for header in headers:
        if not header.to_lower().begins_with("retry-after:"):
            continue
        var value = header.substr(header.find(":") + 1).strip_edges()
        if value.is_valid_float():
            return maxf(1.0, float(value))
        var parts = value.split(" ", false)
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        if parts.size() == 6 and parts[2] in months and parts[5] == "GMT":
            var clock = parts[4].split(":")
            if clock.size() == 3 and parts[1].is_valid_int() and parts[3].is_valid_int():
                var deadline = Time.get_unix_time_from_datetime_dict({"year": int(parts[3]), "month": months.find(parts[2]) + 1,
                    "day": int(parts[1]), "hour": int(clock[0]), "minute": int(clock[1]), "second": int(clock[2])})
                return maxf(1.0, float(deadline) - now)
    return 30.0

static func parse_records(body: String) -> Dictionary:
    var parsed = JSON.parse_string(body)
    if not parsed is Array:
        return {"records": [], "error": "Resposta inválida do LRCLIB."}
    var records: Array = []
    for item in parsed:
        if not item is Dictionary or not item.get("syncedLyrics", null) is String:
            continue
        var duration = item.get("duration", null)
        var id = item.get("id", null)
        if (not duration is float and not duration is int) or not is_finite(float(duration)) or float(duration) <= 0:
            continue
        if (not id is int and not id is float) or not is_finite(float(id)) or float(id) < 0 or floor(float(id)) != float(id):
            continue
        if not item.get("trackName", null) is String or not item.get("artistName", null) is String:
            continue
        var validation = Lyrics.parse(item.syncedLyrics, float(duration))
        if not validation.error.is_empty() or validation.cues.is_empty():
            continue
        records.append({"id": int(id), "title": item.trackName, "artist": item.artistName,
            "album": str(item.get("albumName", "")), "duration": float(duration), "lrc": item.syncedLyrics})
    return {"records": records, "error": ""}

func on_response(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if not waiting:
        return
    waiting = false
    next_request_ms = Time.get_ticks_msec() + 300
    if code == 429:
        var seconds = retry_seconds(headers, Time.get_unix_time_from_system())
        next_request_ms = Time.get_ticks_msec() + int(ceil(seconds * 1000.0))
        failed.emit("LRCLIB limitou as buscas. Aguarde %d segundos." % int(ceil(seconds)))
        return
    if result != HTTPRequest.RESULT_SUCCESS:
        failed.emit("Falha de conexão com LRCLIB. Confira sua conexão; você também pode usar um LRC local.")
        return
    if code != 200:
        failed.emit("LRCLIB respondeu com erro HTTP %d. Tente mais tarde ou use um LRC local." % code)
        return
    var parsed = parse_records(body.get_string_from_utf8())
    if not parsed.error.is_empty():
        failed.emit(parsed.error)
        return
    received.emit(parsed.records)

func _exit_tree() -> void:
    cancel()
