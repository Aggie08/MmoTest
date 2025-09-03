extends CharacterBody2D

@export var speed = 250.0
@export var player_id: int
@export var player_name: String = ""

@onready var name_label = $NameLabel
@onready var camera = $Camera2D
@onready var anim_tree: AnimationTree = $AnimationTree

var input_vector = Vector2.ZERO
var target_position = Vector2.ZERO
var is_moving = false
var playback: AnimationNodeStateMachinePlayback

# Network interpolation
var network_position = Vector2.ZERO
var last_network_update = 0.0

func _ready():
	playback = anim_tree["parameters/playback"]
	# Set up name label
	name_label.text = player_name
	
	# Camera setup will be done in setup_player function
	# to ensure player_id is properly set first

func _physics_process(delta):
	if multiplayer.get_unique_id() == player_id:
		# Handle local player input and movement
		handle_input()
		handle_movement(delta)
		animate()
		
		# Send position updates to server periodically
		if position != network_position:
			rpc("update_position", position, input_vector)
			network_position = position
	else:
		# Interpolate other players' positions
		interpolate_position(delta)

func handle_input():
	input_vector = Input.get_vector("move_left","move_right","move_up", "move_down")
	
	# Normalize diagonal movement
	input_vector = input_vector.normalized()
	
	# Handle interaction input
	if Input.is_action_just_pressed("interact"):
		check_for_interactions()

func animate():
	if velocity == Vector2.ZERO:
		playback.travel("Idle")
	else:
		playback.travel("Walk")
	
	if input_vector == Vector2.ZERO:
		return
	anim_tree["parameters/Idle/blend_position"] = input_vector
	anim_tree["parameters/Walk/blend_position"] = input_vector

func handle_movement(delta):
	if input_vector != Vector2.ZERO:
		velocity = input_vector * speed
		is_moving = true
	else:
		velocity = Vector2.ZERO
		is_moving = false
	
	move_and_slide()

func interpolate_position(delta):
	# Smooth interpolation for other players
	var interpolation_speed = 10.0
	position = position.lerp(target_position, interpolation_speed * delta)

# Called by other clients to update this player's position
@rpc("any_peer", "unreliable")
func update_position(new_position: Vector2, movement_vector: Vector2):
	# Only the server should process this
	if not Network.is_server:
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != player_id:
		return  # Only the owning player can update position
	
	# Basic validation (anti-cheat)
	var max_distance = speed * 2.0 / 60.0  # Max distance per frame at 60 FPS
	if position.distance_to(new_position) > max_distance:
		print("Suspicious movement from player ", player_id)
		return
	
	# Update position
	position = new_position
	input_vector = movement_vector
	is_moving = movement_vector != Vector2.ZERO
	
	# Update in NetworkManager
	Network.update_player_position(player_id, position)
	
	# Broadcast to other clients
	rpc("sync_position", new_position, movement_vector, is_moving)

# Sync position to other clients
@rpc("authority", "unreliable")
func sync_position(new_position: Vector2, movement_vector: Vector2, moving: bool):
	if multiplayer.get_unique_id() != player_id:  # Don't sync to self
		target_position = new_position
		input_vector = movement_vector
		is_moving = moving
		last_network_update = Time.get_datetime_dict_from_system()

func check_for_interactions():
	# Get nearby players for private chat
	var nearby_players = get_nearby_players(50.0)  # 50 pixel radius
	
	if nearby_players.size() > 0:
		# For simplicity, interact with the first nearby player
		var target_player = nearby_players[0]
		show_private_chat_dialog(target_player.player_id, target_player.player_name)

func get_nearby_players(radius: float) -> Array:
	var nearby = []
	var players_in_world = get_tree().get_nodes_in_group("players")
	
	for player in players_in_world:
		if player != self and player.position.distance_to(position) <= radius:
			nearby.append(player)
	
	return nearby

func show_private_chat_dialog(target_id: int, target_name: String):
	# Signal to UI to show private chat dialog
	GameManager.show_private_chat_dialog(target_id, target_name)

func set_player_name(new_name: String):
	player_name = new_name
	if name_label:
		name_label.text = player_name

# Initialize player data
func setup_player(id: int, name: String, spawn_position: Vector2):
	player_id = id
	player_name = name
	position = spawn_position
	target_position = spawn_position
	network_position = spawn_position
	
	set_player_name(name)
	add_to_group("players")
	
	# Set up camera and authority AFTER player_id is set
	setup_camera_and_authority()

func setup_camera_and_authority():
	set_multiplayer_authority(player_id)
	# If this is our player, enable input and camera
	if is_multiplayer_authority():
		print("Setting up local player camera for player ID: ", player_id)
		
		# Enable camera
		if camera:
			camera.enabled = true
			camera.make_current()
			print("Camera enabled and made current for local player")
		else:
			print("WARNING: Camera node not found!")
		
		# Enable input processing
		set_process(true)
		set_physics_process(true)
	else:
		print("Setting up remote player for player ID: ", player_id)
		# For other players, disable physics processing and camera
		set_physics_process(false)
		if camera:
			camera.enabled = false
		print("Remote player setup complete")
