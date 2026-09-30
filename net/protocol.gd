class_name Protocol
extends RefCounted
## Constants and checks both ends must agree on, plus the map hash used in the
## connect handshake.

const GAME_VERSION := "0.1.0-spike"
const DEFAULT_PORT := 24650
const MAX_CLIENTS := 16
const TICK_RATE := 60        # simulation steps per second
const SNAPSHOT_EVERY := 2    # ticks between snapshots (30 Hz)
const AUTH_TIMEOUT_SEC := 5.0
const MAX_NAME_LEN := 16
const MAP_FILES := ["geometry.tscn", "data.json"]


static func map_dir(map_id: String) -> String:
	return "res://maps/%s/" % map_id


## SHA-256 over the map's geometry and data files, or "" if the map id is not
## a plain name or the files are missing.
static func map_hash(map_id: String) -> String:
	var valid := RegEx.create_from_string("^[a-z0-9_]+$")
	if valid.search(map_id) == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for file: String in MAP_FILES:
		var path := map_dir(map_id) + file
		if not FileAccess.file_exists(path):
			return ""
		var bytes := FileAccess.get_file_as_bytes(path)
		ctx.update(("%s:%d:" % [file, bytes.size()]).to_utf8_buffer())
		ctx.update(bytes)
	return ctx.finish().hex_encode()


## Why a client_hello should be refused, or "" if it is acceptable.
static func check_hello(hello: Dictionary, version: String, map_id: String, hash: String) -> String:
	for key in ["version", "map_id", "map_hash"]:
		if not hello.get(key) is String:
			return "malformed hello"
	if hello["version"] != version:
		return "version mismatch (server %s, client %s)" % [version, hello["version"]]
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
