extends Node
## One match. The same script runs on every peer so the RPC tables line up;
## `role` decides which half is live.
##
## Server half (dedicated or listen host) owns the simulation: it queues each
## peer's PlayerInput, steps their Character once per input, and sends
## snapshots. Client half predicts its own Character from local input,
## reconciles against snapshots by replaying unacknowledged inputs, and draws
## everyone else interpolated INTERP_DELAY_TICKS in the past.

signal ended(reason: String, exit_code: int)

enum Role { SERVER, HOST, CLIENT }

const INPUT_REDUNDANCY := 3       # each input packet repeats the last N inputs
const MAX_INPUTS_PER_PACKET := 8  # server ignores packets larger than this
const MAX_INPUT_QUEUE := 10       # server drops the oldest beyond this
const CATCH_UP_QUEUE := 4         # above this the server steps two inputs a tick
const MAX_PENDING := 120          # client keeps two seconds of unacked inputs
const INTERP_DELAY_TICKS := 6     # remote players draw 100 ms behind
const REJECT_GRACE_SEC := 0.5     # lets the reject message out before dropping
const CORRECTION_WARMUP_TICKS := 60
const STATUS_EVERY_TICKS := 120   # status file refresh, when enabled

var role: Role
var config: Dictionary
var world: World
var local_id := 0
var tick := 0

var _smp: SceneMultiplayer
var _source: Object  # HumanInput or ScriptedInput
var _hud: Label
var _ended := false
var _seq := 0

# Server half.
var _players := {}        # peer id -> {name, queue, newest_seq, last_seq, travelled}
var _joining_names := {}  # peer id -> name, between accept and peer_connected
var _rejected := {}       # peer id -> true, until dropped
var _nonces := {}         # peer id -> this connection's password nonce
var _started_msec := 0
var _spawn_index := 0
var _loot_seed := 0

# Client half.
var _pending: Array[PlayerInput] = []
var _own_state: Array = []   # newest server entry for us, not yet reconciled
var _remote_samples := {}    # peer id -> Array of [server tick, position, yaw]
var _roster := {}            # peer id -> name
var _latest_server_tick := -1
var _render_tick := -1.0
var _spawn_pos := Vector3.ZERO
var _travelled := 0.0
var _last_pos := Vector3.ZERO
var _last_correction := 0.0
var _max_correction := 0.0
var _reconciles := 0
var _lag_out: Array = []  # [release msec, packed inputs]
var _lag_in: Array = []   # [release msec, server tick, states]


func start(cfg: Dictionary) -> Error:
	config = cfg
	role = {"server": Role.SERVER, "host": Role.HOST, "client": Role.CLIENT}[cfg.role]
	assert(Engine.physics_ticks_per_second == Protocol.TICK_RATE)
	world = World.new()
	world.name = "World"
	add_child(world)

	_smp = multiplayer as SceneMultiplayer
	_smp.server_relay = false
	_smp.auth_timeout = Protocol.AUTH_TIMEOUT_SEC
	_smp.auth_callback = _on_auth_data
	_smp.peer_authenticating.connect(_on_peer_authenticating)
	_smp.peer_authentication_failed.connect(_on_peer_authentication_failed)
	_smp.peer_connected.connect(_on_peer_connected)
	_smp.peer_disconnected.connect(_on_peer_disconnected)

	var peer := ENetMultiplayerPeer.new()
	var err: Error
	if role == Role.CLIENT:
		_smp.connection_failed.connect(_end.bind("could not reach %s:%d" % [cfg.address, cfg.port], 4))
		_smp.server_disconnected.connect(_end.bind("server closed the connection", 5))
		err = peer.create_client(cfg.address, cfg.port)
	else:
		err = peer.create_server(cfg.port, Protocol.MAX_CLIENTS)
	if err != OK:
		return err
	_smp.multiplayer_peer = peer

	if role == Role.CLIENT:
		_log("connecting to %s:%d as %s (version %s)" % [cfg.address, cfg.port, cfg.name, cfg.version])
	else:
		if not world.load_map(cfg.map):
			return ERR_FILE_NOT_FOUND
		_loot_seed = randi()
		_started_msec = Time.get_ticks_msec()
		_log("serving map '%s' on port %d, version %s, %s" % [world.map_id, cfg.port, cfg.version,
			"password required" if cfg.password != "" else "no password"])
		if role == Role.HOST:
			_add_player(1, cfg.name)
			_become_local(1)
		elif not _headless():
			world.add_overview_camera()
		_write_status()

	if cfg.quit_after > 0.0:
		get_tree().create_timer(cfg.quit_after).timeout.connect(_on_quit_after)
	if not _headless():
		_build_hud()
	return OK


func _exit_tree() -> void:
	_close_network()


func _physics_process(_delta: float) -> void:
	if _ended:
		return
	if role == Role.CLIENT:
		_client_tick()
	else:
		_server_tick()


# --- Handshake ---------------------------------------------------------------
# Runs in SceneMultiplayer's authentication step with JSON payloads, before any
# RPC. RPC ids are indices into a per-script table, so a peer on a different
# version can't be trusted to decode RPCs; JSON stays readable by any version.

func _on_peer_authenticating(id: int) -> void:
	if role == Role.CLIENT:
		return  # the server speaks first
	_nonces[id] = Crypto.new().generate_random_bytes(16).hex_encode()
	_smp.send_auth(id, _encode({
		"t": "server_hello",
		"version": config.version,
		"map_id": world.map_id,
		"map_hash": world.map_hash,
		"nonce": _nonces[id],
		"password": config.password != "",
	}))


func _on_auth_data(id: int, data: PackedByteArray) -> void:
	var msg := _decode(data)
	if role == Role.CLIENT:
		_client_auth(msg)
	else:
		_server_auth(id, msg)


func _server_auth(id: int, msg: Dictionary) -> void:
	var player_name := Protocol.clean_name(msg.get("name"))
	var reason := "malformed hello"
	if msg.get("t") == "client_hello":
		var expected := Protocol.password_proof(config.password, _nonces.get(id, ""))
		reason = Protocol.check_hello(msg, config.version, world.map_id, world.map_hash, expected)
	_nonces.erase(id)
	if reason != "":
		_log("rejected peer %d (%s): %s" % [id, player_name, reason])
		_rejected[id] = true
		_smp.send_auth(id, _encode({"t": "reject", "reason": reason}))
		get_tree().create_timer(REJECT_GRACE_SEC).timeout.connect(_drop_rejected.bind(id))
		return
	_joining_names[id] = player_name
	_smp.send_auth(id, _encode({"t": "accept"}))
	_smp.complete_auth(id)


func _drop_rejected(id: int) -> void:
	if _rejected.erase(id) and _smp:
		_smp.disconnect_peer(id)


func _client_auth(msg: Dictionary) -> void:
	match msg.get("t"):
		"server_hello":
			var map_id := str(msg.get("map_id", ""))
			_smp.send_auth(1, _encode({
				"t": "client_hello",
				"version": config.version,
				"map_id": map_id,
				"map_hash": Protocol.map_hash(map_id),
				"name": config.name,
				"proof": Protocol.password_proof(config.password, str(msg.get("nonce", ""))),
			}))
		"accept":
			_smp.complete_auth(1)
		"reject":
			_end.call_deferred("rejected: %s" % msg.get("reason", "no reason given"), 3)


func _on_peer_authentication_failed(id: int) -> void:
	_rejected.erase(id)
	_joining_names.erase(id)
	_nonces.erase(id)
	if role != Role.CLIENT:
		_log("peer %d dropped during handshake" % id)


# --- Server half -------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if role == Role.CLIENT:
		return
	var player_name: String = _joining_names.get(id, "peer%d" % id)
	_joining_names.erase(id)
	var character := _add_player(id, player_name)
	_log("accepted peer %d (%s)" % [id, player_name])
	_write_status()
	_s2c_welcome.rpc_id(id, {
		"map_id": world.map_id,
		"loot_seed": _loot_seed,
		"tick": tick,
		"spawn": character.global_position,
	})
	_broadcast_roster()


func _on_peer_disconnected(id: int) -> void:
	if role == Role.CLIENT or not _players.has(id):
		return
	var player: Dictionary = _players[id]
	_players.erase(id)
	world.remove_character(id)
	_log("peer %d (%s) left after travelling %.2f m" % [id, player.name, player.travelled])
	_write_status()
	_broadcast_roster()


func _add_player(id: int, player_name: String) -> Character:
	var character := world.spawn_character(id, player_name, world.spawn_point(_spawn_index))
	_spawn_index += 1
	_players[id] = {"name": player_name, "queue": [], "newest_seq": 0, "last_seq": 0, "travelled": 0.0}
	return character


func _server_tick() -> void:
	if role == Role.HOST and _source:
		_seq += 1
		_players[1].queue.push_back(_source.sample(_seq))
		_players[1].newest_seq = _seq
	for id: int in _players:
		var player: Dictionary = _players[id]
		var queue: Array = player.queue
		var steps := 2 if queue.size() > CATCH_UP_QUEUE else 1
		for i in mini(steps, queue.size()):
			var input: PlayerInput = queue.pop_front()
			var character: Character = world.characters[id]
			var before := character.global_position
			character.simulate(input)
			player.travelled += character.global_position.distance_to(before)
			player.last_seq = input.seq
	_track_travel()
	tick += 1
	if tick % Protocol.SNAPSHOT_EVERY == 0:
		_broadcast_snapshot()
	if tick % STATUS_EVERY_TICKS == 0:
		_write_status()


## --status-file: a small JSON file an updater can read to see whether anyone
## is playing and whether the server is alive (it's rewritten every two
## seconds). Written to a temp file then renamed, so readers never see half.
func _write_status() -> void:
	if config.status_file == "":
		return
	var names := PackedStringArray()
	for id: int in _players:
		names.append(_players[id].name)
	var tmp: String = config.status_file + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("can't write status file %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({
		"version": config.version,
		"map": world.map_id,
		"players": _players.size(),
		"names": names,
		"uptime_s": (Time.get_ticks_msec() - _started_msec) / 1000,
		"updated_unix": int(Time.get_unix_time_from_system()),
	}))
	file.close()
	DirAccess.rename_absolute(tmp, config.status_file)


func _broadcast_snapshot() -> void:
	var states := []
	for id: int in _players:
		states.push_back([id, world.characters[id].capture_state(), _players[id].last_seq])
	for id: int in _players:
		if id != 1:
			_s2c_snapshot.rpc_id(id, tick, states)


func _broadcast_roster() -> void:
	var roster := {}
	for id: int in _players:
		roster[id] = _players[id].name
	for id: int in _players:
		if id != 1:
			_s2c_roster.rpc_id(id, roster)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _c2s_input(packed: Array) -> void:
	if role == Role.CLIENT or packed.size() > MAX_INPUTS_PER_PACKET:
		return
	var player: Dictionary = _players.get(multiplayer.get_remote_sender_id(), {})
	if player.is_empty():
		return
	for raw: Variant in packed:
		var input := PlayerInput.from_array(raw)
		if input == null or input.seq <= player.newest_seq:
			continue
		player.newest_seq = input.seq
		player.queue.push_back(input)
	while player.queue.size() > MAX_INPUT_QUEUE:
		player.queue.pop_front()


# --- Client half -------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _s2c_welcome(state: Dictionary) -> void:
	if not world.load_map(str(state.get("map_id", ""))):
		_end("server's map '%s' would not load" % state.get("map_id"), 6)
		return
	local_id = _smp.get_unique_id()
	_latest_server_tick = state.tick
	_spawn_pos = state.spawn
	world.spawn_character(local_id, config.name, _spawn_pos)
	_become_local(local_id)
	_log("joined as peer %d on map '%s' (loot seed %d)" % [local_id, world.map_id, state.loot_seed])


@rpc("authority", "call_remote", "reliable")
func _s2c_roster(roster: Dictionary) -> void:
	_roster = roster
	for id: int in roster:
		if world.characters.has(id):
			world.characters[id].set_display_name(roster[id])


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _s2c_snapshot(server_tick: int, states: Array) -> void:
	if config.lag_ms > 0:
		_lag_in.push_back([Time.get_ticks_msec() + config.lag_ms, server_tick, states])
	else:
		_on_snapshot(server_tick, states)


func _on_snapshot(server_tick: int, states: Array) -> void:
	if local_id == 0 or server_tick <= _latest_server_tick:
		return
	_latest_server_tick = server_tick
	var seen := {}
	for entry: Array in states:
		var id: int = entry[0]
		seen[id] = true
		if id == local_id:
			_own_state = entry
			continue
		var state: Array = entry[1]
		if not world.characters.has(id):
			world.spawn_character(id, _roster.get(id, "peer%d" % id), state[0])
			_remote_samples[id] = []
		_remote_samples[id].push_back([server_tick, state[0], state[2]])
	for id: int in world.characters.keys():
		if id != local_id and not seen.has(id):
			world.remove_character(id)
			_remote_samples.erase(id)


func _client_tick() -> void:
	_release_lagged()
	if local_id == 0:
		return
	var own: Character = world.characters[local_id]
	if not _own_state.is_empty():
		_reconcile(own, _own_state)
		_own_state = []
	_seq += 1
	var input: PlayerInput = _source.sample(_seq)
	own.simulate(input)
	_pending.push_back(input)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()
	var packed := []
	for i in range(maxi(0, _pending.size() - INPUT_REDUNDANCY), _pending.size()):
		packed.push_back(_pending[i].to_array())
	_send_inputs(packed)
	_interpolate_remotes()
	_track_travel()
	tick += 1


## Snap to the server's state for the last input it applied, then re-apply the
## inputs it hasn't seen yet. With matching simulation the result lands where
## prediction already was, so the correction is ~0.
func _reconcile(own: Character, entry: Array) -> void:
	var before := own.global_position
	own.restore_state(entry[1])
	var acked: int = entry[2]
	while not _pending.is_empty() and _pending[0].seq <= acked:
		_pending.pop_front()
	for input in _pending:
		own.simulate(input)
	_last_correction = own.global_position.distance_to(before)
	_reconciles += 1
	if tick > CORRECTION_WARMUP_TICKS:
		_max_correction = maxf(_max_correction, _last_correction)


func _interpolate_remotes() -> void:
	if _latest_server_tick < 0:
		return
	var target := float(_latest_server_tick - INTERP_DELAY_TICKS)
	if _render_tick < 0.0 or absf(target - _render_tick) > 30.0:
		_render_tick = target
	else:
		_render_tick += 1.0 + (target - _render_tick) * 0.1
	for id: int in _remote_samples:
		var samples: Array = _remote_samples[id]
		var character: Character = world.characters.get(id)
		if character == null or samples.is_empty():
			continue
		while samples.size() >= 2 and samples[1][0] <= _render_tick:
			samples.pop_front()
		var a: Array = samples[0]
		if samples.size() >= 2 and _render_tick >= a[0]:
			var b: Array = samples[1]
			var t: float = (_render_tick - a[0]) / float(b[0] - a[0])
			character.global_position = a[1].lerp(b[1], t)
			character.rotation.y = lerp_angle(a[2], b[2], t)
		else:
			character.global_position = a[1]
			character.rotation.y = a[2]


func _send_inputs(packed: Array) -> void:
	if config.lag_ms > 0:
		_lag_out.push_back([Time.get_ticks_msec() + config.lag_ms, packed])
	else:
		_c2s_input.rpc_id(1, packed)


## --fake-lag-ms holds packets in each direction on the client only.
func _release_lagged() -> void:
	var now := Time.get_ticks_msec()
	while not _lag_in.is_empty() and _lag_in[0][0] <= now:
		var entry: Array = _lag_in.pop_front()
		_on_snapshot(entry[1], entry[2])
	while not _lag_out.is_empty() and _lag_out[0][0] <= now:
		_c2s_input.rpc_id(1, _lag_out.pop_front()[1])


# --- Shared ------------------------------------------------------------------

func _become_local(id: int) -> void:
	local_id = id
	if config.auto != "" or _headless():
		_source = ScriptedInput.new(config.auto)
	else:
		var human := HumanInput.new()
		add_child(human)
		_source = human
	var character: Character = world.characters[id]
	character.set_local(true)
	_spawn_pos = character.global_position
	_last_pos = _spawn_pos
	if not _headless():
		var rig := CameraRig.new()
		rig.target = character
		rig.source = _source
		add_child(rig)


## Path length of our own character, for the test report.
func _track_travel() -> void:
	var own: Character = world.characters.get(local_id)
	if own:
		_travelled += own.global_position.distance_to(_last_pos)
		_last_pos = own.global_position


func _on_quit_after() -> void:
	_log(_final_report())
	_end("quit-after elapsed", 0)


## One greppable line for the end-to-end tests.
func _final_report() -> String:
	var others := PackedStringArray()
	for id: int in world.characters:
		if id != local_id:
			others.append(world.characters[id].display_name)
	others.sort()
	var parts := PackedStringArray([
		"final role=%s" % Role.keys()[role].to_lower(),
		"id=%d" % local_id,
		"players=%d" % world.characters.size(),
		"others=%s" % ",".join(others),
	])
	if world.characters.has(local_id):
		var pos: Vector3 = world.characters[local_id].global_position
		parts.append("moved=%.2f" % pos.distance_to(_spawn_pos))
		parts.append("travelled=%.2f" % _travelled)
		parts.append("height=%.2f" % pos.y)
	if role == Role.CLIENT:
		parts.append("reconciles=%d" % _reconciles)
		parts.append("max_correction_cm=%.2f" % (_max_correction * 100.0))
		parts.append("pending=%d" % _pending.size())
	return " ".join(parts)


func _end(reason: String, exit_code: int) -> void:
	if _ended:
		return
	_ended = true
	_log("session ended: %s" % reason)
	_close_network()
	ended.emit(reason, exit_code)


func _close_network() -> void:
	if _smp == null:
		return
	_smp.auth_callback = Callable()
	if _smp.multiplayer_peer:
		_smp.multiplayer_peer.close()
	_smp.multiplayer_peer = OfflineMultiplayerPeer.new()
	_smp = null


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_hud)
	add_child(layer)


func _process(_delta: float) -> void:
	if _hud == null:
		return
	var lines := PackedStringArray()
	lines.append("ROUT %s  |  %s  |  peer %d  |  tick %d  |  players %d" % [
		config.version, Role.keys()[role].to_lower(), local_id, tick, world.characters.size()])
	if role == Role.CLIENT:
		lines.append("rtt %d ms (+%d fake)  |  unacked inputs %d  |  correction %.1f cm (max %.1f)" % [
			_rtt_ms(), config.lag_ms * 2, _pending.size(), _last_correction * 100.0, _max_correction * 100.0])
	if world.characters.has(local_id):
		var c: Character = world.characters[local_id]
		lines.append("pos %.1f, %.1f, %.1f m  |  speed %.1f m/s" % [
			c.global_position.x, c.global_position.y, c.global_position.z, Vector2(c.velocity.x, c.velocity.z).length()])
	lines.append("WASD move · mouse look · Space jump · Esc frees the mouse")
	_hud.text = "\n".join(lines)


func _rtt_ms() -> int:
	var enet := _smp.multiplayer_peer as ENetMultiplayerPeer if _smp else null
	var server := enet.get_peer(1) if enet else null
	return int(server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if server else -1


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func _encode(msg: Dictionary) -> PackedByteArray:
	return JSON.stringify(msg).to_utf8_buffer()


static func _decode(data: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _log(msg: String) -> void:
	print("[rout] ", msg)
