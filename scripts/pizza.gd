extends RigidBody2D

@export var size := Vector2(58, 13)

func _ready() -> void:
	mass = 0.48
	gravity_scale = 1.2
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector2(0, 4)
	linear_damp = 0.04
	angular_damp = 0.42
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = 1
	collision_mask = 1
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 1.25
	physics_material_override.bounce = 0.0

	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape
	add_child(shape_node)

func _physics_process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, Color("#d88c24"))
	draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6)), Color("#ffd45a"))
	draw_line(Vector2(-size.x * 0.5 + 4, 0), Vector2(size.x * 0.5 - 4, 0), Color("#c46e1f"), 2.0)
	draw_rect(Rect2(Vector2(-17, -4), Vector2(6, 4)), Color("#b43a2d"))
	draw_rect(Rect2(Vector2(6, 0), Vector2(6, 4)), Color("#b43a2d"))
	draw_rect(Rect2(Vector2(18, -4), Vector2(5, 4)), Color("#5aa35f"))
