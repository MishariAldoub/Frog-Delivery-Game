extends Node2D

const LevelTestScene = preload("res://scenes/LevelTest.tscn")
const PlayerScene = preload("res://scenes/Player.tscn")
const RoomCameraManagerScript = preload("res://scripts/room_camera_manager.gd")

@export var player_start = Vector2(-180, 500)
@export_group("Room Camera Prototype")
@export var room_camera_transition_time = 0.25
@export var room_entry_margin = 12.0
@export var room_switch_cooldown = 0.08

var player: CharacterBody2D
var level: Node2D
var room_camera_manager: RoomCameraManager

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	_build_prototype()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		restart_level()

func restart_level() -> void:
	get_tree().reload_current_scene()

func _build_prototype() -> void:
	level = LevelTestScene.instantiate()
	add_child(level)

	player = _find_level_player()
	if not player:
		player = PlayerScene.instantiate() as CharacterBody2D
		player.name = "Player"
		player.position = player_start
		level.add_child(player)

	room_camera_manager = RoomCameraManagerScript.new()
	room_camera_manager.name = "RoomCameraManager"
	room_camera_manager.room_camera_transition_time = room_camera_transition_time
	room_camera_manager.room_entry_margin = room_entry_margin
	room_camera_manager.room_switch_cooldown = room_switch_cooldown
	add_child(room_camera_manager)
	room_camera_manager.setup(player, level)

func _find_level_player() -> CharacterBody2D:
	for node in get_tree().get_nodes_in_group("player"):
		if node is CharacterBody2D and level and level.is_ancestor_of(node):
			return node
	var named_player = level.find_child("Player", true, false) as CharacterBody2D
	if named_player:
		return named_player
	return null
