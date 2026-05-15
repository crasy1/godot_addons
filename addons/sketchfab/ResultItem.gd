@tool
extends MarginContainer

const SafeData = preload("res://addons/sketchfab/SafeData.gd")
const Utils = preload("res://addons/sketchfab/Utils.gd")

signal item_clicked(data: Dictionary)

@onready var user_name: Label = %UserName
@onready var model_name: Label = %ModelName
@onready var image: TextureRect = %Image
@onready var download_progress: ProgressBar = %DownloadProgress

var main: Control
var data
var uid
var imported_path

func set_data(data):
	self.data = data


func _ready():
	if !data:
		return
		
	model_name.text = SafeData.string(data, "name")
	uid=SafeData.string(data, "uid")
	var user = SafeData.dictionary(data, "user")
	user_name.text = "by %s" % SafeData.string(user, "displayName")

	var thumbnails = SafeData.dictionary(data, "thumbnails")
	var images = SafeData.array(thumbnails, "images")
	image.url = Utils.get_best_size_url(images, self.image.max_size, SafeData)

func _on_Button_pressed():
	if imported_path:
		if DirAccess.dir_exists_absolute(imported_path):
			EditorInterface.get_file_system_dock().navigate_to_path(imported_path)
			return
		else:
			imported_path=null
			main._downloads.erase(uid)
	item_clicked.emit(data)

func show_download_progress(bytes, total_bytes):
	download_progress.visible = true
	download_progress.max_value = total_bytes
	download_progress.value = bytes

func hide_download_progress():
	download_progress.visible = false

func show_open_button(path):
	imported_path = path
	hide_download_progress()
