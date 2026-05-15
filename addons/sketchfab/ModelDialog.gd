@tool
extends Control

const SafeData = preload("res://addons/sketchfab/SafeData.gd")
const Utils = preload("res://addons/sketchfab/Utils.gd")
const Api = preload("res://addons/sketchfab/Api.gd")

var api = Api.new()

var _main: Control

@onready var label_model: Label = %Model
@onready var label_user: Label = %User
@onready var image: TextureRect = %Image

@onready var info: Label = %Info
@onready var license: Label = %License

@onready var formats: HBoxContainer = %Formats
@onready var download: Button = %Download
@onready var progress: ProgressBar = %ProgressBar
@onready var size_label: Label = %Size

var uid
var imported_path
var view_url
var download_url
var download_size
var source_item
var format_group

func _ready():
	%All.visible = false
	format_group=ButtonGroup.new()


func set_main(main: Control):
	_main = main
	if _main:
		_main.download_progress.connect(_on_main_download_progress)
		_main.download_completed.connect(_on_main_download_completed)
		_main.download_failed.connect(_on_main_download_failed)


func show_for_uid(p_uid, p_source_item):
	uid = p_uid
	source_item = p_source_item
	show()
	%All.visible = false
	_setup()


func close():
	hide()
	# Don't hide ResultItem progress — download continues in Main


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
	download.visible = true
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
		# 不同格式的模型,由于格式不同下载文件不一定是zip的，所以只保留gltf下载
		var formatList=result.keys()
		for c in formats.get_children():
			c.queue_free()
		for f in formatList:
			var check_box = CheckBox.new()
			check_box.text = f
			check_box.set_meta("format", SafeData.dictionary(result,f))
			check_box.button_group=format_group
			formats.add_child(check_box)
			check_box.pressed.connect(
				func():
					download.disabled = f != "gltf"
					download_url = SafeData.string(check_box.get_meta("format"), "url")
					download_size = SafeData.integer(check_box.get_meta("format"), "size")
					download.text = "%s(%.1f MiB)" % ["Download " if f=="gltf" else "",download_size / (1024 * 1024)]
			)
			if f == "gltf":
				check_box.button_pressed=true
				check_box.pressed.emit()
			
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

	# Override UI state if download is already in progress or completed
	if _main:
		var dl_status = _main.get_download_status(uid)
		if !dl_status.is_empty():
			if dl_status.status == "done":
				imported_path = dl_status.imported_path
				download.text = "Locate to filesystem"
			elif dl_status.status == "downloading":
				download.visible = false
				progress.max_value = dl_status.download_size
				progress.value = dl_status.progress_bytes
				progress.visible = true
				size_label.visible = true
				size_label.text = "    %.1f / %.1f MiB" % [
					dl_status.progress_bytes / (1024.0 * 1024.0),
					dl_status.download_size / (1024.0 * 1024.0)]
			elif dl_status.status == "unpacking":
				download.visible = false
				progress.visible = false
				size_label.visible = true
				size_label.text = "    Unpacking..."

	%All.visible = true


func _on_Download_pressed():
	if imported_path:
		EditorInterface.get_file_system_dock().navigate_to_path(imported_path)
		close()
		return

	if !_main || !download_url:
		return

	if _main.is_downloading(uid):
		return

	download.visible = false
	progress.value = 0
	progress.max_value = download_size
	progress.visible = true
	size_label.visible = true
	size_label.text = "    %.1f MiB" % (download_size / (1024 * 1024))

	_main.start_download(uid, download_url, download_size, label_model.text)


func _on_main_download_progress(dl_uid: String, bytes: int, total: int):
	if dl_uid != uid:
		return
	if is_visible_in_tree():
		progress.value = bytes
		size_label.text = "    %.1f / %.1f MiB" % [
			bytes / (1024.0 * 1024.0),
			total / (1024.0 * 1024.0)]
	if is_instance_valid(source_item):
		source_item.show_download_progress(bytes, total)


func _on_main_download_completed(dl_uid: String, path: String):
	if dl_uid != uid:
		return
	imported_path = path
	if is_visible_in_tree():
		progress.visible = false
		size_label.visible = false
		download.visible = true
		download.text = "Locate to filesystem"
		download.disabled = false
	if is_instance_valid(source_item):
		source_item.show_open_button(imported_path)


func _on_main_download_failed(dl_uid: String):
	if dl_uid != uid:
		return
	if is_visible_in_tree():
		download.visible = true
		download.disabled = false
		download.text = "Download"
		progress.visible = false
		size_label.visible = false
	if is_instance_valid(source_item):
		source_item.hide_download_progress()
	OS.alert("Download failed. Please try again.", "Download error")


func _on_ViewOnSite_pressed():
	OS.shell_open(view_url)
