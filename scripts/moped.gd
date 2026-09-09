extends RigidBody2D

@export_group("Handling")
@export var acceleration := 1550.0
@export var reverse_acceleration := 900.0
@export var brake_strength := 1350.0
@export var max_forward_speed := 5000.0
@export var max_reverse_speed := 3000.0
@export var ground_lean_torque := 32000.0
@export var air_lean_torque := 52000.0
@export var ground_lean_acceleration := 3.2
@export var air_lean_acceleration := 6.5
@export var max_ground_angular_speed := 3.6
@export var max_air_angular_speed := 5.6
@export var active_ground_lean_angular_damp := 1.35
@export_range(0.0, 1.0, 0.05) var airborne_control_multiplier := 0.35

@export_group("Body Weight")
@export var moped_mass := 9.5
@export var moped_gravity_scale := 1.45
@export var ground_linear_damp := 0.09
@export var air_linear_damp := 0.035
@export var ground_angular_damp := 2.65
@export var air_angular_damp := 1.65
@export var angular_inertia := 22000.0
@export var landing_settle_time := 0.18
@export var landing_linear_damp := 0.22
@export var landing_angular_damp := 3.4

@export_group("Pizza Caddy")
## Total outside width of the rear pizza tray.
@export var caddy_width := 100
## Height of the front/rear tray walls. Around 80-90 is forgiving without becoming a tall basket.
@export var caddy_wall_height := 60
## Thickness of the front/rear tray walls.
@export var caddy_wall_thickness := 13
## Thickness of the tray floor collision.
@export var caddy_floor_thickness := 24.0
## Small invisible inward lips near the top that catch pizzas during normal ramp tilts.
@export var caddy_top_lip_size := Vector2(0, 0)
## Extra X offset for the rear/back wall. Use small values to fine-tune corner overlap.
@export var caddy_rear_wall_x_offset := 0.0
## Extra X offset for the front wall near the frog. Use small values to fine-tune corner overlap.
@export var caddy_front_wall_x_offset := 0.0

var wheel_spin := 0.0
var was_grounded := false
var landing_settle_timer := 0.0

const CADDY_CENTER_X := -48.0
const CADDY_FLOOR_CENTER_Y := -39.0

func _ready() -> void:
	mass = moped_mass
	gravity_scale = moped_gravity_scale
	linear_damp = ground_linear_damp
	angular_damp = ground_angular_damp
	inertia = angular_inertia
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	collision_layer = 1
	collision_mask = 1
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 1.35
	physics_material_override.bounce = 0.0

	var body_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(122, 26)
	body_shape.shape = rect
	body_shape.position = Vector2(0, -18)
	add_child(body_shape)

	_build_pizza_caddy_collision()

	for wheel_x in [-48.0, 56.0]:
		var wheel_shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 23.0
		wheel_shape.shape = circle
		wheel_shape.position = Vector2(wheel_x, 0)
		add_child(wheel_shape)

func _physics_process(delta: float) -> void:
	var throttle_pressed := _is_pressed("accelerate", KEY_W)
	var brake_pressed := _is_pressed("brake_reverse", KEY_S)
	var lean := _get_lean_input()
	var grounded := _is_grounded()
	if grounded and not was_grounded:
		landing_settle_timer = landing_settle_time
	was_grounded = grounded
	landing_settle_timer = max(landing_settle_timer - delta, 0.0)
	_update_body_damping(grounded, lean)

	if throttle_pressed:
		_apply_engine_force(acceleration, max_forward_speed, grounded)

	if brake_pressed:
		var velocity := linear_velocity
		if velocity.x > 20.0:
			velocity.x = move_toward(velocity.x, 0.0, brake_strength * delta)
		else:
			velocity.x = max(velocity.x - reverse_acceleration * delta, -max_reverse_speed)
		linear_velocity = velocity

	_apply_lean_control(lean, grounded, delta)

	wheel_spin += linear_velocity.x * delta * 0.05
	queue_redraw()

func _get_lean_input() -> float:
	var lean := Input.get_axis("lean_left", "lean_right")
	if _is_pressed("lean_left", KEY_A):
		lean -= 1.0
	if _is_pressed("lean_right", KEY_D):
		lean += 1.0
	return clamp(lean, -1.0, 1.0)

func _apply_engine_force(throttle_acceleration: float, speed_limit: float, grounded: bool) -> void:
	var forward := Vector2.RIGHT.rotated(rotation)
	var forward_speed := linear_velocity.dot(forward)
	if forward_speed >= speed_limit:
		return

	var control_multiplier := 1.0 if grounded else airborne_control_multiplier
	var speed_factor = clamp(1.0 - forward_speed / speed_limit, 0.18, 1.0)
	apply_central_force(forward * throttle_acceleration * mass * control_multiplier * speed_factor)

func _apply_lean_control(lean: float, grounded: bool, delta: float) -> void:
	if is_zero_approx(lean):
		return

	var torque := ground_lean_torque if grounded else air_lean_torque
	var angular_acceleration := ground_lean_acceleration if grounded else air_lean_acceleration
	var angular_speed_limit := max_ground_angular_speed if grounded else max_air_angular_speed

	# A small angular velocity assist keeps lean readable, while torque carries the physical weight.
	apply_torque(lean * torque)
	angular_velocity = clamp(angular_velocity + lean * angular_acceleration * delta, -angular_speed_limit, angular_speed_limit)

func _update_body_damping(grounded: bool, lean: float) -> void:
	if landing_settle_timer > 0.0:
		linear_damp = landing_linear_damp
		angular_damp = landing_angular_damp
		return

	linear_damp = ground_linear_damp if grounded else air_linear_damp
	if grounded and not is_zero_approx(lean):
		angular_damp = active_ground_lean_angular_damp
	else:
		angular_damp = ground_angular_damp if grounded else air_angular_damp

func _is_grounded() -> bool:
	for body in get_colliding_bodies():
		if body is StaticBody2D:
			return true
	return false

func _is_pressed(action_name: String, fallback_key: Key) -> bool:
	return Input.is_action_pressed(action_name) or Input.is_key_pressed(fallback_key)

func _build_pizza_caddy_collision() -> void:
	_add_rect_collision("PizzaCaddyFloor", Vector2(CADDY_CENTER_X, CADDY_FLOOR_CENTER_Y), Vector2(caddy_width, caddy_floor_thickness))
	_add_rect_collision("PizzaCaddyRearWall", Vector2(get_caddy_rear_wall_x(), get_caddy_wall_center_y()), Vector2(caddy_wall_thickness, caddy_wall_height))
	_add_rect_collision("PizzaCaddyFrontWall", Vector2(get_caddy_front_wall_x(), get_caddy_wall_center_y()), Vector2(caddy_wall_thickness, caddy_wall_height))
	_add_rect_collision("PizzaCaddyRearTopLip", Vector2(get_caddy_inner_left_x() + caddy_top_lip_size.x * 0.5, get_caddy_top_y() + caddy_top_lip_size.y * 0.5), caddy_top_lip_size)
	_add_rect_collision("PizzaCaddyFrontTopLip", Vector2(get_caddy_inner_right_x() - caddy_top_lip_size.x * 0.5, get_caddy_top_y() + caddy_top_lip_size.y * 0.5), caddy_top_lip_size)

func _add_rect_collision(shape_name: String, local_position: Vector2, size: Vector2) -> void:
	var shape_node := CollisionShape2D.new()
	shape_node.name = shape_name
	var shape := RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = local_position
	add_child(shape_node)

func get_caddy_rear_wall_x() -> float:
	return CADDY_CENTER_X - caddy_width * 0.5 + caddy_wall_thickness * 0.5 + caddy_rear_wall_x_offset

func get_caddy_front_wall_x() -> float:
	return CADDY_CENTER_X + caddy_width * 0.5 - caddy_wall_thickness * 0.5 + caddy_front_wall_x_offset

func get_caddy_floor_top_y() -> float:
	return CADDY_FLOOR_CENTER_Y - caddy_floor_thickness * 0.5

func get_caddy_wall_center_y() -> float:
	# Walls extend through the floor thickness, closing corner gaps without making the tray tall.
	var floor_bottom_y := CADDY_FLOOR_CENTER_Y + caddy_floor_thickness * 0.5
	return floor_bottom_y - caddy_wall_height * 0.5

func get_caddy_inner_left_x() -> float:
	return get_caddy_rear_wall_x() + caddy_wall_thickness * 0.5

func get_caddy_inner_right_x() -> float:
	return get_caddy_front_wall_x() - caddy_wall_thickness * 0.5

func get_caddy_top_y() -> float:
	var floor_bottom_y := CADDY_FLOOR_CENTER_Y + caddy_floor_thickness * 0.5
	return floor_bottom_y - caddy_wall_height

func _draw() -> void:
	draw_rect(Rect2(Vector2(-61, -32), Vector2(122, 28)), Color("#d2472f"))
	draw_rect(Rect2(Vector2(CADDY_CENTER_X - caddy_width * 0.5, CADDY_FLOOR_CENTER_Y - caddy_floor_thickness * 0.5), Vector2(caddy_width, caddy_floor_thickness)), Color("#825339"))
	draw_rect(Rect2(Vector2(get_caddy_rear_wall_x() - caddy_wall_thickness * 0.5, get_caddy_wall_center_y() - caddy_wall_height * 0.5), Vector2(caddy_wall_thickness, caddy_wall_height)), Color("#825339"))
	draw_rect(Rect2(Vector2(get_caddy_front_wall_x() - caddy_wall_thickness * 0.5, get_caddy_wall_center_y() - caddy_wall_height * 0.5), Vector2(caddy_wall_thickness, caddy_wall_height)), Color("#825339"))
	draw_line(Vector2(18, -32), Vector2(45, -72), Color("#272727"), 6.0)
	draw_line(Vector2(45, -72), Vector2(72, -67), Color("#272727"), 5.0)
	draw_circle(Vector2(-42, 0), 22.0, Color("#161616"))
	draw_circle(Vector2(54, 0), 22.0, Color("#161616"))
	draw_circle(Vector2(-42, 0), 11.0, Color("#d6d1bd"))
	draw_circle(Vector2(54, 0), 11.0, Color("#d6d1bd"))
	draw_line(Vector2(-42, 0), Vector2(-42 + cos(wheel_spin) * 18.0, sin(wheel_spin) * 18.0), Color("#f1ead2"), 3.0)
	draw_line(Vector2(54, 0), Vector2(54 + cos(wheel_spin) * 18.0, sin(wheel_spin) * 18.0), Color("#f1ead2"), 3.0)
