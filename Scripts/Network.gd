extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal player_list_updated()
signal player_authenticated(peer_id: int, player_name: String)
signal client_connected()

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 100
const SERVER_URL = "127.0.0.1"  # Replace with your actual Fly.io domain

var players = {}
var is_server = false
var multiplayer_peer: MultiplayerPeer
var server_port = DEFAULT_PORT

func _ready():
	# Parse command line arguments
	parse_command_line_args()
	
	# Check if running as dedicated server
	if "--server" in OS.get_cmdline_args() or "--dedicated" in OS.get_cmdline_args():
		start_server()
	else:
		# Client mode - show login screen
		GameManager.show_login_screen()

func parse_command_line_args():
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			server_port = int(args[i + 1])
			print("Using port: ", server_port)

func start_server():
	print("Starting dedicated server...")
	is_server = true
	
	multiplayer_peer = ENetMultiplayerPeer.new()
	var result = multiplayer_peer.create_server(server_port, MAX_CLIENTS)
	
	if result == OK:
		multiplayer.multiplayer_peer = multiplayer_peer
		print("Server started on port ", server_port)
		print("Server listening on all interfaces (0.0.0.0:", server_port, ")")
		
		# Connect server signals
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		
		# Load the world scene
		get_tree().change_scene_to_file("res://Scenes/World/World.tscn")
		
		# Setup server heartbeat for health checks
		setup_server_heartbeat()
	else:
		print("Failed to start server: ", result)
		get_tree().quit(1)

func setup_server_heartbeat():
	# Simple heartbeat for monitoring
	var timer = Timer.new()
	timer.wait_time = 30.0  # 30 second heartbeat
	timer.timeout.connect(_on_heartbeat)
	timer.autostart = true
	add_child(timer)

func _on_heartbeat():
	print("Server heartbeat - Players online: ", players.size())

func connect_to_server(address: String = ""):
	# Use default server URL if no address provided
	if address == "":
		address = SERVER_URL
	
	print("Connecting to server at: ", address)
	
	multiplayer_peer = ENetMultiplayerPeer.new()
	var result = multiplayer_peer.create_client(address, DEFAULT_PORT)
	
	if result == OK:
		multiplayer.multiplayer_peer = multiplayer_peer
		
		# Connect client signals
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		
		print("Attempting connection to ", address, ":", DEFAULT_PORT)
	else:
		print("Failed to create client: ", result)
		GameManager.show_connection_error("Failed to create network connection")

func _on_peer_connected(peer_id: int):
	print("Player ", peer_id, " connected")
	players[peer_id] = {
		"id": peer_id,
		"name": "",
		"position": Vector2.ZERO,
		"is_authenticated": false
	}
	player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int):
	print("Player ", peer_id, " disconnected")
	if peer_id in players:
		var player_name = players[peer_id].get("name", "Unknown")
		players.erase(peer_id)
		
		# Notify other players
		rpc("player_left", peer_id, player_name)
		player_disconnected.emit(peer_id)
		player_list_updated.emit()

func _on_connected_to_server():
	print("Connected to server successfully")
	client_connected.emit()
	#get_tree().change_scene_to_file("res://Scenes/World/World.tscn")

func _on_connection_failed():
	print("Failed to connect to server")
	GameManager.show_connection_error("Could not connect to server. Please check your internet connection.")

func _on_server_disconnected():
	print("Disconnected from server")
	players.clear()
	GameManager.show_disconnection_message()

# Graceful shutdown for server
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_server:
			print("Server shutting down gracefully...")
			# Notify all clients
			rpc("server_shutdown_notification")
			await get_tree().create_timer(1.0).timeout
		get_tree().quit()

@rpc("authority", "reliable")
func server_shutdown_notification():
	print("Server is shutting down")
	GameManager.show_connection_error("Server is shutting down for maintenance")

# Add reconnection capability
func attempt_reconnect():
	if not is_server and multiplayer_peer:
		print("Attempting to reconnect...")
		connect_to_server()

# Enhanced error handling
func get_connection_status() -> String:
	if not multiplayer_peer:
		return "No connection"
	
	match multiplayer_peer.get_connection_status():
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			return "Disconnected"
		MultiplayerPeer.CONNECTION_CONNECTING:
			return "Connecting"
		MultiplayerPeer.CONNECTION_CONNECTED:
			return "Connected"
		_:
			return "Unknown"

# Called by client to authenticate with a name
@rpc("any_peer", "reliable")
func authenticate_player(player_name: String):
	var peer_id = multiplayer.get_remote_sender_id()
	print("Authentication request from peer ", peer_id, " with name: ", player_name)
	
	if peer_id in players and not players[peer_id].is_authenticated:
		# Validate name (basic check)
		if player_name.length() >= 3 and player_name.length() <= 20:
			players[peer_id].name = player_name
			players[peer_id].is_authenticated = true
			
			#get_tree().change_scene_to_file("res://Scenes/World/World.tscn")
			
			print("Player ", peer_id, " authenticated as: ", player_name)
			
			# Send success to client
			rpc_id(peer_id, "authentication_result", true, "")
			
			# Send existing players to the new client
			rpc_id(peer_id, "send_existing_players", get_authenticated_players())
			
			# Notify other players about new player
			rpc("player_joined", peer_id, player_name)
			
			# Emit signal for world to spawn player
			player_authenticated.emit(peer_id, player_name)
			player_list_updated.emit()
		else:
			print("Authentication failed for peer ", peer_id, ": invalid name length")
			rpc_id(peer_id, "authentication_result", false, "Name must be 3-20 characters")

# Called by server to inform clients about authentication result
@rpc("authority", "reliable")
func authentication_result(success: bool, error_message: String):
	GameManager.on_authentication_result(success, error_message)

# Send existing players to a newly connected client
@rpc("authority", "reliable")
func send_existing_players(existing_players: Dictionary):
	if not is_server:
		print("Received existing players data: ", existing_players)
		# Tell the world to spawn existing players
		var world = get_tree().current_scene
		if world and world.has_method("spawn_existing_players_data"):
			world.spawn_existing_players_data(existing_players)

# Called by server to notify about new players
@rpc("authority", "reliable")
func player_joined(peer_id: int, player_name: String):
	if not is_server:
		print(player_name, " joined the game")
		#ChatManager.add_system_message(player_name + " joined the game")
		
		# Tell world to spawn this new player if we're already in the world
		var world = get_tree().current_scene
		if world and world.has_method("spawn_new_player"):
			world.spawn_new_player(peer_id, player_name)

# Called by server to notify about players leaving
@rpc("authority", "reliable")
func player_left(peer_id: int, player_name: String):
	if not is_server:
		print(player_name, " left the game")
		ChatManager.add_system_message(player_name + " left the game")

# Get player data
func get_player(peer_id: int):
	return players.get(peer_id)

func get_all_players():
	return players

func get_authenticated_players():
	var auth_players = {}
	for peer_id in players:
		if players[peer_id].is_authenticated:
			auth_players[peer_id] = players[peer_id]
	return auth_players

# Update player position (called by Player nodes)
func update_player_position(peer_id: int, position: Vector2):
	if peer_id in players:
		players[peer_id].position = position
