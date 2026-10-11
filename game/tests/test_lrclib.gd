extends SceneTree

const Client = preload("res://scripts/lrclib_client.gd")
class FakeClient extends Client:
    var requested_url: String
    var requested_headers: PackedStringArray
    func send_request(url: String, headers: PackedStringArray) -> Error:
        requested_url = url
        requested_headers = headers
        return OK

var failures: int = 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func _initialize() -> void:
    call_deferred("verify")

func verify() -> void:
    check(Client.search_url(" música & teste ", " A/B ").contains("track_name=m%C3%BAsica%20%26%20teste&artist_name=A%2FB"), "Encode Unicode and reserved query characters")
    var record = {"id": 123, "trackName": "Test", "artistName": "Artist", "albumName": "Album", "duration": 10,
        "syncedLyrics": "[00:01] Test verse\n[00:03] Another verse"}
    var unsynced = record.duplicate()
    unsynced.syncedLyrics = null
    var invalid = record.duplicate()
    invalid.syncedLyrics = "Untimed text"
    var parsed = Client.parse_records(JSON.stringify([record, unsynced, invalid, null]))
    check(parsed.error.is_empty() and parsed.records.size() == 1, "Accept only valid synchronized lyrics")
    check(not Client.parse_records("{}").error.is_empty(), "Reject invalid API shape")
    check(Client.retry_seconds(PackedStringArray(["Retry-After: 120"]), 0) == 120, "Honor numeric Retry-After")
    var deadline = Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 11, "hour": 10, "minute": 0, "second": 0})
    check(Client.retry_seconds(PackedStringArray(["Retry-After: Sun, 11 Oct 2026 10:00:00 GMT"]), float(deadline) - 60) == 60, "Honor HTTP-date Retry-After")
    var client = FakeClient.new()
    client.client_contact = "https://example.org/karaoke"
    root.add_child(client)
    var responses: Array = []
    var errors: Array = []
    client.received.connect(func(records): responses.append(records))
    client.failed.connect(func(message): errors.append(message))
    client.client_contact = ""
    check(client.search("Test", "") == ERR_UNCONFIGURED and not client.waiting, "Missing client contact fails explicitly")
    client.client_contact = "https://example.org/karaoke"
    check(client.search("Test", "") == OK and client.waiting, "Start asynchronous search")
    check(client.search("Test", "") == ERR_BUSY, "Reject overlapping requests")
    check(client.requested_headers[1].contains("KaraokePoC/0.1"), "Identify API client")
    client.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify([record]).to_utf8_buffer())
    check(responses.size() == 1 and responses[0].size() == 1, "Deliver candidates")
    check(client.search("Test", "") == ERR_BUSY, "Throttle sequential searches")
    client.next_request_ms = 0
    client.search("Test", "")
    client.on_response(HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(["Retry-After: 60"]), "not JSON".to_utf8_buffer())
    check(client.next_request_ms >= Time.get_ticks_msec() + 59000 and errors[-1].contains("60"), "Rate limiting works without JSON")
    client.next_request_ms = 0
    client.search("Test", "")
    client.cancel()
    client.on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify([record]).to_utf8_buffer())
    check(responses.size() == 1, "Discard cancelled responses")
    client.next_request_ms = 0
    client.search("Test", "")
    client.on_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
    check(errors[-1].contains("conexão"), "Report network failures")
    client.queue_free()
    await process_frame
    print("LRCLIB checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
