extends Node

signal message_received(message_data: Dictionary)
signal private_message_received(from: String, message: String)

var chat_history = []
var private_conversations = {}
var max_history = 100

func _ready():
	pass

# Send global chat message
func send_global_message(message: String):
	if message.strip_edges() == "":
		return
		
	var player_data = Network.get_player(multiplayer.get_unique_id())
	if player_data and player_data.is_authenticated:
		rpc("receive_global_message", player_data.name, message, Time.get_unix_time_from_system())

# Send private message to specific player
func send_private_message(target_player_id: int, message: String):
	if message.strip_edges() == "":
		return
		
	var player_data = Network.get_player(multiplayer.get_unique_id())
	var target_data = Network.get_player(target_player_id)
	
	if player_data and player_data.is_authenticated and target_data and target_data.is_authenticated:
		# Send to target and self
		rpc_id(target_player_id, "receive_private_message", player_data.name, message, Time.get_unix_time_from_system())
		# Echo back to sender
		receive_private_message(player_data.name, message, Time.get_unix_time_from_system(), true)

# Receive global message from other players
@rpc("any_peer", "reliable")
func receive_global_message(from: String, message: String, timestamp: int):
	# Validate on server
	if Network.is_server:
		var sender_id = multiplayer.get_remote_sender_id()
		var sender_data = Network.get_player(sender_id)
		
		if not sender_data or not sender_data.is_authenticated or sender_data.name != from:
			print("Invalid global message from ", sender_id)
			return
		
		# Sanitize message
		message = sanitize_message(message)
		if message == "":
			return
			
		# Broadcast to all clients
		rpc("receive_global_message", from, message, timestamp)
		return
	
	# Client receiving message
	var message_data = {
		"type": "global",
		"from": from,
		"message": message,
		"timestamp": timestamp
	}
	
	add_to_history(message_data)
	message_received.emit(message_data)
	print("[GLOBAL] ", from, ": ", message)

# Receive private message
@rpc("any_peer", "reliable")
func receive_private_message(from: String, message: String, timestamp: int, is_echo: bool = false):
	# Validate on server if not an echo
	if Network.is_server and not is_echo:
		var sender_id = multiplayer.get_remote_sender_id()
		var sender_data = Network.get_player(sender_id)
		
		if not sender_data or not sender_data.is_authenticated or sender_data.name != from:
			print("Invalid private message from ", sender_id)
			return
		
		# This should be handled by send_private_message, not here
		print("Server received private message RPC - this shouldn't happen")
		return
	
	# Client receiving message
	message = sanitize_message(message)
	
	# Store in private conversation
	if not from in private_conversations:
		private_conversations[from] = []
	
	private_conversations[from].append({
		"message": message,
		"timestamp": timestamp,
		"from_me": is_echo
	})
	
	# Keep conversation history limited
	if private_conversations[from].size() > max_history:
		private_conversations[from] = private_conversations[from].slice(-max_history)
	
	private_message_received.emit(from, message)
	print("[PRIVATE] ", from, ": ", message)

# Add system message (server announcements, join/leave messages)
func add_system_message(message: String):
	var message_data = {
		"type": "system",
		"from": "System",
		"message": message,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	add_to_history(message_data)
	message_received.emit(message_data)
	print("[SYSTEM] ", message)

# Sanitize chat messages
func sanitize_message(message: String) -> String:
	# Remove excess whitespace
	message = message.strip_edges()
	
	# Limit length
	if message.length() > 200:
		message = message.substr(0, 200)
	
	# Basic profanity filter (add your own words)
	var banned_words = ["badword1", "badword2"]  # Add actual banned words
	for word in banned_words:
		message = message.replace(word, "***")
	
	# Remove HTML tags for security
	message = message.replace("<", "&lt;").replace(">", "&gt;")
	
	return message

# Add message to chat history
func add_to_history(message_data: Dictionary):
	chat_history.append(message_data)
	
	# Limit history size
	if chat_history.size() > max_history:
		chat_history = chat_history.slice(-max_history)

# Get chat history
func get_chat_history() -> Array:
	return chat_history

# Get private conversation with a player
func get_private_conversation(player_name: String) -> Array:
	return private_conversations.get(player_name, [])

# Clear private conversation
func clear_private_conversation(player_name: String):
	if player_name in private_conversations:
		private_conversations.erase(player_name)

# Get all active private conversations
func get_active_conversations() -> Array:
	return private_conversations.keys()
