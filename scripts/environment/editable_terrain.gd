@tool
extends StaticBody2D

## Whitebox terrain polygon. Edit these points in the Inspector, then press
## Sync Visuals And Collision if needed. Polygon2D and CollisionPolygon2D use
## this same point list.
@export var points: PackedVector2Array = PackedVector2Array([
	Vector2(-300, 0),
	Vector2(300, 0),
	Vector2(300, 160),
	Vector2(-300, 160),
]):
	set(value):
		points = value
		_apply_points()

## Editor helper: turn this on to copy the current Polygon2D shape back into
## the exported points array, then sync collision. It resets itself to false.
@export var sync_from_polygon_now := false:
	set(value):
		if value:
			sync_from_polygon()
		sync_from_polygon_now = false

@export var fill_color := Color("#5a3f2b"):
	set(value):
		fill_color = value
		_apply_points()

@onready var polygon_2d: Polygon2D = $Polygon2D
@onready var collision_polygon_2d: CollisionPolygon2D = $CollisionPolygon2D

func _ready() -> void:
	_apply_points()

func sync_from_polygon() -> void:
	if not is_inside_tree():
		return
	var visual := get_node_or_null("Polygon2D") as Polygon2D
	if visual:
		points = visual.polygon
	_apply_points()

func sync_visuals_and_collision() -> void:
	_apply_points()

func _apply_points() -> void:
	if not is_inside_tree():
		return

	var visual := get_node_or_null("Polygon2D") as Polygon2D
	var collision := get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if visual:
		visual.polygon = points
		visual.color = fill_color
	if collision:
		collision.polygon = points
