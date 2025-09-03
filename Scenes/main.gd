extends Node

# Main scene that handles the initial setup and routing

func _ready():
	print("=== MMO Game Starting ===")
	
	# Check if running as dedicated server
	if is_server_mode():
		print("Running in server mode")
		setup_server_mode()
	else:
		print("Running in client mode")
		setup_client_mode()

func is_server_mode() -> bool:
	var args = OS.get_cmdline_args()
	return ("--server" in args) || ("--dedicated" in args)

func setup_server_mode():
	# Server doesn't need UI, just start networking
	print("Initializing server...")
	
	# The NetworkManager autoload will handle server startup
	# We just need to make sure we don't show any UI
	
	# Hide mouse cursor on server
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	# Server will automatically start via NetworkManager._ready()
	print("Server initialization complete - waiting for NetworkManager...")

func setup_client_mode():
	# Client mode - show the login screen
	print("Initializing client...")
	
	# Set window properties
	#setup_window()
	
	# The NetworkManager autoload will show the login screen
	# We just need to make sure the scene is ready
	
	print("Client initialization complete - showing login screen...")

func setup_window():
	# Configure the game window for client
	get_window().title = "MMO Game"
	
	# Set a reasonable default window size
	get_window().size = Vector2i(1024, 768)
	
	# Center the window
	var screen_size = DisplayServer.screen_get_size()
	var window_size = get_window().size
	get_window().position = Vector2i(
		(screen_size.x - window_size.x) / 2,
		(screen_size.y - window_size.y) / 2
	)
	
	# Set minimum window size
	get_window().min_size = Vector2i(800, 600)

func _notification(what):
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			print("Application closing...")
			cleanup_and_quit()
		
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Handle Android back button
			cleanup_and_quit()

func cleanup_and_quit():
	print("Cleaning up...")
	
	# Disconnect from network if connected
	if Network.multiplayer_peer:
		if Network.is_server:
			print("Shutting down server...")
			# Notify all connected clients
			if Network.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				Network.rpc("server_shutdown_notification")
				
			# Wait a moment for the message to send
			await get_tree().create_timer(0.5).timeout
		else:
			print("Disconnecting from server...")
		
		Network.multiplayer_peer.close()
	
	print("Goodbye!")
	get_tree().quit()

# Handle any global input that should work everywhere
func _unhandled_input(event):
	# Toggle fullscreen with F11
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F11:
				toggle_fullscreen()
			KEY_ESCAPE:
				# Handle escape key globally
				if not is_server_mode():
					handle_escape_key()

func toggle_fullscreen():
	if not is_server_mode():
		if get_window().mode == Window.MODE_FULLSCREEN:
			get_window().mode = Window.MODE_WINDOWED
		else:
			get_window().mode = Window.MODE_FULLSCREEN

func handle_escape_key():
	# In game, ESC could open a pause menu or settings
	# For now, we'll let individual scenes handle it
	print("Escape pressed - handled by individual scenes")

# Debug information
func _process(_delta):
	# Only show debug info in debug builds
	if OS.is_debug_build():
		update_debug_info()

var debug_timer = 0.0
func update_debug_info():
	debug_timer += get_process_delta_time()
	
	# Update debug info every second
	if debug_timer >= 1.0:
		debug_timer = 0.0
		
		if Network.is_server:
			var player_count = Network.players.size()
			get_window().title = "MMO Server - Players: %d" % player_count
		else:
			var status = Network.get_connection_status()
			get_window().title = "MMO Game - Status: %s" % status
