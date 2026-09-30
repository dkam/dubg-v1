class_name Character
extends CharacterBody3D
## The one character controller. The server steps it with authority; the
## owning client steps the same code to predict, and again to replay after a
## correction. One simulate() is one tick; units are metres and seconds.

const HEIGHT := 1.8
const RADIUS := 0.35
const RUN_SPEED := 5.0      # m/s
const GROUND_ACCEL := 40.0  # m/s^2
const AIR_ACCEL := 8.0      # m/s^2
const GRAVITY := 9.81       # m/s^2
const JUMP_SPEED := 4.2     # m/s, about a 0.9 m apex
const DT := 1.0 / Protocol.TICK_RATE

var peer_id := 0
var display_name := ""
## Whether the last step ended on the floor. Tracked here rather than read from
## is_on_floor() so a rewind can restore it along with position.
var grounded := false

var _label: Label3D


func _init() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = HEIGHT / 2.0
	add_child(shape)


func setup(id: int, player_name: String) -> void:
	peer_id = id
	name = "Player%d" % id
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(id * 0.618034, 1.0), 0.55, 0.9)

	var capsule := CapsuleMesh.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	capsule.material = mat
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.position.y = HEIGHT / 2.0
	add_child(body)

	# A visor on the front (-Z) so facing is readable.
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.24, 0.1, 0.3)
	visor_mesh.material = mat
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 1.58, -RADIUS)
	add_child(visor)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = HEIGHT + 0.35
	_label.font_size = 48
	_label.outline_size = 12
	add_child(_label)
	set_display_name(player_name)


func set_display_name(player_name: String) -> void:
	display_name = player_name
	if _label:
		_label.text = player_name


func set_local(is_local: bool) -> void:
	if _label:
		_label.visible = not is_local


func simulate(input: PlayerInput) -> void:
	rotation.y = input.yaw
	var wish := Vector3(input.move.x, 0.0, -input.move.y).rotated(Vector3.UP, input.yaw) * RUN_SPEED
	var accel := GROUND_ACCEL if grounded else AIR_ACCEL
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish, accel * DT)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if grounded and input.jump:
		velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * DT
	move_and_slide()
	grounded = is_on_floor()


## Everything simulate() reads that a rewind must put back.
func capture_state() -> Array:
	return [global_position, velocity, rotation.y, grounded]


func restore_state(state: Array) -> void:
	global_position = state[0]
	velocity = state[1]
	rotation.y = state[2]
	grounded = state[3]
