class_name World
extends Node3D
## The loaded map and every Character in the match, keyed by peer id.

var map_id := ""
var map_hash := ""
var map_data := {}
var characters := {}  # peer id -> Character


func load_map(id: String) -> bool:
	if map_id == id:
		return true
	var hash := Protocol.map_hash(id)
	if hash == "":
		push_error("map '%s' not found" % id)
		return false
	var scene := load(Protocol.map_dir(id) + "geometry.tscn") as PackedScene
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(Protocol.map_dir(id) + "data.json"))
	if scene == null or not data is Dictionary:
		push_error("map '%s' failed to load" % id)
		return false
	add_child(scene.instantiate())
	map_id = id
	map_hash = hash
	map_data = data
	return true


func spawn_point(index: int) -> Vector3:
	var spawns: Array = map_data.get("spawns", [])
	if spawns.is_empty():
		return Vector3.ZERO
	var s: Array = spawns[index % spawns.size()]
	return Vector3(s[0], s[1], s[2])


func spawn_character(id: int, player_name: String, pos: Vector3, with_visuals := false) -> Character:
	var character := Character.new()
	character.setup(id, player_name, with_visuals)
	add_child(character)
	character.global_position = pos
	character.reset_physics_interpolation()
	characters[id] = character
	return character


func remove_character(id: int) -> void:
	var character: Character = characters.get(id)
	if character:
		characters.erase(id)
		character.queue_free()


## Fixed view for a dedicated server run with a window.
func add_overview_camera() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 45, 45)
	cam.look_at(Vector3.ZERO)
	cam.make_current()
