extends HumanAI
class_name Scientist

const HealthComponentScript = preload("res://scripts/components/health_component.gd")

enum ScientistState {
	WORKING,
	WANDERING,
	IDLE,
	SUSPICIOUS,
	AIMING,
	ATTACKING,
}

enum CombatState {
	NORMAL,
	GRABBED,
	STUNNED,
	DEAD,
}

enum GrabType {
	NORMAL,
	CEILING_STRANGLE,
	REAR_DRAG,
}

@export_group("Scientist Routine")
@export var work_point_group = "scientist_work_point"
@export var wander_point_group = "scientist_wander_point"
@export var default_work_duration_min = 4.0
@export var default_work_duration_max = 8.0
@export var idle_duration_min = 1.0
@export var idle_duration_max = 3.0
@export_range(0.0, 1.0, 0.05) var idle_after_work_chance = 0.35
@export_range(0.0, 1.0, 0.05) var work_destination_chance = 0.65

@export_group("Suspicious Search")
@export var suspicious_search_duration = 4.0
@export var suspicious_arrival_distance = 26.0
@export var suspicious_look_interval = 0.75
@export var calm_suspicion_target = 8.0
@export var investigation_stopping_distance = 34.0

@export_group("Pistol")
@export var aim_reaction_time = 0.9
@export var lost_sight_aim_time = 2.4
@export var fire_rate = 1.15
@export var aim_spread_degrees = 7.0
@export var aim_tracking_speed = 4.0
@export var preferred_distance = 260.0
@export var bullet_range = 520.0
@export var bullet_damage = 1.0
@export var shot_noise_radius = 520.0
@export var shot_noise_loudness = 1.0

@export_group("Navigation")
@export var same_surface_vertical_tolerance = 72.0
@export var blocked_repath_delay = 0.8

@export_group("Combat Prototype")
@export var recovery_stun_time = 0.85
@export var grabbed_pull_strength = 18.0
@export var grabbed_velocity_damping = 5.0
@export var grabbed_max_speed = 640.0
@export var ceiling_strangle_damage_per_second = 5.0
@export var ceiling_strangle_reel_pull_strength = 38.0
@export var ceiling_strangle_rope_tension_strength = 52.0
@export var ceiling_strangle_velocity_damping = 14.0
@export var ceiling_strangle_max_speed = 920.0
@export var captured_swing_force_response = 1.0
@export var captured_struggle_force = 90.0
@export var captured_struggle_interval_min = 0.35
@export var captured_struggle_interval_max = 0.95
@export_range(0.0, 1.0, 0.05) var captured_struggle_randomness = 0.45
@export var minimum_impact_speed = 220.0
@export var impact_damage_multiplier = 0.045
@export var max_impact_damage = 35.0
@export var impact_damage_cooldown = 0.35

var state = ScientistState.IDLE
var combat_state = CombatState.NORMAL
var grab_type = GrabType.NORMAL
var state_time = 0.0
var state_duration = 0.0
var aim_time = 0.0
var fire_cooldown = 0.0
var search_time = 0.0
var look_cycle_time = 0.0
var aim_direction = Vector2.RIGHT
var destination = Vector2.ZERO
var has_destination = false
var blocked_repath_timer = 0.0
var routine_initialized = false
var grabbed_target_position = Vector2.ZERO
var grabbed_anchor_position = Vector2.ZERO
var grabbed_tongue_length = 0.0
var has_grabbed_tongue_anchor = false
var grabbed_swing_force = Vector2.ZERO
var grabbed_by: Node2D
var recovery_timer = 0.0
var impact_cooldown_timer = 0.0
var captured_struggle_timer = 0.0
var captured_struggle_force_current = Vector2.ZERO
var captured_struggle_debug_timer = 0.0
var last_impact_speed = 0.0
var last_impact_damage = 0.0
var default_floor_snap_length = 0.0

var _work_points: Array[Node2D] = []
var _wander_points: Array[Node2D] = []
var _current_point: Node2D
var _debug_label: Label
var _health_component: HealthComponent

func _ready() -> void:
	super()
	default_floor_snap_length = floor_snap_length
	add_to_group("tongue_combat_target")
	collision_layer = 2
	collision_mask = 1
	_build_body()
	_build_health_component()
	_build_debug_label()
	_initialize_routine_after_navigation_sync()

func _physics_process(delta: float) -> void:
	if combat_state == CombatState.NORMAL:
		super(delta)
		return

	impact_cooldown_timer = max(impact_cooldown_timer - delta, 0.0)
	match combat_state:
		CombatState.GRABBED:
			_update_grabbed(delta)
		CombatState.STUNNED:
			_update_stunned(delta)
		CombatState.DEAD:
			_update_dead(delta)

	_update_debug_label()
	queue_redraw()

func _initialize_routine_after_navigation_sync() -> void:
	await get_tree().physics_frame
	_collect_points()
	routine_initialized = true
	_enter_state(ScientistState.WORKING)

func _update_human_ai(delta: float) -> void:
	if not routine_initialized:
		stop_horizontal(delta)
		_update_debug_label()
		return
	state_time += delta
	fire_cooldown = max(fire_cooldown - delta, 0.0)
	blocked_repath_timer = max(blocked_repath_timer - delta, 0.0)
	_update_alert_state_from_suspicion()

	match state:
		ScientistState.WORKING:
			_update_working(delta)
		ScientistState.WANDERING:
			_update_wandering(delta)
		ScientistState.IDLE:
			_update_idle(delta)
		ScientistState.SUSPICIOUS:
			_update_suspicious(delta)
		ScientistState.AIMING:
			_update_aiming(delta)
		ScientistState.ATTACKING:
			_update_attacking(delta)

	_update_debug_label()

func on_noise_heard(_world_position: Vector2, _suspicion_gain: float) -> void:
	if combat_state != CombatState.NORMAL:
		return
	if suspicion >= suspicious_threshold and state < ScientistState.SUSPICIOUS:
		_enter_state(ScientistState.SUSPICIOUS)

func on_warning_received(_source_position: Vector2, _approximate_threat_position: Vector2, _severity: float) -> void:
	if combat_state != CombatState.NORMAL:
		return
	if state < ScientistState.SUSPICIOUS:
		_enter_state(ScientistState.SUSPICIOUS)

func hear_noise(world_position: Vector2, loudness: float, radius: float, noise_type: StringName = &"generic", source: Node = null) -> void:
	if combat_state != CombatState.NORMAL:
		return
	super(world_position, loudness, radius, noise_type, source)

func _update_alert_state_from_suspicion() -> void:
	if player_visible and suspicion >= attack_threshold and state != ScientistState.ATTACKING:
		_enter_state(ScientistState.ATTACKING)
		return
	if suspicion >= aiming_threshold and state < ScientistState.AIMING:
		_enter_state(ScientistState.AIMING)
		return
	if suspicion >= suspicious_threshold and state < ScientistState.SUSPICIOUS:
		_enter_state(ScientistState.SUSPICIOUS)

func _update_working(delta: float) -> void:
	stop_horizontal(delta)
	if _current_point:
		var point_facing = _current_point.get("facing_direction")
		if point_facing is int and point_facing != 0:
			facing_direction = point_facing
			look_direction = Vector2.RIGHT * facing_direction

	if state_time >= state_duration:
		if randf() < idle_after_work_chance:
			_enter_state(ScientistState.IDLE)
		else:
			_choose_destination()
			_enter_state(ScientistState.WANDERING)

func _update_wandering(delta: float) -> void:
	if not has_destination:
		_choose_destination()
	if not has_destination:
		_enter_state(ScientistState.IDLE)
		return

	if move_toward_destination(destination, casual_move_speed, delta):
		if _current_point and _is_work_point(_current_point):
			_enter_state(ScientistState.WORKING)
		else:
			_enter_state(ScientistState.IDLE)
	elif movement_blocked_by_ledge and blocked_repath_timer <= 0.0:
		blocked_repath_timer = blocked_repath_delay
		_choose_destination()
		if not has_destination:
			_enter_state(ScientistState.IDLE)

func _update_idle(delta: float) -> void:
	stop_horizontal(delta)
	if state_time >= state_duration:
		if randf() < 0.5:
			facing_direction *= -1
			look_direction = Vector2.RIGHT * facing_direction
			state_duration += randf_range(0.5, 1.2)
		else:
			_choose_destination()
			_enter_state(ScientistState.WANDERING if has_destination else ScientistState.WORKING)

func _update_suspicious(delta: float) -> void:
	var investigate = current_investigation_position if has_investigation_position else global_position
	set_facing_from_vector(investigate - get_eye_position())

	var safe_investigation_position = get_nearest_navigation_position(investigate)
	if global_position.distance_to(safe_investigation_position) > max(suspicious_arrival_distance, investigation_stopping_distance):
		if can_reach_navigation_target(safe_investigation_position):
			move_toward_destination(safe_investigation_position, cautious_move_speed, delta)
		else:
			stop_horizontal(delta)
			search_time += delta
		if movement_blocked_by_ledge and blocked_repath_timer <= 0.0:
			blocked_repath_timer = blocked_repath_delay
			clear_navigation_target()
		return

	stop_horizontal(delta)
	search_time += delta
	look_cycle_time += delta
	if look_cycle_time >= suspicious_look_interval:
		look_cycle_time = 0.0
		facing_direction *= -1
		look_direction = Vector2.RIGHT * facing_direction

	if search_time >= suspicious_search_duration and suspicion <= calm_suspicion_target:
		_enter_state(ScientistState.IDLE)

func _update_aiming(delta: float) -> void:
	stop_horizontal(delta)
	aim_time += delta
	_track_aim_toward(get_current_aim_target(), delta)

	if player_visible:
		if aim_time >= aim_reaction_time and suspicion >= attack_threshold:
			_enter_state(ScientistState.ATTACKING)
	elif aim_time >= lost_sight_aim_time:
		_enter_state(ScientistState.SUSPICIOUS)

func _update_attacking(delta: float) -> void:
	if not player_visible:
		_enter_state(ScientistState.AIMING)
		return

	warn_nearby_humans(1.0)
	_track_aim_toward(get_current_aim_target(), delta)
	_move_defensively(delta)
	if fire_cooldown <= 0.0:
		_fire_pistol()
		fire_cooldown = 1.0 / max(fire_rate, 0.01)

func _move_defensively(delta: float) -> void:
	if not player:
		stop_horizontal(delta)
		return
	var distance = global_position.distance_to(player.global_position)
	if distance >= preferred_distance:
		stop_horizontal(delta)
		return
	var away = sign(global_position.x - player.global_position.x)
	if is_zero_approx(away):
		away = -facing_direction
	if not can_move_horizontally(away):
		stop_horizontal(delta)
		return
	facing_direction = int(-away)
	velocity.x = move_toward(velocity.x, away * retreat_move_speed, ground_acceleration * delta)
	move_and_slide()

func _track_aim_toward(world_position: Vector2, delta: float) -> void:
	var desired = world_position - get_eye_position()
	if desired.length_squared() <= 0.001:
		return
	aim_direction = aim_direction.slerp(desired.normalized(), clamp(aim_tracking_speed * delta, 0.0, 1.0))
	look_direction = aim_direction
	set_facing_from_vector(aim_direction)

func _fire_pistol() -> void:
	if combat_state != CombatState.NORMAL:
		return
	var origin = get_eye_position() + aim_direction.normalized() * 22.0
	var shot_direction = aim_direction.rotated(deg_to_rad(randf_range(-aim_spread_degrees, aim_spread_degrees))).normalized()
	var end = origin + shot_direction * bullet_range
	var query = PhysicsRayQueryParameters2D.create(origin, end)
	query.collision_mask = vision_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider == player and player and player.has_method("take_damage"):
			player.take_damage(bullet_damage)
	HumanNoise.emit_noise(self, origin, shot_noise_loudness, shot_noise_radius, &"pistol")

func _enter_state(new_state: int) -> void:
	if combat_state != CombatState.NORMAL:
		return
	if state == new_state:
		return
	state = new_state
	state_time = 0.0

	match state:
		ScientistState.WORKING:
			_current_point = _nearest_or_random_work_point()
			if _current_point:
				destination = _current_point.global_position
				has_destination = true
				if global_position.distance_to(destination) > destination_arrival_distance:
					state = ScientistState.WANDERING
				state_duration = _get_point_duration(_current_point, default_work_duration_min, default_work_duration_max, true)
			else:
				state_duration = randf_range(default_work_duration_min, default_work_duration_max)
		ScientistState.WANDERING:
			if not has_destination:
				_choose_destination()
		ScientistState.IDLE:
			state_duration = randf_range(idle_duration_min, idle_duration_max)
		ScientistState.SUSPICIOUS:
			search_time = 0.0
			look_cycle_time = 0.0
			if has_last_suspicious_position:
				current_investigation_position = last_suspicious_position
				has_investigation_position = true
		ScientistState.AIMING:
			aim_time = 0.0
			var aim_target = get_current_aim_target()
			aim_direction = (aim_target - get_eye_position()).normalized() if aim_target != Vector2.ZERO else Vector2.RIGHT * facing_direction
		ScientistState.ATTACKING:
			aim_time = 0.0
			fire_cooldown = min(fire_cooldown, 0.15)
	_update_debug_label()

func _choose_destination() -> void:
	_collect_points()
	var candidates: Array[Node2D] = []
	if randf() < work_destination_chance and not _work_points.is_empty():
		candidates = _work_points.duplicate()
	elif not _wander_points.is_empty():
		candidates = _wander_points.duplicate()
	else:
		candidates = _work_points.duplicate()

	candidates = _filter_reachable_points(candidates)
	if candidates.is_empty():
		has_destination = false
		clear_navigation_target()
		return

	_current_point = candidates.pick_random()
	destination = _current_point.global_position
	has_destination = true
	set_navigation_target(destination, true)

func _nearest_or_random_work_point() -> Node2D:
	_collect_points()
	if _work_points.is_empty():
		return null
	var reachable_points = _filter_reachable_points(_work_points)
	if reachable_points.is_empty():
		return null
	var nearest: Node2D
	var nearest_distance = INF
	for point in reachable_points:
		var distance = global_position.distance_to(point.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = point
	if nearest and nearest_distance <= destination_arrival_distance * 2.0:
		return nearest
	return reachable_points.pick_random()

func _filter_reachable_points(points: Array[Node2D]) -> Array[Node2D]:
	var reachable: Array[Node2D] = []
	for point in points:
		if not is_instance_valid(point):
			continue
		if abs(point.global_position.y - global_position.y) > same_surface_vertical_tolerance:
			continue
		if not can_reach_navigation_target(point.global_position):
			continue
		reachable.append(point)
	return reachable

func _collect_points() -> void:
	_work_points.clear()
	_wander_points.clear()
	for node in get_tree().get_nodes_in_group(work_point_group):
		if node is Node2D:
			_work_points.append(node)
	for node in get_tree().get_nodes_in_group(wander_point_group):
		if node is Node2D:
			_wander_points.append(node)

func _is_work_point(point: Node) -> bool:
	return point and point.is_in_group(work_point_group)

func _get_point_duration(point: Node, fallback_min: float, fallback_max: float, working: bool) -> float:
	if not point:
		return randf_range(fallback_min, fallback_max)
	var min_property = "work_duration_min" if working else "idle_duration_min"
	var max_property = "work_duration_max" if working else "idle_duration_max"
	var min_value = point.get(min_property)
	var max_value = point.get(max_property)
	if (min_value is float or min_value is int) and (max_value is float or max_value is int):
		return randf_range(float(min_value), float(max_value))
	return randf_range(fallback_min, fallback_max)

func _build_body() -> void:
	if get_node_or_null("CollisionShape2D"):
		return
	var collision = CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var capsule = CapsuleShape2D.new()
	capsule.radius = 12.0
	capsule.height = 52.0
	collision.shape = capsule
	collision.position = Vector2(0, -22)
	add_child(collision)

func _build_health_component() -> void:
	_health_component = get_node_or_null("HealthComponent") as HealthComponent
	if not _health_component:
		_health_component = HealthComponentScript.new()
		_health_component.name = "HealthComponent"
		add_child(_health_component)
	var died_callable = Callable(self, "_on_health_died")
	var health_changed_callable = Callable(self, "_on_health_changed")
	if not _health_component.died.is_connected(died_callable):
		_health_component.died.connect(died_callable)
	if not _health_component.health_changed.is_connected(health_changed_callable):
		_health_component.health_changed.connect(health_changed_callable)

func _build_debug_label() -> void:
	_debug_label = get_node_or_null("DebugAILabel") as Label
	if _debug_label:
		_debug_label.size = Vector2(210, 116)
		return
	_debug_label = Label.new()
	_debug_label.name = "DebugAILabel"
	_debug_label.position = Vector2(-86, -96)
	_debug_label.size = Vector2(210, 116)
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debug_label.add_theme_color_override("font_color", Color("#fff2b8"))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_debug_label)

func _update_debug_label() -> void:
	if not _debug_label:
		return
	_debug_label.visible = show_debug_ai
	if not show_debug_ai:
		return
	if combat_state != CombatState.NORMAL:
		_debug_label.text = "State: %s\nHP: %d / %d\nGrab type: %s\nAI suspended:%s\nVel:%.0f impact:%.0f dmg:%.1f\nStruggle:%s swing:%.0f" % [
			_get_combat_state_name(),
			int(round(get_current_health())),
			int(round(get_max_health())),
			_get_grab_type_name(),
			str(is_ai_suspended_by_tongue()),
			velocity.length(),
			last_impact_speed,
			last_impact_damage,
			str(captured_struggle_debug_timer > 0.0),
			grabbed_swing_force.length(),
		]
		return
	var target_text = "none"
	if has_investigation_position:
		target_text = "%d,%d" % [int(current_investigation_position.x), int(current_investigation_position.y)]
	_debug_label.text = "%s\nS:%03d VISIBLE:%s LOS:%s\nAIM:%s Ground:%s Target:%s" % [
		_get_state_name(),
		int(round(suspicion)),
		"YES" if player_visible else "NO",
		los_debug_state,
		aim_source,
		"YES" if ground_ahead else "NO",
		target_text,
	]

func _get_state_name() -> String:
	match state:
		ScientistState.WORKING:
			return "WORKING"
		ScientistState.WANDERING:
			return "WANDERING"
		ScientistState.IDLE:
			return "IDLE"
		ScientistState.SUSPICIOUS:
			return "SUSPICIOUS"
		ScientistState.AIMING:
			return "AIMING"
		ScientistState.ATTACKING:
			return "ATTACKING"
	return "UNKNOWN"

func take_damage(amount: float) -> void:
	if _health_component:
		_health_component.take_damage(amount)

func heal(amount: float) -> void:
	if _health_component:
		_health_component.heal(amount)

func die() -> void:
	if _health_component:
		_health_component.die()
	else:
		_on_health_died()

func get_current_health() -> float:
	return _health_component.current_health if _health_component else 0.0

func get_max_health() -> float:
	return _health_component.max_health if _health_component else 1.0

func is_attack_from_behind(attacker_position: Vector2) -> bool:
	var attacker_side = sign(attacker_position.x - global_position.x)
	if is_zero_approx(attacker_side):
		return false
	return attacker_side == -facing_direction

func get_tongue_target_position() -> Vector2:
	var shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		return shape.global_position
	return global_position + Vector2(0, -24)

func get_tongue_neck_grab_position() -> Vector2:
	var neck_marker = get_node_or_null("TongueNeckGrabPoint") as Marker2D
	if neck_marker:
		return neck_marker.global_position
	return global_position + Vector2(0, -50)

func begin_tongue_grab(grabber: Node2D, grab_kind: int, tongue_target_position: Vector2) -> bool:
	if combat_state == CombatState.DEAD or not _health_component or _health_component.is_dead:
		return false
	grabbed_by = grabber
	grab_type = grab_kind
	grabbed_target_position = tongue_target_position
	grabbed_anchor_position = Vector2.ZERO
	grabbed_tongue_length = 0.0
	has_grabbed_tongue_anchor = false
	grabbed_swing_force = Vector2.ZERO
	combat_state = CombatState.GRABBED
	recovery_timer = 0.0
	impact_cooldown_timer = 0.0
	captured_struggle_timer = randf_range(captured_struggle_interval_min, captured_struggle_interval_max)
	captured_struggle_force_current = Vector2.ZERO
	captured_struggle_debug_timer = 0.0
	last_impact_speed = 0.0
	last_impact_damage = 0.0
	has_destination = false
	floor_snap_length = 0.0
	clear_navigation_target()
	player_visible = false
	velocity *= 0.35
	_update_debug_label()
	return true

func update_tongue_grab(tongue_target_position: Vector2, delta: float) -> void:
	if combat_state != CombatState.GRABBED:
		return
	grabbed_target_position = tongue_target_position
	has_grabbed_tongue_anchor = false
	grabbed_swing_force = Vector2.ZERO
	if grab_type == GrabType.CEILING_STRANGLE:
		take_damage(ceiling_strangle_damage_per_second * delta)

func update_ceiling_tongue_grab(anchor_position: Vector2, tongue_length: float, tongue_endpoint: Vector2, swing_force: Vector2, delta: float) -> void:
	if combat_state != CombatState.GRABBED:
		return
	grabbed_anchor_position = anchor_position
	grabbed_tongue_length = max(tongue_length, 1.0)
	grabbed_target_position = tongue_endpoint
	has_grabbed_tongue_anchor = true
	grabbed_swing_force = swing_force
	if grab_type == GrabType.CEILING_STRANGLE:
		take_damage(ceiling_strangle_damage_per_second * delta)

func release_tongue_grab() -> void:
	if combat_state != CombatState.GRABBED:
		return
	grabbed_by = null
	grabbed_target_position = Vector2.ZERO
	grabbed_anchor_position = Vector2.ZERO
	grabbed_tongue_length = 0.0
	has_grabbed_tongue_anchor = false
	grabbed_swing_force = Vector2.ZERO
	captured_struggle_force_current = Vector2.ZERO
	captured_struggle_debug_timer = 0.0
	grab_type = GrabType.NORMAL
	if _health_component and _health_component.is_dead:
		combat_state = CombatState.DEAD
		floor_snap_length = default_floor_snap_length
		return
	combat_state = CombatState.STUNNED
	recovery_timer = recovery_stun_time
	floor_snap_length = default_floor_snap_length
	clear_navigation_target()

func _update_grabbed(delta: float) -> void:
	var previous_velocity = velocity
	captured_struggle_debug_timer = max(captured_struggle_debug_timer - delta, 0.0)
	velocity.y += gravity * delta
	if grab_type == GrabType.CEILING_STRANGLE:
		_update_ceiling_strangle_motion(delta)
	else:
		var grabbed_point = get_tongue_target_position()
		var displacement = grabbed_target_position - grabbed_point
		var spring_velocity = displacement * grabbed_pull_strength
		velocity = velocity.move_toward(spring_velocity, grabbed_velocity_damping * max(velocity.length(), 80.0) * delta)
		velocity = velocity.limit_length(grabbed_max_speed)
	move_and_slide()
	_apply_impact_damage(previous_velocity)

func _update_ceiling_strangle_motion(delta: float) -> void:
	var neck_point = get_tongue_neck_grab_position()
	var displacement = grabbed_target_position - neck_point
	var target_velocity = displacement * ceiling_strangle_reel_pull_strength
	var rope_direction = Vector2.ZERO

	if has_grabbed_tongue_anchor:
		var anchor_to_neck = neck_point - grabbed_anchor_position
		var distance = anchor_to_neck.length()
		if distance > 0.001:
			rope_direction = anchor_to_neck / distance
		if distance > grabbed_tongue_length and distance > 0.001:
			var excess_length = distance - grabbed_tongue_length
			target_velocity += -rope_direction * excess_length * ceiling_strangle_rope_tension_strength
			var outward_speed = velocity.dot(rope_direction)
			if outward_speed > 0.0:
				velocity -= rope_direction * outward_speed

	var external_force = _get_tangential_captured_force(grabbed_swing_force, rope_direction)
	external_force += _update_captured_struggle_force(delta, rope_direction)

	velocity = velocity.move_toward(
		target_velocity,
		ceiling_strangle_velocity_damping * max(velocity.length(), 100.0) * delta
	)
	velocity += external_force * captured_swing_force_response * delta
	velocity = velocity.limit_length(ceiling_strangle_max_speed)

func _get_tangential_captured_force(force: Vector2, rope_direction: Vector2) -> Vector2:
	if force.length_squared() <= 0.001:
		return Vector2.ZERO
	if rope_direction.length_squared() <= 0.001:
		return force
	return force - rope_direction * force.dot(rope_direction)

func _update_captured_struggle_force(delta: float, rope_direction: Vector2) -> Vector2:
	captured_struggle_timer = max(captured_struggle_timer - delta, 0.0)
	if captured_struggle_timer <= 0.0:
		captured_struggle_timer = randf_range(captured_struggle_interval_min, captured_struggle_interval_max)
		var random_direction = Vector2.from_angle(randf_range(0.0, TAU))
		if rope_direction.length_squared() > 0.001:
			var tangent = Vector2(-rope_direction.y, rope_direction.x)
			random_direction = tangent * (1.0 if randf() >= 0.5 else -1.0)
			random_direction = random_direction.slerp(Vector2.from_angle(randf_range(0.0, TAU)), captured_struggle_randomness).normalized()
		captured_struggle_force_current = random_direction * captured_struggle_force * randf_range(0.65, 1.15)
		captured_struggle_debug_timer = 0.18
	if captured_struggle_debug_timer <= 0.0:
		captured_struggle_force_current = Vector2.ZERO
		return Vector2.ZERO
	return _get_tangential_captured_force(captured_struggle_force_current, rope_direction)

func _update_stunned(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
	move_and_slide()
	recovery_timer = max(recovery_timer - delta, 0.0)
	if recovery_timer <= 0.0:
		combat_state = CombatState.NORMAL
		_enter_state(ScientistState.SUSPICIOUS if suspicion >= suspicious_threshold else ScientistState.IDLE)

func _update_dead(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
	move_and_slide()

func _apply_impact_damage(previous_velocity: Vector2) -> void:
	if impact_cooldown_timer > 0.0:
		return
	last_impact_speed = 0.0
	for index in range(get_slide_collision_count()):
		var collision = get_slide_collision(index)
		var normal = collision.get_normal()
		var impact_speed = max(0.0, previous_velocity.dot(-normal))
		last_impact_speed = max(last_impact_speed, impact_speed)
		if impact_speed < minimum_impact_speed:
			continue
		var collider = collision.get_collider()
		if not (collider is StaticBody2D or (collider is Node and collider.is_in_group("grapple_surface"))):
			continue
		var damage = clamp((impact_speed - minimum_impact_speed) * impact_damage_multiplier, 0.0, max_impact_damage)
		if damage > 0.0:
			take_damage(damage)
			last_impact_damage = damage
			impact_cooldown_timer = impact_damage_cooldown
			return

func _on_health_changed(_current_health: float, _max_health: float) -> void:
	queue_redraw()
	_update_debug_label()

func _on_health_died() -> void:
	combat_state = CombatState.DEAD
	grabbed_by = null
	grabbed_anchor_position = Vector2.ZERO
	grabbed_tongue_length = 0.0
	has_grabbed_tongue_anchor = false
	grabbed_swing_force = Vector2.ZERO
	captured_struggle_force_current = Vector2.ZERO
	captured_struggle_debug_timer = 0.0
	grab_type = GrabType.NORMAL
	floor_snap_length = default_floor_snap_length
	clear_navigation_target()
	velocity *= 0.25
	_update_debug_label()

func is_tongue_grab_active() -> bool:
	return combat_state == CombatState.GRABBED

func is_ai_suspended_by_tongue() -> bool:
	return combat_state == CombatState.GRABBED

func _get_combat_state_name() -> String:
	match combat_state:
		CombatState.NORMAL:
			return "NORMAL"
		CombatState.GRABBED:
			return "GRABBED"
		CombatState.STUNNED:
			return "STUNNED"
		CombatState.DEAD:
			return "DEAD"
	return "UNKNOWN"

func _get_grab_type_name() -> String:
	match grab_type:
		GrabType.NORMAL:
			return "NORMAL"
		GrabType.CEILING_STRANGLE:
			return "CEILING_STRANGLE"
		GrabType.REAR_DRAG:
			return "REAR_DRAG"
	return "UNKNOWN"

func _draw() -> void:
	super()
	var body_color = Color("#d7d6c9")
	var coat_color = Color("#eef1e8")
	var skin_color = Color("#e7c19d")
	var alert_color = Color("#ff5a4f") if state == ScientistState.ATTACKING else Color("#ffc857")
	draw_rect(Rect2(Vector2(-10, -50), Vector2(20, 42)), coat_color)
	draw_rect(Rect2(Vector2(-13, -22), Vector2(26, 32)), body_color)
	draw_circle(Vector2(0, -62), 10.0, skin_color)
	draw_line(Vector2(-8, -14), Vector2(-22, 4), coat_color, 5.0)
	draw_line(Vector2(8, -14), Vector2(22, 4), coat_color, 5.0)
	draw_line(Vector2(-6, 8), Vector2(-8, 22), Color("#2f3540"), 5.0)
	draw_line(Vector2(6, 8), Vector2(8, 22), Color("#2f3540"), 5.0)
	draw_circle(Vector2(4 * facing_direction, -64), 2.0, Color.BLACK)
	if state == ScientistState.AIMING or state == ScientistState.ATTACKING:
		var gun_origin = Vector2(12 * facing_direction, -34)
		var gun_direction = to_local(get_eye_position() + aim_direction.normalized() * 52.0) - to_local(get_eye_position())
		draw_line(gun_origin, gun_origin + gun_direction.limit_length(34.0), Color("#202126"), 4.0)
		draw_circle(gun_origin + gun_direction.limit_length(34.0), 2.5, alert_color)
	_draw_health_bar()

func _draw_health_bar() -> void:
	if not _health_component:
		return
	var bar_size = Vector2(46, 6)
	var bar_position = Vector2(-bar_size.x * 0.5, -82.0)
	var ratio = clamp(get_current_health() / max(get_max_health(), 1.0), 0.0, 1.0)
	draw_rect(Rect2(bar_position, bar_size), Color(0.05, 0.05, 0.05, 0.8))
	draw_rect(Rect2(bar_position + Vector2.ONE, Vector2((bar_size.x - 2.0) * ratio, bar_size.y - 2.0)), Color("#ff5a4f"))
