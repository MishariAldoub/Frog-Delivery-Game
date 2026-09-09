extends Node2D

const LevelTestScene = preload("res://scenes/LevelTest.tscn")
const Player = preload("res://scripts/player.gd")

@export var player_start = Vector2(-180, 500)

var player: CharacterBody2D
var level: Node2D

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

	player = Player.new()
	player.name = "Player"
	player.position = player_start
	add_child(player)
