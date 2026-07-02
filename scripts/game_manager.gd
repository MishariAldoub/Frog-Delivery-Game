extends Node2D

const LevelTestScene = preload("res://scenes/LevelTest.tscn")
const Player = preload("res://scripts/player.gd")
const PizzaBoxScene = preload("res://scenes/PizzaBox.tscn")
const HUDScene = preload("res://scenes/HUD.tscn")

@export_group("Level")
## Number of pizza boxes spawned at the start of the level.
@export var pizza_count := 4
## X position of the finish line. Reaching this completes the level.
@export var finish_x := 4300.0

@export_group("Loading Rules")
## Max pizza speed allowed before it can be counted as loaded. Lower = stricter catches.
@export var load_speed_threshold := 500.0
## How close a pizza must be to the next empty stack slot before it can count as loaded.
@export var load_slot_distance := 28.0
## How long the pizza must stay valid inside the LoadZone before being marked loaded.
@export var load_confirm_time := 0.15

@export_group("MagnetZone")
## Gentle pull strength used only when a loose pizza is inside the small rear holder MagnetZone.
@export var magnet_strength := 9.0
## Velocity damping applied by the MagnetZone. Higher = less overshoot, but less lively.
@export var magnet_damping := 2.0
## Maximum force the MagnetZone can apply. Keep this low so the moped does not feel sticky.
@export var magnet_max_force := 650.0

@export_group("Soft Holder")
## Pull strength used inside the LoadZone to help pizzas settle into the stack while staying physical.
@export var holder_strength := 22.0
## Linear damping inside the LoadZone. Higher values slow pizzas faster.
@export var holder_damping := 5.5
## Maximum force the soft holder can apply. Raise if pizzas will not settle; lower if it feels too grabby.
@export var holder_max_force := 1200.0
## Torque correction that gently rotates pizzas toward horizontal inside the holder.
@export var holder_torque := 10.0
## Angular damping inside the holder. Higher values reduce spinning faster.
@export var holder_angular_damping := 2.5

var player
var road
var hud
var pizzas: Array[RigidBody2D] = []
var complete := false

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	_build_level()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		restart_level()

	if complete:
		return

	var remaining := _count_remaining_pizzas()
	hud.set_run_status(remaining, _get_distance())
	if player and player.get_runner_x() >= finish_x:
		complete = true
		hud.show_complete(remaining, pizza_count)

func _physics_process(delta: float) -> void:
	if complete:
		return

	_update_pizza_recovery(delta)

func restart_level() -> void:
	get_tree().reload_current_scene()

func _build_level() -> void:
	road = LevelTestScene.instantiate()
	road.finish_x = finish_x
	add_child(road)

	player = Player.new()
	player.position = Vector2(160, 493)
	add_child(player)
	player.tongue.set_pizza_source(pizzas)

	_spawn_pizzas()

	hud = HUDScene.instantiate()
	add_child(hud)
	hud.restart_requested.connect(restart_level)
	hud.set_run_status(pizza_count, 0.0)

func _spawn_pizzas() -> void:
	var base = player.get_stack_anchor_global()
	for i in range(pizza_count):
		var pizza := PizzaBoxScene.instantiate() as RigidBody2D
		pizza.position = base + Vector2(randf_range(-2.5, 2.5), -i * 13.0)
		pizza.rotation = randf_range(-0.045, 0.045)
		pizza.name = "Pizza%02d" % i
		pizza.set_meta("loaded", true)
		pizza.set_meta("loaded_slot", i)
		pizza.set_meta("eligible_for_loading", false)
		pizza.set_meta("load_zone_time", 0.0)
		add_child(pizza)
		pizzas.append(pizza)

func _count_remaining_pizzas(excluded_pizza: RigidBody2D = null) -> int:
	var count := 0
	if not player:
		return count

	for pizza in pizzas:
		if not is_instance_valid(pizza):
			continue
		if pizza == excluded_pizza:
			continue

		if _is_loaded(pizza):
			count += 1
	return count

func _update_pizza_recovery(delta: float) -> void:
	if not player:
		return

	for pizza in pizzas:
		if not is_instance_valid(pizza):
			continue
		if _is_loaded(pizza):
			_update_loaded_pizza(pizza)
			continue

		if not pizza.get_meta("eligible_for_loading", false):
			if not player.is_pizza_on_cargo(pizza):
				pizza.set_meta("eligible_for_loading", true)
				pizza.set_meta("load_zone_time", 0.0)
			continue

		var slot_index := _get_next_load_slot(pizza)
		if slot_index < 0:
			pizza.set_meta("load_zone_time", 0.0)
			continue

		var slot_position = player.get_stack_slot_global(slot_index)
		if player.is_pizza_in_magnet_zone(pizza):
			_apply_magnet_force(pizza, slot_position)

		if not player.is_pizza_in_load_zone(pizza):
			pizza.set_meta("load_zone_time", 0.0)
			continue
		_apply_holder_force(pizza, slot_position)
		if pizza.linear_velocity.length() > load_speed_threshold:
			pizza.set_meta("load_zone_time", 0.0)
			continue
		if pizza.global_position.distance_to(slot_position) > load_slot_distance:
			pizza.set_meta("load_zone_time", 0.0)
			continue

		var load_zone_time := float(pizza.get_meta("load_zone_time", 0.0)) + delta
		pizza.set_meta("load_zone_time", load_zone_time)
		if load_zone_time < load_confirm_time:
			continue

		player.tongue.release_if_grabbing(pizza)
		player.mark_pizza_loaded(pizza, slot_index)
		return

func _apply_magnet_force(pizza: RigidBody2D, slot_position: Vector2) -> void:
	var displacement := slot_position - pizza.global_position
	var force := displacement * magnet_strength - pizza.linear_velocity * magnet_damping
	pizza.apply_central_force(force.limit_length(magnet_max_force))

func _update_loaded_pizza(pizza: RigidBody2D) -> void:
	var slot_index := int(pizza.get_meta("loaded_slot", 0))
	var slot_position = player.get_stack_slot_global(slot_index)
	if player.is_pizza_in_load_zone(pizza):
		_apply_holder_force(pizza, slot_position)
		return

	player.mark_pizza_loose(pizza)

func _apply_holder_force(pizza: RigidBody2D, slot_position: Vector2) -> void:
	var displacement := slot_position - pizza.global_position
	var force := displacement * holder_strength - pizza.linear_velocity * holder_damping
	pizza.apply_central_force(force.limit_length(holder_max_force))

	var angle_error := wrapf(-pizza.global_rotation, -PI, PI)
	var torque := angle_error * holder_torque - pizza.angular_velocity * holder_angular_damping
	pizza.apply_torque(torque)

func _is_loaded(pizza: RigidBody2D) -> bool:
	return pizza.has_meta("loaded") and pizza.get_meta("loaded")

func _get_next_load_slot(excluded_pizza: RigidBody2D = null) -> int:
	for slot_index in range(pizza_count):
		var slot_taken := false
		for pizza in pizzas:
			if not is_instance_valid(pizza):
				continue
			if pizza == excluded_pizza:
				continue
			if _is_loaded(pizza) and int(pizza.get_meta("loaded_slot", -1)) == slot_index:
				slot_taken = true
				break
		if not slot_taken:
			return slot_index
	return -1

func _get_distance() -> float:
	if not player:
		return 0.0
	return clamp(player.get_runner_x() - 160.0, 0.0, finish_x - 160.0)
