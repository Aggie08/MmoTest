extends Control

@onready var chat_display = $VBoxContainer/ChatDisplay
@onready var chat_input = $VBoxContainer/HBoxContainer/ChatInput
@onready var send_button = $VBoxContainer/HBoxContainer/SendButton
@onready var private_chat_panel = $PrivateChatPanel
@onready var private_display = $PrivateChatPanel/VBoxContainer/PrivateDisplay
@onready var private_input = $PrivateChatPanel/VBoxContainer/HBoxContainer/PrivateInput
@onready var private_send = $PrivateChatPanel/VBoxContainer/HBoxContainer/PrivateSendButton
@onready var private_close = $PrivateChatPanel/VBoxContainer/CloseButton
@onready var private_title = $PrivateChatPanel/VBoxContainer/PrivateTitle

var current_private_target_id = -1
var current_private_target_name = ""
var max_chat_lines = 50

func _ready():
	setup()

func setup():
	# Connect to chat manager
	ChatManager.message_received.connect(_on_message_received)
	ChatManager.private_message_received.connect(_on_private_message_received)
	
	# Connect to game manager for private chat requests
	GameManager.private_chat_requested.connect(_on_private_chat_requested)
	
	# Hide private chat panel initially
	private_chat_panel.hide()
	
	# Set up input handling
	chat_input.grab_focus()
	
	# Load existing chat history
	load_chat_history()
	
	# Set up UI properties
	chat_display.scroll_following = true
	private_display.scroll_following = true

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if private_chat_panel.visible:
			_on_private_close_pressed()
		else:
			# Toggle chat input focus
			if chat_input.has_focus():
				chat_input.release_focus()
			else:
				chat_input.grab_focus()

func _on_send_pressed():
	send_global_message()

func _on_chat_submitted(_text: String):
	send_global_message()

func send_global_message():
	var message = chat_input.text.strip_edges()
	if message != "":
		ChatManager.send_global_message(message)
		chat_input.text = ""

func _on_private_send_pressed():
	send_private_message()

func _on_private_submitted(_text: String):
	send_private_message()

func send_private_message():
	var message = private_input.text.strip_edges()
	if message != "" and current_private_target_id != -1:
		ChatManager.send_private_message(current_private_target_id, message)
		
		# Add to private display immediately
		add_private_message(GameManager.get_player_name(), message, true)
		private_input.text = ""

func _on_private_close_pressed():
	private_chat_panel.hide()
	current_private_target_id = -1
	current_private_target_name = ""
	chat_input.grab_focus()

func _on_message_received(message_data: Dictionary):
	add_chat_message(message_data)

func _on_private_message_received(from: String, message: String):
	# If we have the private chat open with this person, show it there
	if current_private_target_name == from and private_chat_panel.visible:
		add_private_message(from, message, false)
	else:
		# Show in main chat as notification
		add_chat_message({
			"type": "private_notification",
			"from": from,
			"message": "[Private] " + message,
			"timestamp": Time.get_unix_time_from_system()
		})

func _on_private_chat_requested(target_id: int, target_name: String):
	open_private_chat(target_id, target_name)

func open_private_chat(target_id: int, target_name: String):
	current_private_target_id = target_id
	current_private_target_name = target_name
	
	private_title.text = "Private chat with " + target_name
	private_chat_panel.show()
	private_input.grab_focus()
	
	# Load conversation history
	load_private_conversation(target_name)

func add_chat_message(message_data: Dictionary):
	var timestamp = Time.get_datetime_string_from_unix_time(message_data.timestamp)
	var color = get_message_color(message_data.type)
	var prefix = get_message_prefix(message_data.type)
	
	var formatted_message = "[color=%s]%s[%s] %s: %s[/color]" % [
		color,
		prefix,
		timestamp.split(" ")[1].substr(0, 5),  # Just show HH:MM
		message_data.from,
		message_data.message
	]
	
	chat_display.append_text(formatted_message + "\n")
	
	# Limit chat history
	limit_chat_display()

func add_private_message(from: String, message: String, from_me: bool):
	var timestamp = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system())
	var color = "#FFFF88" if from_me else "#88FFFF"
	var sender = "You" if from_me else from
	
	var formatted_message = "[color=%s][%s] %s: %s[/color]" % [
		color,
		timestamp.split(" ")[1].substr(0, 5),
		sender,
		message
	]
	
	private_display.append_text(formatted_message + "\n")

func get_message_color(message_type: String) -> String:
	match message_type:
		"global":
			return "#FFFFFF"
		"system":
			return "#FFFF00"
		"private_notification":
			return "#FF88FF"
		_:
			return "#FFFFFF"

func get_message_prefix(message_type: String) -> String:
	match message_type:
		"global":
			return ""
		"system":
			return "[SYSTEM] "
		"private_notification":
			return "[PRIVATE] "
		_:
			return ""

func load_chat_history():
	var history = ChatManager.get_chat_history()
	for message_data in history:
		add_chat_message(message_data)

func load_private_conversation(player_name: String):
	private_display.clear()
	var conversation = ChatManager.get_private_conversation(player_name)
	
	for msg in conversation:
		add_private_message(player_name if not msg.from_me else "You", msg.message, msg.from_me)

func limit_chat_display():
	var lines = chat_display.get_parsed_text().split("\n")
	if lines.size() > max_chat_lines:
		var keep_lines = lines.slice(-max_chat_lines)
		chat_display.clear()
		for line in keep_lines:
			if line.strip_edges() != "":
				chat_display.append_text(line + "\n")
