class_name HumanInput
extends Node
## Keyboard and mouse -> PlayerInput. The mouse turns the view every frame;
## sample() snapshots it once per tick.

const MOUSE_RAD_PER_PX := 0.0025
const KEYS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
}

var look_yaw := 0.0
var look_pitch := -0.15


func _ready() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, ev)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw = wrapf(look_yaw - event.relative.x * MOUSE_RAD_PER_PX, -PI, PI)
		look_pitch = clampf(look_pitch - event.relative.y * MOUSE_RAD_PER_PX, -1.3, 1.0)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func sample(seq: int) -> PlayerInput:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var move := Input.get_vector("move_left", "move_right", "move_back", "move_forward") if captured else Vector2.ZERO
	return PlayerInput.create(seq, move, look_yaw, captured and Input.is_action_pressed("jump"))
