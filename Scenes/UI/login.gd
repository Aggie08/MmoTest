extends Control

signal login_requested(player_name: String)
#signal connect_requested(server_address: String)

@onready var name_input = $VBoxContainer/NameInput
@onready var address_input = $VBoxContainer/AddressInput
@onready var connect_button = $VBoxContainer/Connect
@onready var error_label = $VBoxContainer/ErrorLabel
@onready var status_label = $VBoxContainer/StatusLabel

func _ready():
	print("Login screen ready")
	
	# Set default server address
	address_input.text = "127.0.0.1"  # localhost for testing
	address_input.placeholder_text = "Server IP Address"
	name_input.placeholder_text = "Enter your name (3-20 characters)"
	
	# Focus on name input
	name_input.grab_focus()
	
	# Hide error initially
	error_label.hide()
	status_label.text = "Enter your name and server address"
	
	print("Login screen setup complete")
	Network.connect("client_connected", _client_connected)

func _on_connect_pressed():
	var player_name = name_input.text.strip_edges()
	var server_address = address_input.text.strip_edges()
	
	# Validate input
	if player_name.length() < 3 or player_name.length() > 20:
		show_error("Name must be 3-20 characters long")
		return
	
	if server_address == "":
		show_error("Please enter server address")
		return
	
	# Disable UI while connecting
	set_ui_enabled(false)
	status_label.text = "Connecting to server..."
	error_label.hide()
	
	# First connect to server
	#connect_requested.emit(server_address)
	Network.connect_to_server(server_address)
	
	# Wait a moment then try to authenticate
	await get_tree().create_timer(1.0).timeout
	
	# Check if we're connected before trying to authenticate
	#if Network.multiplayer and Network.multiplayer.multiplayer_peer:
		#var connection_status = Network.multiplayer.multiplayer_peer.get_connection_status()
		#print("Connection status: ", connection_status)
		#
		#if connection_status == MultiplayerPeer.CONNECTION_CONNECTED:
			#status_label.text = "Authenticating..."
			#login_requested.emit(player_name)
		#else:
			#show_error("Failed to connect to server")
	#else:
		#show_error("No network connection available")

func _client_connected():
	if Network.multiplayer and Network.multiplayer.multiplayer_peer:
		var connection_status = Network.multiplayer.multiplayer_peer.get_connection_status()
		print("Connection status: ", connection_status)
		
		if connection_status == MultiplayerPeer.CONNECTION_CONNECTED:
			status_label.text = "Authenticating..."
			login_requested.emit(name_input.text.strip_edges())
		else:
			show_error("Failed to connect to server")
	else:
		show_error("No network connection available")

func _on_name_submitted(text: String):
	print("Name submitted: ", text)
	_on_connect_pressed()

func show_error(message: String):
	print("Showing error: ", message)
	error_label.text = message
	error_label.show()
	status_label.text = "Ready to connect"
	set_ui_enabled(true)

func set_ui_enabled(enabled: bool):
	name_input.editable = enabled
	address_input.editable = enabled
	connect_button.disabled = not enabled
