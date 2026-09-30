class_name PlayerInput
extends RefCounted
## The one input format that drives a Character. The keyboard, the network and
## (later) bots all produce these; nothing else moves a Character.

var seq := 0
var move := Vector2.ZERO  # x = strafe right, y = forward; length <= 1
var yaw := 0.0            # radians, world space
var jump := false


## Clamps on the way in, so the sender predicts with exactly the values the
## server will simulate.
static func create(p_seq: int, p_move: Vector2, p_yaw: float, p_jump: bool) -> PlayerInput:
	var input := PlayerInput.new()
	input.seq = p_seq
	input.move = p_move.limit_length(1.0)
	input.yaw = wrapf(p_yaw, -PI, PI)
	input.jump = p_jump
	return input


func to_array() -> Array:
	return [seq, move, yaw, jump]


## Null if the packet is not a well-formed input.
static func from_array(raw: Variant) -> PlayerInput:
	if not raw is Array or raw.size() != 4:
		return null
	if typeof(raw[0]) != TYPE_INT or typeof(raw[1]) != TYPE_VECTOR2 \
			or typeof(raw[2]) != TYPE_FLOAT or typeof(raw[3]) != TYPE_BOOL:
		return null
	var m: Vector2 = raw[1]
	if not m.is_finite() or not is_finite(raw[2]):
		return null
	return create(raw[0], m, raw[2], raw[3])
