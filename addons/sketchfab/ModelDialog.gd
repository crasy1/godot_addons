@tool
extends Control

const SafeData = preload("res://addons/sketchfab/SafeData.gd")
const Utils = preload("res://addons/sketchfab/Utils.gd")
const Requestor = preload("res://addons/sketchfab/Requestor.gd")
const Api = preload("res://addons/sketchfab/Api.gd")

var api = Api.new()
var downloader

@onready var label_model: Label = %Model
@onready var label_user: Label = %User
@onready var image: TextureRect = %Image

@onready var info: Label = %Info
@onready var license: Label = %License

@onready var download: Button = %Download
@onready var progress: ProgressBar = %ProgressBar
@onready var size_label: Label = %Size

var uid
var imported_path
var view_url
var download_url
var download_size
var source_item

func _ready():
	%All.visible = false

func show_for_uid(uid, source_item):
	self.uid = uid
	self.source_item = source_item
	show()
	%All.visible = false
	_setup()

func close():
	hide()
	if is_instance_valid(source_item):
		source_item.hide_download_progress()
	if downloader:
		downloader.term()
		downloader = null
	source_item = null

func _on_dimmer_input(event):
	if event is InputEventMouseButton and event.pressed:
		close()

func _on_close_pressed():
	close()

func _setup():
	if !uid:
		close()
		return

	imported_path = null
	download.disabled = false
	download.text = "Download"
	progress.visible = false
	size_label.visible = false

	if Api.get_token():
		var result = await api.request_download(uid)
		if !get_tree():
			return

		if typeof(result) == TYPE_INT && result == Api.SymbolicErrors.NOT_AUTHORIZED:
			OS.alert("Your session may have expired. Please log in again.", "Not authorized")
			close()
			return

		if typeof(result) != TYPE_DICTIONARY:
			close()
			return

		var gtlf = SafeData.dictionary(result, "gltf")
		if !gtlf.size():
			OS.alert("This model has not a glTF version.", "Sorry")
			close()
			return

		download_url = SafeData.string(gtlf, "url")
		download_size = SafeData.integer(gtlf, "size")
		if !download_url:
			close()
			return

		download.text = "Download (%.1f MiB)" % [download_size / (1024 * 1024)]
	else:
		download.text = "To download models you need to be logged in."
		download.disabled = true

	var data = await api.get_model_detail(uid)
	if typeof(data) != TYPE_DICTIONARY:
		close()
		return

	label_model.text = SafeData.string(data, "name")

	var user = SafeData.dictionary(data, "user")
	label_user.text = "by %s" % SafeData.string(user, "displayName")

	view_url = SafeData.string(data, "viewerUrl")

	var thumbnails = SafeData.dictionary(data, "thumbnails")
	var images = SafeData.array(thumbnails, "images")
	image.max_size = 440
	image.url = Utils.get_best_size_url(images, image.max_size, SafeData)

	var vc = SafeData.integer(data, "vertexCount")
	var fc = SafeData.integer(data, "faceCount")
	var ac = SafeData.integer(data, "animationCount")
	info.text = (
		"Vertex count: %.1fk\n" +
		"Face count: %.1fk\n" +
		"Animation: %s") % [
			vc * 0.001,
			fc * 0.001,
			"Yes" if ac else "No",
		]

	var license_data = SafeData.dictionary(data, "license")

	license.text = "%s\n(%s)" % [
		SafeData.string(license_data, "fullName"),
		SafeData.string(license_data, "requirements"),
	]
	%All.visible = true

func _on_Download_pressed():
	if imported_path:
		EditorInterface.open_scene_from_path(imported_path)
		close()
		return

	# Download file

	download.visible = false
	progress.value = 0
	progress.max_value = download_size
	progress.visible = true
	size_label.visible = true
	size_label.text = "    %.1f MiB" % (download_size / (1024 * 1024))

	var host_idx = download_url.find("//") + 2
	var path_idx = download_url.find("/", host_idx)
	var host = download_url.substr(host_idx, path_idx - host_idx)

	var path = download_url.right(download_url.length() - path_idx)
	downloader = Requestor.new(host)

	DirAccess.make_dir_absolute("res://sketchfab")

	var file_regex = RegEx.new()
	file_regex.compile("[^/]+?\\.zip")
	var filename = file_regex.search(download_url).get_string()
	var zip_path = "res://sketchfab/%s" % filename

	downloader.download_progressed.connect(_on_download_progressed)
	downloader.request(path, null, { "download_to": zip_path })
	var result = await downloader.completed
	if !result:
		return
	downloader.term()
	downloader = null

	if !result.ok:
		print("result.code : ", result.code)
		download.visible = true
		progress.visible = false
		size_label.visible = false
		if is_instance_valid(source_item):
			source_item.hide_download_progress()
		OS.alert(
			"Please check your network connectivity, free disk space and try again.",
			"Download error")
		return

	# Unpack

	progress.show_percentage = false
	size_label.text = "    Model downloaded! Unpacking..."
	await get_tree().process_frame
	if !get_tree():
		return

	var out = []
	OS.execute(OS.get_executable_path(), [
		"-s", ProjectSettings.globalize_path("res://addons/sketchfab/unzip.gd"),
		"--zip-to-unpack %s" % ProjectSettings.globalize_path(zip_path),
		"--no-window",
		"--quit",
	], out)
	print(out[0])

	size_label.text = "    Model unpacked into project!"

	# Import and open

	var base_name = filename.substr(0, filename.find(".zip"))
	imported_path = "res://sketchfab/%s/scene.gltf" % base_name
	EditorInterface.get_resource_filesystem().scan()
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
		if !get_tree():
			return
	EditorInterface.select_file(imported_path)

	progress.visible = false
	size_label.visible = false
	download.visible = true
	download.text = "OPEN IMPORTED MODEL"
	if is_instance_valid(source_item):
		source_item.show_open_button(imported_path)

func _on_download_progressed(bytes, total_bytes):
	if !get_tree():
		downloader.term()
	progress.value = bytes
	if is_instance_valid(source_item):
		source_item.show_download_progress(bytes, total_bytes)

func _on_ViewOnSite_pressed():
	OS.shell_open(view_url)
