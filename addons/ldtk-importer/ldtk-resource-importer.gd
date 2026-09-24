@tool
extends EditorImportPlugin

const LDTK_LATEST_VERSION = "1.5.3"

enum Presets { DEFAULT }
enum SaveExtensions { SCN, TSCN }
enum SaveAsScenes { LEVELS_ONLY, WORLDS_ONLY, BOTH }

const Util = preload("src/util/util.gd")
const World = preload("src/world.gd")
const Level = preload("src/level.gd")
const Tileset = preload("src/tileset.gd")
const DefinitionUtil = preload("src/util/definition_util.gd")

#region EditorImportPlugin Overrides


#region Simple
func _get_importer_name():
	return "ldtk.import.resource"


func _get_visible_name():
	return "LDTK Resource"


func _get_priority():
	return 1.0


func _get_resource_type():
	return "Resource"


func _get_recognized_extensions():
	return ["ldtk"]


func _get_save_extension():
	return "res"


func _get_preset_count():
	return Presets.size()


func _get_preset_name(index):
	match index:
		Presets.DEFAULT:
			return "Default"
		_:
			return "Unknown"


func _get_option_visibility(_path, option_name, _options):
	match option_name:
		_:
			return true
	return true


func _can_import_threaded() -> bool:
	return false


#endregion


func _get_import_options(_path, _index):
	return [
		# --- Levels --- #
		{"name": "World & Level", "default_value": "", "usage": PROPERTY_USAGE_GROUP},
		{
			# What to save as a scene.
			"name": "save_as_scenes",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Levels Only,World(s) Only,Both"
		},
		{
			# Define LDTKLevels save extension.
			"name": "save_extension",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "scn,tscn",
		},
		{"name": "group_world_layers", "default_value": false},
		# --- Layers --- #
		{"name": "Layer", "default_value": "", "usage": PROPERTY_USAGE_GROUP},
		{
			"name": "layers_always_visible",
			"default_value": false,
		},
		# --- Tileset --- #
		{"name": "Tileset", "default_value": "", "usage": PROPERTY_USAGE_GROUP},
		{
			# Add LDTK Custom Data to Tilesets
			"name": "tileset_custom_data",
			"default_value": false,
		},
		{
			# Create TileAtlasSources & TileMapLayers for IntGrid Layers
			"name": "integer_grid_tilesets",
			"default_value": false,
		},
		{
			# Define default texture type for TilesetAtlasSource (e.g. to apply normal maps to tilesets after import)
			"name": "atlas_texture_type",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "CompressedTexture2D,CanvasTexture",
		},
		{
			# Define Godot tileset save extension.
			"name": "tileset_save_extension",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "res,tres",
		},
		# --- Entities --- #
		{"name": "Entity", "default_value": "", "usage": PROPERTY_USAGE_GROUP},
		{
			#
			"name": "resolve_entityrefs",
			"default_value": true,
		},
		{
			# Create LDTKEntityPlaceholder nodes to help debug importing.
			"name": "use_entity_placeholders",
			"default_value": false,
		},
		# --- Post Import --- #
		{"name": "Post Import", "default_value": "", "usage": PROPERTY_USAGE_GROUP},
		{
			# Define a post-import script to apply on imported Tilesets.
			"name": "tileset_post_import",
			"default_value": "",
			"property_hint": PROPERTY_HINT_FILE,
			"hint_string": "*.gd;GDScript"
		},
		{
			# Define a post-import script to apply on imported Entities.
			"name": "entities_post_import",
			"default_value": "",
			"property_hint": PROPERTY_HINT_FILE,
			"hint_string": "*.gd;GDScript"
		},
		{
			# Define a post-import script to apply on imported Levels.
			"name": "level_post_import",
			"default_value": "",
			"property_hint": PROPERTY_HINT_FILE,
			"hint_string": "*.gd;GDScript"
		},
		{
			# Define a post-import script to apply on imported WorldDatas.
			"name": "world_resource_post_import",
			"default_value": "",
			"property_hint": PROPERTY_HINT_FILE,
			"hint_string": "*.gd;GDScript"
		},
		{
			# Define a post-import script to apply on imported WorldDatas.
			"name": "world_post_import",
			"default_value": "",
			"property_hint": PROPERTY_HINT_FILE,
			"hint_string": "*.gd;GDScript"
		},
		# --- Debug --- #
		{"name": "Debug", "default_value": "", "usage": PROPERTY_USAGE_GROUP},
		{
			# Force Tilesets to be recreated, resetting modifications (if experiencing import issues)
			"name": "force_tileset_reimport",
			"default_value": false,
		},
		{
			# Debug: Enable Verbose Output (used by the importer)
			"name": "verbose_output",
			"default_value": false
		}
	]


func _import(
	source_file: String,
	save_path: String,
	options: Dictionary,
	platform_variants: Array[String],
	gen_files: Array[String]
) -> Error:
	Util.timer_reset()
	Util.timer_start(Util.DebugTime.TOTAL)
	Util.print("import_start", source_file)

	# Add options to static var in "Util", accessible from any script.
	Util.options = options
	Util.options["pack_levels"] = true

	# Parse source_file
	var base_dir := source_file.get_base_dir() + "/"
	var file_name := source_file.get_file()
	var world_name := file_name.split(".")[0]

	Util.timer_start(Util.DebugTime.LOAD)
	var world_data := Util.parse_file(source_file)
	var external_levels: bool = world_data.externalLevels
	Util.timer_finish("File parsed")

	# Check version
	if Util.check_version(world_data.jsonVersion, LDTK_LATEST_VERSION):
		Util.print("item_ok", "LDTK VERSION (%s) OK" % [world_data.jsonVersion])
	else:
		return ERR_PARSE_ERROR

	Util.timer_start(Util.DebugTime.GENERAL)
	var definitions := DefinitionUtil.build_definitions(world_data)
	var tileset_overrides := Tileset.get_tileset_overrides(world_data, base_dir, external_levels)
	Util.timer_finish("Definitions Created")

	# Build Tilesets and save as Resources
	if Util.options.verbose_output:
		Util.print("block", "Tilesets")
	var tileset_paths := Tileset.build_tilesets(definitions, base_dir, tileset_overrides)
	gen_files.append_array(tileset_paths)

	# Fetch EntityDef Tile textures
	Tileset.get_entity_def_tiles(definitions, Util.tilesets)

	# Detect Multi-Worlds
	var world_iid: String = world_data.iid

	var data: LDTKData = LDTKData.new()
	var worlds: Array[LDTKWorld]
	if world_data.worldLayout == null:
		var world_instances: Array = world_data.worlds
		# Build each world instance
		for world_instance in world_instances:
			var world_instance_name: String = world_instance.identifier
			var world_instance_iid: String = world_instance.iid
			var levels := pack_levels_if_needed(
				Level.build_levels(world_instance, definitions, base_dir, external_levels),
				base_dir,
				gen_files
			)
			var world := World.create_world(world_instance_name, world_instance_iid, levels)

			worlds.append(world)

		#world = World.create_multi_world(world_name, world_iid, world_nodes)
	else:
		var world: LDTKWorld
		if Util.options.verbose_output:
			Util.print("block", "Levels")
		var levels := pack_levels_if_needed(
			Level.build_levels(world_data, definitions, base_dir, external_levels),
			base_dir,
			gen_files
		)

		if Util.options.verbose_output:
			Util.print("block", "Save World")
		world = World.create_world(world_name, world_iid, levels)
		worlds.append(world)

	worlds = pack_worlds_if_needed(worlds, base_dir, gen_files)
	for world in worlds:
		var world_resource: LDTKWorldData = World.create_world_resource(world)
		data.worlds.append(world_resource)

	# Save World as PackedScene
	Util.timer_start(Util.DebugTime.SAVE)
	var err = save_data(data, save_path, gen_files)
	Util.timer_finish("World Saved", 1)

	if Util.options.verbose_output:
		Util.print("block", "Results")

	Util.timer_finish("Completed.")

	var total_time: int = Util.DebugTime.get_total_time()
	var result_message: String = Util.DebugTime.get_result()

	if Util.options.verbose_output:
		Util.print("item_info", result_message)
	Util.print("import_finish", str(total_time))

	return err


#endregion


func save_data(data: LDTKData, save_path: String, gen_files: Array[String]) -> Error:
	Util.print("item_save", "Saving LDTKData [color=#fe8019][i]'%s'[/i][/color]" % [save_path], 1)

	var path = "%s.%s" % [save_path, _get_save_extension()]
	var err = ResourceSaver.save(data, path)
	if err == OK:
		gen_files.append(path)
	return err


func save_node(node: Node, save_path: String, gen_files: Array[String]) -> String:
	var packed_level = PackedScene.new()
	packed_level.pack(node)
	var world_path = (
		"%s%s.%s"
		% [save_path, node.name, SaveExtensions.keys()[Util.options.save_extension].to_lower()]
	)

	var err = ResourceSaver.save(packed_level, world_path)
	if err == OK:
		gen_files.append(world_path)

	return world_path


func pack_worlds_if_needed(
	worlds: Array[LDTKWorld],
	base_dir: String,
	gen_files: Array[String],
) -> Array[LDTKWorld]:
	if Util.options.verbose_output:
		Util.print("block", "Save World")
	if Util.options.save_as_scenes == SaveAsScenes.LEVELS_ONLY:
		return worlds

	var levels_path := base_dir + "worlds/"
	var directory = DirAccess.open(base_dir)
	if not directory.dir_exists(levels_path):
		directory.make_dir(levels_path)

	return save_worlds(worlds, levels_path, gen_files)


func save_worlds(
	worlds: Array[LDTKWorld], save_path: String, gen_files: Array[String]
) -> Array[LDTKWorld]:
	Util.timer_start(Util.DebugTime.SAVE)
	var packed_worlds: Array[LDTKWorld] = []

	var world_names := worlds.map(func(elem): return elem.name)
	Util.print("item_save", "Saving World(s): [color=#fe8019]%s[/color]" % [world_names], 1)

	for world in worlds:
		var world_path = save_node(world, save_path, gen_files)
		var packed_world = load(world_path).instantiate()
		packed_worlds.append(packed_world)

	Util.timer_finish("%s Worlds Saved" % [worlds.size()], 1)
	return packed_worlds


func pack_levels_if_needed(
	levels: Array[LDTKLevel],
	base_dir: String,
	gen_files: Array[String],
) -> Array[LDTKLevel]:
	if Util.options.verbose_output:
		Util.print("block", "Save Levels")
	if Util.options.save_as_scenes == SaveAsScenes.WORLDS_ONLY:
		return levels

	var levels_path := base_dir + "levels/"
	var directory = DirAccess.open(base_dir)
	if not directory.dir_exists(levels_path):
		directory.make_dir(levels_path)

	# Resolve Refs + Cleanup Resolvers. We don't want to save 'NodePathResolver' in the Level scene.
	#if (Util.options.verbose_output): Util.print("block", "References")
	Util.handle_references()

	return save_levels(levels, levels_path, gen_files)


func save_levels(
	levels: Array[LDTKLevel], save_path: String, gen_files: Array[String]
) -> Array[LDTKLevel]:
	Util.timer_start(Util.DebugTime.SAVE)
	var packed_levels: Array[LDTKLevel] = []

	var level_names := levels.map(func(elem): return elem.name)
	Util.print("item_save", "Saving Levels: [color=#fe8019]%s[/color]" % [level_names], 1)

	for level in levels:
		for child in level.get_children():
			Util.recursive_set_owner(child, level)
		var level_path = save_node(level, save_path, gen_files)
		var packed_level = load(level_path).instantiate()
		packed_levels.append(packed_level)

	Util.timer_finish("%s Levels Saved" % [levels.size()], 1)
	return packed_levels
