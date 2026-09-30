extends Node
## Entry point: parse flags, show the Host/Join menu, run a Session.
##
##   godot --path spike-godot                               menu
##   godot --path spike-godot -- --host [--port=N] [--name=X]
##   godot --path spike-godot -- --join=ADDR[:PORT] [--name=X]
##   godot --headless --path spike-godot -- --server [--port=N]
##
## Test flags: --auto=circle|line|idle  --fake-lag-ms=N  --fake-version=V
##             --quit-after=SEC

const SessionScript := preload("res://game/session.gd")

var _cfg := {}
var _session: Node
var _menu: Control
var _status: Label
var _name_edit: LineEdit
var _addr_edit: LineEdit


func _ready() -> void:
	_cfg = _parse_args(OS.get_cmdline_user_args())
	if _cfg.has("error"):
		printerr("[rout] ", _cfg.error)
		get_tree().quit(1)
	elif _cfg.role != "":
		_start(_cfg)
	elif DisplayServer.get_name() == "headless":
		printerr("[rout] headless needs --server, --host or --join=ADDR")
		get_tree().quit(1)
	else:
		_show_menu("")


func _parse_args(args: PackedStringArray) -> Dictionary:
	var cfg := {
		"role": "",
		"address": "127.0.0.1",
		"port": Protocol.DEFAULT_PORT,
		"name": "player%d" % randi_range(100, 999),
		"map": "plane",
		"auto": "",
		"lag_ms": 0,
		"version": Protocol.GAME_VERSION,
		"quit_after": 0.0,
	}
	for arg in args:
		var key := arg.trim_prefix("--").get_slice("=", 0)
		var value := arg.get_slice("=", 1) if "=" in arg else ""
		match key:
			"server", "host":
				cfg.role = key
			"join":
				cfg.role = "client"
				if not _apply_address(cfg, value):
					return {"error": "bad --join address '%s'" % value}
			"port":
				cfg.port = value.to_int()
			"name":
				cfg.name = Protocol.clean_name(value)
			"map":
				cfg.map = value
			"auto":
				cfg.auto = value
			"fake-lag-ms":
				cfg.lag_ms = value.to_int()
			"fake-version":
				cfg.version = value
			"quit-after":
				cfg.quit_after = value.to_float()
			_:
				return {"error": "unknown flag '%s'" % arg}
	return cfg


## "host" or "host:port" into cfg. False if the port part is not a number.
static func _apply_address(cfg: Dictionary, text: String) -> bool:
	var parts := text.strip_edges().split(":")
	if parts[0] == "" or parts.size() > 2:
		return false
	cfg.address = parts[0]
	if parts.size() == 2:
		if not parts[1].is_valid_int():
			return false
		cfg.port = parts[1].to_int()
	return true


func _start(cfg: Dictionary) -> void:
	if _menu:
		_menu.hide()
	_session = SessionScript.new()
	_session.name = "Session"  # must match on every peer: RPCs are routed by path
	add_child(_session)
	_session.ended.connect(_on_session_ended)
	var err: Error = _session.start(cfg)
	if err != OK:
		_on_session_ended("could not start: %s" % error_string(err), 4)


func _on_session_ended(reason: String, exit_code: int) -> void:
	if _session:
		_session.queue_free()
		_session = null
	if DisplayServer.get_name() == "headless" or _cfg.quit_after > 0.0:
		get_tree().quit(exit_code)
	else:
		_show_menu(reason)


func _show_menu(status: String) -> void:
	if _menu == null:
		_build_menu()
	_status.text = status
	_menu.show()


func _build_menu() -> void:
	_menu = CenterContainer.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 10)
	_menu.add_child(box)

	var title := Label.new()
	title.text = "ROUT"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Godot spike %s" % Protocol.GAME_VERSION
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	_name_edit = LineEdit.new()
	_name_edit.text = _cfg.name
	_name_edit.placeholder_text = "Name"
	box.add_child(_name_edit)
	_addr_edit = LineEdit.new()
	_addr_edit.text = "%s:%d" % [_cfg.address, _cfg.port]
	_addr_edit.placeholder_text = "address:port"
	box.add_child(_addr_edit)

	var host := Button.new()
	host.text = "Host (listen server)"
	host.pressed.connect(_on_menu_pressed.bind("host"))
	box.add_child(host)
	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(_on_menu_pressed.bind("client"))
	box.add_child(join)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	add_child(_menu)


func _on_menu_pressed(role: String) -> void:
	var cfg := _cfg.duplicate()
	cfg.role = role
	cfg.name = Protocol.clean_name(_name_edit.text)
	if not _apply_address(cfg, _addr_edit.text):
		_status.text = "Address should look like 192.168.1.20:%d" % Protocol.DEFAULT_PORT
		return
	_status.text = "Connecting…" if role == "client" else ""
	_start(cfg)
