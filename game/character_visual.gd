class_name CharacterVisual
extends Node3D
## What a Character looks like: the Quaternius mannequin, animated from how the
## character actually moved. Purely cosmetic: nothing here feeds back into the
## simulation, and headless processes (the dedicated server, bot arenas) never
## create one.

const MODEL := "res://assets/characters/UAL1_Standard.glb"
## Ground speed (m/s) each clip was authored at, measured from the library's
## root-motion version. Playback is scaled by actual / authored speed so feet
## don't slide. Godot's importer strips the pack's "_Loop" suffixes and marks
## those clips as looping, hence "Jog_Fwd" rather than "Jog_Fwd_Loop".
const CLIP_SPEEDS := {"Walk": 0.975, "Jog_Fwd": 5.357, "Sprint": 8.25}
const IDLE_BELOW := 0.3     # m/s
const JOG_ABOVE := 2.0      # m/s
const SPRINT_ABOVE := 6.8   # m/s
const BLEND_SEC := 0.15
const TURN_RATE := 12.0     # 1/s: how quickly the body swings to a new heading

static var _model_scene: PackedScene
## How many have ever been built in this process; the tests use it to prove a
## headless server builds none.
static var created := 0

var _color: Color
var _model: Node3D
var _player: AnimationPlayer
var _last_pos := Vector3.ZERO
var _velocity := Vector3.ZERO
var _turn := 0.0
var _clip := ""
var _was_grounded := true


func _init(color: Color) -> void:
	_color = color


func _ready() -> void:
	created += 1
	if _model_scene == null:
		_model_scene = load(MODEL)
	_model = _model_scene.instantiate()
	add_child(_model)
	_model.rotation.y = PI  # glTF faces +Z, Godot faces -Z
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_tint(_model)
	_last_pos = (get_parent() as Node3D).global_position
	_play("Idle", 1.0)


func animation_player() -> AnimationPlayer:
	return _player


## [clip name, playback speed] for a ground speed in m/s.
static func choose_clip(speed: float, grounded: bool) -> Array:
	if not grounded:
		return ["Jump", 1.0]
	if speed < IDLE_BELOW:
		return ["Idle", 1.0]
	var clip := "Walk"
	if speed > SPRINT_ABOVE:
		clip = "Sprint"
	elif speed > JOG_ABOVE:
		clip = "Jog_Fwd"
	return [clip, clampf(speed / CLIP_SPEEDS[clip], 0.5, 2.5)]


## [body yaw relative to aim, play in reverse] for a velocity in the
## character's own frame (-Z forward, +X right). The library has no strafe or
## backpedal clips, so the body turns toward its travel (up to 90 degrees
## either side of the aim) and runs the forward cycle backwards when retreating.
## Positive yaw turns left.
static func body_turn(local_velocity: Vector3) -> Array:
	var heading := atan2(local_velocity.x, -local_velocity.z)  # 0 forward, +PI/2 right
	if absf(heading) <= PI / 2 + 0.001:
		return [-heading, false]
	return [-wrapf(heading - PI, -PI, PI), true]


func _physics_process(delta: float) -> void:
	var body := get_parent() as Character
	var pos := body.global_position
	var raw := (pos - _last_pos) / delta
	_last_pos = pos
	if raw.length() > 30.0:  # spawn or teleport, not movement
		raw = Vector3.ZERO
	_velocity = _velocity.lerp(raw, 0.5)
	var planar := Vector3(_velocity.x, 0.0, _velocity.z)
	var speed := planar.length()

	var target_turn := 0.0
	var reverse := false
	if not body.grounded:
		target_turn = _turn  # hold the heading mid-air
	elif speed >= IDLE_BELOW:
		var turn := body_turn(body.global_basis.inverse() * planar)
		target_turn = turn[0]
		reverse = turn[1]
	_turn = lerp_angle(_turn, target_turn, 1.0 - exp(-TURN_RATE * delta))
	_model.rotation.y = PI + _turn

	if _was_grounded and not body.grounded and _velocity.y > 0.5:
		_player.play("Jump_Start", 0.1)
		_player.queue("Jump")
		_clip = "Jump"
	_was_grounded = body.grounded
	var pick := choose_clip(speed, body.grounded)
	_play(pick[0], pick[1] * (-1.0 if reverse else 1.0))


func _play(clip: String, speed_scale: float) -> void:
	if clip != _clip:
		_player.play(clip, BLEND_SEC)
		_clip = clip
	_player.speed_scale = speed_scale


## Player colour on the main body material; the joint material stays as is.
func _tint(node: Node) -> void:
	for mesh_instance: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.mesh.surface_get_material(i) as StandardMaterial3D
			if mat and mat.resource_name == "M_Main":
				var tinted := mat.duplicate() as StandardMaterial3D
				tinted.albedo_color = _color
				mesh_instance.set_surface_override_material(i, tinted)
