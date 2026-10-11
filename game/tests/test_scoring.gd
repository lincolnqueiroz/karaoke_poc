extends SceneTree

const Score = preload("res://scripts/singing_score.gd")
const Player = preload("res://scripts/karaoke_player.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func scenario(error: float, silence: bool = false, half: bool = false) -> Dictionary:
    var score = Score.new()
    score.configure([{"start": 1.0, "duration": 1.0, "midi": 69.0}], 3.0, 0.0)
    score.reset(0.0)
    for index in range(60):
        var time = (index + 0.5) * Score.STEP
        score.record(time, 69.0 + error, not silence and (not half or time < 1.5))
        # Duplicate callbacks must not multiply points.
        score.record(time, 69.0 + error, not silence and (not half or time < 1.5))
    score.advance(3.0)
    return score.result()

func _initialize() -> void:
    check(scenario(0).points == 10000, "Perfect pitch gets full points")
    check(scenario(0.5).points == 10000, "50 cents tolerance")
    check(scenario(1).points == 5000, "One semitone earns half credit")
    check(scenario(1.5).points == 0, "150 cents earns no credit")
    check(scenario(12).points == 0, "Unselected octave is not silently corrected")
    check(scenario(0, true).points == 0, "Silence earns zero")
    var partial = scenario(0, false, true)
    check(partial.points == 5000 and partial.coverage == 50 and partial.accuracy == 100,
          "Missing half the vocal counts even when sung half is perfect")
    var score = Score.new()
    score.configure([{"start": 1.0, "duration": 1.0, "midi": 69.0}], 3.0, 0.1)
    check(score.target_at(0.91) == 69 and not is_finite(score.target_at(0.89)),
          "Reference timing matches calibrated visual offset")
    check(not is_finite(score.target_at(1.9)), "Exact note end is excluded")
    score.reset(1.4)
    score.advance(3.0)
    check(absf(score.result().evaluated_seconds - 0.5) < 0.001,
          "Late activation evaluates only remaining notes")
    score.record(1.5, 69, true)
    check(score.result().points == 0, "Late samples cannot change finalized bins")
    score.reset(0)
    score.record(1.025, 69, true)
    score.advance(3)
    check(score.result().coverage <= 15, "One sample cannot sustain an entire note")
    score.reset(0)
    check(score.result().points == 0 and score.samples.is_empty(), "Reset clears session")
    var player = Player.new()
    player.scorer.configure([{"start": 1.0, "duration": 1.0, "midi": 69.0}], 3, 0)
    player.scorer.reset(0)
    player.voice_octaves = 1
    player.elapsed = 1.065
    player._on_microphone_sample({"frequency": 220.0, "midi": 57.0, "rms_db": -20}, 0.04)
    player.scorer.advance(1.05)
    check(player.scorer.result().points == 10000, "Player applies selected octave before scoring")
    player.free()
    print("Scoring checks: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
