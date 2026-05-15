@tool
extends EditorPlugin

const Utils = preload("res://addons/sketchfab/Utils.gd")

var Main = preload("res://addons/sketchfab/Main.tscn")
var main 

func _enter_tree():
	var name: String="sketchfab/assets_path"
	var default_value: String="res://assets/sketchfab"
	var hint: int=PROPERTY_HINT_DIR
	if not ProjectSettings.has_setting(name):
			ProjectSettings.set_setting(name, default_value)
			ProjectSettings.set_initial_value(name, default_value)
			ProjectSettings.add_property_info({
				"name": name,
				"type": typeof(default_value),
				"hint": hint,
			})
	main = Main.instantiate()
	get_tree().set_meta("__http_image_count", 0)
	EditorInterface.get_editor_main_screen().add_child(main)
	main.visible = false

func _exit_tree():
	main.queue_free()

func _has_main_screen():
	return true

func _get_plugin_name():
	return "Sketchfab"

func _get_plugin_icon():
	return load("res://addons/sketchfab/icon.png")

func _make_visible(visible):
	main.visible = visible

