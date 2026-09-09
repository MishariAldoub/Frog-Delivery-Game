extends Node2D

@export var finish_x := 4300.0:
	set(value):
		finish_x = value
		_update_finish_line()
@export var use_unified_terrain_collision := true
@export var show_collision_debug := false:
	set(value):
		show_collision_debug = value
		_update_collision_debug()

const TERRAIN_COLLIDER_NAME := "UnifiedTerrainCollision"
const TERRAIN_DEBUG_NAME := "TerrainCollisionDebug"
const TERRAIN_BOTTOM_Y := 760.0

func _ready() -> void:
	_rebuild_terrain_collision()
	_update_finish_line()

func _rebuild_terrain_collision() -> void:
	if not is_inside_tree():
		return

	var terrain_nodes := _get_terrain_nodes()
	for terrain in terrain_nodes:
		var chunk_collision := terrain.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
		if chunk_collision:
			chunk_collision.disabled = use_unified_terrain_collision

	var existing_collision := get_node_or_null(TERRAIN_COLLIDER_NAME)
	if existing_collision:
		remove_child(existing_collision)
		existing_collision.queue_free()

	if not use_unified_terrain_collision:
		_update_collision_debug()
		return

	var top_points := _get_continuous_terrain_top_points(terrain_nodes)
	if top_points.size() < 2:
		_update_collision_debug()
		return

	var terrain_body := StaticBody2D.new()
	terrain_body.name = TERRAIN_COLLIDER_NAME
	terrain_body.collision_layer = 1
	terrain_body.collision_mask = 1
	add_child(terrain_body)

	var collision_shape := CollisionPolygon2D.new()
	collision_shape.name = "CollisionPolygon2D"
	collision_shape.polygon = _make_solid_terrain_polygon(top_points)
	terrain_body.add_child(collision_shape)
	_update_collision_debug()

func _get_terrain_nodes() -> Array[Node]:
	var terrain_nodes: Array[Node] = []
	for child in get_children():
		if child == get_node_or_null(TERRAIN_COLLIDER_NAME) or child == get_node_or_null(TERRAIN_DEBUG_NAME):
			continue
		if child is StaticBody2D and child.has_method("sync_visuals_and_collision"):
			terrain_nodes.append(child)

	terrain_nodes.sort_custom(func(a: Node, b: Node) -> bool:
		return _get_leftmost_point_x(a.points) < _get_leftmost_point_x(b.points)
	)
	return terrain_nodes

func _get_leftmost_point_x(points: PackedVector2Array) -> float:
	var left := INF
	for point in points:
		left = min(left, point.x)
	return left

func _get_continuous_terrain_top_points(terrain_nodes: Array[Node]) -> PackedVector2Array:
	var top_points := PackedVector2Array()
	for terrain in terrain_nodes:
		var chunk_points: PackedVector2Array = terrain.points
		if chunk_points.size() < 2:
			continue

		var chunk_top := _get_top_edge_points(chunk_points)
		for point in chunk_top:
			if top_points.size() > 0 and top_points[top_points.size() - 1].distance_to(point) <= 0.05:
				continue
			top_points.append(point)
	return top_points

func _get_top_edge_points(points: PackedVector2Array) -> PackedVector2Array:
	var bottom_start := -1
	for index in range(points.size()):
		if is_equal_approx(points[index].y, TERRAIN_BOTTOM_Y):
			bottom_start = index
			break

	if bottom_start <= 0:
		return points

	var top := PackedVector2Array()
	for index in range(bottom_start):
		top.append(points[index])
	return top

func _make_solid_terrain_polygon(top_points: PackedVector2Array) -> PackedVector2Array:
	var polygon := PackedVector2Array(top_points)
	var last_top := top_points[top_points.size() - 1]
	var first_top := top_points[0]
	polygon.append(Vector2(last_top.x, TERRAIN_BOTTOM_Y))
	polygon.append(Vector2(first_top.x, TERRAIN_BOTTOM_Y))
	return polygon

func _update_finish_line() -> void:
	if not is_inside_tree():
		return

	var finish_area := get_node_or_null("FinishLine") as Area2D
	if not finish_area:
		finish_area = Area2D.new()
		finish_area.name = "FinishLine"
		add_child(finish_area)

		var finish_shape_node := CollisionShape2D.new()
		finish_shape_node.name = "CollisionShape2D"
		var finish_shape := RectangleShape2D.new()
		finish_shape.size = Vector2(20, 360)
		finish_shape_node.shape = finish_shape
		finish_area.add_child(finish_shape_node)

	finish_area.position = Vector2(finish_x, 340)

func _update_collision_debug() -> void:
	if not is_inside_tree():
		return

	var existing_debug := get_node_or_null(TERRAIN_DEBUG_NAME)
	if existing_debug:
		existing_debug.queue_free()

	if not show_collision_debug or not use_unified_terrain_collision:
		return

	var terrain_body := get_node_or_null(TERRAIN_COLLIDER_NAME)
	if not terrain_body:
		return

	var collision_shape := terrain_body.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if not collision_shape:
		return

	var debug_line := Line2D.new()
	debug_line.name = TERRAIN_DEBUG_NAME
	debug_line.default_color = Color(0.1, 0.85, 1.0, 0.9)
	debug_line.width = 4.0
	debug_line.z_index = 100
	for point in collision_shape.polygon:
		debug_line.add_point(point)
	debug_line.add_point(collision_shape.polygon[0])
	add_child(debug_line)
