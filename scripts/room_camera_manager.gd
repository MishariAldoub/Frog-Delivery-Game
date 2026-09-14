extends Node2D
class_name RoomCameraManager

@export var room_camera_transition_time = 0.25
@export var room_entry_margin = 12.0
@export var room_switch_cooldown = 0.08
@export var room_group = "room_area"

var player: Node2D
var level_root: Node
var active_room: RoomArea

var _camera: Camera2D
var _rooms: Array[RoomArea] = []
var _switch_cooldown_timer = 0.0
var _camera_tween: Tween

func setup(player_node: Node2D, room_root: Node) -> void:
	player = player_node
	level_root = room_root
	if is_inside_tree():
		_initialize()

func _ready() -> void:
	if player:
		_initialize()

func _physics_process(delta: float) -> void:
	if not player or not _camera or _rooms.is_empty():
		return

	_switch_cooldown_timer = max(_switch_cooldown_timer - delta, 0.0)
	var player_position = player.global_position

	if active_room and active_room.has_method("contains_global_point"):
		if active_room.contains_global_point(player_position):
			return

	var next_room = _find_room_at_position(player_position, room_entry_margin)
	if not next_room and not active_room:
		next_room = _find_room_at_position(player_position, 0.0)

	if next_room and next_room != active_room and _switch_cooldown_timer <= 0.0:
		_set_active_room(next_room, false)

func _initialize() -> void:
	_collect_rooms()
	_adopt_or_create_camera()
	var start_room = _find_room_at_position(player.global_position, 0.0)
	if start_room:
		_set_active_room(start_room, true)

func _collect_rooms() -> void:
	_rooms.clear()
	for node in get_tree().get_nodes_in_group(room_group):
		if node is RoomArea and (not level_root or level_root == node or level_root.is_ancestor_of(node)):
			_rooms.append(node)

func _adopt_or_create_camera() -> void:
	if _camera:
		return

	_camera = player.get_node_or_null("Camera2D") as Camera2D
	if _camera:
		_camera.reparent(self, true)
	else:
		_camera = Camera2D.new()
		_camera.name = "RoomCamera2D"
		add_child(_camera)

	_camera.position_smoothing_enabled = false
	_camera.make_current()

func _find_room_at_position(position: Vector2, margin: float) -> RoomArea:
	var found_room: RoomArea
	for room in _rooms:
		if room.contains_global_point(position, margin):
			found_room = room
			break
	return found_room

func _set_active_room(room: RoomArea, immediate: bool) -> void:
	if active_room:
		active_room.set_active(false)

	active_room = room
	_switch_cooldown_timer = room_switch_cooldown

	active_room.mark_visited()
	active_room.set_active(true)

	_move_camera_to_active_room(immediate)

func _move_camera_to_active_room(immediate: bool) -> void:
	if not active_room or not _camera:
		return

	var viewport_size = get_viewport_rect().size
	var target_position = active_room.get_camera_global_position()
	var target_zoom = active_room.get_camera_zoom(viewport_size)
	var transition_time = active_room.get_transition_time(room_camera_transition_time)

	if _camera_tween:
		_camera_tween.kill()

	if immediate or transition_time <= 0.0:
		_camera.global_position = target_position
		_camera.zoom = target_zoom
		return

	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_SINE)
	_camera_tween.set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(_camera, "global_position", target_position, transition_time)
	_camera_tween.tween_property(_camera, "zoom", target_zoom, transition_time)
