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
