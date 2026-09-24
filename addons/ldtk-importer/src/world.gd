@tool

const Util = preload("util/util.gd")
const PostImport = preload("post-import.gd")


static func create_world(name: String, iid: String, levels: Array) -> LDTKWorld:
	Util.timer_start(Util.DebugTime.GENERAL)
	var world = LDTKWorld.new()
	world.name = name
	world.iid = iid

	# Update World_Rect
	var x1 = world.rect.position.x
	var x2 = world.rect.end.x
	var y1 = world.rect.position.y
	var y2 = world.rect.end.y

	var world_depths := {}

	for level in levels:
		level.position = level.world_position

		if Util.options.group_world_layers:
			var world_depth_layer: LDTKWorldLayer
			var z_index: int = level.z_index if (level is not PackedScene) else 0
			if not z_index in world_depths:
				world_depth_layer = LDTKWorldLayer.new()
				world_depth_layer.name = "WorldLayer_" + str(z_index)
				world_depth_layer.depth = z_index
				world.add_child(world_depth_layer)
				world_depth_layer.set_owner(world)
				world_depths[z_index] = world_depth_layer
			else:
				world_depth_layer = world_depths[z_index]
			world_depth_layer.add_child(level)
		else:
			world.add_child(level)

		x1 = min(x1, level.position.x)
		y1 = min(y1, level.position.y)
		x2 = max(x2, level.position.x + level.size.x)
		y2 = max(y2, level.position.y + level.size.y)

		# Set owner - this ensures nodes get saved correctly
		level.set_owner(world)
		if Util.options.save_as_scenes == 1: # World only
			Util.recursive_set_owner(level, world)

	# Sort WorldLayers based on depth
	if not world_depths.is_empty():
		var keys = world_depths.keys()
		keys.sort_custom(func(a, b): return a < b)
		for i in range(keys.size()):
			world.move_child(world_depths[keys[i]], i)

	world.rect.position = Vector2i(x1, y1)
	world.rect.end = Vector2i(x2, y2)

	Util.timer_finish("World Created", 1)

	# Post-Import
	if Util.options.world_post_import:
		world = PostImport.run_world_post_import(world, Util.options.world_post_import)

	return world


static func create_world_resource(world: LDTKWorld) -> LDTKWorldData:
	Util.timer_start(Util.DebugTime.GENERAL)
	var resource = LDTKWorldData.new()
	resource.resource_name = world.name
	resource.iid = world.iid

	for level: LDTKLevel in world.levels:
		var level_resource := LDTKLevelData.new()
		level_resource.iid = level.iid
		level_resource.world_position = level.world_position
		level_resource.size = level.size
		level_resource.fields = level.fields
		level_resource.neighbours = level.neighbours
		level_resource.bg_color = level.bg_color
		resource.levels.append(level_resource)

		level.queue_free()

	resource.rect = world.rect

	Util.timer_finish("World Created", 1)

	# Post-Import
	if Util.options.world_resource_post_import:
		resource = PostImport.run_world_resource_post_import(
			resource, Util.options.world_resource_post_import
		)

	return resource


static func create_multi_world(name: String, iid: String, worlds: Array[LDTKWorld]) -> LDTKWorld:
	var multi_world = LDTKWorld.new()
	multi_world.name = name
	multi_world.iid = iid

	worlds.sort_custom(
		func(a, b): return a.depth < b.depth if "depth" in a and "depth" in b else false
	)

	for world in worlds:
		multi_world.add_child(world)
		Util.recursive_set_owner(world, multi_world)

	return multi_world
