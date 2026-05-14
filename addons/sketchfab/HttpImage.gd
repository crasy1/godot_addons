@tool
extends TextureRect

const MAX_COUNT = 4

@export var max_size = 256
@export var background = Color(0, 0, 0, 0)
@export var immediate = false

var url:
	set(value):
		_set_url(value)
var url_to_load

var http_request = null
var busy = false

func _enter_tree():
	if !http_request:
		http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.request_completed.connect(_http_request_completed)
		http_request.set_tls_options(TLSOptions.client())

	busy = false
	if url_to_load:
		_start_load()

func _exit_tree():
	if busy:
		http_request.cancel_request()
		_dec_count()
		busy = false


func _set_url(url):
	url_to_load = url
	if !is_inside_tree():
		return

	_start_load()

func _start_load():
	http_request.cancel_request()
	texture = null
	queue_redraw()

	if !url_to_load:
		return

	while true:
		if !is_inside_tree():
			return
		var count := _get_count()
		if immediate || count < MAX_COUNT:
			get_tree().set_meta("__http_image_count", count + 1)
			break
		else:
			await get_tree().process_frame

	busy = true
	_load(url_to_load)
	url_to_load = null

func _load(url_to_load):
	var error = http_request.request(url_to_load)
	if error != OK:
		push_error("An error occurred in the HTTP request.")
		busy = false
		_dec_count()

func _http_request_completed(result, response_code, headers, body):
	busy = false
	_dec_count()

	if !is_inside_tree():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Image couldn't be downloaded.")
		return

	var img := Image.new()
	if img.load_jpg_from_buffer(body) != OK and img.load_png_from_buffer(body) != OK and img.load_webp_from_buffer(body) != OK:
		push_error("Couldn't load the image (unsupported format).")
		return

	var w := img.get_width()
	var h := img.get_height()
	if w > h:
		var new_w := mini(w, max_size)
		img.resize(new_w, int((float(h) / w) * new_w))
	else:
		var new_h := mini(h, max_size)
		img.resize(int((float(w) / h) * new_h), new_h)

	texture = ImageTexture.create_from_image(img)

func _get_count() -> int:
	if get_tree().has_meta("__http_image_count"):
		return get_tree().get_meta("__http_image_count")
	return 0

func _dec_count():
	if is_inside_tree() and get_tree().has_meta("__http_image_count"):
		get_tree().set_meta("__http_image_count", max(0, get_tree().get_meta("__http_image_count") - 1))
