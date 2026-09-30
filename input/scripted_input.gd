class_name ScriptedInput
extends RefCounted
## Canned, deterministic movement for headless test clients. A stand-in for a
## bot: same PlayerInput out, no keyboard.

var pattern := "idle"
var look_yaw := 0.0
var look_pitch := -0.15


func _init(p_pattern: String) -> void:
	pattern = p_pattern


func sample(seq: int) -> PlayerInput:
	match pattern:
		"circle":  # ~4.2 m radius, jumping every two seconds
			look_yaw = wrapf(seq * 0.02, -PI, PI)
			return PlayerInput.create(seq, Vector2(0, 1), look_yaw, seq % 120 == 0)
		"line":  # 3 s forward, 3 s back, along Z
			var forward := 1.0 if int(seq / 180.0) % 2 == 0 else -1.0
			return PlayerInput.create(seq, Vector2(0, forward), look_yaw, false)
		_:
			return PlayerInput.create(seq, Vector2.ZERO, look_yaw, false)
