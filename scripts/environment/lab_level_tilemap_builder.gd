extends Node2D

const TILE_SIZE := 32
const TILESET_RESOURCE := preload("res://assets/generated/lab_tileset.tres")
const ATLAS_TEXTURE := preload("res://assets/generated/lab_tileset_atlas.png")
const SCIENTIST_SCENE := preload("res://scenes/Scientist.tscn")
const ROOM_AREA_SCRIPT := preload("res://scripts/room_area.gd")
const INTEREST_POINT_SCRIPT := preload("res://scripts/ai/human_interest_point.gd")

const WALL_FILL := Vector2i(4, 4)
const WALL_FACE := Vector2i(5, 4)
const PANEL_A := Vector2i(1, 3)
const FLOOR_TOP := Vector2i(4, 1)
const FLOOR_EDGE_LEFT := Vector2i(0, 3)
const FLOOR_EDGE_RIGHT := Vector2i(3, 3)
const BACK_PANEL := Vector2i(1, 1)
const BACK_PANEL_DARK := Vector2i(2, 2)
const VENT := Vector2i(6, 4)
const PIPE := Vector2i(7, 4)
const MACHINE := Vector2i(5, 5)
const MONITOR := Vector2i(7, 5)
const SMALL_LIGHT := Vector2i(7, 8)
const HAZARD := Vector2i(6, 8)

@export var disable_legacy_level := true

var background_layer: TileMapLayer
var environment_layer: TileMapLayer
var decoration_layer: TileMapLayer
var generated_container: Node2D
var _tile_set: TileSet
var _source_id := 0

func _ready() -> void:
	if disable_legacy_level:
		_disable_legacy_level_nodes()
	_build_tileset()
	_create_generated_container()
	_create_layers()
	_paint_level()
	_create_room_areas()
	_create_navigation()
	_create_scientist_setup()

func _build_tileset() -> void:
	_tile_set = TILESET_RESOURCE.duplicate(true) as TileSet
	if not _tile_set:
		_tile_set = TileSet.new()
	_tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	while _tile_set.get_physics_layers_count() < 1:
		_tile_set.add_physics_layer()
	_tile_set.set_physics_layer_collision_layer(0, 1)
	_tile_set.set_physics_layer_collision_mask(0, 1)

	var atlas := _tile_set.get_source(0) as TileSetAtlasSource
	if not atlas:
		atlas = TileSetAtlasSource.new()
		atlas.texture = ATLAS_TEXTURE
		atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
		_source_id = _tile_set.add_source(atlas)
	else:
		_source_id = 0

	for y in range(10):
		for x in range(10):
			var coords := Vector2i(x, y)
			if not atlas.has_tile(coords):
				atlas.create_tile(coords)
			var data := atlas.get_tile_data(coords, 0)
			data.set_collision_polygons_count(0, 1)
			data.set_collision_polygon_points(0, 0, PackedVector2Array([
				Vector2(-16, -16),
				Vector2(16, -16),
				Vector2(16, 16),
				Vector2(-16, 16),
			]))

func _create_generated_container() -> void:
	generated_container = Node2D.new()
	generated_container.name = "GeneratedMechanicsPlayground"
	add_child(generated_container)

func _create_layers() -> void:
	background_layer = _new_tile_layer("BackgroundTileMap", false, -30)
	environment_layer = _new_tile_layer("EnvironmentTileMap", true, -20)
	decoration_layer = _new_tile_layer("DecorationTileMap", false, -10)

func _new_tile_layer(layer_name: String, collision_enabled: bool, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = _tile_set
	layer.collision_enabled = collision_enabled
	layer.z_index = z
	if collision_enabled:
		layer.add_to_group("grapple_surface")
	generated_container.add_child(layer)
	return layer

func _paint_level() -> void:
	_fill_background(Rect2i(-16, -12, 132, 32))

	# Room 1: readable start room with ground, simple platforms, wall and ceiling discovery.
	_paint_solid_rect(Rect2i(-14, 17, 26, 3))
	_paint_solid_rect(Rect2i(-15, 8, 2, 12))
	_paint_solid_rect(Rect2i(10, 7, 2, 13))
	_paint_solid_rect(Rect2i(-10, 13, 6, 1))
	_paint_solid_rect(Rect2i(-3, 10, 6, 1))
	_paint_solid_rect(Rect2i(2, 6, 8, 1))
	_paint_solid_rect(Rect2i(6, 12, 4, 1))

	# Room 2: ascent chamber with multiple recovery shelves and two ceiling options.
	_paint_solid_rect(Rect2i(12, 17, 17, 3))
	_paint_solid_rect(Rect2i(12, -3, 2, 20))
	_paint_solid_rect(Rect2i(27, -3, 2, 22))
	_paint_solid_rect(Rect2i(14, 13, 5, 1))
	_paint_solid_rect(Rect2i(22, 12, 5, 1))
	_paint_solid_rect(Rect2i(16, 8, 5, 1))
	_paint_solid_rect(Rect2i(22, 5, 5, 1))
	_paint_solid_rect(Rect2i(15, 1, 12, 1))
	_paint_solid_rect(Rect2i(14, -3, 13, 1))

	# Room 3: predator-overhead space, with floor patrol and solid LOS breakers.
	_paint_solid_rect(Rect2i(29, 17, 21, 3))
	_paint_solid_rect(Rect2i(29, 5, 2, 12))
	_paint_solid_rect(Rect2i(48, 5, 2, 15))
	_paint_solid_rect(Rect2i(31, 5, 17, 1))
	_paint_solid_rect(Rect2i(34, 11, 4, 1))
	_paint_solid_rect(Rect2i(42, 10, 4, 1))
	_paint_solid_rect(Rect2i(38, 13, 2, 4))
	_paint_solid_rect(Rect2i(45, 14, 3, 1))

	# Room 4: forgiving grapple and swing span, with catch walls and midair direction changes.
	_paint_solid_rect(Rect2i(50, 17, 8, 3))
	_paint_solid_rect(Rect2i(67, 17, 8, 3))
	_paint_solid_rect(Rect2i(50, 6, 2, 11))
	_paint_solid_rect(Rect2i(73, 4, 2, 16))
	_paint_solid_rect(Rect2i(53, 4, 8, 1))
	_paint_solid_rect(Rect2i(62, 2, 7, 1))
	_paint_solid_rect(Rect2i(58, 11, 3, 1))
	_paint_solid_rect(Rect2i(64, 9, 3, 1))
	_paint_solid_rect(Rect2i(69, 12, 4, 1))

	# Room 5: stealth puzzle, lower exposure route plus upper ceiling and side passage.
	_paint_solid_rect(Rect2i(75, 17, 21, 3))
	_paint_solid_rect(Rect2i(75, 5, 2, 12))
	_paint_solid_rect(Rect2i(94, 4, 2, 16))
	_paint_solid_rect(Rect2i(77, 5, 17, 1))
	_paint_solid_rect(Rect2i(82, 13, 3, 4))
	_paint_solid_rect(Rect2i(89, 12, 2, 5))
	_paint_solid_rect(Rect2i(78, 10, 5, 1))
	_paint_solid_rect(Rect2i(86, 8, 5, 1))
	_paint_solid_rect(Rect2i(92, 14, 2, 1))

	# Room 6: compact combined test using every existing traversal affordance.
	_paint_solid_rect(Rect2i(96, 17, 20, 3))
	_paint_solid_rect(Rect2i(96, 2, 2, 15))
	_paint_solid_rect(Rect2i(114, -2, 2, 22))
	_paint_solid_rect(Rect2i(98, 2, 16, 1))
	_paint_solid_rect(Rect2i(101, 13, 4, 1))
	_paint_solid_rect(Rect2i(108, 12, 4, 1))
	_paint_solid_rect(Rect2i(103, 7, 5, 1))
	_paint_solid_rect(Rect2i(110, 5, 4, 1))
	_paint_solid_rect(Rect2i(105, 9, 2, 8))
	_paint_solid_rect(Rect2i(99, -2, 15, 1))

	_paint_decor()

func _fill_background(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var tile := BACK_PANEL if (x + y) % 4 != 0 else BACK_PANEL_DARK
			_set_tile(background_layer, Vector2i(x, y), tile)

func _paint_solid_rect(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			_set_tile(environment_layer, Vector2i(x, y), _tile_for_solid_cell(x, y, rect))

func _tile_for_solid_cell(x: int, y: int, rect: Rect2i) -> Vector2i:
	var local_x := x - rect.position.x
	var local_y := y - rect.position.y
	if local_y == 0:
		if local_x == 0:
			return FLOOR_EDGE_LEFT
		if local_x == rect.size.x - 1:
			return FLOOR_EDGE_RIGHT
		return FLOOR_TOP
	if rect.size.x <= 2:
		return WALL_FACE
	return WALL_FILL if (local_x + local_y) % 2 == 0 else PANEL_A

func _paint_decor() -> void:
	for coords in [
		Vector2i(-12, 16), Vector2i(-1, 9), Vector2i(8, 11),
		Vector2i(13, 16), Vector2i(20, 7), Vector2i(26, 4),
		Vector2i(32, 16), Vector2i(47, 13), Vector2i(54, 16),
		Vector2i(71, 16), Vector2i(78, 16), Vector2i(93, 13),
		Vector2i(99, 16), Vector2i(112, 4)
	]:
		_set_tile(decoration_layer, coords, VENT)
	for coords in [Vector2i(-6, 16), Vector2i(15, 12), Vector2i(35, 16), Vector2i(80, 16), Vector2i(101, 16)]:
		_set_tile(decoration_layer, coords, MACHINE)
	for coords in [Vector2i(5, 5), Vector2i(25, 11), Vector2i(43, 16), Vector2i(88, 11), Vector2i(111, 16)]:
		_set_tile(decoration_layer, coords, MONITOR)
	for coords in [Vector2i(1, 9), Vector2i(18, 0), Vector2i(36, 4), Vector2i(59, 3), Vector2i(68, 1), Vector2i(83, 4), Vector2i(108, 1)]:
		_set_tile(decoration_layer, coords, SMALL_LIGHT)
	for coords in [Vector2i(57, 16), Vector2i(58, 16), Vector2i(67, 16), Vector2i(91, 16), Vector2i(92, 16), Vector2i(109, 16)]:
		_set_tile(decoration_layer, coords, HAZARD)
	for coords in [Vector2i(10, 9), Vector2i(27, 7), Vector2i(48, 8), Vector2i(73, 8), Vector2i(75, 9), Vector2i(94, 9), Vector2i(114, 8)]:
		_set_tile(decoration_layer, coords, PIPE)

func _create_room_areas() -> void:
	var rooms := Node2D.new()
	rooms.name = "RoomAreas"
	generated_container.add_child(rooms)
	_add_room_area(rooms, "Room1_MovementIntro", Rect2(Vector2(-480, 160), Vector2(864, 520)), Vector2(1.0, 1.0))
	_add_room_area(rooms, "Room2_VerticalTraversal", Rect2(Vector2(384, -160), Vector2(544, 840)), Vector2(0.78, 0.78))
	_add_room_area(rooms, "Room3_CeilingPredator", Rect2(Vector2(928, 128), Vector2(704, 552)), Vector2(0.92, 0.92))
	_add_room_area(rooms, "Room4_GrappleSwing", Rect2(Vector2(1600, 96), Vector2(832, 584)), Vector2(0.86, 0.86))
	_add_room_area(rooms, "Room5_StealthPuzzle", Rect2(Vector2(2400, 96), Vector2(704, 584)), Vector2(0.9, 0.9))
	_add_room_area(rooms, "Room6_CombinedMechanics", Rect2(Vector2(3072, -96), Vector2(672, 776)), Vector2(0.82, 0.82))

func _add_room_area(parent: Node, room_name: String, rect: Rect2, zoom: Vector2) -> void:
	var room := Area2D.new()
	room.name = room_name
	room.script = ROOM_AREA_SCRIPT
	room.room_name = room_name.replace("_", " ")
	room.camera_zoom = zoom
	room.auto_fit_camera_to_bounds = false
	room.position = rect.position

	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	collision.position = rect.size * 0.5
	room.add_child(collision)
	parent.add_child(room)

func _create_navigation() -> void:
	var nav := Node2D.new()
	nav.name = "Navigation"
	generated_container.add_child(nav)
	_add_nav_strip(nav, "Room3ScientistFloor", Rect2(Vector2(1024, 532), Vector2(512, 16)))
	_add_nav_strip(nav, "Room5ScientistFloor", Rect2(Vector2(2464, 532), Vector2(576, 16)))
	_add_nav_strip(nav, "Room6ScientistFloor", Rect2(Vector2(3136, 532), Vector2(512, 16)))

func _add_nav_strip(parent: Node, strip_name: String, rect: Rect2) -> void:
	var region := NavigationRegion2D.new()
	region.name = strip_name
	var polygon := NavigationPolygon.new()
	polygon.vertices = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = polygon
	parent.add_child(region)

func _create_scientist_setup() -> void:
	var actors := Node2D.new()
	actors.name = "ScientistsAndInterestPoints"
	generated_container.add_child(actors)

	_add_interest_point(actors, "Room3WorkLeft", Vector2(1110, 532), true, -1)
	_add_interest_point(actors, "Room3WanderRight", Vector2(1450, 532), false, 1)
	_add_scientist(actors, "Scientist_Room3", Vector2(1340, 500))

	_add_interest_point(actors, "Room5WorkLeft", Vector2(2520, 532), true, 1)
	_add_interest_point(actors, "Room5WanderMid", Vector2(2750, 532), false, -1)
	_add_interest_point(actors, "Room5WorkRight", Vector2(2980, 532), true, -1)
	_add_scientist(actors, "Scientist_Room5_A", Vector2(2600, 500))
	_add_scientist(actors, "Scientist_Room5_B", Vector2(2910, 500))

	_add_interest_point(actors, "Room6Work", Vector2(3220, 532), true, 1)
	_add_interest_point(actors, "Room6Wander", Vector2(3520, 532), false, -1)
	_add_scientist(actors, "Scientist_Room6", Vector2(3440, 500))

func _add_interest_point(parent: Node, point_name: String, position: Vector2, work: bool, facing: int) -> void:
	var point := Marker2D.new()
	point.name = point_name
	point.position = position
	point.script = INTEREST_POINT_SCRIPT
	point.facing_direction = facing
	point.add_to_group("human_interest_point")
	point.add_to_group("scientist_work_point" if work else "scientist_wander_point")
	parent.add_child(point)

func _add_scientist(parent: Node, scientist_name: String, position: Vector2) -> void:
	var scientist := SCIENTIST_SCENE.instantiate() as Node2D
	scientist.name = scientist_name
	scientist.position = position
	parent.add_child(scientist)

func _set_tile(layer: TileMapLayer, coords: Vector2i, atlas_coords: Vector2i) -> void:
	layer.set_cell(coords, _source_id, atlas_coords)

func _disable_legacy_level_nodes() -> void:
	var root := get_parent()
	if not root:
		return
	for child in root.get_children():
		if child == self:
			continue
		if child.name == "Background" and child is CanvasItem:
			child.visible = false
		var disable := false
		disable = disable or child is StaticBody2D
		disable = disable or child is NavigationRegion2D
		disable = disable or child.is_in_group("room_area")
		disable = disable or child.is_in_group("human_interest_point")
		disable = disable or child.is_in_group("human_ai")
		disable = disable or String(child.name).begins_with("Scientist")
		if disable:
			if child is CanvasItem:
				child.visible = false
			child.process_mode = Node.PROCESS_MODE_DISABLED
			child.remove_from_group("room_area")
			child.remove_from_group("human_interest_point")
			child.remove_from_group("scientist_work_point")
			child.remove_from_group("scientist_wander_point")
			child.remove_from_group("human_ai")
			if child is CollisionObject2D:
				child.collision_layer = 0
				child.collision_mask = 0
