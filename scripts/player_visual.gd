extends Node2D
class_name PlayerVisual

@export var sprite_offset = Vector2(0, -6)
@export var sprite_scale = Vector2(0.55, 0.55)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _current_animation := &""

func _ready() -> void:
	animated_sprite.position = sprite_offset
	animated_sprite.scale = sprite_scale
	_play(&"idle", 1.0)

func update_from_player(player: Node) -> void:
	if not player:
		return

	_apply_orientation(player)
	_apply_animation(player)

func _apply_orientation(player: Node) -> void:
	var state_name = _get_player_state_name(player)
	var facing_direction = int(player.get("facing_direction"))
	if facing_direction == 0:
		facing_direction = 1

	match state_name:
		"WALL_LEFT":
			rotation = -PI * 0.5
			scale.x = 1.0
		"WALL_RIGHT":
			rotation = PI * 0.5
			scale.x = 1.0
		"CEILING", "TAIL_HANG":
			rotation = PI
			scale.x = facing_direction
		"CORNER_TRANSITION":
			_apply_surface_normal_orientation(player, facing_direction)
		_:
			rotation = 0.0
			scale.x = facing_direction

func _apply_animation(player: Node) -> void:
	var state_name = _get_player_state_name(player)
	var velocity = player.get("velocity") as Vector2
	var animation := &"idle"
	var speed_scale := 1.0

	match state_name:
		"GROUNDED":
			if abs(velocity.x) > 12.0:
				animation = &"run"
				speed_scale = 1.35 if _player_is_sprinting(player) else 1.0
		"WALL_LEFT", "WALL_RIGHT":
			if abs(velocity.y) > 12.0:
				animation = &"run"
				speed_scale = 1.15 if _player_is_sprinting(player) else 0.85
		"CEILING":
			if abs(velocity.x) > 12.0:
				animation = &"run"
				speed_scale = 1.15 if _player_is_sprinting(player) else 0.85
		"CORNER_TRANSITION":
			animation = &"run"
			speed_scale = 1.15
		"GRAPPLING", "GRAPPLE_PULL":
			animation = &"run" if velocity.length() > 90.0 else &"idle"
			speed_scale = 1.2
		_:
			animation = &"idle"

	_play(animation, speed_scale)

func _play(animation: StringName, speed_scale: float) -> void:
	if not animated_sprite.sprite_frames or not animated_sprite.sprite_frames.has_animation(animation):
		animation = &"idle"
	if _current_animation != animation:
		animated_sprite.play(animation)
		_current_animation = animation
	animated_sprite.speed_scale = speed_scale

func _get_player_state_name(player: Node) -> String:
	if player.has_method("_get_state_label"):
		return player._get_state_label(player.get("state"))
	if player.has_method("_get_state_name"):
		return String(player._get_state_name()).split(" ")[0]
	return ""

func _apply_surface_normal_orientation(player: Node, facing_direction: int) -> void:
	var normal = player.get("attached_surface_normal") as Vector2
	if normal.y > 0.65:
		rotation = PI
		scale.x = facing_direction
	elif normal.x > 0.65:
		rotation = -PI * 0.5
		scale.x = 1.0
	elif normal.x < -0.65:
		rotation = PI * 0.5
		scale.x = 1.0
	else:
		rotation = 0.0
		scale.x = facing_direction

func _player_is_sprinting(player: Node) -> bool:
	if player.has_method("_is_sprinting"):
		return player._is_sprinting()
	return false
