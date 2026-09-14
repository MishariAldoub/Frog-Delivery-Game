extends CharacterBody2D

const PlayerVisualScene = preload("res://scenes/PlayerVisual.tscn")
const TongueScene = preload("res://scenes/Tongue.tscn")
const HumanNoiseEvents = preload("res://scripts/ai/human_noise.gd")

enum PlayerState {
	GROUNDED,
	AIRBORNE,
	WALL_LEFT,
	WALL_RIGHT,
	CEILING,
	TAIL_HANG,
	GRAPPLING,
	GRAPPLE_PULL,
}

@export_group("Movement")
@export var normal_move_speed = 260.0
@export var sprint_move_speed = 390.0
@export var move_speed = 260.0
@export var ground_acceleration = 2200.0
@export var ground_deceleration = 2800.0
@export var air_acceleration = 1300.0
@export var jump_velocity = -520.0
@export var gravity = 1500.0
@export var max_fall_speed = 760.0
@export var coyote_time = 0.12

@export_group("Stamina")
@export var max_stamina = 100.0
@export var sprint_stamina_drain_rate = 28.0
@export var stamina_regeneration_rate = 34.0
@export var stamina_regeneration_delay = 0.75
@export var stamina_bar_hide_delay = 0.6

@export_group("Surface Crawling")
@export var wall_crawl_speed = 180.0
@export var ceiling_crawl_speed = 190.0
@export var wall_sprint_speed = 270.0
@export var ceiling_sprint_speed = 285.0
@export var surface_adhesion_strength = 38.0
@export var surface_corner_snap_distance = 34.0
@export var surface_corner_carry_time = 0.16
@export var surface_hold_probe_extra_distance = 18.0
@export var surface_hold_probe_spread = 0.82
@export var ground_corner_capture_distance = 22.0
@export var wall_ceiling_corner_probe_distance = 48.0
@export var airborne_ceiling_grab_extra_distance = 8.0
@export var wall_capture_distance = 22.0
@export var ceiling_capture_distance = 30.0
@export var surface_capture_rearm_delay = 0.12
@export var surface_capture_commit_time = 0.12
@export var surface_attach_offset = 1.5
@export var ceiling_contact_grace_time = 0.16
@export var ceiling_hold_check_distance = 10.0
@export var surface_transition_lock_time = 0.10
@export var wall_jump_horizontal_velocity = 360.0
@export var wall_jump_vertical_velocity = -500.0
@export var ceiling_detach_velocity = 260.0
@export var surface_reattach_delay = 0.16

@export_group("Tail Hang")
@export var tail_min_length = 30.0
@export var tail_max_length = 105.0
@export var tail_extend_speed = 92.0
@export var tail_retract_speed = 120.0
@export var tail_follow_speed = 620.0

@export_group("Tongue")
@export var tongue_origin = Vector2(14, -16)

@export_group("Grapple")
@export var grapple_max_length = 288.0
@export var grapple_pull_force = 1150.0
@export var grapple_spring_strength = 8.0
@export var grapple_damping = 1.7
@export var grapple_air_control = 520.0
@export var grapple_max_speed = 900.0
@export var grapple_release_lift = 0.16
@export var grapple_release_lift_max = 115.0
@export var grapple_release_speed_threshold = 260.0

@export_group("Tongue Grapple Pull")
@export var grapple_range = 240.0
@export var grapple_pull_speed = 1850.0
@export var grapple_acceleration = 12000.0
@export var grapple_stop_distance = 34.0
@export var grapple_max_duration = 0.28
@export var grapple_exit_speed_multiplier = 0.72

@export_group("Debug")
@export var show_debug_state_label = true
@export var debug_noise_radius = 560.0

@export_group("Noise")
@export var tongue_noise_radius = 300.0
@export var tongue_noise_loudness = 0.6
@export var grapple_pull_noise_radius = 520.0
@export var grapple_pull_noise_loudness = 1.0
@export var sprint_noise_radius = 340.0
@export var sprint_noise_loudness = 0.45
@export var sprint_noise_interval = 0.45
@export var hard_landing_noise_radius = 480.0
@export var hard_landing_noise_loudness = 1.0
@export var hard_landing_speed_threshold = 520.0

const FLOOR_NORMAL_THRESHOLD = 0.65
const WALL_NORMAL_THRESHOLD = 0.65
const CEILING_NORMAL_THRESHOLD = 0.65
const BODY_HALF_WIDTH = 18.0
const BODY_HALF_HEIGHT = 28.0

var state = PlayerState.AIRBORNE
var attached_normal = Vector2.ZERO
var attached_contact_point = Vector2.ZERO
var reattach_timer = 0.0
var capture_rearm_timer = 0.0
var capture_commit_timer = 0.0
var ceiling_contact_grace_timer = 0.0
var surface_transition_lock_timer = 0.0
var coyote_timer = 0.0
var surface_corner_carry_timer = 0.0
var surface_corner_carry_velocity = Vector2.ZERO
var facing_direction = 1
var current_stamina = 100.0
var stamina_regen_timer = 0.0
var stamina_bar_visible_timer = 0.0
var is_grappling = false
var grapple_anchor = Vector2.ZERO
var grapple_length = 0.0
var is_grapple_pulling = false
var grapple_pull_anchor = Vector2.ZERO
var grapple_pull_timer = 0.0
var tail_anchor = Vector2.ZERO
var tail_length = 30.0
var tail_catch_visual_point = Vector2.ZERO
var tail_catch_visual_timer = 0.0
var sprint_noise_timer = 0.0
var was_on_floor_last_frame = false

var tongue: Node2D
var frog_visual: Node2D
var debug_state_label: Label

func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_snap_length = 6.0
	floor_max_angle = deg_to_rad(48.0)
	collision_layer = 1
	collision_mask = 1
	current_stamina = max_stamina
	move_speed = normal_move_speed
	tail_length = tail_min_length

	_add_collision()
	_add_visuals()
	_add_tongue()
	_add_camera()
	_add_debug_state_label()
	set_movement_state(PlayerState.AIRBORNE)

func _physics_process(delta: float) -> void:
	var fall_speed_before_motion = velocity.y
	reattach_timer = max(reattach_timer - delta, 0.0)
	capture_rearm_timer = max(capture_rearm_timer - delta, 0.0)
	capture_commit_timer = max(capture_commit_timer - delta, 0.0)
	surface_transition_lock_timer = max(surface_transition_lock_timer - delta, 0.0)
	coyote_timer = max(coyote_timer - delta, 0.0)
	surface_corner_carry_timer = max(surface_corner_carry_timer - delta, 0.0)
	tail_catch_visual_timer = max(tail_catch_visual_timer - delta, 0.0)
	sprint_noise_timer = max(sprint_noise_timer - delta, 0.0)
	_update_stamina(delta)

	match state:
		PlayerState.GRAPPLING:
			_update_grapple_motion(delta)
		PlayerState.GRAPPLE_PULL:
			_update_grapple_pull_motion(delta)
		PlayerState.TAIL_HANG:
			_update_tail_hang(delta)
		PlayerState.WALL_LEFT, PlayerState.WALL_RIGHT, PlayerState.CEILING:
			_update_surface_crawl(delta)
		_:
			_update_platformer_motion(delta)

	_update_visual_orientation()
	_update_debug_state_label()
	_update_noise_emission(fall_speed_before_motion)
	queue_redraw()

func set_movement_state(new_state, surface_normal = Vector2.ZERO, contact_point = Vector2.ZERO) -> void:
	var previous_state = state

	if state == PlayerState.TAIL_HANG and new_state != PlayerState.TAIL_HANG:
		_clear_tail_data()

	if new_state != PlayerState.GRAPPLING:
		is_grappling = false

	if new_state != PlayerState.GRAPPLE_PULL:
		is_grapple_pulling = false

	if not _is_surface_state(new_state):
		attached_normal = Vector2.ZERO
		attached_contact_point = Vector2.ZERO

	state = new_state

	if _is_surface_state(state):
		attached_normal = _cardinalize_surface_normal(surface_normal)
		attached_contact_point = contact_point
		if attached_contact_point == Vector2.ZERO:
			attached_contact_point = global_position + attached_normal * tail_min_length
		is_grappling = false
		if state == PlayerState.CEILING:
			ceiling_contact_grace_timer = ceiling_contact_grace_time
		else:
			ceiling_contact_grace_timer = 0.0

	if state == PlayerState.GRAPPLING:
		attached_normal = Vector2.ZERO
		attached_contact_point = Vector2.ZERO
		is_grappling = true
		ceiling_contact_grace_timer = 0.0

	if state == PlayerState.GRAPPLE_PULL:
		attached_normal = Vector2.ZERO
		attached_contact_point = Vector2.ZERO
		is_grapple_pulling = true
		ceiling_contact_grace_timer = 0.0

	if state != PlayerState.CEILING:
		ceiling_contact_grace_timer = 0.0

	if _is_surface_state(previous_state) and _is_surface_state(state) and previous_state != state:
		surface_transition_lock_timer = surface_transition_lock_time

	if state == PlayerState.GRAPPLING or state == PlayerState.GRAPPLE_PULL or state == PlayerState.TAIL_HANG or _is_surface_state(state):
		coyote_timer = 0.0

	_update_debug_state_label()

func _update_platformer_motion(delta: float) -> void:
	var input_axis = _get_horizontal_input()
	var on_ground = is_on_floor()
	var wants_jump = _jump_pressed()

	if on_ground:
		set_movement_state(PlayerState.GROUNDED)
		coyote_timer = coyote_time
	else:
		set_movement_state(PlayerState.AIRBORNE)
		velocity.y = min(velocity.y + gravity * delta, max_fall_speed)

	if wants_jump and (on_ground or coyote_timer > 0.0):
		velocity.y = jump_velocity
		coyote_timer = 0.0
		set_movement_state(PlayerState.AIRBORNE)

	if not is_zero_approx(input_axis):
		var acceleration = ground_acceleration if on_ground else air_acceleration
		var target_speed = _get_target_horizontal_speed(input_axis, on_ground)
		velocity.x = move_toward(velocity.x, input_axis * target_speed, acceleration * delta)
		facing_direction = int(sign(input_axis))
	else:
		if on_ground:
			velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)

	move_and_slide()
	if _try_ground_to_wall_corner_transition(input_axis):
		return
	if _try_surface_capture_assist(delta):
		return
	_try_attach_from_contacts()

func _update_surface_crawl(delta: float) -> void:
	if _jump_pressed():
		_jump_away_from_surface()
		move_and_slide()
		return

	if state == PlayerState.CEILING and _get_vertical_crawl_input() < 0.0:
		_start_tail_hang()
		return

	var previous_state = state
	var along_surface = _get_surface_tangent()
	var along_input = _get_surface_input()
	if is_zero_approx(along_input) and surface_corner_carry_timer > 0.0:
		along_input = surface_corner_carry_velocity.dot(along_surface)
	var adhesion = -attached_normal * surface_adhesion_strength
	velocity = along_surface * along_input + adhesion

	if state == PlayerState.CEILING and not is_zero_approx(along_input):
		facing_direction = int(sign(along_input))

	if _try_surface_corner_transition(previous_state, delta):
		move_and_slide()
		_hold_attached_surface(delta)
		return

	move_and_slide()

	if _try_surface_corner_transition(previous_state, delta):
		return

	if not _refresh_attached_contact():
		if capture_commit_timer > 0.0 and _confirm_committed_surface():
			return
		if _hold_attached_surface(delta):
			return
		if previous_state == PlayerState.CEILING:
			print("CEILING EXIT: SURFACE_LOST")
		set_movement_state(PlayerState.AIRBORNE)

func _update_tail_hang(delta: float) -> void:
	if _jump_pressed():
		_detach_tail(true)
		move_and_slide()
		return

	var vertical_input = _get_vertical_crawl_input()
	var next_length = tail_length
	if vertical_input < 0.0:
		next_length += tail_extend_speed * delta
	elif vertical_input > 0.0:
		next_length -= tail_retract_speed * delta
	tail_length = clamp(next_length, tail_min_length, tail_max_length)

	var target_position = tail_anchor + Vector2.DOWN * tail_length
	var to_target = target_position - global_position
	if to_target.length() <= 1.0:
		velocity = Vector2.ZERO
	else:
		velocity = to_target.limit_length(tail_follow_speed * delta) / max(delta, 0.001)

	move_and_slide()

	if vertical_input > 0.0 and tail_length <= tail_min_length + 0.5:
		set_movement_state(PlayerState.CEILING, Vector2.DOWN, tail_anchor)
		velocity = Vector2.ZERO

func _update_grapple_motion(delta: float) -> void:
	velocity.y = min(velocity.y + gravity * delta, max_fall_speed)

	var input_axis = _get_horizontal_input()
	if not is_zero_approx(input_axis):
		velocity.x += input_axis * grapple_air_control * delta
		facing_direction = int(sign(input_axis))

	var to_anchor = grapple_anchor - global_position
	var distance = to_anchor.length()
	if distance > 1.0:
		var direction = to_anchor / distance
		var stretch = max(distance - grapple_length, 0.0)
		var pull_scale = clamp(distance / max(grapple_max_length, 1.0), 0.25, 1.35)
		var pull = direction * grapple_pull_force * pull_scale
		var spring = direction * stretch * grapple_spring_strength
		var damping = -velocity.dot(direction) * grapple_damping * direction
		velocity += (pull + spring + damping) * delta

		if distance > grapple_length:
			var radial_velocity = velocity.dot(direction)
			if radial_velocity < 0.0:
				var tangent_velocity = velocity - direction * radial_velocity
				velocity = tangent_velocity + direction * radial_velocity * 0.35

	velocity = velocity.limit_length(grapple_max_speed)
	move_and_slide()
	_try_surface_capture_assist(delta)

func _update_grapple_pull_motion(delta: float) -> void:
	grapple_pull_timer += delta
	var to_anchor = grapple_pull_anchor - global_position
	var distance = to_anchor.length()

	if distance <= grapple_stop_distance or grapple_pull_timer >= grapple_max_duration:
		_finish_grapple_pull()
		return

	var direction = to_anchor / max(distance, 0.001)
	var target_velocity = direction * grapple_pull_speed
	velocity = velocity.move_toward(target_velocity, grapple_acceleration * delta)
	if abs(direction.x) > 0.1:
		facing_direction = int(sign(direction.x))

	move_and_slide()
	if _try_surface_capture_assist(delta):
		return

	if get_slide_collision_count() > 0:
		_try_attach_from_contacts()
		if _is_surface_state(state):
			_clear_tongue_grapple_pull_for_surface_attach()

func _try_surface_corner_transition(previous_state, _delta: float) -> bool:
	if surface_transition_lock_timer > 0.0:
		return false

	match previous_state:
		PlayerState.WALL_LEFT, PlayerState.WALL_RIGHT:
			if _wants_wall_to_floor_transition():
				var floor_hit = _find_floor_for_wall_corner(previous_state)
				if not floor_hit.is_empty():
					var wall_to_floor_sprint = Input.is_action_pressed("sprint") and current_stamina > 0.0
					var floor_speed = sprint_move_speed if wall_to_floor_sprint else normal_move_speed
					var floor_direction = 1.0 if previous_state == PlayerState.WALL_LEFT else -1.0
					set_movement_state(PlayerState.GROUNDED)
					velocity = Vector2(floor_direction * floor_speed, surface_adhesion_strength)
					capture_commit_timer = surface_capture_commit_time
					surface_transition_lock_timer = surface_transition_lock_time
					_set_surface_corner_carry(velocity)
					print("SURFACE TRANSITION: ", _get_state_label(previous_state), " -> GROUNDED")
					return true
			return _try_wall_to_ceiling_corner_transition(previous_state)
		PlayerState.CEILING:
			var horizontal_input = _get_horizontal_input()
			if not _wants_ceiling_to_wall_transition(horizontal_input):
				return false
			var wall_hit = _find_wall_for_ceiling_corner(horizontal_input)
			if wall_hit.is_empty():
				return false
			var target_state = _state_from_normal(wall_hit["normal"])
			if not _is_intended_ceiling_wall_state(horizontal_input, target_state):
				return false
			var ceiling_to_wall_sprint = Input.is_action_pressed("sprint") and current_stamina > 0.0
			var wall_speed = wall_sprint_speed if ceiling_to_wall_sprint else wall_crawl_speed
			_align_to_captured_surface(wall_hit)
			set_movement_state(target_state, wall_hit["normal"], wall_hit["position"])
			velocity = Vector2(-attached_normal.x * surface_adhesion_strength, wall_speed)
			capture_commit_timer = surface_capture_commit_time
			surface_transition_lock_timer = surface_transition_lock_time
			_set_surface_corner_carry(velocity)
			print("SURFACE TRANSITION: CEILING -> ", _get_state_label(target_state))
			return true
	return false

func _try_ground_to_wall_corner_transition(horizontal_input: float) -> bool:
	if surface_transition_lock_timer > 0.0:
		return false
	if not is_on_floor() or is_zero_approx(horizontal_input):
		return false
	var wall_hit = _find_wall_in_direction(sign(horizontal_input), ground_corner_capture_distance)
	if wall_hit.is_empty():
		return false
	var target_state = _state_from_normal(wall_hit["normal"])
	if not _is_surface_state(target_state):
		return false
	_align_to_captured_surface(wall_hit)
	set_movement_state(target_state, wall_hit["normal"], wall_hit["position"])
	var ground_to_wall_sprint = Input.is_action_pressed("sprint") and current_stamina > 0.0
	var wall_speed = wall_sprint_speed if ground_to_wall_sprint else wall_crawl_speed
	velocity = -attached_normal * surface_adhesion_strength + Vector2.UP * wall_speed
	capture_commit_timer = surface_capture_commit_time
	surface_transition_lock_timer = surface_transition_lock_time
	_set_surface_corner_carry(velocity)
	print("SURFACE TRANSITION: GROUNDED -> ", _get_state_label(target_state))
	return true

func _try_wall_to_ceiling_corner_transition(wall_state) -> bool:
	if surface_transition_lock_timer > 0.0:
		return false
	if wall_state != PlayerState.WALL_LEFT and wall_state != PlayerState.WALL_RIGHT:
		return false
	if not _wants_wall_to_ceiling_transition():
		return false
	var ceiling_hit = _find_ceiling_for_wall_corner(wall_state)
	if ceiling_hit.is_empty():
		return false
	_align_to_captured_surface(ceiling_hit)
	var wall_to_ceiling_sprint = Input.is_action_pressed("sprint") and current_stamina > 0.0
	var ceiling_speed = ceiling_sprint_speed if wall_to_ceiling_sprint else ceiling_crawl_speed
	set_movement_state(PlayerState.CEILING, ceiling_hit["normal"], ceiling_hit["position"])
	var ceiling_direction = _get_ceiling_corner_exit_direction(wall_state)
	velocity = Vector2(ceiling_direction * ceiling_speed, -surface_adhesion_strength)
	capture_commit_timer = surface_capture_commit_time
	ceiling_contact_grace_timer = ceiling_contact_grace_time
	surface_transition_lock_timer = surface_transition_lock_time
	_set_surface_corner_carry(velocity)
	print("SURFACE TRANSITION: ", _get_state_label(wall_state), " -> CEILING")
	return true

func _wants_wall_to_ceiling_transition() -> bool:
	if _get_vertical_crawl_input() <= 0.0:
		return false
	return velocity.dot(Vector2.UP) >= -20.0

func _wants_wall_to_floor_transition() -> bool:
	if _get_vertical_crawl_input() >= 0.0:
		return false
	return velocity.dot(Vector2.DOWN) >= -20.0

func _wants_ceiling_to_wall_transition(horizontal_input: float) -> bool:
	if is_zero_approx(horizontal_input):
		return false
	var intended_direction = Vector2.RIGHT * sign(horizontal_input)
	return velocity.dot(intended_direction) >= -20.0

func _is_intended_ceiling_wall_state(horizontal_input: float, target_state) -> bool:
	if horizontal_input > 0.0:
		return target_state == PlayerState.WALL_RIGHT
	if horizontal_input < 0.0:
		return target_state == PlayerState.WALL_LEFT
	return false

func _get_state_label(check_state) -> String:
	match check_state:
		PlayerState.GROUNDED:
			return "GROUNDED"
		PlayerState.AIRBORNE:
			return "AIRBORNE"
		PlayerState.WALL_LEFT:
			return "WALL_LEFT"
		PlayerState.WALL_RIGHT:
			return "WALL_RIGHT"
		PlayerState.CEILING:
			return "CEILING"
		PlayerState.TAIL_HANG:
			return "TAIL_HANG"
		PlayerState.GRAPPLING:
			return "GRAPPLING"
		PlayerState.GRAPPLE_PULL:
			return "GRAPPLE_PULL"
	return "UNKNOWN"

func _set_surface_corner_carry(carry_velocity: Vector2) -> void:
	surface_corner_carry_velocity = carry_velocity
	surface_corner_carry_timer = surface_corner_carry_time

func _try_surface_capture_assist(delta: float) -> bool:
	if capture_rearm_timer > 0.0 or reattach_timer > 0.0:
		return false
	if state != PlayerState.AIRBORNE and state != PlayerState.GRAPPLING and state != PlayerState.GRAPPLE_PULL:
		return false
	if velocity.length() < 45.0:
		return false

	var capture_hit = _get_capture_contact_from_slides()
	if capture_hit.is_empty():
		capture_hit = _find_surface_capture_hit()
	if capture_hit.is_empty():
		return false

	var normal = capture_hit["normal"]
	var target_state = _state_from_normal(normal)
	if not _is_surface_state(target_state):
		return false

	_show_tail_catch_visual(capture_hit["position"])
	HumanNoiseEvents.emit_noise(self, capture_hit["position"], grapple_pull_noise_loudness, grapple_pull_noise_radius, &"surface_attach")
	_align_to_captured_surface(capture_hit)
	set_movement_state(target_state, normal, capture_hit["position"])
	velocity = _get_surface_attach_velocity(normal)
	capture_commit_timer = surface_capture_commit_time
	capture_rearm_timer = surface_capture_rearm_delay
	_clear_tongue_grapple_for_surface_attach()
	_clear_tongue_grapple_pull_for_surface_attach()
	return true

func _get_capture_contact_from_slides() -> Dictionary:
	for index in range(get_slide_collision_count()):
		var collision = get_slide_collision(index)
		var normal = collision.get_normal()
		if _is_floor_normal(normal):
			continue
		if _is_attachable_normal(normal) and _is_moving_toward_surface(normal):
			return {
				"normal": normal,
				"position": collision.get_position(),
			}
	return {}

func _find_surface_capture_hit() -> Dictionary:
	var candidates = []
	if velocity.y < -35.0:
		var ceiling_hit = _find_ceiling_in_reach(ceiling_capture_distance + airborne_ceiling_grab_extra_distance)
		if _is_ceiling_hit(ceiling_hit) and _is_moving_toward_surface(ceiling_hit["normal"]):
			candidates.append(ceiling_hit)

	if velocity.x < -35.0:
		var left_origin = global_position + Vector2(-BODY_HALF_WIDTH, 0.0)
		var left_hit = _raycast_level_surface(left_origin, left_origin + Vector2.LEFT * wall_capture_distance)
		if _is_wall_hit(left_hit) and _is_moving_toward_surface(left_hit["normal"]):
			candidates.append(left_hit)

	if velocity.x > 35.0:
		var right_origin = global_position + Vector2(BODY_HALF_WIDTH, 0.0)
		var right_hit = _raycast_level_surface(right_origin, right_origin + Vector2.RIGHT * wall_capture_distance)
		if _is_wall_hit(right_hit) and _is_moving_toward_surface(right_hit["normal"]):
			candidates.append(right_hit)

	if candidates.is_empty():
		return {}

	candidates.sort_custom(func(a, b):
		var a_normal = a["normal"]
		var b_normal = b["normal"]
		var a_score = -velocity.normalized().dot(a_normal)
		var b_score = -velocity.normalized().dot(b_normal)
		if velocity.y < -35.0:
			if a_normal.y > CEILING_NORMAL_THRESHOLD:
				a_score += 0.2
			if b_normal.y > CEILING_NORMAL_THRESHOLD:
				b_score += 0.2
		return a_score > b_score
	)
	return candidates[0]

func _is_moving_toward_surface(surface_normal: Vector2) -> bool:
	return velocity.dot(surface_normal) < -35.0

func _align_to_captured_surface(hit: Dictionary) -> void:
	var normal = _cardinalize_surface_normal(hit["normal"])
	var hit_position = hit["position"]
	var body_radius = _get_surface_body_radius(normal)
	var desired_position = hit_position + normal * (body_radius + surface_attach_offset)
	var offset = normal * (desired_position - global_position).dot(normal)
	var max_snap = max(wall_capture_distance, ceiling_capture_distance) + surface_attach_offset + 2.0
	if abs(offset.dot(normal)) <= max_snap:
		global_position += offset

func _get_surface_body_radius(normal: Vector2) -> float:
	if abs(normal.x) > abs(normal.y):
		return BODY_HALF_WIDTH
	return BODY_HALF_HEIGHT

func _confirm_committed_surface() -> bool:
	var probe_distance = surface_attach_offset + 5.0
	var probe_from = global_position
	var probe_to = global_position - attached_normal * (_get_surface_body_radius(attached_normal) + probe_distance)
	var hit = _raycast_level_surface(probe_from, probe_to)
	if hit.is_empty():
		return false
	var normal = hit["normal"]
	if normal.dot(attached_normal) <= 0.72:
		return false
	attached_contact_point = hit["position"]
	_align_to_captured_surface(hit)
	if state == PlayerState.CEILING:
		ceiling_contact_grace_timer = ceiling_contact_grace_time
	return true

func _hold_attached_surface(delta: float) -> bool:
	if state == PlayerState.CEILING:
		return _hold_ceiling_contact(delta)

	var hit = _find_attached_surface_hold_hit()
	if hit.is_empty():
		return false

	attached_normal = _cardinalize_surface_normal(hit["normal"])
	attached_contact_point = hit["position"]
	_align_to_captured_surface(hit)
	return true

func _find_attached_surface_hold_hit() -> Dictionary:
	if state != PlayerState.WALL_LEFT and state != PlayerState.WALL_RIGHT:
		return {}
	var normal = attached_normal
	if normal == Vector2.ZERO:
		return {}
	return _find_surface_hold_hit(normal)

func _hold_ceiling_contact(delta: float) -> bool:
	var hit = _find_ceiling_hold_hit()
	if not hit.is_empty():
		attached_normal = _cardinalize_surface_normal(hit["normal"])
		attached_contact_point = hit["position"]
		ceiling_contact_grace_timer = ceiling_contact_grace_time
		_align_to_captured_surface(hit)
		_remove_ceiling_outward_velocity()
		return true

	ceiling_contact_grace_timer = max(ceiling_contact_grace_timer - delta, 0.0)
	if ceiling_contact_grace_timer > 0.0:
		_remove_ceiling_outward_velocity()
		return true
	return false

func _find_ceiling_hold_hit() -> Dictionary:
	var normal = attached_normal
	if normal == Vector2.ZERO:
		normal = Vector2.DOWN
	return _find_surface_hold_hit(normal, ceiling_hold_check_distance)

func _find_surface_hold_hit(normal: Vector2, extra_distance: float = -1.0) -> Dictionary:
	var cardinal_normal = _cardinalize_surface_normal(normal)
	if cardinal_normal == Vector2.ZERO:
		return {}
	var tangent = _get_tangent_for_normal(cardinal_normal)
	var body_radius = _get_surface_body_radius(cardinal_normal)
	var tangent_radius = BODY_HALF_HEIGHT if abs(cardinal_normal.x) > abs(cardinal_normal.y) else BODY_HALF_WIDTH
	var probe_distance = body_radius + surface_attach_offset + surface_hold_probe_extra_distance
	if extra_distance >= 0.0:
		probe_distance = body_radius + surface_attach_offset + max(extra_distance, surface_hold_probe_extra_distance)
	var spread = tangent_radius * surface_hold_probe_spread
	var probe_offsets = [
		Vector2.ZERO,
		tangent * spread,
		-tangent * spread,
		tangent * spread * 0.5,
		-tangent * spread * 0.5,
	]
	for probe_offset in probe_offsets:
		var probe_from = global_position + probe_offset
		var probe_to = probe_from - cardinal_normal * probe_distance
		var hit = _raycast_level_surface(probe_from, probe_to)
		if hit.is_empty():
			continue
		var hit_normal = _cardinalize_surface_normal(hit["normal"])
		if hit_normal.dot(cardinal_normal) > 0.72:
			return hit
	return {}

func _get_surface_attach_velocity(surface_normal: Vector2) -> Vector2:
	var normal = _cardinalize_surface_normal(surface_normal)
	var tangent = _get_tangent_for_normal(normal)
	var tangent_component = tangent * velocity.dot(tangent)
	var adhesion = -normal * surface_adhesion_strength
	return tangent_component + adhesion

func _remove_ceiling_outward_velocity() -> void:
	if state != PlayerState.CEILING:
		return
	var normal = attached_normal
	if normal == Vector2.ZERO:
		normal = Vector2.DOWN
	var outward_speed = velocity.dot(normal)
	if outward_speed > 0.0:
		velocity -= normal * outward_speed

func _show_tail_catch_visual(catch_point: Vector2) -> void:
	tail_catch_visual_point = catch_point
	tail_catch_visual_timer = 0.12

func _clear_tongue_grapple_for_surface_attach() -> void:
	is_grappling = false
	grapple_anchor = Vector2.ZERO
	grapple_length = 0.0
	if tongue and tongue.has_method("clear_grapple_without_player_release"):
		tongue.clear_grapple_without_player_release()

func _clear_tongue_grapple_pull_for_surface_attach() -> void:
	is_grapple_pulling = false
	grapple_pull_anchor = Vector2.ZERO
	grapple_pull_timer = 0.0
	if tongue and tongue.has_method("clear_grapple_pull_without_player_release"):
		tongue.clear_grapple_pull_without_player_release()

func _find_ceiling_for_wall_corner(wall_state) -> Dictionary:
	var exit_direction = _get_ceiling_corner_exit_direction(wall_state)
	var search_distance = max(wall_ceiling_corner_probe_distance, ceiling_capture_distance)
	var side = Vector2.RIGHT * exit_direction
	var probes = [
		global_position + Vector2(0.0, -BODY_HALF_HEIGHT),
		global_position + Vector2(exit_direction * BODY_HALF_WIDTH * 0.35, -BODY_HALF_HEIGHT),
		global_position + Vector2(exit_direction * BODY_HALF_WIDTH * 0.85, -BODY_HALF_HEIGHT),
		global_position + Vector2(exit_direction * BODY_HALF_WIDTH * 1.25, -BODY_HALF_HEIGHT),
		global_position + Vector2(exit_direction * BODY_HALF_WIDTH * 1.25, -BODY_HALF_HEIGHT * 0.45),
		global_position + Vector2(exit_direction * BODY_HALF_WIDTH * 0.35, -BODY_HALF_HEIGHT * 0.72),
		global_position + Vector2(-exit_direction * BODY_HALF_WIDTH * 0.25, -BODY_HALF_HEIGHT * 0.72),
	]

	for probe_origin in probes:
		var hit = _raycast_level_surface(probe_origin, probe_origin + Vector2.UP * search_distance)
		if _is_ceiling_hit(hit):
			return hit
		hit = _raycast_level_surface(probe_origin, probe_origin + (Vector2.UP + side).normalized() * search_distance)
		if _is_ceiling_hit(hit):
			return hit

	for index in range(get_slide_collision_count()):
		var collision = get_slide_collision(index)
		var normal = collision.get_normal()
		if normal.y > CEILING_NORMAL_THRESHOLD:
			return {"normal": normal, "position": collision.get_position()}
	return {}

func _find_ceiling_in_reach(distance: float) -> Dictionary:
	var probes = [
		global_position + Vector2(0.0, -BODY_HALF_HEIGHT),
		global_position + Vector2(-BODY_HALF_WIDTH * 0.75, -BODY_HALF_HEIGHT),
		global_position + Vector2(BODY_HALF_WIDTH * 0.75, -BODY_HALF_HEIGHT),
		global_position + Vector2(-BODY_HALF_WIDTH * 0.35, -BODY_HALF_HEIGHT),
		global_position + Vector2(BODY_HALF_WIDTH * 0.35, -BODY_HALF_HEIGHT),
	]
	for probe_origin in probes:
		var hit = _raycast_level_surface(probe_origin, probe_origin + Vector2.UP * distance)
		if _is_ceiling_hit(hit):
			return hit
	return {}

func _get_ceiling_corner_exit_direction(wall_state) -> float:
	return 1.0 if wall_state == PlayerState.WALL_LEFT else -1.0

func _find_wall_for_ceiling_corner(horizontal_input: float) -> Dictionary:
	var direction = sign(horizontal_input)
	var hit = _find_wall_in_direction(direction, surface_corner_snap_distance)
	if not hit.is_empty():
		return hit
	var side = 1.0 if direction > 0.0 else -1.0
	var search_distance = max(surface_corner_snap_distance, wall_capture_distance + BODY_HALF_WIDTH)
	var probes = [
		global_position + Vector2(side * BODY_HALF_WIDTH, -BODY_HALF_HEIGHT),
		global_position + Vector2(side * BODY_HALF_WIDTH, -BODY_HALF_HEIGHT * 0.55),
		global_position + Vector2(side * BODY_HALF_WIDTH * 1.2, -BODY_HALF_HEIGHT),
		global_position + Vector2(side * BODY_HALF_WIDTH * 1.2, 0.0),
	]
	for probe_origin in probes:
		hit = _raycast_level_surface(probe_origin, probe_origin + Vector2.RIGHT * side * search_distance)
		if _is_wall_hit(hit):
			return hit

	for index in range(get_slide_collision_count()):
		var collision = get_slide_collision(index)
		var normal = collision.get_normal()
		if abs(normal.x) > WALL_NORMAL_THRESHOLD:
			return {"normal": normal, "position": collision.get_position()}
	return {}

func _find_wall_in_direction(direction: float, distance: float) -> Dictionary:
	if is_zero_approx(direction):
		return {}
	var side = 1.0 if direction > 0.0 else -1.0
	var search_distance = max(distance, ground_corner_capture_distance)
	var probes = [
		global_position + Vector2(side * BODY_HALF_WIDTH, 0.0),
		global_position + Vector2(side * BODY_HALF_WIDTH, -BODY_HALF_HEIGHT * 0.7),
		global_position + Vector2(side * BODY_HALF_WIDTH, BODY_HALF_HEIGHT * 0.55),
		global_position + Vector2(side * BODY_HALF_WIDTH, -BODY_HALF_HEIGHT),
		global_position + Vector2(side * BODY_HALF_WIDTH * 1.2, BODY_HALF_HEIGHT),
		global_position + Vector2(side * BODY_HALF_WIDTH * 1.2, -BODY_HALF_HEIGHT * 1.05),
	]
	for probe_origin in probes:
		var hit = _raycast_level_surface(probe_origin, probe_origin + Vector2.RIGHT * side * search_distance)
		if _is_wall_hit(hit):
			return hit
	return {}

func _find_floor_for_wall_corner(wall_state) -> Dictionary:
	var side = -1.0 if wall_state == PlayerState.WALL_RIGHT else 1.0
	var probes = [
		global_position + Vector2(0.0, BODY_HALF_HEIGHT),
		global_position + Vector2(side * BODY_HALF_WIDTH * 0.65, BODY_HALF_HEIGHT),
		global_position + Vector2(side * BODY_HALF_WIDTH, BODY_HALF_HEIGHT * 0.5),
		global_position + Vector2(side * BODY_HALF_WIDTH * 1.2, BODY_HALF_HEIGHT),
		global_position + Vector2(side * BODY_HALF_WIDTH * 1.2, BODY_HALF_HEIGHT * 0.25),
	]
	for probe_origin in probes:
		var hit = _raycast_level_surface(probe_origin, probe_origin + Vector2.DOWN * surface_corner_snap_distance)
		if _is_floor_hit(hit):
			return hit
	for index in range(get_slide_collision_count()):
		var collision = get_slide_collision(index)
		var normal = collision.get_normal()
		if _is_floor_normal(normal):
			return {"normal": normal, "position": collision.get_position()}
	return {}

func _raycast_level_surface(from: Vector2, to: Vector2) -> Dictionary:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider = hit.get("collider")
	if collider is StaticBody2D or (collider is Node and collider.is_in_group("grapple_surface")):
		return hit
	return {}

func _is_ceiling_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var normal = hit.get("normal", Vector2.ZERO)
	return normal.y > CEILING_NORMAL_THRESHOLD

func _is_wall_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var normal = hit.get("normal", Vector2.ZERO)
	return abs(normal.x) > WALL_NORMAL_THRESHOLD

func _is_floor_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	return _is_floor_normal(hit.get("normal", Vector2.ZERO))

func _try_attach_from_contacts() -> void:
	if reattach_timer > 0.0:
		return

	var contact = _get_attachable_contact()
	if contact.is_empty():
		return

	set_movement_state(_state_from_normal(contact["normal"]), contact["normal"], contact["position"])

func _get_attachable_contact() -> Dictionary:
	for index in range(get_slide_collision_count()):
		var collision = get_slide_collision(index)
		var normal = collision.get_normal()
		if _is_floor_normal(normal):
			continue
		if _is_attachable_normal(normal):
			return {
				"normal": normal,
				"position": collision.get_position(),
			}
	return {}

func _refresh_attached_contact() -> bool:
	for index in range(get_slide_collision_count()):
		var collision = get_slide_collision(index)
		var normal = collision.get_normal()
		if normal.dot(attached_normal) > 0.72:
			attached_normal = _cardinalize_surface_normal(normal)
			attached_contact_point = collision.get_position()
			if state == PlayerState.CEILING:
				ceiling_contact_grace_timer = ceiling_contact_grace_time
			return true
	return false

func _jump_away_from_surface() -> void:
	match state:
		PlayerState.WALL_LEFT:
			velocity = Vector2(wall_jump_horizontal_velocity, wall_jump_vertical_velocity)
		PlayerState.WALL_RIGHT:
			velocity = Vector2(-wall_jump_horizontal_velocity, wall_jump_vertical_velocity)
		PlayerState.CEILING:
			velocity = Vector2(velocity.x, ceiling_detach_velocity)
		_:
			velocity = Vector2.ZERO

	reattach_timer = surface_reattach_delay
	set_movement_state(PlayerState.AIRBORNE)

func start_grapple(anchor: Vector2, requested_length: float) -> void:
	if state == PlayerState.CEILING:
		return
	grapple_anchor = anchor
	grapple_length = clamp(requested_length, 24.0, grapple_max_length)
	reattach_timer = surface_reattach_delay
	set_movement_state(PlayerState.GRAPPLING)

func start_grapple_pull(anchor: Vector2) -> bool:
	var origin = get_tongue_origin_global()
	if origin.distance_to(anchor) > grapple_range:
		return false

	if state == PlayerState.TAIL_HANG:
		_clear_tail_data()

	grapple_pull_anchor = anchor
	grapple_pull_timer = 0.0
	reattach_timer = 0.0
	capture_rearm_timer = 0.0
	capture_commit_timer = 0.0
	set_movement_state(PlayerState.GRAPPLE_PULL)
	return true

func cancel_grapple_pull() -> void:
	if state != PlayerState.GRAPPLE_PULL and not is_grapple_pulling:
		return
	_finish_grapple_pull()

func _finish_grapple_pull() -> void:
	var saved_velocity = velocity * grapple_exit_speed_multiplier
	is_grapple_pulling = false
	grapple_pull_anchor = Vector2.ZERO
	grapple_pull_timer = 0.0
	set_movement_state(PlayerState.AIRBORNE)
	velocity = saved_velocity
	_clear_tongue_grapple_pull_for_surface_attach()
	_try_surface_capture_assist(0.0)

func release_grapple() -> void:
	if state != PlayerState.GRAPPLING and not is_grappling:
		return

	_apply_grapple_release_lift()
	is_grappling = false
	grapple_anchor = Vector2.ZERO
	grapple_length = 0.0
	set_movement_state(PlayerState.AIRBORNE)

func _apply_grapple_release_lift() -> void:
	var speed = velocity.length()
	if speed < grapple_release_speed_threshold:
		return

	var lift = clamp((speed - grapple_release_speed_threshold) * grapple_release_lift, 0.0, grapple_release_lift_max)
	if velocity.y < -grapple_release_lift_max:
		return

	var available_lift = grapple_release_lift_max + min(velocity.y, 0.0)
	velocity.y -= min(lift, max(available_lift, 0.0))

func _start_tail_hang() -> void:
	tail_anchor = attached_contact_point
	if tail_anchor == Vector2.ZERO:
		tail_anchor = global_position + Vector2.UP * tail_min_length
	tail_length = clamp(tail_anchor.distance_to(global_position), tail_min_length, tail_max_length)
	set_movement_state(PlayerState.TAIL_HANG)
	velocity = Vector2.ZERO

func _detach_tail(preserve_velocity: bool) -> void:
	var saved_velocity = velocity
	set_movement_state(PlayerState.AIRBORNE)
	if preserve_velocity:
		velocity = saved_velocity
	reattach_timer = surface_reattach_delay

func _clear_tail_data() -> void:
	tail_anchor = Vector2.ZERO
	tail_length = tail_min_length

func _get_surface_tangent() -> Vector2:
	match state:
		PlayerState.WALL_LEFT, PlayerState.WALL_RIGHT:
			return Vector2.UP
		PlayerState.CEILING:
			return Vector2.RIGHT
	return Vector2.ZERO

func _get_tangent_for_normal(normal: Vector2) -> Vector2:
	if abs(normal.x) > abs(normal.y):
		return Vector2.UP
	return Vector2.RIGHT

func _get_surface_input() -> float:
	match state:
		PlayerState.WALL_LEFT, PlayerState.WALL_RIGHT:
			return _get_vertical_crawl_input() * _get_wall_crawl_speed()
		PlayerState.CEILING:
			return _get_horizontal_input() * _get_ceiling_crawl_speed()
	return 0.0

func _state_from_normal(normal: Vector2):
	if normal.y > CEILING_NORMAL_THRESHOLD:
		return PlayerState.CEILING
	if normal.x > WALL_NORMAL_THRESHOLD:
		return PlayerState.WALL_LEFT
	if normal.x < -WALL_NORMAL_THRESHOLD:
		return PlayerState.WALL_RIGHT
	return PlayerState.AIRBORNE

func _cardinalize_surface_normal(normal: Vector2) -> Vector2:
	if normal.y > CEILING_NORMAL_THRESHOLD and abs(normal.y) >= abs(normal.x):
		return Vector2.DOWN
	if normal.x > WALL_NORMAL_THRESHOLD:
		return Vector2.RIGHT
	if normal.x < -WALL_NORMAL_THRESHOLD:
		return Vector2.LEFT
	return normal.normalized()

func _is_surface_state(check_state) -> bool:
	return check_state == PlayerState.WALL_LEFT or check_state == PlayerState.WALL_RIGHT or check_state == PlayerState.CEILING

func _update_stamina(delta: float) -> void:
	var draining = _is_sprinting()
	if draining:
		current_stamina = max(current_stamina - sprint_stamina_drain_rate * delta, 0.0)
		stamina_regen_timer = stamina_regeneration_delay
		stamina_bar_visible_timer = stamina_bar_hide_delay
	elif current_stamina < max_stamina:
		stamina_regen_timer = max(stamina_regen_timer - delta, 0.0)
		stamina_bar_visible_timer = stamina_bar_hide_delay
		if stamina_regen_timer <= 0.0:
			current_stamina = min(current_stamina + stamina_regeneration_rate * delta, max_stamina)
	else:
		stamina_bar_visible_timer = max(stamina_bar_visible_timer - delta, 0.0)

func _is_sprinting() -> bool:
	if not Input.is_action_pressed("sprint") or current_stamina <= 0.0:
		return false
	if state == PlayerState.GROUNDED:
		return is_on_floor() and not is_zero_approx(_get_horizontal_input())
	if state == PlayerState.WALL_LEFT or state == PlayerState.WALL_RIGHT:
		return not is_zero_approx(_get_vertical_crawl_input())
	if state == PlayerState.CEILING:
		return not is_zero_approx(_get_horizontal_input())
	return false

func _is_sprinting_on_ground() -> bool:
	return (
		state == PlayerState.GROUNDED
		and is_on_floor()
		and Input.is_action_pressed("sprint")
		and not is_zero_approx(_get_horizontal_input())
		and current_stamina > 0.0
	)

func _is_sprint_crawling() -> bool:
	return (
		Input.is_action_pressed("sprint")
		and current_stamina > 0.0
		and (
			((state == PlayerState.WALL_LEFT or state == PlayerState.WALL_RIGHT) and not is_zero_approx(_get_vertical_crawl_input()))
			or (state == PlayerState.CEILING and not is_zero_approx(_get_horizontal_input()))
		)
	)

func _get_wall_crawl_speed() -> float:
	return wall_sprint_speed if _is_sprint_crawling() else wall_crawl_speed

func _get_ceiling_crawl_speed() -> float:
	return ceiling_sprint_speed if _is_sprint_crawling() else ceiling_crawl_speed

func _get_target_horizontal_speed(input_axis: float, on_ground: bool) -> float:
	if on_ground:
		return sprint_move_speed if _is_sprinting_on_ground() else normal_move_speed
	if sign(input_axis) == sign(velocity.x) and abs(velocity.x) > normal_move_speed:
		return abs(velocity.x)
	return normal_move_speed

func _is_attachable_normal(normal: Vector2) -> bool:
	return abs(normal.x) >= WALL_NORMAL_THRESHOLD or normal.y >= CEILING_NORMAL_THRESHOLD

func _is_floor_normal(normal: Vector2) -> bool:
	return normal.y <= -FLOOR_NORMAL_THRESHOLD

func _add_collision() -> void:
	if get_node_or_null("CollisionShape2D"):
		return
	var collision = CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var capsule = CapsuleShape2D.new()
	capsule.radius = 18.0
	capsule.height = 52.0
	collision.shape = capsule
	collision.position = Vector2(0, 2)
	add_child(collision)

func _add_visuals() -> void:
	frog_visual = get_node_or_null("Visuals") as Node2D
	if frog_visual:
		return
	frog_visual = PlayerVisualScene.instantiate() as Node2D
	frog_visual.name = "Visuals"
	add_child(frog_visual)

func _add_tongue() -> void:
	tongue = get_node_or_null("Tongue") as Node2D
	if tongue:
		tongue.player = self
		return
	tongue = TongueScene.instantiate() as Node2D
	tongue.name = "Tongue"
	tongue.player = self
	add_child(tongue)

func _add_camera() -> void:
	var camera = get_node_or_null("Camera2D") as Camera2D
	if not camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		add_child(camera)
	camera.name = "Camera2D"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.zoom = Vector2(1.0, 1.0)
	camera.make_current()

func _add_debug_state_label() -> void:
	debug_state_label = get_node_or_null("DebugStateLabel") as Label
	if debug_state_label:
		return
	debug_state_label = Label.new()
	debug_state_label.name = "DebugStateLabel"
	debug_state_label.position = Vector2(-70, -78)
	debug_state_label.size = Vector2(140, 20)
	debug_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	debug_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	debug_state_label.add_theme_color_override("font_color", Color("#d7f7cf"))
	debug_state_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	debug_state_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_state_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(debug_state_label)

func _update_visual_orientation() -> void:
	if not frog_visual:
		return
	if frog_visual.has_method("update_from_player"):
		frog_visual.update_from_player(self)
		return

	match state:
		PlayerState.WALL_LEFT:
			frog_visual.rotation = -PI * 0.5
			frog_visual.scale.x = 1
		PlayerState.WALL_RIGHT:
			frog_visual.rotation = PI * 0.5
			frog_visual.scale.x = 1
		PlayerState.CEILING, PlayerState.TAIL_HANG:
			frog_visual.rotation = PI
			frog_visual.scale.x = facing_direction
		_:
			frog_visual.rotation = 0.0
			frog_visual.scale.x = facing_direction

func _update_debug_state_label() -> void:
	if not debug_state_label:
		return
	debug_state_label.visible = show_debug_state_label
	debug_state_label.text = _get_state_name()

func _update_noise_emission(fall_speed_before_motion: float) -> void:
	if Input.is_action_just_pressed("debug_noise"):
		HumanNoiseEvents.emit_noise(self, global_position, 1.0, debug_noise_radius, &"debug")
	if _is_sprinting() and sprint_noise_timer <= 0.0:
		HumanNoiseEvents.emit_noise(self, global_position, sprint_noise_loudness, sprint_noise_radius, &"sprint")
		sprint_noise_timer = sprint_noise_interval
	if is_on_floor() and not was_on_floor_last_frame and fall_speed_before_motion >= hard_landing_speed_threshold:
		HumanNoiseEvents.emit_noise(self, global_position, hard_landing_noise_loudness, hard_landing_noise_radius, &"hard_landing")
	was_on_floor_last_frame = is_on_floor()

func _get_state_name() -> String:
	var suffix = " [SPRINT]" if _is_sprinting() else ""
	if capture_commit_timer > 0.0 and _is_surface_state(state):
		suffix += " [CAPTURE]"
	if surface_transition_lock_timer > 0.0 and _is_surface_state(state):
		suffix += " [LOCK]"
	match state:
		PlayerState.GROUNDED:
			return "GROUNDED" + suffix
		PlayerState.AIRBORNE:
			return "AIRBORNE"
		PlayerState.WALL_LEFT:
			return "WALL_LEFT" + suffix
		PlayerState.WALL_RIGHT:
			return "WALL_RIGHT" + suffix
		PlayerState.CEILING:
			return "CEILING" + suffix
		PlayerState.TAIL_HANG:
			return "TAIL_HANG"
		PlayerState.GRAPPLING:
			return "GRAPPLING"
		PlayerState.GRAPPLE_PULL:
			return "GRAPPLE_PULL"
	return "UNKNOWN"

func _draw() -> void:
	if state == PlayerState.TAIL_HANG and tail_anchor != Vector2.ZERO:
		var local_anchor = to_local(tail_anchor)
		draw_line(local_anchor, Vector2.ZERO, Color("#4f5f4b"), 4.0)
		draw_circle(local_anchor, 5.0, Color("#4f5f4b"))
	elif tail_catch_visual_timer > 0.0 and tail_catch_visual_point != Vector2.ZERO:
		var local_catch = to_local(tail_catch_visual_point)
		draw_line(local_catch, Vector2.ZERO, Color("#6f805f"), 3.0)
		draw_circle(local_catch, 4.0, Color("#6f805f"))

	if _should_draw_stamina_bar():
		var bar_size = Vector2(46, 6)
		var bar_position = Vector2(-bar_size.x * 0.5, -58.0)
		var ratio = current_stamina / max(max_stamina, 1.0)
		draw_rect(Rect2(bar_position, bar_size), Color(0.04, 0.05, 0.05, 0.75))
		draw_rect(Rect2(bar_position + Vector2.ONE, Vector2((bar_size.x - 2.0) * ratio, bar_size.y - 2.0)), Color("#90d95a"))

func _should_draw_stamina_bar() -> bool:
	return current_stamina < max_stamina or stamina_bar_visible_timer > 0.0

func get_tongue_origin_global() -> Vector2:
	if frog_visual:
		return frog_visual.to_global(tongue_origin)
	return to_global(Vector2(tongue_origin.x * facing_direction, tongue_origin.y))

func get_runner_x() -> float:
	return global_position.x

func is_pizza_on_cargo(_pizza: RigidBody2D) -> bool:
	return false

func _get_horizontal_input() -> float:
	return Input.get_axis("move_left", "move_right")

func _get_vertical_crawl_input() -> float:
	var axis = 0.0
	if Input.is_action_pressed("move_up"):
		axis += 1.0
	if Input.is_action_pressed("move_down"):
		axis -= 1.0
	return clamp(axis, -1.0, 1.0)

func _jump_pressed() -> bool:
	return Input.is_action_just_pressed("surface_jump") or Input.is_action_just_pressed("jump")
