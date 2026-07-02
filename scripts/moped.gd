extends RigidBody2D

@export var acceleration := 4000
@export var reverse_acceleration := 2000
@export var brake_strength := 1350.0
@export var max_forward_speed := 5000
@export var max_reverse_speed := 3000
@export var lean_acceleration := 20
@export var lean_torque := 48000.0
@export var max_angular_speed := 7.5

@export_group("Pizza Caddy")
## Total outside width of the rear pizza tray.
@export var caddy_width := 100
## Height of the front/rear tray walls. Around 80-90 is forgiving without becoming a tall basket.
@export var caddy_wall_height := 72
## Thickness of the front/rear tray walls.
@export var caddy_wall_thickness := 13
## Thickness of the tray floor collision.
@export var caddy_floor_thickness := 24.0
## Small invisible inward lips near the top that catch pizzas during normal ramp tilts.
@export var caddy_top_lip_size := Vector2(20, 8)
## Partial cover pieces that make the caddy behave like a shallow pizza delivery slot.
@export var caddy_cover_size := Vector2(34, 10)
## Extra X offset for the rear/back wall. Use small values to fine-tune corner overlap.
@export var caddy_rear_wall_x_offset := 0.0
## Extra X offset for the front wall near the frog. Use small values to fine-tune corner overlap.
@export var caddy_front_wall_x_offset := 0.0

var wheel_spin := 0.0

const CADDY_CENTER_X := -48.0
const CADDY_FLOOR_CENTER_Y := -39.0

func _ready() -> void:
	mass = 6.2
	gravity_scale = 1.35
	linear_damp = 0.03
	angular_damp = 1.15
	contact_monitor = true
	max_contacts_reported = 8
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
	var velocity := linear_velocity

	if throttle_pressed:
		velocity.x = min(velocity.x + acceleration * delta, max_forward_speed)
		# The first press must always produce visible motion, even if the bike is nudged into terrain.
		if velocity.x < 75.0:
			velocity.x = 75.0

	if brake_pressed:
		if velocity.x > 20.0:
			velocity.x = move_toward(velocity.x, 0.0, brake_strength * delta)
		else:
			velocity.x = max(velocity.x - reverse_acceleration * delta, -max_reverse_speed)

	linear_velocity = velocity

	var lean := Input.get_axis("lean_left", "lean_right")
	if _is_pressed("lean_left", KEY_A):
		lean -= 1.0
	if _is_pressed("lean_right", KEY_D):
		lean += 1.0
	lean = clamp(lean, -1.0, 1.0)

	# Torque keeps the lean physical; angular velocity control makes it arcade-responsive.
	apply_torque(lean * lean_torque)
	angular_velocity = clamp(angular_velocity + lean * lean_acceleration * delta, -max_angular_speed, max_angular_speed)

	wheel_spin += linear_velocity.x * delta * 0.05
	queue_redraw()

func _is_pressed(action_name: String, fallback_key: Key) -> bool:
	return Input.is_action_pressed(action_name) or Input.is_key_pressed(fallback_key)

func _build_pizza_caddy_collision() -> void:
	_add_rect_collision("PizzaCaddyFloor", Vector2(CADDY_CENTER_X, CADDY_FLOOR_CENTER_Y), Vector2(caddy_width, caddy_floor_thickness))
	_add_rect_collision("PizzaCaddyRearWall", Vector2(get_caddy_rear_wall_x(), get_caddy_wall_center_y()), Vector2(caddy_wall_thickness, caddy_wall_height))
	_add_rect_collision("PizzaCaddyFrontWall", Vector2(get_caddy_front_wall_x(), get_caddy_wall_center_y()), Vector2(caddy_wall_thickness, caddy_wall_height))
	_add_rect_collision("PizzaCaddyRearTopLip", Vector2(get_caddy_inner_left_x() + caddy_top_lip_size.x * 0.5, get_caddy_top_y() + caddy_top_lip_size.y * 0.5), caddy_top_lip_size)
	_add_rect_collision("PizzaCaddyFrontTopLip", Vector2(get_caddy_inner_right_x() - caddy_top_lip_size.x * 0.5, get_caddy_top_y() + caddy_top_lip_size.y * 0.5), caddy_top_lip_size)
	_add_rect_collision("PizzaCaddyRearCover", Vector2(get_caddy_inner_left_x() + caddy_cover_size.x * 0.5, get_caddy_top_y() + caddy_cover_size.y * 0.5), caddy_cover_size)
	_add_rect_collision("PizzaCaddyFrontCover", Vector2(get_caddy_inner_right_x() - caddy_cover_size.x * 0.5, get_caddy_top_y() + caddy_cover_size.y * 0.5), caddy_cover_size)

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
	draw_rect(Rect2(Vector2(get_caddy_inner_left_x(), get_caddy_top_y()), caddy_cover_size), Color("#9b6847"))
	draw_rect(Rect2(Vector2(get_caddy_inner_right_x() - caddy_cover_size.x, get_caddy_top_y()), caddy_cover_size), Color("#9b6847"))
	draw_line(Vector2(18, -32), Vector2(45, -72), Color("#272727"), 6.0)
	draw_line(Vector2(45, -72), Vector2(72, -67), Color("#272727"), 5.0)
	draw_circle(Vector2(-42, 0), 22.0, Color("#161616"))
	draw_circle(Vector2(54, 0), 22.0, Color("#161616"))
	draw_circle(Vector2(-42, 0), 11.0, Color("#d6d1bd"))
	draw_circle(Vector2(54, 0), 11.0, Color("#d6d1bd"))
	draw_line(Vector2(-42, 0), Vector2(-42 + cos(wheel_spin) * 18.0, sin(wheel_spin) * 18.0), Color("#f1ead2"), 3.0)
	draw_line(Vector2(54, 0), Vector2(54 + cos(wheel_spin) * 18.0, sin(wheel_spin) * 18.0), Color("#f1ead2"), 3.0)
