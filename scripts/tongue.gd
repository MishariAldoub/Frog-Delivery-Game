extends Node2D

const HumanNoiseEvents = preload("res://scripts/ai/human_noise.gd")

@export var max_range = 288.0
@export var latch_radius = 44.0
@export var spring_strength = 18.0
@export var damping_force = 6.5
@export var max_force = 3400.0
@export var max_grabbed_angular_velocity = 8.0
@export var grapple_collision_mask = 1
@export var tongue_shot_noise_radius = 300.0
@export var tongue_shot_noise_loudness = 0.45
@export var grapple_impact_noise_radius = 520.0
@export var grapple_impact_noise_loudness = 1.0
@export_group("Ceiling Scientist Tongue")
@export var ceiling_tongue_min_length = 34.0
@export var ceiling_tongue_max_length = 288.0
@export var ceiling_tongue_initial_length = 72.0
@export var ceiling_tongue_wheel_step = 34.0
@export var ceiling_tongue_extension_speed = 220.0
@export var ceiling_tongue_retraction_speed = 260.0
@export var captured_mouse_swing_force_scale = 2.8
@export var captured_mouse_swing_max_force = 520.0

const ENEMY_GRAB_NORMAL = 0
const ENEMY_GRAB_CEILING_STRANGLE = 1
const ENEMY_GRAB_REAR_DRAG = 2

const TONGUE_STATE_NORMAL = 0
const TONGUE_STATE_AIMING = 1
const TONGUE_STATE_SCIENTIST_GRABBED = 2
const TONGUE_STATE_SCIENTIST_STRANGLING = 3
const TONGUE_STATE_RELEASING = 4

var player
var pizzas: Array[RigidBody2D] = []
var latched_pizza: RigidBody2D
var latched_enemy: Node2D
var local_grab_point = Vector2.ZERO
var aim_point = Vector2.ZERO
var grapple_anchor = Vector2.ZERO
var is_grappled_to_surface = false
var grapple_pull_anchor = Vector2.ZERO
var is_grapple_pulling_to_surface = false
var suppressed_until_release = false
var enemy_grab_type = ENEMY_GRAB_NORMAL
var enemy_rope_length = 0.0
var tongue_state = TONGUE_STATE_NORMAL
var ceiling_tongue_active = false
var ceiling_tongue_current_length = 0.0
var ceiling_tongue_target_length = 0.0
var ceiling_tongue_direction = Vector2.DOWN
var ceiling_tongue_length_state = "IDLE"
var previous_mouse_position = Vector2.ZERO
var captured_swing_force = Vector2.ZERO

func set_pizza_source(source: Array[RigidBody2D]) -> void:
	pizzas = source

func _unhandled_input(event: InputEvent) -> void:
	if not ceiling_tongue_active:
		return
	if not Input.is_action_pressed("shoot_tongue"):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_ceiling_tongue_target_length(-ceiling_tongue_wheel_step)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_ceiling_tongue_target_length(ceiling_tongue_wheel_step)
			get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
	if not player:
		return

	aim_point = get_global_mouse_position()
	if Input.is_action_just_pressed("shoot_tongue"):
		suppressed_until_release = false
		tongue_state = TONGUE_STATE_AIMING
		if _has_valid_ceiling_strangle_anchor():
			_start_ceiling_tongue()
		else:
			_try_latch()
	if Input.is_action_just_released("shoot_tongue"):
		_release()
	if Input.is_action_just_pressed("grapple_tongue"):
		_try_grapple_pull()

	if Input.is_action_pressed("shoot_tongue") and ceiling_tongue_active:
		_update_ceiling_tongue(_delta)
	elif Input.is_action_pressed("shoot_tongue") and is_instance_valid(latched_enemy):
		_update_enemy_grab(_delta)
	if Input.is_action_pressed("shoot_tongue") and is_instance_valid(latched_pizza):
		_pull_toward_mouse_target()

	queue_redraw()

func _try_latch() -> void:
	if player and player.has_method("cancel_grapple_pull"):
		player.cancel_grapple_pull()
	_release()
	tongue_state = TONGUE_STATE_AIMING
	var origin = player.get_tongue_origin_global()
	HumanNoiseEvents.emit_noise(player, origin, tongue_shot_noise_loudness, tongue_shot_noise_radius, &"tongue_shot")
	var cursor = get_global_mouse_position()
	var clamped_target = origin + (cursor - origin).limit_length(max_range)
	var surface_target = _get_surface_grapple_target(origin, cursor)

	var enemy_hit = _get_enemy_tongue_hit(origin, clamped_target)
	if not enemy_hit.is_empty():
		var enemy = enemy_hit["target"] as Node2D
		var grab_kind = _get_enemy_grab_type(enemy, origin, clamped_target)
		enemy_rope_length = clamp(origin.distance_to(enemy_hit["point"]), 16.0, max_range)
		var grab_target = _get_enemy_rope_target(origin, enemy_hit["point"], grab_kind)
		if enemy and enemy.has_method("begin_tongue_grab") and enemy.begin_tongue_grab(player, grab_kind, grab_target):
			latched_enemy = enemy
			enemy_grab_type = grab_kind
			tongue_state = TONGUE_STATE_SCIENTIST_STRANGLING if grab_kind == ENEMY_GRAB_CEILING_STRANGLE else TONGUE_STATE_SCIENTIST_GRABBED
			HumanNoiseEvents.emit_noise(player, enemy.global_position, grapple_impact_noise_loudness, grapple_impact_noise_radius, &"tongue_enemy_grab")
			return
		enemy_rope_length = 0.0

	var surface_hit = _get_grapple_surface_hit(origin, surface_target)
	if not surface_hit.is_empty():
		grapple_anchor = surface_hit["position"]
		is_grappled_to_surface = true
		HumanNoiseEvents.emit_noise(player, grapple_anchor, grapple_impact_noise_loudness, grapple_impact_noise_radius, &"tongue_impact")
		if player and player.has_method("start_grapple"):
			player.start_grapple(grapple_anchor, origin.distance_to(grapple_anchor))
		return

	var best_distance = latch_radius
	var best_grab_world = Vector2.ZERO

	for pizza in pizzas:
		if not is_instance_valid(pizza):
			continue
		if player.is_pizza_on_cargo(pizza):
			continue
		var along_tongue = Geometry2D.get_closest_point_to_segment(pizza.global_position, origin, clamped_target)
		var distance = pizza.global_position.distance_to(along_tongue)
		if distance < best_distance:
			best_distance = distance
			latched_pizza = pizza
			best_grab_world = along_tongue

	if is_instance_valid(latched_pizza):
		local_grab_point = _get_clamped_local_grab_point(latched_pizza, best_grab_world, origin)
		HumanNoiseEvents.emit_noise(player, latched_pizza.global_position, grapple_impact_noise_loudness, grapple_impact_noise_radius, &"tongue_grab")

func _start_ceiling_tongue() -> void:
	if player and player.has_method("cancel_grapple_pull"):
		player.cancel_grapple_pull()
	_release()
	ceiling_tongue_active = true
	ceiling_tongue_current_length = clamp(ceiling_tongue_initial_length, ceiling_tongue_min_length, ceiling_tongue_max_length)
	ceiling_tongue_target_length = ceiling_tongue_current_length
	ceiling_tongue_direction = _get_ceiling_tongue_aim_direction()
	ceiling_tongue_length_state = "IDLE"
	previous_mouse_position = get_global_mouse_position()
	captured_swing_force = Vector2.ZERO
	tongue_state = TONGUE_STATE_AIMING
	var origin = player.get_tongue_origin_global()
	HumanNoiseEvents.emit_noise(player, origin, tongue_shot_noise_loudness, tongue_shot_noise_radius, &"tongue_shot")

func _update_ceiling_tongue(delta: float) -> void:
	if not _has_valid_ceiling_strangle_anchor():
		_release()
		return
	_update_ceiling_tongue_length(delta)
	_update_captured_swing_force(delta)
	if not is_instance_valid(latched_enemy):
		ceiling_tongue_direction = _get_ceiling_tongue_aim_direction()
		_try_latch_ceiling_tongue_enemy()
		return
	if latched_enemy.has_method("is_tongue_grab_active") and not latched_enemy.is_tongue_grab_active():
		_clear_enemy_grab_tracking()
		return
	var endpoint = _get_ceiling_tongue_endpoint()
	if latched_enemy.has_method("update_ceiling_tongue_grab"):
		latched_enemy.update_ceiling_tongue_grab(player.get_tongue_origin_global(), ceiling_tongue_current_length, endpoint, captured_swing_force, delta)
	elif latched_enemy.has_method("update_tongue_grab"):
		latched_enemy.update_tongue_grab(endpoint, delta)

func _update_ceiling_tongue_length(delta: float) -> void:
	var previous_length = ceiling_tongue_current_length
	if ceiling_tongue_current_length < ceiling_tongue_target_length:
		ceiling_tongue_current_length = min(ceiling_tongue_current_length + ceiling_tongue_extension_speed * delta, ceiling_tongue_target_length)
	elif ceiling_tongue_current_length > ceiling_tongue_target_length:
		ceiling_tongue_current_length = max(ceiling_tongue_current_length - ceiling_tongue_retraction_speed * delta, ceiling_tongue_target_length)
	ceiling_tongue_current_length = clamp(ceiling_tongue_current_length, ceiling_tongue_min_length, ceiling_tongue_max_length)
	if ceiling_tongue_current_length > previous_length + 0.05:
		ceiling_tongue_length_state = "EXTENDING"
	elif ceiling_tongue_current_length < previous_length - 0.05:
		ceiling_tongue_length_state = "RETRACTING"
	else:
		ceiling_tongue_length_state = "IDLE"

func _update_captured_swing_force(delta: float) -> void:
	if not is_instance_valid(latched_enemy):
		captured_swing_force = Vector2.ZERO
		previous_mouse_position = get_global_mouse_position()
		return
	var mouse_position = get_global_mouse_position()
	var mouse_velocity = (mouse_position - previous_mouse_position) / max(delta, 0.001)
	previous_mouse_position = mouse_position
	captured_swing_force = (mouse_velocity * captured_mouse_swing_force_scale).limit_length(captured_mouse_swing_max_force)

func _try_latch_ceiling_tongue_enemy() -> void:
	var origin = player.get_tongue_origin_global()
	var endpoint = _get_ceiling_tongue_endpoint()
	var enemy_hit = _get_enemy_tongue_hit(origin, endpoint, true)
	if enemy_hit.is_empty():
		return
	var enemy = enemy_hit["target"] as Node2D
	var neck_point = _get_enemy_neck_grab_position(enemy)
	ceiling_tongue_current_length = clamp(origin.distance_to(neck_point), ceiling_tongue_min_length, ceiling_tongue_max_length)
	ceiling_tongue_target_length = ceiling_tongue_current_length
	ceiling_tongue_direction = (neck_point - origin).normalized()
	if ceiling_tongue_direction.length_squared() <= 0.001:
		ceiling_tongue_direction = Vector2.DOWN
	var grab_target = _get_ceiling_tongue_endpoint()
	enemy_rope_length = ceiling_tongue_current_length
	if enemy and enemy.has_method("begin_tongue_grab") and enemy.begin_tongue_grab(player, ENEMY_GRAB_CEILING_STRANGLE, grab_target):
		latched_enemy = enemy
		enemy_grab_type = ENEMY_GRAB_CEILING_STRANGLE
		tongue_state = TONGUE_STATE_SCIENTIST_STRANGLING
		HumanNoiseEvents.emit_noise(player, enemy.global_position, grapple_impact_noise_loudness, grapple_impact_noise_radius, &"tongue_enemy_grab")
	else:
		enemy_rope_length = 0.0

func _try_grapple_pull() -> void:
	var origin = player.get_tongue_origin_global()
	var cursor = get_global_mouse_position()
	var pull_range = _get_grapple_pull_range()
	var clamped_target = origin + (cursor - origin).limit_length(pull_range)
	var surface_hit = _get_grapple_surface_hit(origin, clamped_target)
	if surface_hit.is_empty():
		return
	if not _is_wall_or_ceiling_hit(surface_hit):
		return

	var anchor = surface_hit["position"]
	if origin.distance_to(anchor) > pull_range:
		return
	if not player or not player.has_method("start_grapple_pull"):
		return
	if not player.start_grapple_pull(anchor):
		return

	_release()
	HumanNoiseEvents.emit_noise(player, anchor, grapple_impact_noise_loudness, grapple_impact_noise_radius, &"grapple_pull")
	grapple_pull_anchor = anchor
	is_grapple_pulling_to_surface = true
	suppressed_until_release = false

func _pull_toward_mouse_target() -> void:
	var origin = player.get_tongue_origin_global()
	var target = _get_mouse_target(origin)
	var grab_world = latched_pizza.to_global(local_grab_point)
	var grab_offset = grab_world - latched_pizza.global_position

	# Damping at the latch point makes the pizza trail the mouse like a rope instead of snapping.
	var grab_velocity = latched_pizza.linear_velocity + Vector2(
		-latched_pizza.angular_velocity * grab_offset.y,
		latched_pizza.angular_velocity * grab_offset.x
	)
	var displacement = target - grab_world
	var force = displacement * spring_strength - grab_velocity * damping_force
	force = force.limit_length(max_force)

	latched_pizza.apply_force(force, grab_offset)
	latched_pizza.angular_velocity = clamp(
		latched_pizza.angular_velocity,
		-max_grabbed_angular_velocity,
		max_grabbed_angular_velocity
	)

func _update_enemy_grab(delta: float) -> void:
	if not is_instance_valid(latched_enemy):
		latched_enemy = null
		_clear_enemy_grab_tracking()
		return
	if latched_enemy.has_method("is_tongue_grab_active") and not latched_enemy.is_tongue_grab_active():
		_clear_enemy_grab_tracking()
		return
	if enemy_grab_type == ENEMY_GRAB_CEILING_STRANGLE and not _has_valid_ceiling_strangle_anchor():
		_release()
		return
	var origin = player.get_tongue_origin_global()
	var desired_point = latched_enemy.get_tongue_target_position() if enemy_grab_type == ENEMY_GRAB_CEILING_STRANGLE else get_global_mouse_position()
	var target = _get_enemy_rope_target(origin, desired_point, enemy_grab_type)
	if latched_enemy.has_method("update_tongue_grab"):
		latched_enemy.update_tongue_grab(target, delta)

func _get_mouse_target(origin: Vector2) -> Vector2:
	return origin + (get_global_mouse_position() - origin).limit_length(max_range)

func _get_surface_grapple_target(origin: Vector2, cursor: Vector2) -> Vector2:
	var aim_vector = cursor - origin
	if aim_vector.length_squared() <= 1.0:
		return origin + Vector2.RIGHT * max_range
	if player and player.has_method("should_airborne_grapple_use_full_range") and player.should_airborne_grapple_use_full_range():
		return origin + aim_vector.normalized() * max_range
	return origin + aim_vector.limit_length(max_range)

func _adjust_ceiling_tongue_target_length(amount: float) -> void:
	ceiling_tongue_target_length = clamp(
		ceiling_tongue_target_length + amount,
		ceiling_tongue_min_length,
		ceiling_tongue_max_length
	)

func _get_ceiling_tongue_aim_direction() -> Vector2:
	var origin = player.get_tongue_origin_global()
	var direction = get_global_mouse_position() - origin
	if direction.length_squared() <= 1.0:
		return Vector2.DOWN
	return direction.normalized()

func _get_ceiling_tongue_endpoint() -> Vector2:
	var origin = player.get_tongue_origin_global()
	return origin + ceiling_tongue_direction.normalized() * ceiling_tongue_current_length

func _get_enemy_rope_target(origin: Vector2, desired_world_point: Vector2, grab_kind: int) -> Vector2:
	if grab_kind == ENEMY_GRAB_CEILING_STRANGLE:
		if ceiling_tongue_active:
			return _get_ceiling_tongue_endpoint()
		var hang_length = max(enemy_rope_length, ceiling_tongue_min_length)
		return origin + Vector2.DOWN * min(hang_length, max_range)
	var direction = desired_world_point - origin
	if direction.length_squared() <= 1.0:
		direction = Vector2.RIGHT
	return origin + direction.limit_length(min(max(enemy_rope_length, 20.0), max_range))

func _get_clamped_local_grab_point(pizza: RigidBody2D, world_point: Vector2, tongue_origin: Vector2) -> Vector2:
	var local_point = pizza.to_local(world_point)
	var pizza_size = pizza.get("size")
	if pizza_size is Vector2:
		var half_size = pizza_size * 0.5
		var direction = local_point
		if direction.length_squared() < 1.0:
			direction = pizza.to_local(tongue_origin)
		if direction.length_squared() < 1.0:
			direction = Vector2.RIGHT

		var x_scale = half_size.x / max(abs(direction.x), 0.001)
		var y_scale = half_size.y / max(abs(direction.y), 0.001)
		local_point = direction * min(x_scale, y_scale)
		local_point.x = clamp(local_point.x, -half_size.x, half_size.x)
		local_point.y = clamp(local_point.y, -half_size.y, half_size.y)
	return local_point

func _release() -> void:
	tongue_state = TONGUE_STATE_RELEASING
	if is_instance_valid(latched_enemy) and latched_enemy.has_method("release_tongue_grab"):
		latched_enemy.release_tongue_grab()
	_clear_enemy_grab_tracking()
	_clear_ceiling_tongue()
	latched_pizza = null
	local_grab_point = Vector2.ZERO
	grapple_anchor = Vector2.ZERO
	is_grappled_to_surface = false
	suppressed_until_release = false
	tongue_state = TONGUE_STATE_NORMAL
	if player and player.has_method("release_grapple"):
		player.release_grapple()

func release_if_grabbing(pizza: RigidBody2D) -> void:
	if latched_pizza == pizza:
		_release()

func clear_grapple_without_player_release() -> void:
	if is_instance_valid(latched_enemy) and latched_enemy.has_method("release_tongue_grab"):
		latched_enemy.release_tongue_grab()
	_clear_enemy_grab_tracking()
	_clear_ceiling_tongue()
	latched_pizza = null
	local_grab_point = Vector2.ZERO
	grapple_anchor = Vector2.ZERO
	is_grappled_to_surface = false
	suppressed_until_release = true

func clear_grapple_pull_without_player_release() -> void:
	grapple_pull_anchor = Vector2.ZERO
	is_grapple_pulling_to_surface = false

func _draw() -> void:
	if not player:
		return

	var origin = to_local(player.get_tongue_origin_global())
	var end = to_local(aim_point)
	var color = Color("#ff6fa8")
	if is_grapple_pulling_to_surface:
		draw_line(origin, to_local(grapple_pull_anchor), Color("#ffcc4d"), 7.0)
		draw_circle(to_local(grapple_pull_anchor), 8.0, Color("#ffcc4d"))
		return
	elif is_grappled_to_surface:
		draw_line(origin, to_local(grapple_anchor), Color("#ff397c"), 7.0)
		draw_circle(to_local(grapple_anchor), 8.0, Color("#ff397c"))
		return
	elif is_instance_valid(latched_enemy):
		var global_origin = player.get_tongue_origin_global()
		var desired_point = get_global_mouse_position()
		if enemy_grab_type == ENEMY_GRAB_CEILING_STRANGLE and latched_enemy.has_method("get_tongue_target_position"):
			desired_point = latched_enemy.get_tongue_target_position()
		var rope_target = _get_enemy_rope_target(global_origin, desired_point, enemy_grab_type)
		var grab_point = latched_enemy.global_position
		if enemy_grab_type == ENEMY_GRAB_CEILING_STRANGLE:
			grab_point = _get_enemy_neck_grab_position(latched_enemy)
		elif latched_enemy.has_method("get_tongue_target_position"):
			grab_point = latched_enemy.get_tongue_target_position()
		var target_color = Color("#a8f0ff") if enemy_grab_type == ENEMY_GRAB_CEILING_STRANGLE else Color("#ff397c")
		draw_line(origin, to_local(rope_target), Color("#ff8fbd"), 4.0)
		draw_line(to_local(rope_target), to_local(grab_point), target_color, 6.0)
		draw_circle(to_local(rope_target), 6.0, Color("#ff8fbd"))
		draw_circle(to_local(grab_point), 8.0, target_color)
		return
	elif ceiling_tongue_active:
		var endpoint = _get_ceiling_tongue_endpoint()
		draw_line(origin, to_local(endpoint), Color("#a8f0ff"), 6.0)
		draw_circle(to_local(endpoint), 7.0, Color("#a8f0ff"))
		return
	elif is_instance_valid(latched_pizza):
		var global_origin = player.get_tongue_origin_global()
		var target = _get_mouse_target(global_origin)
		var grab_point = latched_pizza.to_global(local_grab_point)
		draw_line(origin, to_local(target), Color("#ff8fbd"), 4.0)
		draw_line(to_local(target), to_local(grab_point), Color("#ff397c"), 6.0)
		draw_circle(to_local(target), 6.0, Color("#ff8fbd"))
		draw_circle(to_local(grab_point), 8.0, Color("#ff397c"))
		return
	elif Input.is_action_pressed("shoot_tongue") and not suppressed_until_release:
		var global_origin = player.get_tongue_origin_global()
		end = to_local(_get_mouse_target(global_origin))
	else:
		return

	draw_line(origin, end, color, 7.0)
	draw_circle(end, 8.0, color)

func _get_grapple_surface_hit(origin: Vector2, target: Vector2) -> Dictionary:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(origin, target)
	query.collision_mask = grapple_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_player_exclusion_rids()

	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		return {}

	if _classify_tongue_hit(hit) != "GRAPPLE_SURFACE":
		return {}

	return hit

func _get_enemy_tongue_hit(origin: Vector2, target: Vector2, use_neck_point: bool = false) -> Dictionary:
	var best_hit = {}
	var best_along_distance = INF
	for candidate in get_tree().get_nodes_in_group("tongue_combat_target"):
		if not (candidate is Node2D):
			continue
		if candidate == player or not candidate.has_method("get_tongue_target_position") or not candidate.has_method("begin_tongue_grab"):
			continue
		var target_position = _get_enemy_neck_grab_position(candidate) if use_neck_point else candidate.get_tongue_target_position()
		var along_tongue = Geometry2D.get_closest_point_to_segment(target_position, origin, target)
		var distance = target_position.distance_to(along_tongue)
		if distance > latch_radius:
			continue
		var along_distance = origin.distance_to(along_tongue)
		if along_distance >= best_along_distance:
			continue
		if not _has_clear_tongue_path(origin, along_tongue):
			continue
		best_along_distance = along_distance
		best_hit = {
			"target": candidate,
			"point": along_tongue,
			"distance": distance,
		}
	return best_hit

func _get_enemy_neck_grab_position(enemy: Node2D) -> Vector2:
	if enemy and enemy.has_method("get_tongue_neck_grab_position"):
		return enemy.get_tongue_neck_grab_position()
	if enemy and enemy.has_method("get_tongue_target_position"):
		return enemy.get_tongue_target_position() + Vector2.UP * 22.0
	return enemy.global_position + Vector2.UP * 44.0

func _has_clear_tongue_path(origin: Vector2, grab_point: Vector2) -> bool:
	var surface_hit = _get_grapple_surface_hit(origin, grab_point)
	if surface_hit.is_empty():
		return true
	return origin.distance_to(surface_hit["position"]) >= origin.distance_to(grab_point) - 8.0

func _get_enemy_grab_type(enemy: Node2D, origin: Vector2, target: Vector2) -> int:
	if _is_ceiling_strangle_attempt(origin, target):
		return ENEMY_GRAB_CEILING_STRANGLE
	return ENEMY_GRAB_NORMAL

func _is_ceiling_strangle_attempt(origin: Vector2, target: Vector2) -> bool:
	if not _has_valid_ceiling_strangle_anchor():
		return false
	var shot_direction = target - origin
	if shot_direction.length_squared() <= 1.0:
		return false
	return shot_direction.normalized().dot(Vector2.DOWN) > 0.55

func _has_valid_ceiling_strangle_anchor() -> bool:
	if not player:
		return false
	if player.has_method("is_tongue_ceiling_strangle_anchor_valid"):
		return player.is_tongue_ceiling_strangle_anchor_valid()
	if player.has_method("is_ceiling_attached"):
		return player.is_ceiling_attached()
	return false

func _clear_enemy_grab_tracking() -> void:
	latched_enemy = null
	enemy_grab_type = ENEMY_GRAB_NORMAL
	enemy_rope_length = 0.0
	if Input.is_action_pressed("shoot_tongue") and not suppressed_until_release:
		tongue_state = TONGUE_STATE_AIMING
	else:
		tongue_state = TONGUE_STATE_NORMAL

func _clear_ceiling_tongue() -> void:
	ceiling_tongue_active = false
	ceiling_tongue_current_length = 0.0
	ceiling_tongue_target_length = 0.0
	ceiling_tongue_direction = Vector2.DOWN
	ceiling_tongue_length_state = "IDLE"
	previous_mouse_position = Vector2.ZERO
	captured_swing_force = Vector2.ZERO

func get_tongue_debug_state_name() -> String:
	match tongue_state:
		TONGUE_STATE_NORMAL:
			return "NORMAL"
		TONGUE_STATE_AIMING:
			return "TONGUE_AIMING"
		TONGUE_STATE_SCIENTIST_GRABBED:
			return "SCIENTIST_GRABBED"
		TONGUE_STATE_SCIENTIST_STRANGLING:
			return "SCIENTIST_STRANGLING"
		TONGUE_STATE_RELEASING:
			return "RELEASING"
	return "UNKNOWN"

func get_debug_status_text() -> String:
	var enemy_valid = is_instance_valid(latched_enemy)
	var ai_suspended = enemy_valid and latched_enemy.has_method("is_ai_suspended_by_tongue") and latched_enemy.is_ai_suspended_by_tongue()
	var reeling = ceiling_tongue_active and ceiling_tongue_target_length < ceiling_tongue_current_length - 0.5
	return "Tongue:%s %s\nLen:%.0f->%.0f reeling:%s\nCaptured:%s strangle:%s AI:%s anchor:%s\nSwing:%.0f,%.0f | %.0f" % [
		get_tongue_debug_state_name(),
		"CEIL" if ceiling_tongue_active else "NORMAL",
		ceiling_tongue_current_length,
		ceiling_tongue_target_length,
		str(reeling),
		str(enemy_valid),
		str(enemy_valid and enemy_grab_type == ENEMY_GRAB_CEILING_STRANGLE),
		str(ai_suspended),
		str(_has_valid_ceiling_strangle_anchor()),
		captured_swing_force.x,
		captured_swing_force.y,
		captured_swing_force.length(),
	]

func _get_grapple_pull_range() -> float:
	if player:
		var configured_range = player.get("grapple_range")
		if configured_range is float or configured_range is int:
			return configured_range
	return max_range

func _classify_tongue_hit(hit: Dictionary) -> String:
	var collider = hit.get("collider")
	if collider == player:
		return "OTHER"
	if collider is Node and collider.is_in_group("grapple_surface"):
		return "GRAPPLE_SURFACE"
	return "OTHER"

func _is_wall_or_ceiling_hit(hit: Dictionary) -> bool:
	var normal = hit.get("normal", Vector2.ZERO)
	return abs(normal.x) > 0.65 or normal.y > 0.65

func _get_player_exclusion_rids() -> Array[RID]:
	var excluded: Array[RID] = []
	if player is CollisionObject2D:
		excluded.append(player.get_rid())
	return excluded
