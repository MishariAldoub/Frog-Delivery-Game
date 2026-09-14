extends Area2D
class_name RoomArea

@export var room_name = ""
@export var camera_anchor = Vector2.ZERO
@export var use_bounds_center_for_camera = true
@export var camera_zoom = Vector2.ZERO
@export var auto_fit_camera_to_bounds = true
@export var camera_padding = Vector2(120.0, 120.0)
@export_range(1.0, 1.5, 0.01) var camera_context_scale = 1.15
@export var min_auto_zoom = 0.55
@export var max_auto_zoom = 1.35
@export var transition_time_override = -1.0
@export var unexplored_color = Color(0.0, 0.0, 0.0, 0.94)
@export var show_debug = false
@export var debug_color = Color(0.55, 0.95, 1.0, 0.45)
@export var show_camera_preview = true
@export var camera_preview_viewport_size = Vector2(1280.0, 720.0)
@export var camera_preview_color = Color(1.0, 0.72, 0.28, 0.65)
@export var visited = false:
	set(value):
		visited = value
		_update_overlay_visibility()

var is_active_room = false
var _darkness_overlay: Polygon2D
var _debug_label: Label

func _ready() -> void:
	add_to_group("room_area")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	_build_darkness_overlay()
	_build_debug_label()
	_update_overlay_visibility()
	queue_redraw()

func contains_global_point(point: Vector2, margin: float = 0.0) -> bool:
	var bounds = _get_margin_bounds(margin)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		bounds = get_local_bounds()
	return bounds.has_point(to_local(point))

func mark_visited() -> void:
	visited = true

func set_active(active: bool) -> void:
	if is_active_room == active:
		return
	is_active_room = active
	queue_redraw()

func get_camera_global_position() -> Vector2:
	var local_position = camera_anchor
	if use_bounds_center_for_camera:
		local_position += get_local_bounds().get_center()
	return to_global(local_position)

func get_camera_zoom(viewport_size: Vector2) -> Vector2:
	if camera_zoom != Vector2.ZERO:
		return camera_zoom
	if not auto_fit_camera_to_bounds:
		return Vector2.ONE

	var target_size = (get_local_bounds().size + camera_padding) * camera_context_scale
	var zoom_value = min(
		viewport_size.x / max(target_size.x, 1.0),
		viewport_size.y / max(target_size.y, 1.0)
	)
	zoom_value = clamp(zoom_value, min_auto_zoom, max_auto_zoom)
	return Vector2(zoom_value, zoom_value)

func get_transition_time(default_transition_time: float) -> float:
	if transition_time_override >= 0.0:
		return transition_time_override
	return default_transition_time

func get_camera_visible_rect(viewport_size: Vector2) -> Rect2:
	var zoom = get_camera_zoom(viewport_size)
	var visible_size = Vector2(
		viewport_size.x / max(zoom.x, 0.001),
		viewport_size.y / max(zoom.y, 0.001)
	)
	var camera_center = to_local(get_camera_global_position())
	return Rect2(camera_center - visible_size * 0.5, visible_size)

func get_local_bounds() -> Rect2:
	var collision_shape = _get_bounds_collision()
	if not collision_shape:
		return Rect2(Vector2.ZERO, Vector2.ONE)

	var rectangle = collision_shape.shape as RectangleShape2D
	if not rectangle:
		return Rect2(Vector2.ZERO, Vector2.ONE)

	return Rect2(collision_shape.position - rectangle.size * 0.5, rectangle.size)

func _get_margin_bounds(margin: float) -> Rect2:
	var bounds = get_local_bounds()
	if is_zero_approx(margin):
		return bounds
	return Rect2(
		bounds.position + Vector2.ONE * margin,
		bounds.size - Vector2.ONE * margin * 2.0
	)

func _get_bounds_collision() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return child
	return null

func _build_darkness_overlay() -> void:
	if _darkness_overlay:
		return

	var bounds = get_local_bounds()
	_darkness_overlay = Polygon2D.new()
	_darkness_overlay.name = "UnexploredOverlay"
	_darkness_overlay.z_index = 100
	_darkness_overlay.color = unexplored_color
	_darkness_overlay.polygon = PackedVector2Array([
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	])
	add_child(_darkness_overlay)

func _build_debug_label() -> void:
	if _debug_label:
		return

	var bounds = get_local_bounds()
	_debug_label = Label.new()
	_debug_label.name = "DebugLabel"
	_debug_label.z_index = 101
	_debug_label.position = bounds.position + Vector2(12.0, 10.0)
	_debug_label.size = Vector2(260.0, 24.0)
	_debug_label.text = room_name if not room_name.is_empty() else name
	_debug_label.add_theme_color_override("font_color", Color(0.75, 1.0, 1.0, 0.95))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_debug_label)

func _update_overlay_visibility() -> void:
	if _darkness_overlay:
		_darkness_overlay.visible = not visited

func _draw() -> void:
	if not show_debug:
		if _debug_label:
			_debug_label.visible = false
		return

	if _debug_label:
		_debug_label.visible = true

	var bounds = get_local_bounds()
	var outline_color = Color(0.95, 0.96, 0.45, 0.85) if is_active_room else debug_color
	draw_rect(bounds, Color(outline_color.r, outline_color.g, outline_color.b, 0.08), true)
	draw_rect(bounds, outline_color, false, 3.0)
	draw_circle(to_local(get_camera_global_position()), 8.0, outline_color)

	if show_camera_preview:
		draw_rect(get_camera_visible_rect(camera_preview_viewport_size), camera_preview_color, false, 2.0)
