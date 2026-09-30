class_name CameraRig
extends Node3D
## Third-person camera. Follows the target's interpolated transform but takes
## look angles straight from the input source, so looking responds every frame
## even though the character only turns once per tick.

const HEAD_HEIGHT := 1.6
const OFFSET := Vector3(0.6, 0.25, 3.2)  # right, up, back (m)

var target: Character
var source: Object  # HumanInput or ScriptedInput


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var cam := Camera3D.new()
	cam.position = OFFSET
	cam.fov = 75.0
	add_child(cam)


func _ready() -> void:
	(get_child(0) as Camera3D).make_current()


func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	global_position = target.get_global_transform_interpolated().origin + Vector3.UP * HEAD_HEIGHT
	rotation = Vector3(source.look_pitch, source.look_yaw, 0.0)
