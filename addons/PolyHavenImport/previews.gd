@tool
extends Page

var _resources: Array = []
var _filter: int = 0  # 0=all, 1=material, 2=hdri, 3=model
var _model_instance: Node3D
var _current_material: StandardMaterial3D
var _selected_path: String = ""

# orbit camera
var _orbit_theta: float = 0.0
var _orbit_phi: float = 0.17
var _orbit_distance: float = 3.0
var _orbit_center: Vector3 = Vector3.ZERO
var _orbiting: bool = false
var _last_mouse_pos: Vector2

@onready var mesh_inst: MeshInstance3D = $%MeshInstance3D
@onready var world_env: WorldEnvironment = %WorldEnvironment
@onready var light: DirectionalLight3D = $%DirectionalLight3D
@onready var item_list: ItemList = $%ItemList
@onready var InfoLabel: Label = $%InfoLabel
@onready var SearchInput: LineEdit = $%SearchInput
@onready var camera: Camera3D = $%Camera3D
@onready var AllBtn: Button = $%AllBtn
@onready var MaterialsBtn: Button = $%MaterialsBtn
@onready var HDRIsBtn: Button = $%HDRIsBtn
@onready var ModelsBtn: Button = $%ModelsBtn
@onready var MeshOptionBtn: OptionButton = $%MeshOptionBtn
@onready var PreviewContainer: SubViewportContainer = $%PreviewContainer
@onready var LocateBtn: Button = $%LocateBtn


func _ready():
	_setup_3d()
	scan_resources()


func _setup_3d():
	_update_mesh_shape()
	camera.current = true
	_show_default_env()
	_update_filter_buttons()
	_update_orbit_camera()


func _show_default_env():
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	world_env.environment = env


# --- mesh shape ---

func _update_mesh_shape():
	var shapes := [SphereMesh.new(), BoxMesh.new(), CylinderMesh.new(),
		TorusMesh.new(), PlaneMesh.new()]
	var idx := MeshOptionBtn.selected
	if idx < 0 or idx >= shapes.size():
		idx = 0
	mesh_inst.mesh = shapes[idx]
	if _current_material:
		mesh_inst.set_surface_override_material(0, _current_material)


func _on_MeshOptionBtn_item_selected(_index: int):
	_update_mesh_shape()


# --- orbit camera ---

func _reset_orbit(center: Vector3 = Vector3.ZERO, distance: float = 3.0):
	_orbit_center = center
	_orbit_distance = distance
	_orbit_theta = 0.0
	_orbit_phi = 0.17
	_update_orbit_camera()


func _update_orbit_camera():
	var x := _orbit_distance * cos(_orbit_phi) * sin(_orbit_theta)
	var y := _orbit_distance * sin(_orbit_phi)
	var z := _orbit_distance * cos(_orbit_phi) * cos(_orbit_theta)
	camera.position = _orbit_center + Vector3(x, y, z)
	camera.look_at(_orbit_center)


func _on_PreviewContainer_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = event.pressed
			_last_mouse_pos = event.position
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = max(0.5, _orbit_distance - 0.3)
			_update_orbit_camera()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = min(50.0, _orbit_distance + 0.3)
			_update_orbit_camera()
			accept_event()
	elif event is InputEventMouseMotion and _orbiting:
		var pos_delta: Vector2 = event.position - _last_mouse_pos
		_last_mouse_pos = event.position
		_orbit_theta -= pos_delta.x * 0.01
		_orbit_phi = clamp(_orbit_phi + pos_delta.y * 0.01, -PI * 0.45, PI * 0.45)
		_update_orbit_camera()
		accept_event()


# --- scanning ---

func scan_resources():
	_resources.clear()

	var textures_path: String = ProjectSettings.get_setting("poly_haven_import/textures_path", "res://assets/textures")
	var hdris_path: String = ProjectSettings.get_setting("poly_haven_import/hdris_path", "res://assets/HDRIs")
	var models_path: String = ProjectSettings.get_setting("poly_haven_import/models_path", "res://assets/models")

	_scan_dir(textures_path, "material")
	_scan_dir(hdris_path, "hdri")
	_scan_dir(models_path, "model")

	_resources.sort_custom(func(a, b): return a.name.naturalcasecmp_to(b.name) < 0)
	populate_list()


func _scan_dir(path: String, type: String):
	var dir = DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue

		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			_scan_dir(full_path, type)
		else:
			var ext = file_name.get_extension().to_lower()
			var matched := false
			if type == "model":
				matched = ext in ["gltf", "glb", "fbx"]
			else:
				matched = ext == "tres"
			if matched:
				_resources.append({
					"name": file_name.get_basename(),
					"path": full_path,
					"type": type,
				})
		file_name = dir.get_next()
	dir.list_dir_end()


# --- list ---

func populate_list():
	item_list.clear()

	var search: String = SearchInput.text.to_lower()

	for res in _resources:
		var matches_filter = (_filter == 0 or
			(_filter == 1 and res.type == "material") or
			(_filter == 2 and res.type == "hdri") or
			(_filter == 3 and res.type == "model"))
		if not matches_filter:
			continue
		if search != "" and search not in res.name.to_lower():
			continue

		var tag = {"material": "[material]", "hdri": "[HDR]", "model": "[model]"}.get(res.type, "")
		item_list.add_item(tag + " " + res.name)
		item_list.set_item_metadata(item_list.item_count - 1, res)

	if _resources.is_empty():
		_set_info("resource not found")
	elif item_list.item_count == 0:
		_set_info("resource not found")
	else:
		_set_info("resource count: %d" % item_list.item_count)


func _set_info(text: String):
	InfoLabel.text = text


# --- filter ---

func _set_filter(f: int):
	_filter = f
	_update_filter_buttons()
	populate_list()


func _update_filter_buttons():
	AllBtn.disabled = (_filter == 0)
	MaterialsBtn.disabled = (_filter == 1)
	HDRIsBtn.disabled = (_filter == 2)
	ModelsBtn.disabled = (_filter == 3)


# --- preview ---

func _preview_material(path: String, name: String):
	_clear_model()
	var mat = load(path)
	if not mat is StandardMaterial3D:
		_set_info("can't load material: %s" % name)
		return

	_current_material = mat
	mesh_inst.visible = true
	mesh_inst.set_surface_override_material(0, mat)
	light.visible = true
	_reset_orbit()
	_show_default_env()
	_set_info("material: %s" % name)


func _preview_hdri(path: String, name: String):
	_clear_model()
	_current_material = null
	var sky = load(path)
	if not sky is Sky:
		_set_info("can't load  HDR sky: %s" % name)
		return

	mesh_inst.visible = false
	light.visible = false
	_reset_orbit()

	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	world_env.environment = env
	_set_info("HDR sky: %s" % name)


func _preview_model(path: String, name: String):
	_clear_model()
	_current_material = null
	var scene = load(path)
	if not scene is PackedScene:
		_set_info("can't load model: %s" % name)
		return

	mesh_inst.visible = false
	light.visible = true
	_show_default_env()

	var model := scene.instantiate() as Node3D
	_model_instance = model
	camera.get_parent().add_child(model)

	var aabb := _get_combined_aabb(model)
	var center := aabb.get_center()
	var size := aabb.get_longest_axis_size()
	if size < 0.01:
		size = 1.0
	_reset_orbit(center, size * 2.5)
	_set_info("model: %s" % name)


func _clear_model():
	if _model_instance and is_instance_valid(_model_instance):
		_model_instance.queue_free()
		_model_instance = null


func _get_combined_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D"):
		var mi := child as MeshInstance3D
		if not mi.mesh:
			continue
		var child_aabb: AABB = mi.get_aabb()
		child_aabb = mi.transform * child_aabb
		if not found:
			result = child_aabb
			found = true
		else:
			result = result.merge(child_aabb)
	if not found:
		result = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	return result


# --- signals ---

func _on_BackBtn_pressed():
	navigate("res://addons/PolyHavenImport/browse.tscn")


func _on_RefreshBtn_pressed():
	scan_resources()


func _on_AllBtn_pressed():
	_set_filter(0)


func _on_MaterialsBtn_pressed():
	_set_filter(1)


func _on_HDRIsBtn_pressed():
	_set_filter(2)


func _on_ModelsBtn_pressed():
	_set_filter(3)


func _on_SearchInput_text_changed(_new_text: String):
	populate_list()


func _on_ItemList_item_selected(index: int):
	var res: Dictionary = item_list.get_item_metadata(index)
	_selected_path = res.path
	LocateBtn.disabled = false
	if res.type == "material":
		_preview_material(res.path, res.name)
	elif res.type == "hdri":
		_preview_hdri(res.path, res.name)
	else:
		_preview_model(res.path, res.name)


func _on_LocateBtn_pressed():
	if _selected_path != "":
		EditorInterface.get_file_system_dock().navigate_to_path(_selected_path)
