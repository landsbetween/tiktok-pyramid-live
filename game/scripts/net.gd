extends Node
## WebSocket client for the TikTok LIVE bridge (server/server.js). Reconnects forever.

signal event(d: Dictionary)

var url := "ws://127.0.0.1:3001"
var ws := WebSocketPeer.new()
var connected := false
var retry := 0.0


func _ready() -> void:
	_open()


func _open() -> void:
	ws = WebSocketPeer.new()
	if ws.connect_to_url(url) != OK:
		retry = 2.0


func send(d: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


func _process(delta: float) -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			print("[net] connected to ", url)
		while ws.get_available_packet_count() > 0:
			var d = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if typeof(d) == TYPE_DICTIONARY:
				event.emit(d)
	elif st == WebSocketPeer.STATE_CLOSED:
		if connected:
			connected = false
			print("[net] disconnected")
		retry -= delta
		if retry <= 0.0:
			retry = 2.0
			_open()
