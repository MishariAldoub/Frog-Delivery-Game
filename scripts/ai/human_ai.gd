extends CharacterBody2D
class_name HumanAI

signal suspicion_changed(value: float)
signal player_visibility_changed(is_visible: bool)

@export_group("Target")
@export var player_group = "player"
@export var eye_offset = Vector2(0, -28)

@export_group("Movement")
@export var gravity = 1500.0
@export var casual_move_speed = 70.0
@export var cautious_move_speed = 48.0
@export var retreat_move_speed = 36.0
@export var ground_acceleration = 800.0
@export var ground_deceleration = 1000.0
@export var destination_arrival_distance = 18.0
@export var navigation_repath_interval = 0.35
@export var navigation_target_reach_distance = 24.0
@export var use_navigation_agent = true
@export var ledge_check_forward_distance = 22.0
@export var ledge_check_down_distance = 84.0
@export var wall_check_distance = 18.0
@export var floor_probe_mask = 1

@export_group("Vision")
@export var vision_distance = 760.0
@export_range(10.0, 180.0, 1.0) var vision_fov_degrees = 115.0
@export var vision_collision_mask = 1
@export var visual_suspicion_gain_per_second = 38.0
@export var clear_visual_suspicion_gain_per_second = 82.0
@export var clear_visual_time = 0.75
@export var questionable_glimpse_suspicion = 10.0
@export var distant_visual_gain_scale = 0.35
@export var player_vision_target_offset = Vector2.ZERO
@export var vision_ray_target_extension = 36.0

@export_group("Hearing")
@export var hearing_radius = 560.0
@export var hearing_sensitivity = 1.0
@export var awareness_radius = 620.0
@export var hearing_suspicion_gain = 60.0
@export var minimum_noise_suspicion = 6.0

@export_group("Suspicion")
@export var max_suspicion = 100.0
@export var suspicious_threshold = 12.0
@export var aiming_threshold = 50.0
@export var attack_threshold = 85.0
@export var suspicion_decay_per_second = 7.5
@export var alert_decay_delay = 6.0
@export var confirmed_memory_duration = 12.0
@export var warning_suspicion_gain = 44.0

@export_group("Warning")
@export var warning_radius = 520.0
@export var warning_cooldown = 5.0
@export var warning_event_memory_time = 10.0

@export_group("Debug")
@export var show_debug_ai = true
@export var draw_debug_perception = true

var suspicion = 0.0
var player_visible = false
var last_seen_player_position = Vector2.ZERO
var last_heard_position = Vector2.ZERO
var last_suspicious_position = Vector2.ZERO
var has_last_seen_player_position = false
var has_last_heard_position = false
var has_last_suspicious_position = false
var time_since_player_seen = INF
var time_since_confirmed = INF
var visible_player_duration = 0.0
var facing_direction = 1
var look_direction = Vector2.RIGHT
var current_investigation_position = Vector2.ZERO
var has_investigation_position = false
var player_in_awareness_area = false
var movement_blocked_by_ledge = false
var current_navigation_target = Vector2.ZERO
var has_navigation_target = false
var ground_ahead = true
var aim_source = "NONE"
var los_debug_target = Vector2.ZERO
var los_debug_hit_position = Vector2.ZERO
var has_los_debug_target = false
var los_debug_blocked = false
var los_debug_state = "BLOCKED"

var player: Node2D

var _last_warning_time = -999.0
var _seen_warning_events: Dictionary = {}
var _navigation_repath_timer = 0.0
var _last_path_points: PackedVector2Array = PackedVector2Array()

@onready var hearing_area: Area2D = get_node_or_null("HearingArea") as Area2D
@onready var hearing_shape: CollisionShape2D = get_node_or_null("HearingArea/CollisionShape2D") as CollisionShape2D
@onready var vision_ray: RayCast2D = get_node_or_null("VisionRay") as RayCast2D
@onready var navigation_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
@onready var forward_floor_ray: RayCast2D = get_node_or_null("ForwardFloorRay") as RayCast2D
@onready var left_floor_ray: RayCast2D = get_node_or_null("LeftFloorRay") as RayCast2D
@onready var right_floor_ray: RayCast2D = get_node_or_null("RightFloorRay") as RayCast2D
@onready var wall_ray: RayCast2D = get_node_or_null("WallRay") as RayCast2D

func _ready() -> void:
	add_to_group("human_ai")
	add_to_group("human_noise_listener")
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_snap_length = 6.0
	look_direction = Vector2.RIGHT * facing_direction
	_configure_hearing_area()
	_configure_vision_ray()
	_configure_navigation_agent()
	_configure_ledge_rays()
	_find_player()

func _physics_process(delta: float) -> void:
	_find_player()
	_navigation_repath_timer = max(_navigation_repath_timer - delta, 0.0)
	_update_perception(delta)
	_decay_warning_memory()
	_apply_gravity(delta)
	_update_human_ai(delta)
	_update_memory_timers(delta)
	queue_redraw()

func _update_human_ai(_delta: float) -> void:
	pass

func hear_noise(world_position: Vector2, loudness: float, radius: float, _noise_type: StringName = &"generic", source: Node = null) -> void:
	if source == self:
		return
	var distance = global_position.distance_to(world_position)
	var effective_hearing_radius = _get_effective_hearing_radius(loudness)
	if distance > max(radius, effective_hearing_radius):
		return

	var falloff = 1.0 - clamp(distance / max(effective_hearing_radius, 1.0), 0.0, 1.0)
	var noise_falloff = 1.0 - clamp(distance / max(radius, 1.0), 0.0, 1.0)
	var audible_strength = max(falloff, noise_falloff * 0.65)
	var gain = max(minimum_noise_suspicion, hearing_suspicion_gain * loudness * hearing_sensitivity * audible_strength)
	last_heard_position = world_position
	last_suspicious_position = world_position
	current_investigation_position = world_position
	has_last_heard_position = true
	has_last_suspicious_position = true
	has_investigation_position = true
	add_suspicion(gain)
	on_noise_heard(world_position, gain)

func on_noise_heard(_world_position: Vector2, _suspicion_gain: float) -> void:
	pass

func receive_warning(source_position: Vector2, approximate_threat_position: Vector2, severity: float, event_id: int, source_human: Node = null) -> void:
	if source_human == self:
		return
	if _seen_warning_events.has(event_id):
		return
	if global_position.distance_to(source_position) > warning_radius:
		return

	_seen_warning_events[event_id] = Time.get_ticks_msec() / 1000.0
	var warning_position = approximate_threat_position
	if warning_position == Vector2.ZERO:
		warning_position = source_position
	last_suspicious_position = warning_position
	current_investigation_position = warning_position
	has_last_suspicious_position = true
	has_investigation_position = true
	add_suspicion(warning_suspicion_gain * hearing_sensitivity * clamp(severity, 0.25, 1.25))
	on_warning_received(source_position, warning_position, severity)

func on_warning_received(_source_position: Vector2, _approximate_threat_position: Vector2, _severity: float) -> void:
	pass

func warn_nearby_humans(severity: float = 1.0) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_warning_time < warning_cooldown:
		return
	_last_warning_time = now

	var threat_position = last_seen_player_position if has_last_seen_player_position else last_suspicious_position
	var event_id = hash("%s:%s:%s" % [get_instance_id(), now, threat_position])
	_seen_warning_events[event_id] = now
	get_tree().call_group(
		"human_ai",
		"receive_warning",
		global_position,
		threat_position,
		severity,
		event_id,
		self
	)

func add_suspicion(amount: float) -> void:
	if amount <= 0.0:
		return
	var previous = suspicion
	suspicion = clamp(suspicion + amount, 0.0, max_suspicion)
	if not is_equal_approx(previous, suspicion):
		suspicion_changed.emit(suspicion)

func reduce_suspicion(amount: float) -> void:
	if amount <= 0.0:
		return
	var previous = suspicion
	suspicion = clamp(suspicion - amount, 0.0, max_suspicion)
	if not is_equal_approx(previous, suspicion):
		suspicion_changed.emit(suspicion)

func can_see_player() -> bool:
	return player_visible

func get_eye_position() -> Vector2:
	return to_global(Vector2(eye_offset.x * facing_direction, eye_offset.y))

func set_facing_from_vector(direction: Vector2) -> void:
	if abs(direction.x) > 0.05:
		facing_direction = 1 if direction.x > 0.0 else -1
	if direction.length_squared() > 0.001:
		look_direction = direction.normalized()

func move_toward_destination(destination: Vector2, speed: float, delta: float) -> bool:
	var movement_target = _get_navigation_step(destination)
	var offset = movement_target - global_position
	if abs(offset.x) <= destination_arrival_distance:
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		move_and_slide()
		return global_position.distance_to(destination) <= navigation_target_reach_distance or _is_navigation_finished()

	var direction = sign(offset.x)
	if not can_move_horizontally(direction):
		movement_blocked_by_ledge = true
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		move_and_slide()
		return false
	movement_blocked_by_ledge = false
	facing_direction = int(direction)
	look_direction = Vector2(direction, 0)
	velocity.x = move_toward(velocity.x, direction * speed, ground_acceleration * delta)
	move_and_slide()
	return false

func stop_horizontal(delta: float) -> void:
	movement_blocked_by_ledge = false
	velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
	move_and_slide()

func set_navigation_target(target: Vector2, force: bool = false) -> void:
	current_navigation_target = target
	has_navigation_target = true
	if navigation_agent and use_navigation_agent and (force or _navigation_repath_timer <= 0.0 or navigation_agent.target_position.distance_to(target) > 4.0):
		navigation_agent.target_position = target
		_navigation_repath_timer = navigation_repath_interval
		_last_path_points = navigation_agent.get_current_navigation_path()

func clear_navigation_target() -> void:
	has_navigation_target = false
	current_navigation_target = Vector2.ZERO
	_last_path_points = PackedVector2Array()

func can_reach_navigation_target(target: Vector2) -> bool:
	if not navigation_agent or not use_navigation_agent:
		return _has_floor_near(target)

	var navigation_map = navigation_agent.get_navigation_map()
	if not navigation_map.is_valid():
		return _has_floor_near(target)

	var start = NavigationServer2D.map_get_closest_point(navigation_map, global_position)
	var end = NavigationServer2D.map_get_closest_point(navigation_map, target)
	if start == Vector2.ZERO and global_position.distance_to(Vector2.ZERO) > navigation_target_reach_distance:
		return _has_floor_near(target)
	if end == Vector2.ZERO and target.distance_to(Vector2.ZERO) > navigation_target_reach_distance:
		return false
	if start.distance_to(global_position) > navigation_target_reach_distance * 2.0:
		return false
	if end.distance_to(target) > navigation_target_reach_distance * 2.0:
		return false

	var path = NavigationServer2D.map_get_path(navigation_map, start, end, false)
	return path.size() > 0

func get_nearest_navigation_position(world_position: Vector2) -> Vector2:
	if not navigation_agent or not use_navigation_agent:
		return world_position
	var navigation_map = navigation_agent.get_navigation_map()
	if not navigation_map.is_valid():
		return world_position
	var nearest = NavigationServer2D.map_get_closest_point(navigation_map, world_position)
	if nearest == Vector2.ZERO and world_position.distance_to(Vector2.ZERO) > navigation_target_reach_distance:
		return world_position
	return nearest

func can_move_horizontally(direction: float) -> bool:
	if is_zero_approx(direction):
		return true
	_update_ledge_rays(direction)
	if wall_ray and wall_ray.is_colliding():
		return false
	if forward_floor_ray and not forward_floor_ray.is_colliding():
		ground_ahead = false
		return false
	ground_ahead = true
	return true

func get_current_aim_target() -> Vector2:
	if player_visible and player:
		aim_source = "LIVE PLAYER"
		return player.global_position
	if has_last_seen_player_position:
		aim_source = "LAST SEEN"
		return last_seen_player_position
	if has_last_heard_position:
		aim_source = "LAST HEARD"
		return last_heard_position
	if has_last_suspicious_position:
		aim_source = "SUSPICIOUS"
		return last_suspicious_position
	aim_source = "NONE"
	return global_position + look_direction.normalized() * 64.0

func _update_perception(delta: float) -> void:
	var was_visible = player_visible
	player_visible = _has_line_of_sight_to_player()
	if was_visible != player_visible:
		player_visibility_changed.emit(player_visible)

	if player_visible and player:
		visible_player_duration += delta
		last_seen_player_position = player.global_position
		last_suspicious_position = last_seen_player_position
		current_investigation_position = last_seen_player_position
		has_last_seen_player_position = true
		has_last_suspicious_position = true
		has_investigation_position = true
		time_since_player_seen = 0.0
		set_facing_from_vector(last_seen_player_position - get_eye_position())
		var distance_scale = _get_visual_distance_scale()
		var gain_rate = clear_visual_suspicion_gain_per_second if visible_player_duration >= clear_visual_time else visual_suspicion_gain_per_second
		gain_rate *= distance_scale
		add_suspicion(gain_rate * delta)
	else:
		if was_visible and visible_player_duration > 0.05 and visible_player_duration < clear_visual_time:
			add_suspicion(questionable_glimpse_suspicion)
		visible_player_duration = 0.0
		_decay_suspicion(delta)

	if suspicion >= attack_threshold:
		time_since_confirmed = 0.0

func _has_line_of_sight_to_player() -> bool:
	if not player:
		los_debug_state = "BLOCKED"
		return false
	var eye = get_eye_position()
	var target = _get_player_vision_target_position()
	los_debug_target = target
	has_los_debug_target = true
	los_debug_blocked = false
	_update_vision_ray_debug(eye, target)
	var to_target = target - eye
	var distance = to_target.length()
	if distance > vision_distance or distance <= 1.0:
		los_debug_hit_position = target
		los_debug_blocked = true
		los_debug_state = "BLOCKED"
		return false

	var forward = look_direction.normalized()
	if forward.length_squared() <= 0.001:
		forward = Vector2.RIGHT * facing_direction
	var angle = rad_to_deg(forward.angle_to(to_target.normalized()))
	if abs(angle) > vision_fov_degrees * 0.5:
		los_debug_hit_position = target
		los_debug_blocked = true
		los_debug_state = "BLOCKED"
		return false

	var space_state = get_world_2d().direct_space_state
	var ray_end = target + to_target.normalized() * vision_ray_target_extension
	var query = PhysicsRayQueryParameters2D.create(eye, ray_end)
	query.collision_mask = vision_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		los_debug_hit_position = ray_end
		los_debug_blocked = true
		los_debug_state = "BLOCKED"
		return false
	var collider = hit.get("collider")
	los_debug_hit_position = hit.get("position", target)
	var hit_player = collider == player or (collider is Node and player.is_ancestor_of(collider))
	los_debug_blocked = not hit_player
	los_debug_state = "CLEAR" if hit_player else "BLOCKED"
	return hit_player

func _decay_suspicion(delta: float) -> void:
	if suspicion <= 0.0:
		return
	var decay_delay = alert_decay_delay
	if time_since_confirmed < confirmed_memory_duration:
		decay_delay = confirmed_memory_duration
	if time_since_player_seen < decay_delay:
		return
	reduce_suspicion(suspicion_decay_per_second * delta)

func _update_memory_timers(delta: float) -> void:
	if not player_visible:
		time_since_player_seen += delta
	time_since_confirmed += delta

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

func _find_player() -> void:
	if is_instance_valid(player):
		return
	player = get_tree().get_first_node_in_group(player_group) as Node2D
	if not player:
		player = get_tree().root.find_child("Player", true, false) as Node2D

func _get_navigation_step(destination: Vector2) -> Vector2:
	set_navigation_target(destination)
	if navigation_agent and use_navigation_agent and not navigation_agent.is_navigation_finished():
		var next_position = navigation_agent.get_next_path_position()
		if next_position != Vector2.ZERO:
			return next_position
	return destination

func _is_navigation_finished() -> bool:
	if navigation_agent and use_navigation_agent:
		return navigation_agent.is_navigation_finished()
	return false

func _get_effective_hearing_radius(loudness: float) -> float:
	return hearing_radius * max(0.75, loudness) * hearing_sensitivity

func _get_visual_distance_scale() -> float:
	if not player:
		return 1.0
	var distance = get_eye_position().distance_to(_get_player_vision_target_position())
	var ratio = clamp(distance / max(vision_distance, 1.0), 0.0, 1.0)
	return lerp(1.0, distant_visual_gain_scale, ratio)

func _get_player_vision_target_position() -> Vector2:
	if not player:
		return Vector2.ZERO
	var collision_shape = player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape:
		return collision_shape.global_position + player_vision_target_offset
	return player.global_position + player_vision_target_offset

func _configure_hearing_area() -> void:
	if not hearing_area:
		return
	hearing_area.collision_layer = 0
	hearing_area.collision_mask = 1
	hearing_area.monitoring = true
	hearing_area.monitorable = false
	var entered_callable = Callable(self, "_on_hearing_area_body_entered")
	var exited_callable = Callable(self, "_on_hearing_area_body_exited")
	if not hearing_area.body_entered.is_connected(entered_callable):
		hearing_area.body_entered.connect(entered_callable)
	if not hearing_area.body_exited.is_connected(exited_callable):
		hearing_area.body_exited.connect(exited_callable)
	if hearing_shape and hearing_shape.shape is CircleShape2D:
		if not hearing_shape.shape.resource_local_to_scene:
			hearing_shape.shape = hearing_shape.shape.duplicate()
		var circle = hearing_shape.shape as CircleShape2D
		circle.radius = awareness_radius

func _configure_navigation_agent() -> void:
	if not navigation_agent:
		return
	navigation_agent.path_desired_distance = destination_arrival_distance
	navigation_agent.target_desired_distance = navigation_target_reach_distance
	navigation_agent.avoidance_enabled = false

func _configure_vision_ray() -> void:
	if not vision_ray:
		return
	vision_ray.collision_mask = vision_collision_mask
	vision_ray.enabled = draw_debug_perception
	vision_ray.add_exception(self)

func _configure_ledge_rays() -> void:
	for ray in [forward_floor_ray, left_floor_ray, right_floor_ray, wall_ray]:
		if ray:
			ray.collision_mask = floor_probe_mask
			ray.enabled = true
	_update_ledge_rays(facing_direction)

func _update_ledge_rays(direction: float) -> void:
	var side = 1.0 if direction >= 0.0 else -1.0
	if forward_floor_ray:
		forward_floor_ray.position = Vector2(ledge_check_forward_distance * side, 2.0)
		forward_floor_ray.target_position = Vector2(0.0, ledge_check_down_distance)
		forward_floor_ray.force_raycast_update()
		ground_ahead = forward_floor_ray.is_colliding()
	if left_floor_ray:
		left_floor_ray.position = Vector2(-ledge_check_forward_distance, 2.0)
		left_floor_ray.target_position = Vector2(0.0, ledge_check_down_distance)
		left_floor_ray.force_raycast_update()
	if right_floor_ray:
		right_floor_ray.position = Vector2(ledge_check_forward_distance, 2.0)
		right_floor_ray.target_position = Vector2(0.0, ledge_check_down_distance)
		right_floor_ray.force_raycast_update()
	if wall_ray:
		wall_ray.position = Vector2(0.0, -22.0)
		wall_ray.target_position = Vector2(wall_check_distance * side, 0.0)
		wall_ray.force_raycast_update()

func _update_vision_ray_debug(eye: Vector2, target: Vector2) -> void:
	if not vision_ray:
		return
	vision_ray.enabled = show_debug_ai and draw_debug_perception
	vision_ray.global_position = eye
	vision_ray.target_position = vision_ray.to_local(target)

func _has_floor_near(world_position: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(world_position + Vector2.UP * 18.0, world_position + Vector2.DOWN * ledge_check_down_distance)
	query.collision_mask = floor_probe_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	return not space_state.intersect_ray(query).is_empty()

func _on_hearing_area_body_entered(body: Node2D) -> void:
	if body == player or body.is_in_group(player_group):
		player_in_awareness_area = true

func _on_hearing_area_body_exited(body: Node2D) -> void:
	if body == player or body.is_in_group(player_group):
		player_in_awareness_area = false

func _decay_warning_memory() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	for event_id in _seen_warning_events.keys():
		if now - float(_seen_warning_events[event_id]) > warning_event_memory_time:
			_seen_warning_events.erase(event_id)

func _draw() -> void:
	if not show_debug_ai or not draw_debug_perception:
		return

	var eye_local = to_local(get_eye_position())
	var forward = look_direction.normalized()
	if forward.length_squared() <= 0.001:
		forward = Vector2.RIGHT * facing_direction
	var left = forward.rotated(deg_to_rad(-vision_fov_degrees * 0.5)) * vision_distance
	var right = forward.rotated(deg_to_rad(vision_fov_degrees * 0.5)) * vision_distance
	var vision_color = Color(0.2, 0.8, 1.0, 0.22) if player_visible else Color(1.0, 0.9, 0.25, 0.15)
	draw_line(eye_local, eye_local + left, vision_color, 1.0)
	draw_line(eye_local, eye_local + right, vision_color, 1.0)
	if has_los_debug_target:
		var los_color = Color(0.2, 1.0, 0.35, 0.8) if player_visible else Color(1.0, 0.1, 0.1, 0.8)
		var los_end = los_debug_hit_position if los_debug_blocked else los_debug_target
		draw_line(eye_local, to_local(los_end), los_color, 2.0)
	if has_investigation_position:
		draw_circle(to_local(current_investigation_position), 5.0, Color(1.0, 0.75, 0.2, 0.8))
	if has_last_seen_player_position:
		draw_circle(to_local(last_seen_player_position), 4.0, Color(1.0, 0.2, 0.2, 0.9))
	if has_navigation_target:
		draw_circle(to_local(current_navigation_target), 5.0, Color(0.35, 0.95, 0.55, 0.9))
	if _last_path_points.size() > 1:
		for index in range(_last_path_points.size() - 1):
			draw_line(to_local(_last_path_points[index]), to_local(_last_path_points[index + 1]), Color(0.35, 0.95, 0.55, 0.65), 2.0)
