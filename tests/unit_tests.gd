extends SceneTree
## Headless unit tests. Run via tests/run.sh, or:
##   godot --headless --path . --script res://tests/unit_tests.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	test_input_round_trip()
	test_input_rejects_malformed()
	test_input_clamps()
	test_check_hello()
	test_map_hash()
	test_password_proof()
	test_check_hello_password()
	test_game_version()
	test_headless_character_has_no_visuals()
	test_character_is_a_person()
	test_locomotion_clip_choice()
	test_body_turns_toward_travel()
	await test_replay_reproduces_original_run()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", what)


func test_input_round_trip() -> void:
	var a := PlayerInput.create(42, Vector2(0.5, -0.5), 1.25, true)
	var b := PlayerInput.from_array(a.to_array())
	check(b != null, "round trip decodes")
	if b:
		check(b.seq == 42 and b.move == a.move and b.yaw == a.yaw and b.jump, "round trip preserves fields")


func test_input_rejects_malformed() -> void:
	for raw: Variant in [null, [], [1, Vector2.ZERO, 0.0], ["1", Vector2.ZERO, 0.0, false],
			[1, Vector2(NAN, 0), 0.0, false], [1, Vector2.ZERO, INF, false], [1, Vector2.ZERO, 0.0, 1]]:
		check(PlayerInput.from_array(raw) == null, "rejects %s" % [raw])


func test_input_clamps() -> void:
	var fast := PlayerInput.from_array([1, Vector2(10, 10), 0.0, false])
	check(fast != null and is_equal_approx(fast.move.length(), 1.0), "move is clamped to length 1")
	var spun := PlayerInput.from_array([1, Vector2.ZERO, 7.0, false])
	check(spun != null and spun.yaw >= -PI and spun.yaw <= PI, "yaw is wrapped")


func test_check_hello() -> void:
	var good := {"version": "1.0", "map_id": "plane", "map_hash": "abc"}
	check(Protocol.check_hello(good, "1.0", "plane", "abc") == "", "matching hello accepted")
	check(Protocol.check_hello(good, "1.1", "plane", "abc").begins_with("version mismatch"), "version mismatch")
	check(Protocol.check_hello(good, "1.0", "other", "abc").begins_with("map mismatch"), "map id mismatch")
	check(Protocol.check_hello(good, "1.0", "plane", "xyz").contains("differs"), "map hash mismatch")
	var missing := good.duplicate()
	missing.map_hash = ""
	check(Protocol.check_hello(missing, "1.0", "plane", "abc").contains("does not have"), "client lacks map")
	check(Protocol.check_hello({"version": 1}, "1.0", "plane", "abc") == "malformed hello", "malformed hello")


func test_map_hash() -> void:
	var h := Protocol.map_hash("plane")
	check(h.length() == 64, "plane hash is SHA-256 hex")
	check(h == Protocol.map_hash("plane"), "hash is stable")
	check(Protocol.map_hash("nope") == "", "unknown map hashes to empty")
	check(Protocol.map_hash("../plane") == "", "path-like map id refused")


func test_password_proof() -> void:
	var a := Protocol.password_proof("hunter2", "nonce1")
	check(a.length() == 64, "proof is SHA-256 hex")
	check(a == Protocol.password_proof("hunter2", "nonce1"), "proof is deterministic")
	check(a != Protocol.password_proof("hunter2", "nonce2"), "proof depends on the nonce")
	check(a != Protocol.password_proof("hunter3", "nonce1"), "proof depends on the password")
	check(Protocol.password_proof("", "nonce1") == "", "no password, no proof")


func test_check_hello_password() -> void:
	var expected := Protocol.password_proof("hunter2", "n")
	var hello := {"version": "1.0", "map_id": "plane", "map_hash": "abc", "proof": expected}
	check(Protocol.check_hello(hello, "1.0", "plane", "abc", expected) == "", "right password accepted")
	hello.proof = Protocol.password_proof("wrong", "n")
	check(Protocol.check_hello(hello, "1.0", "plane", "abc", expected) == "wrong password", "wrong password refused")
	hello.erase("proof")
	check(Protocol.check_hello(hello, "1.0", "plane", "abc", expected) == "password required", "missing password refused")
	check(Protocol.check_hello(hello, "1.0", "plane", "abc") == "", "open server ignores a missing proof")
	hello.version = "0.9"
	check(Protocol.check_hello(hello, "1.0", "plane", "abc", expected).begins_with("version mismatch"),
		"version is reported before the password")


## The version carries a hash of the code, so a server and client built from
## different code refuse each other instead of desyncing.
func test_game_version() -> void:
	var files := Protocol.code_files()
	check("res://sim/character.gd" in files, "code hash covers the simulation")
	check("res://project.godot" in files, "code hash covers project settings (tick rate, physics)")
	check(Array(files).all(func(f: String) -> bool: return not f.begins_with("res://tests/")),
		"tests don't change the version")
	check(Array(files).all(func(f: String) -> bool: return not f.begins_with("res://maps/")),
		"maps are covered by their own hash")
	var v := Protocol.game_version()
	check(v.begins_with(Protocol.GAME_VERSION + "+") and v.length() == Protocol.GAME_VERSION.length() + 9,
		"version is GAME_VERSION+8 hex (%s)" % v)
	check(v == Protocol.game_version(), "version is stable")


func _count_visual_nodes(node: Node) -> int:
	var n := 1 if node is VisualInstance3D or node is AnimationMixer else 0
	for child in node.get_children():
		n += _count_visual_nodes(child)
	return n


## The dedicated server (and the bot arenas) must not pay for skinned meshes
## and animation nobody sees.
func test_headless_character_has_no_visuals() -> void:
	var world := World.new()
	root.add_child(world)
	var c := world.spawn_character(1, "server-side", Vector3.ZERO, false)
	check(_count_visual_nodes(c) == 0, "character without visuals has no meshes, labels or animation")
	world.free()


func test_character_is_a_person() -> void:
	var world := World.new()
	root.add_child(world)
	var c := world.spawn_character(1, "someone", Vector3.ZERO, true)
	var visual := c.get_node_or_null("Visual") as CharacterVisual
	check(visual != null, "character with visuals has a CharacterVisual")
	if visual:
		var player := visual.animation_player()
		check(player != null, "visual has an AnimationPlayer")
		for clip in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump", "Jump_Start"]:
			check(player != null and player.has_animation(clip), "animation %s is available" % clip)
		if player and player.has_animation("Jog_Fwd"):
			check(player.get_animation("Jog_Fwd").loop_mode == Animation.LOOP_LINEAR, "locomotion clips loop")
		check(visual.find_children("*", "Skeleton3D", true, false).size() == 1, "visual has a skeleton")
	world.free()


## Clip names and natural speeds (m/s) come from the root-motion version of
## the library; playback speed is scaled so feet don't slide.
func test_locomotion_clip_choice() -> void:
	var idle := CharacterVisual.choose_clip(0.0, true)
	check(idle[0] == "Idle", "standing still idles (%s)" % [idle])
	var jog := CharacterVisual.choose_clip(5.0, true)
	check(jog[0] == "Jog_Fwd" and absf(jog[1] - 5.0 / 5.357) < 0.01, "5 m/s jogs at 0.93x (%s)" % [jog])
	var walk := CharacterVisual.choose_clip(1.0, true)
	check(walk[0] == "Walk", "1 m/s walks (%s)" % [walk])
	var sprint := CharacterVisual.choose_clip(8.0, true)
	check(sprint[0] == "Sprint", "8 m/s sprints (%s)" % [sprint])
	var air := CharacterVisual.choose_clip(5.0, false)
	check(air[0] == "Jump", "airborne uses the jump loop (%s)" % [air])


## Without strafe or backpedal clips, the body turns toward its direction of
## travel (up to 90 degrees either side of the aim) and runs backwards by
## playing the forward cycle in reverse. Positive yaw turns left.
func test_body_turns_toward_travel() -> void:
	var cases := [
		[Vector3(0, 0, -1), 0.0, false, "forward"],
		[Vector3(1, 0, 0), -PI / 2, false, "strafe right"],
		[Vector3(-1, 0, 0), PI / 2, false, "strafe left"],
		[Vector3(0, 0, 1), 0.0, true, "backwards"],
		[Vector3(1, 0, 1), PI / 4, true, "back and right"],
		[Vector3(1, 0, -1), -PI / 4, false, "forward and right"],
	]
	for c: Array in cases:
		var turn := CharacterVisual.body_turn(c[0])
		check(absf(angle_difference(turn[0], c[1])) < 0.001 and turn[1] == c[2],
			"%s: yaw %.2f reverse %s (got %.2f, %s)" % [c[3], c[1], c[2], turn[0], turn[1]])


## Reconciliation depends on this: restoring a captured state and replaying
## the same inputs must land exactly where the original run did, including
## from mid-jump.
func test_replay_reproduces_original_run() -> void:
	var world := World.new()
	root.add_child(world)
	check(world.load_map("plane"), "plane map loads")
	var c := world.spawn_character(1, "t", Vector3(0, 0.1, 0))
	await physics_frame
	await physics_frame

	var inputs: Array[PlayerInput] = []
	for i in 180:
		inputs.append(PlayerInput.create(i + 1, Vector2(0.3, 1.0), i * 0.015, i % 70 == 10))  # jumps at 10, 80, 150
	var states := []  # state before each input
	var peak := 0.0
	for input in inputs:
		states.append(c.capture_state())
		c.simulate(input)
		peak = maxf(peak, c.global_position.y)
	var final_pos := c.global_position

	check(final_pos.distance_to(Vector3(0, 0.1, 0)) > 5.0, "character actually moved (%.2f m)" % final_pos.length())
	check(peak > 0.5, "character actually jumped (peak %.2f m)" % peak)
	# The run ends mid-air, so a rewind to tick 80 (grounded, jump pressed) only
	# jumps if restore_state really puts `grounded` back.
	check(not c.grounded, "run ends airborne")
	check(states[80][3] and inputs[80].jump, "tick 80 is grounded with jump pressed")
	check(not states[100][3], "tick 100 is mid-air, so one rewind starts airborne")

	states.append(c.capture_state())  # state after the last input

	# Compare every replayed tick, not just the end: runs that diverge (a
	# swallowed jump, say) can reconverge before the last tick.
	for rewind: int in [80, 100, 160]:
		c.restore_state(states[rewind])
		var worst := 0.0
		var worst_tick := -1
		for i in range(rewind, inputs.size()):
			c.simulate(inputs[i])
			var expected: Array = states[i + 1]
			var err := c.global_position.distance_to(expected[0]) + c.velocity.distance_to(expected[1])
			if c.grounded != expected[3]:
				err += 1.0
			if err > worst:
				worst = err
				worst_tick = i
		check(worst < 0.0001, "replay from tick %d tracks the original (worst %.6f at tick %d)" % [rewind, worst, worst_tick])
	world.queue_free()
