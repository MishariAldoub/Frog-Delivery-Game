extends Node2D

const TILE_SIZE = 32.0
const TILE_SOURCE = "res://assets/tileset/tile%03d.png"

@export var hide_placeholder_polygons := true
@export var target_group := "grapple_surface"
@export var horizontal_top_tile := 14
@export var horizontal_middle_tile := 44
@export var horizontal_bottom_tile := 74
@export var vertical_left_tile := 40
@export var vertical_middle_tile := 45
@export var vertical_right_tile := 49

var _textures: Dictionary = {}

func _ready() -> void:
	call_deferred("_reskin_existing_surfaces")

func _reskin_existing_surfaces() -> void:
	var root := get_parent()
	if not root:
		return

	for child in root.get_children():
		var body := child as StaticBody2D
		if not body or not body.is_in_group(target_group):
			continue
		_reskin_surface(body)

func _reskin_surface(body: StaticBody2D) -> void:
	var collision := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not collision or not (collision.shape is RectangleShape2D):
		return

	var placeholder := body.get_node_or_null("Visual") as CanvasItem
	if placeholder and hide_placeholder_polygons:
		placeholder.visible = false

	var old_tiles := body.get_node_or_null("TileVisuals")
	if old_tiles:
		body.remove_child(old_tiles)
		old_tiles.queue_free()

	var container := Node2D.new()
	container.name = "TileVisuals"
	container.z_index = -1
	body.add_child(container)

	var rect := collision.shape as RectangleShape2D
	var size := rect.size
	var columns := maxi(1, ceili(size.x / TILE_SIZE))
	var rows := maxi(1, ceili(size.y / TILE_SIZE))
	var origin := collision.position - size * 0.5
	var vertical_surface := size.y > size.x

	for y in range(rows):
		for x in range(columns):
			var sprite := Sprite2D.new()
			sprite.texture = _get_texture(_pick_tile(x, y, columns, rows, vertical_surface))
			sprite.centered = false
			sprite.position = origin + Vector2(x, y) * TILE_SIZE
			container.add_child(sprite)

func _pick_tile(x: int, y: int, columns: int, rows: int, vertical_surface: bool) -> int:
	if vertical_surface:
		if x == 0:
			return vertical_left_tile
		if x == columns - 1:
			return vertical_right_tile
		return vertical_middle_tile

	if y == 0:
		return horizontal_top_tile
	if y == rows - 1:
		return horizontal_bottom_tile
	return horizontal_middle_tile

func _get_texture(tile_index: int) -> Texture2D:
	if _textures.has(tile_index):
		return _textures[tile_index]
	var texture := load(TILE_SOURCE % tile_index) as Texture2D
	_textures[tile_index] = texture
	return texture
