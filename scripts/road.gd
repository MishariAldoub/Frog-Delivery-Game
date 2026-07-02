extends Node2D

@export var finish_x := 4300.0

var terrain_points: PackedVector2Array

func _ready() -> void:
	terrain_points = _make_terrain()
	_build_collision()
	queue_redraw()

func _make_terrain() -> PackedVector2Array:
	var points := PackedVector2Array()
	var x := -300.0
	while x <= finish_x + 500.0:
		var y := 520.0
		y -= _bump(x, 600.0, 18.0)
		y -= _bump(x, 720.0, 25.0)
		if x > 900.0 and x < 1350.0:
			y -= sin((x - 900.0) / 450.0 * PI) * 72.0
		y -= _bump(x, 1510.0, 28.0)
		y -= _bump(x, 1620.0, 22.0)
		if x > 1900.0 and x < 2180.0:
			y -= _smooth_step((x - 1900.0) / 280.0) * 105.0
		if x > 2180.0 and x < 2380.0:
			y = lerp(415.0, 545.0, _smooth_step((x - 2180.0) / 200.0))
		if x > 2600.0 and x < 3220.0:
			y += _smooth_step((x - 2600.0) / 620.0) * 95.0
		if x > 3300.0 and x < 3720.0:
			y += 95.0
			y -= sin((x - 3300.0) / 420.0 * PI) * 58.0
		points.append(Vector2(x, y))
		x += 24.0
	return points

func _bump(x: float, center: float, height: float) -> float:
	var width := 64.0
	var t = clamp(1.0 - abs(x - center) / width, 0.0, 1.0)
	return sin(t * PI * 0.5) * height

func _smooth_step(t: float) -> float:
	var clamped = clamp(t, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "RoadCollision"
	add_child(body)

	for i in range(terrain_points.size() - 1):
		var segment := CollisionShape2D.new()
		var shape := SegmentShape2D.new()
		shape.a = terrain_points[i]
		shape.b = terrain_points[i + 1]
		segment.shape = shape
		body.add_child(segment)

	var finish_area := Area2D.new()
	finish_area.name = "FinishLine"
	finish_area.position = Vector2(finish_x, 340)
	add_child(finish_area)

	var finish_shape_node := CollisionShape2D.new()
	var finish_shape := RectangleShape2D.new()
	finish_shape.size = Vector2(20, 360)
	finish_shape_node.shape = finish_shape
	finish_area.add_child(finish_shape_node)

func _draw() -> void:
	if terrain_points.is_empty():
		return

	var fill := PackedVector2Array(terrain_points)
	var last_point := terrain_points[terrain_points.size() - 1]
	fill.append(Vector2(last_point.x, 760))
	fill.append(Vector2(terrain_points[0].x, 760))
	draw_colored_polygon(fill, Color("#5a3f2b"))

	for i in range(terrain_points.size() - 1):
		draw_line(terrain_points[i], terrain_points[i + 1], Color("#304047"), 10.0)
		draw_line(terrain_points[i] + Vector2(0, 6), terrain_points[i + 1] + Vector2(0, 6), Color("#6f5842"), 6.0)

	draw_rect(Rect2(Vector2(finish_x - 10, 250), Vector2(20, 280)), Color("#eeeeee"))
	for y in range(250, 530, 28):
		var offset := 0 if (int(y / 28) % 2 == 0) else 10
		draw_rect(Rect2(Vector2(finish_x - 10 + offset, y), Vector2(10, 14)), Color.BLACK)
		draw_rect(Rect2(Vector2(finish_x + offset, y + 14), Vector2(10, 14)), Color.BLACK)
