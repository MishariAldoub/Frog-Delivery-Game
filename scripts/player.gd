extends Node2D

const Moped = preload("res://scripts/moped.gd")
const Frog = preload("res://scripts/frog.gd")
const Tongue = preload("res://scripts/tongue.gd")

var moped: RigidBody2D
var frog: Node2D
var tongue: Node2D
var camera: Camera2D
var magnet_zone: Area2D
var load_zone: Area2D
var holder_left_x := -90.0
var holder_right_x := -6.0
var holder_floor_y := -46.0
var holder_top_y := -108.0
var magnet_zone_size := Vector2(74, 58)
var load_zone_size := Vector2(62, 48)

func _ready() -> void:
	moped = Moped.new()
	add_child(moped)

	frog = Frog.new()
	moped.add_child(frog)
	frog.position = Vector2(39, -47)

	_sync_holder_from_caddy()
	var zone_center := _get_holder_zone_center()
	magnet_zone = _make_zone("MagnetZone", zone_center, magnet_zone_size)
	load_zone = _make_zone("LoadZone", zone_center, load_zone_size)

	tongue = Tongue.new()
	tongue.player = self
	add_child(tongue)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.zoom = Vector2(0.88, 0.88)
	camera.ignore_rotation = true
	moped.add_child(camera)
	camera.make_current()

func _make_zone(zone_name: String, local_position: Vector2, size: Vector2) -> Area2D:
	var zone := Area2D.new()
	zone.name = zone_name
	zone.monitoring = true
	zone.monitorable = false
	moped.add_child(zone)
	zone.position = local_position

	var zone_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	zone_shape.shape = rectangle
	zone.add_child(zone_shape)
	return zone

func get_holder_floor_y_global() -> float:
	return moped.to_global(Vector2(0, holder_floor_y)).y

func _sync_holder_from_caddy() -> void:
	holder_left_x = moped.get_caddy_inner_left_x()
	holder_right_x = moped.get_caddy_inner_right_x()
	holder_floor_y = moped.get_caddy_floor_top_y()
	holder_top_y = moped.get_caddy_top_y()

	var inner_width = max(holder_right_x - holder_left_x, 12.0)
	var inner_height = max(holder_floor_y - holder_top_y, 12.0)
	magnet_zone_size = Vector2(max(inner_width - 4.0, 10.0), max(inner_height - 4.0, 10.0))
	load_zone_size = Vector2(max(inner_width - 16.0, 10.0), max(inner_height - 4.0, 10.0))

func get_tongue_origin_global() -> Vector2:
	return moped.to_global(Vector2(52, -63))

func get_stack_anchor_global() -> Vector2:
	return moped.to_global(Vector2(-48, holder_floor_y - 8.0))

func get_stack_slot_global(slot_index: int) -> Vector2:
	return moped.to_global(_get_stack_slot_local(slot_index))

func _get_stack_slot_local(slot_index: int) -> Vector2:
	return Vector2(-48, holder_floor_y - 8.0 - slot_index * 13.0)

func is_pizza_in_magnet_zone(pizza: RigidBody2D) -> bool:
	return _is_pizza_inside_holder_bounds(pizza) and _is_pizza_in_zone(pizza, magnet_zone, magnet_zone_size)

func is_pizza_in_load_zone(pizza: RigidBody2D) -> bool:
	return _is_pizza_inside_holder_bounds(pizza) and _is_pizza_in_zone(pizza, load_zone, load_zone_size)

func _get_holder_zone_center() -> Vector2:
	return Vector2(
		(holder_left_x + holder_right_x) * 0.5,
		(holder_floor_y + holder_top_y) * 0.5
	)

func _is_pizza_in_zone(pizza: RigidBody2D, zone: Area2D, size: Vector2) -> bool:
	var local_position := zone.to_local(pizza.global_position)
	return abs(local_position.x) <= size.x * 0.5 and abs(local_position.y) <= size.y * 0.5

func _is_pizza_inside_holder_bounds(pizza: RigidBody2D) -> bool:
	var local_position := moped.to_local(pizza.global_position)
	var between_sides := local_position.x >= holder_left_x and local_position.x <= holder_right_x
	var above_floor := local_position.y <= holder_floor_y
	var below_top := local_position.y >= holder_top_y
	var above_global_floor := pizza.global_position.y <= get_holder_floor_y_global()
	return between_sides and above_floor and below_top and above_global_floor

func is_pizza_on_cargo(pizza: RigidBody2D) -> bool:
	var local_position := moped.to_local(pizza.global_position)
	return (
		local_position.x >= holder_left_x
		and local_position.x <= holder_right_x
		and local_position.y >= holder_top_y
		and local_position.y <= holder_floor_y
	)

func mark_pizza_loaded(pizza: RigidBody2D, slot_index: int) -> void:
	pizza.set_meta("loaded", true)
	pizza.set_meta("loaded_slot", slot_index)
	pizza.set_meta("eligible_for_loading", false)
	pizza.set_meta("load_zone_time", 0.0)
	pizza.scale = Vector2(1.22, 1.22)

	var tween := create_tween()
	tween.tween_property(pizza, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func mark_pizza_loose(pizza: RigidBody2D) -> void:
	pizza.set_meta("loaded", false)
	pizza.set_meta("eligible_for_loading", true)
	pizza.set_meta("load_zone_time", 0.0)

func get_runner_x() -> float:
	return moped.global_position.x
