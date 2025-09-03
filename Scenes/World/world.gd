extends Node2D

@export var player_scene: PackedScene

var spawn_points = [
	Vector2(100, 100),
	Vector2(200, 100),
	Vector2(300, 100),
	Vector2(100, 200),
	Vector2(200, 200),
	Vector2(300, 200)
]

var spawned_players = {}

func _ready():
	print("World scene loaded")
	
	# Ensure player scene is set
	if not player_scene:
		player_scene = preload("res://Scenes/Player/player.tscn")
		print("Player scene loaded from preload")
	
	# Connect network signals
	Network.player_connected.connect(_on_player_connected)
	Network.player_disconnected.connect(_on_player_disconnected)
	Network.player_authenticated.connect(_on_player_authenticated)
	
	if Network.is_server:
		print("World loaded on server")
	else:
		print("World loaded on client")

func _on_player_connected(peer_id: int):
	print("Player connected signal received: ", peer_id)

func _on_player_disconnected(peer_id: int):
	print("Player disconnected signal received: ", peer_id)
	if peer_id in spawned_players:
		spawned_players[peer_id].queue_free()
		spawned_players.erase(peer_id)

func _on_player_authenticated(peer_id: int, player_name: String):
	print("Player authenticated signal received: ", peer_id, " - ", player_name)
	# Spawn player when they authenticate
	spawn_player(peer_id, player_name)

# Called by Network when sending existing players to a new client
func spawn_existing_players_data(existing_players: Dictionary):
	print("Spawning existing players: ", existing_players)
	for peer_id in existing_players:
		var player_data = existing_players[peer_id]
		if player_data.is_authenticated:
			spawn_player(peer_id, player_data.name, player_data.position)

# Called by Network when a new player joins (for existing clients)
func spawn_new_player(peer_id: int, player_name: String):
	print("Spawning new player: ", peer_id, " - ", player_name)
	spawn_player(peer_id, player_name)

func spawn_player(peer_id: int, player_name: String, spawn_position: Vector2 = Vector2.ZERO):
	print("Attempting to spawn player: ", peer_id, " - ", player_name)
	
	if peer_id in spawned_players:
		print("Player already spawned: ", peer_id)
		return  # Already spawned
	
	if not player_scene:
		print("ERROR: Player scene not set!")
		return
	
	var player_instance = player_scene.instantiate()
	if not player_instance:
		print("ERROR: Failed to instantiate player scene!")
		return
	
	get_node("Players").add_child(player_instance)
	print("Player instance added to world")
	
	# Set spawn position
	if spawn_position == Vector2.ZERO:
		spawn_position = get_spawn_point()
	
	player_instance.setup_player(peer_id, player_name, spawn_position)
	spawned_players[peer_id] = player_instance
	
	print("Successfully spawned player: ", player_name, " (", peer_id, ") at ", spawn_position)
	
	# If this is the server, tell all clients to spawn this player
	if Network.is_server:
		rpc("client_spawn_player", peer_id, player_name, spawn_position)

func get_spawn_point() -> Vector2:
	# Simple random spawn point selection
	return spawn_points[randi() % spawn_points.size()]

# Called by server to tell clients to spawn a player
@rpc("authority", "reliable")
func client_spawn_player(peer_id: int, player_name: String, spawn_position: Vector2):
	print("Client received spawn command for: ", peer_id, " - ", player_name)
	spawn_player(peer_id, player_name, spawn_position)
