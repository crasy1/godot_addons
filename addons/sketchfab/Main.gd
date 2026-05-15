@tool
extends Control

const CONFIG_FILE_PATH = "user://sketchfab.ini"
const ASSETS_PATH_SETTING = "sketchfab/assets_path"


func _get_assets_path() -> String:
	if ProjectSettings.has_setting(ASSETS_PATH_SETTING):
		var path: String = ProjectSettings.get_setting(ASSETS_PATH_SETTING)
		if not path.is_empty():
			return path
	return "res://assets/sketchfab"

const FACE_COUNT_OPTIONS = [
	# Label, face_count, max_face_count
	["Any", null, null],
	["Up to 10k", null, 10000],
	["10k to 50k", 10000, 50000],
	["50k to 100k", 50000, 100000],
	["100k to 250k", 100000, 250000],
	["More than 250k", 250000, null],
]

const SORT_BY_OPTIONS = [
	["Relevance", null],
	["Recent", "-publishedAt"],
	["Likes", "-likeCount"],
	["Views", "-viewCount"],
]

const SEARCH_DOMAIN = [
	["Whole site", "/search?type=models&downloadable=true"],
	["Own models (PRO)", "/me/search?type=models&downloadable=true"],
	["Purchased models", "/me/models/purchases?"],
]

const SORT_BY_DEFAULT_INDEX = 1
const DEFAULT_DOMAIN = 0

const SafeData = preload("res://addons/sketchfab/SafeData.gd")
const Utils = preload("res://addons/sketchfab/Utils.gd")
const Api = preload("res://addons/sketchfab/Api.gd")
const ModelDialogScene = preload("res://addons/sketchfab/ModelDialog.tscn")
const Requestor = preload("res://addons/sketchfab/Requestor.gd")
var api = Api.new()

# Download management
var _downloads: Dictionary = {}

signal download_progress(uid: String, bytes: int, total: int)
signal download_completed(uid: String, imported_path: String)
signal download_failed(uid: String)

@onready var search_text: LineEdit = %Text
@onready var search_categories: MenuButton = %Categories
@onready var search_animated: CheckBox = %Animated
@onready var search_staff_picked: CheckBox = %StaffPicked
@onready var search_face_count: OptionButton = %FaceCount
@onready var search_sort_by: OptionButton = %SortBy
@onready var search_domain: OptionButton = %SearchDomain
@onready var cta_button: Button = %CTA
@onready var trailer: VBoxContainer = %Trailer

@onready var paginator: ScrollContainer = %Paginator

@onready var not_logged: HBoxContainer = %NotLogged
@onready var login_name: LineEdit = %LoginName
@onready var login_password: LineEdit = %Password
@onready var login_button: Button = %Login

@onready var logged: VBoxContainer = %Logged
@onready var logged_name: Label = %DisplayName
@onready var logged_plan: Label = %Plan
@onready var logged_avatar: TextureRect = %Avatar

@onready var model_dialog: Control = %ModelDialog

var cfg
var can_search
var must_start_up = true

func _enter_tree():
	cfg = ConfigFile.new()
	cfg.load(CONFIG_FILE_PATH)


func _ready():
	var editor_scale = EditorInterface.get_editor_scale()
	logged_avatar.custom_minimum_size *= editor_scale
	not_logged.custom_minimum_size *= editor_scale
	%MainBlock.custom_minimum_size *= editor_scale

	paginator.item_selected.connect(_on_item_selected)
	paginator.main= self
	model_dialog.set_main(self)

func _exit_tree():
	for uid in _downloads:
		var task = _downloads[uid]
		if task.downloader:
			task.downloader.term()
	_downloads.clear()
	cfg.save(CONFIG_FILE_PATH)

func _notification(what):
	if what != NOTIFICATION_VISIBILITY_CHANGED:
		return
	if !is_visible_in_tree() || !is_node_ready() || !must_start_up:
		return

	must_start_up = false

	logged_avatar.max_size = logged_avatar.custom_minimum_size.y
	can_search = false
	var popup_menu = search_categories.get_popup()
	popup_menu.clear()
	popup_menu.add_check_item("All")
	popup_menu.index_pressed.connect(_on_Categories_index_pressed)

	search_face_count.clear()
	for item in FACE_COUNT_OPTIONS:
		search_face_count.add_item(item[0])
	_commit_face_count(0)

	search_sort_by.clear()
	for item in SORT_BY_OPTIONS:
		search_sort_by.add_item(item[0])
	_commit_sort_by(SORT_BY_DEFAULT_INDEX)

	search_domain.clear()
	for item in SEARCH_DOMAIN:
		search_domain.add_item(item[0])
	_commit_domain(DEFAULT_DOMAIN)
	search_domain.hide()
	cta_button.hide()

	logged.visible = false
	not_logged.visible = false
	login_name.text = cfg.get_value("api", "user", "")

	if cfg.has_section_key("api", "token"):
		api.set_token(cfg.get_value("api", "token"))
		await _populate_login()
	else:
		not_logged.visible = true

	await _load_categories()
	_commit_category(0)

	can_search = true
	_search()

##### UI

func _on_any_login_text_changed(new_text):
	_refresh_login_button()

func _on_UserName_text_entered(new_text):
	login_password.grab_focus()

func _on_Password_text_entered(new_text):
	_login()

func _on_Login_pressed():
	_login()

func _on_Logout_pressed():
	_logout()

func _on_any_search_trigger_changed():
	_search()

func _on_Categories_index_pressed(index):
	_commit_category(index)
	_search()

func _on_FaceCount_item_selected(index):
	_commit_face_count(index)
	_search()

func _on_SortBy_item_selected(index):
	_commit_sort_by(index)
	_search()

func _on_SearchDomain_item_selected(index):
	_commit_domain(index)
	_search()

func _on_SearchButton_pressed():
	_search()

func _on_SearchText_text_entered(new_text):
	_search()

func _on_item_selected(data, item):
	model_dialog.show_for_uid(SafeData.string(data, "uid"), item)

##### Actions

func _login():
	if api.busy:
		return

	cfg.set_value("api", "user", login_name.text)

	_set_login_disabled(true)
	var token = await api.login(login_name.text, login_password.text)
	_set_login_disabled(false)

	if token:
		cfg.set_value("api", "token", token)
		cfg.save(CONFIG_FILE_PATH)
		await _populate_login()
	else:
		OS.alert('Please check username and password and try again.', 'Cannot login')
		_logout()

	cfg.save(CONFIG_FILE_PATH)

func _populate_login():

	search_domain.show()

	_set_login_disabled(true)
	var user = await api.get_my_info()
	_set_login_disabled(false)

	if !user || typeof(user) != TYPE_DICTIONARY:
		_logout()
		return

	if !user.has("username") || !user.has("account"):
		_logout()
		return

	not_logged.visible = false
	logged.visible = true

	logged_name.text = "User: %s" % user["username"]

	var plan_name
	if user["account"] == "plus":
		plan_name = "PLUS"
	elif user["account"] == "pro":
		plan_name = "PRO"
	elif user["account"] == "prem":
		plan_name = "PREMIUM"
	elif user["account"] == "biz":
		plan_name = "BUSINESS"
	elif user["account"] == "ent":
		plan_name = "ENTERPRISE"
	else:
		plan_name = "BASIC";

	logged_plan.text = "Plan: %s" % plan_name

	var avatar = SafeData.dictionary(user, "avatar")
	var images = SafeData.array(avatar, "images")
	var image = SafeData.dictionary(images, 0)
	logged_avatar.url = SafeData.string(image, "url")

func _logout():
	Api.set_token(null)
	cfg.set_value("api", "token", null)
	cfg.save(CONFIG_FILE_PATH)
	not_logged.visible = true
	logged.visible = false
	logged_avatar.url = null
	search_domain.hide()
	cta_button.hide()
	trailer.modulate.a = 0.0
	search_domain.set_meta("__suffix", SEARCH_DOMAIN[0][1])

func _load_categories():
	var result = await api.get_categories()
	if typeof(result) != TYPE_DICTIONARY:
		return

	var categories = SafeData.array(result, "results")
	var i = 0
	var popup = search_categories.get_popup()
	for category in categories:
		popup.add_check_item(SafeData.string(category, "name"))
		popup.set_item_metadata(i + 1, SafeData.string(category, "slug"))
		i += 1

func _search():
	if !can_search:
		return

	paginator.search(
		search_text.text,
		search_categories.get_meta("__slugs"),
		search_animated.button_pressed,
		search_staff_picked.button_pressed,
		search_face_count.get_meta("__data")[1],
		search_face_count.get_meta("__data")[2],
		search_sort_by.get_meta("__key"),
		search_domain.get_meta("__suffix")
	)

##### Helpers

func _commit_category(index):
	var popup = search_categories.get_popup()
	var checked = !popup.is_item_checked(index)
	popup.set_item_checked(index, checked)

	var all = false

	if index == 0:
		for i in range(popup.get_item_count()):
			popup.set_item_checked(i, checked)
	else:
		if !checked:
			popup.set_item_checked(0, false)

	var n = 0
	var label
	var some = []
	for i in range(popup.get_item_count()):
		if popup.is_item_checked(i):
			if i == 0:
				label = "All"
				all = true
				n = -1
				break
			if n == 0:
				label = popup.get_item_text(i)
				some.append(popup.get_item_metadata(i))
				n += 1
			elif n >= 1:
				label = "<Multiple>"
				some.append(popup.get_item_metadata(i))
				n += 1

	if n == 0:
		all = true
	elif n == popup.get_item_count() - 1:
		popup.set_item_checked(0, true)
		all = true
	search_categories.text = "All" if all else label

	if all:
		search_categories.set_meta("__slugs", [])
	else:
		search_categories.set_meta("__slugs", some)

func _commit_face_count(index):
	search_face_count.set_meta("__data", FACE_COUNT_OPTIONS[index])

func _commit_sort_by(index):
	search_sort_by.set_meta("__key", SORT_BY_OPTIONS[index][1])

func _commit_domain(index):
	search_domain.set_meta("__suffix", SEARCH_DOMAIN[index][1])

func _set_login_disabled(disabled):
	login_name.editable = !disabled
	login_password.editable = !disabled
	if disabled:
		login_button.disabled = true
	else:
		_refresh_login_button()

func _refresh_login_button():
	login_button.disabled = !(login_name.text.length() > 0 && login_password.text.length() > 0)

##### Download Management

func start_download(uid: String, download_url: String, download_size: int, model_name: String):
	if _downloads.has(uid):
		return
	var host_idx = download_url.find("//") + 2
	var path_idx = download_url.find("/", host_idx)
	var host = download_url.substr(host_idx, path_idx - host_idx)
	var path = download_url.right(download_url.length() - path_idx)

	var file_regex = RegEx.new()
	file_regex.compile("[^/]+?\\.zip")
	var filename = file_regex.search(download_url).get_string()
	var assets_path := _get_assets_path()
	var zip_path = "%s/%s" % [assets_path, filename]

	DirAccess.make_dir_recursive_absolute(assets_path)

	var downloader = Requestor.new(host)

	_downloads[uid] = {
		"downloader": downloader,
		"zip_path": zip_path,
		"filename": filename,
		"model_name": model_name,
		"download_size": download_size,
		"status": "downloading",
		"progress_bytes": 0,
		"imported_path": "",
		"thread": null,
	}

	downloader.download_progressed.connect(_on_download_progress.bind(uid))
	downloader.request(path, null, { "download_to": zip_path })
	_await_download_completion(uid)


func _await_download_completion(uid: String):
	var task = _downloads.get(uid)
	if !task:
		return
	var downloader = task.downloader
	var result = await downloader.completed
	if !is_instance_valid(self):
		return
	if !result || !result.ok:
		_downloads.erase(uid)
		download_failed.emit(uid)
		return

	task.status = "unpacking"
	task.downloader = null
	downloader.term()

	var thread = Thread.new()
	task.thread = thread
	thread.start(_do_unzip.bind(task.zip_path, uid))


func _on_download_progress(bytes: int, total_bytes: int, uid: String):
	var task = _downloads.get(uid)
	if task:
		task.progress_bytes = bytes
	download_progress.emit(uid, bytes, total_bytes)


func _do_unzip(zip_path: String, uid: String):
	print("start unzip")
	var zip := ZIPReader.new()
	var err := zip.open(zip_path)
	if err != OK:
		_on_unzip_failed.call_deferred(uid)
		return

	var files := zip.get_files()
	if files.is_empty():
		zip.close()
		_on_unzip_failed.call_deferred(uid)
		return

	var base_name := zip_path.get_file().get_basename()
	var out_dir := zip_path.get_base_dir() + "/" + base_name + "/"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var prefix := ""
	for entry in files:
		var slash_pos := entry.find("/")
		if slash_pos < 0:
			prefix = ""
			break
		var candidate := entry.left(slash_pos + 1)
		if prefix.is_empty():
			prefix = candidate
		elif prefix != candidate:
			prefix = ""
			break

	for path in files:
		var extract_path := path
		if not prefix.is_empty() and path.begins_with(prefix):
			extract_path = path.substr(prefix.length())
		if extract_path.is_empty() or extract_path.ends_with("/"):
			if not extract_path.is_empty():
				DirAccess.make_dir_recursive_absolute(out_dir + extract_path)
			continue
		var data := zip.read_file(path)
		var full_path := out_dir + extract_path
		DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())
		var out_file := FileAccess.open(full_path, FileAccess.WRITE)
		if out_file:
			out_file.store_buffer(data)
			out_file.close()

	zip.close()
	DirAccess.remove_absolute(zip_path)
	_on_unzip_done.call_deferred(uid)


func _on_unzip_done(uid: String) -> void:
	print("unzip done")
	var task = _downloads.get(uid)
	if !task:
		return
	if task.thread:
		task.thread.wait_to_finish()
		task.thread = null

	var base_name = task.filename.get_basename()
	task.imported_path = "%s/%s" % [_get_assets_path(), base_name]
	task.status = "done"

	EditorInterface.get_resource_filesystem().scan()
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame

	download_completed.emit(uid, task.imported_path)


func _on_unzip_failed(uid: String):
	print("unzip failed")
	var task = _downloads.get(uid)
	if !task:
		return
	if task.thread:
		task.thread.wait_to_finish()
		task.thread = null
	_downloads.erase(uid)
	download_failed.emit(uid)


func get_download_status(uid: String) -> Dictionary:
	return _downloads.get(uid, {})


func is_downloading(uid: String) -> bool:
	var task = _downloads.get(uid)
	return task != null and (task.status == "downloading" or task.status == "unpacking")


func _on_setting_btn_pressed():
	var base = EditorInterface.get_base_control()
	var project_settings_editor = base.find_child("*ProjectSettingsEditor*", true, false)
	if not project_settings_editor:
		# Fallback: open project settings directly
		EditorInterface.get_base_control().find_child("*ProjectSettingsEditor*", true, false)
		return

	var tab_container:TabContainer = project_settings_editor.find_child("*TabContainer*", true, false)
	if not tab_container:
		project_settings_editor.popup()
		return

	# Find the General tab
	var general_tab:Control
	for i in range(tab_container.get_tab_count()):
		if "General" in tab_container.get_tab_title(i) or "general" in tab_container.get_tab_title(i).to_lower():
			general_tab = tab_container.get_tab_control(i)
			break

	if not general_tab:
		project_settings_editor.popup()
		return

	var search_field:LineEdit = general_tab.find_child("*LineEdit*", true, false)
	project_settings_editor.popup()
	if tab_container and general_tab:
		tab_container.set_current_tab(tab_container.get_tab_idx_from_control(general_tab))
	if search_field:
		search_field.text = "sketchfab"
		search_field.text_changed.emit("sketchfab")