class_name Protocol
extends RefCounted
## Constants and checks both ends must agree on, plus the map hash used in the
## connect handshake.

const GAME_VERSION := "0.1.0"
const DEFAULT_PORT := 24650
const MAX_CLIENTS := 16
const TICK_RATE := 60        # simulation steps per second
const SNAPSHOT_EVERY := 2    # ticks between snapshots (30 Hz)
const AUTH_TIMEOUT_SEC := 5.0
const MAX_NAME_LEN := 16
const MAP_FILES := ["geometry.tscn", "data.json"]
## Code that must match between server and client. Maps have their own hash;
## tests and docs don't affect play.
const CODE_EXTENSIONS := ["gd", "tscn"]
const CODE_EXCLUDE := ["res://tests", "res://maps", "res://docs", "res://deploy"]

static var _game_version := ""


## GAME_VERSION plus the first 8 hex of a hash over the code, e.g.
## "0.1.0+1a2b3c4d". Peers on different code refuse each other at connect
## instead of desyncing mid-game.
static func game_version() -> String:
	if _game_version == "":
		_game_version = "%s+%s" % [GAME_VERSION, _hash_files(code_files()).left(8)]
	return _game_version


static func code_files() -> PackedStringArray:
	var files := PackedStringArray(["res://project.godot"])
	_collect_code("res://", files)
	files.sort()
	return files


static func _collect_code(dir: String, out: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		var path := dir.path_join(sub)
		if not path in CODE_EXCLUDE:
			_collect_code(path, out)
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in CODE_EXTENSIONS:
			out.append(dir.path_join(file))


static func map_dir(map_id: String) -> String:
	return "res://maps/%s/" % map_id


## SHA-256 over the map's geometry and data files, or "" if the map id is not
## a plain name or the files are missing.
static func map_hash(map_id: String) -> String:
	var valid := RegEx.create_from_string("^[a-z0-9_]+$")
	if valid.search(map_id) == null:
		return ""
	var paths := PackedStringArray()
	for file: String in MAP_FILES:
		paths.append(map_dir(map_id) + file)
	return _hash_files(paths)


## SHA-256 over the files' paths, sizes and bytes; "" if any is missing.
static func _hash_files(paths: PackedStringArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for path in paths:
		if not FileAccess.file_exists(path):
			return ""
		var bytes := FileAccess.get_file_as_bytes(path)
		ctx.update(("%s:%d:" % [path, bytes.size()]).to_utf8_buffer())
		ctx.update(bytes)
	return ctx.finish().hex_encode()


## HMAC-SHA256(password, nonce) as hex, or "" when there is no password. The
## server sends a fresh nonce per connection, so the password never crosses
## the wire and a captured proof can't be replayed.
static func password_proof(password: String, nonce: String) -> String:
	if password == "":
		return ""
	var mac := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, password.to_utf8_buffer(), nonce.to_utf8_buffer())
	return mac.hex_encode()


## Why a client_hello should be refused, or "" if it is acceptable.
## `expected_proof` is password_proof() for this connection's nonce, or "" for
## an open server.
static func check_hello(hello: Dictionary, version: String, map_id: String, hash: String,
		expected_proof := "") -> String:
	for key in ["version", "map_id", "map_hash"]:
		if not hello.get(key) is String:
			return "malformed hello"
	if hello["version"] != version:
		return "version mismatch (server %s, client %s)" % [version, hello["version"]]
	if expected_proof != "":
		var proof: Variant = hello.get("proof", "")
		if not proof is String or proof == "":
			return "password required"
		if proof.length() != expected_proof.length() \
				or not Crypto.new().constant_time_compare(proof.to_utf8_buffer(), expected_proof.to_utf8_buffer()):
			return "wrong password"
	if hello["map_id"] != map_id:
		return "map mismatch (server '%s', client '%s')" % [map_id, hello["map_id"]]
	if hello["map_hash"] == "":
		return "client does not have map '%s'" % map_id
	if hello["map_hash"] != hash:
		return "map '%s' differs from the server's copy" % map_id
	return ""


static func clean_name(raw: Variant) -> String:
	var out := ""
	if raw is String:
		for ch in (raw as String).strip_edges().left(MAX_NAME_LEN):
			if ch.unicode_at(0) >= 32:
				out += ch
	return out if out != "" else "player"
