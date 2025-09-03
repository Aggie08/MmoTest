extends Node

signal private_chat_requested(target_id: int, target_name: String)

var login_screen_scene = preload("res://Scenes/UI/Login.tscn")
var chat_ui_scene = preload("res://Scenes/UI/Chat.tscn")
var world_scene = preload("res://Scenes/World/World.tscn")

var current_ui = null
var player_name = ""
var is_authenticated = false

func _ready():
	# Don't show UI on server
	if "--server" in OS.get_cmdline_args() or "--dedicated" in OS.get_cmdline_args():
		return

func show_login_screen():
	print("Showing login screen")
	if current_ui:
		current_ui.queue_free()
	
	current_ui = login_screen_scene.instantiate()
	get_tree().current_scene.add_child(current_ui)
	
	# Connect login screen signals - THIS WAS MISSING!
	current_ui.connect("login_requested", _on_login_requested)
	current_ui.connect("connect_requested", _on_connect_requested)
	print("Login screen signals connected")

func show_connection_error(message: String = ""):
	print("Showing connection error: ", message)
	if current_ui and current_ui.has_method("show_error"):
		var error_msg = message if message != "" else "Failed to connect to server"
		current_ui.show_error(error_msg)
	else:
		# Fallback to showing login screen with error
		show_login_screen()

func show_disconnection_message():
	print("Showing disconnection message")
	# Show reconnection dialog
	if current_ui:
		current_ui.queue_free()
		current_ui = null
	
	show_login_screen()
	
	# Wait a frame for UI to load, then show error
	await get_tree().process_frame
	if current_ui and current_ui.has_method("show_error"):
		current_ui.show_error("Disconnected from server. Please reconnect.")

func _on_login_requested(name: String):
	print("Login requested for name: ", name)
	player_name = name
	Network.rpc("authenticate_player", name)
	get_tree().change_scene_to_packed(world_scene)
	current_ui = null

func _on_connect_requested(address: String):
	Network.connect_to_server(address)

func on_authentication_result(success: bool, error_message: String):
	print("Authentication result: ", success, " - ", error_message)
	if success:
		is_authenticated = true
		print("Authentication successful!")
		
		# Hide login screen and show game UI
		if current_ui:
			current_ui.queue_free()
			current_ui = null
		
		#show_chat_ui()
	else:
		print("Authentication failed: ", error_message)
		if current_ui and current_ui.has_method("show_error"):
			current_ui.show_error(error_message)

func show_chat_ui():
	print("Showing chat UI")
	if current_ui:
		current_ui.queue_free()
	
	current_ui = chat_ui_scene.instantiate()
	get_tree().current_scene.add_child(current_ui)
	
	# Connect chat UI signals if needed
	if current_ui.has_method("setup"):
		current_ui.setup()

func show_private_chat_dialog(target_id: int, target_name: String):
	private_chat_requested.emit(target_id, target_name)
	print("Private chat with ", target_name, " requested")

func get_player_name() -> String:
	return player_name

func is_player_authenticated() -> bool:
	return is_authenticated
