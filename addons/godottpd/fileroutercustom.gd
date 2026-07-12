# Class inheriting HttpRouter for handling file serving requests
extends HttpRouter
class_name HttpFileRouter

# Full path to the folder which will be exposed to web
var path: String = ""

# Relative path to the index page, which will be served when a request is made to "/" (server root)
var index_page: String = "index.html"

# Relative path to the fallback page which will be served if the requested file was not found
var fallback_page: String = "404.html"

# An ordered list of extensions that will be checked 
# if no file extension is provided by the request
var extensions: PoolStringArray = ["html", "jpg", "jpeg", "png", "webm", "mp3"]

# A list of extensions that will be excluded if requested
var exclude_extensions: PoolStringArray = []

var block_html_render: bool = false
# Creates an HttpFileRouter intance
#
# #### Parameters
# - path: Full path to the folder which will be exposed to web
# - options: Optional Dictionary of options which can be configured.
# 	- fallback_page: Full path to the fallback page which will be served if the requested file was not found
#	- extensions: A list of extensions that will be checked if no file extension is provided by the request
# 	- exclude_extensions: A list of extensions that will be excluded if requested
func _init(
	path: String, 
	options: Dictionary = { 
		index_page = index_page,
		fallback_page = fallback_page, 
		extensions = extensions, 
		exclude_extensions = exclude_extensions,
		block_html_render = block_html_render,
	}
	) -> void:
	self.path = path
	self.index_page = options.get("index_page", "")
	self.fallback_page = options.get("fallback_page", "")
	self.extensions = options.get("extensions", [])
	self.exclude_extensions = options.get("exclude_extensions", [])
	self.block_html_render = options.get("block_html_render", false)

# Handle a GET request
func handle_get(request: HttpRequest, response: HttpResponse) -> void:
	var serving_path: String = path + request.path
	var file_exists: bool = _file_exists(serving_path)

	if request.path == "/" and not file_exists:
		if not index_page.empty():
			serving_path = path + "/" + index_page
			file_exists = _file_exists(serving_path)
	
	if request.path.get_extension() == "" and not file_exists:
		for extension in extensions:
			serving_path = path + request.path + "." + extension
			file_exists = _file_exists(serving_path)
			if file_exists: 
				break
	if !request.headers.has("Range"):
		# GDScript must be excluded, unless it is used as a preprocessor (php-like)
		response.headers = {"Cache-Control":"public, max-age=31536000, immutable"}
		if (file_exists and not serving_path.get_extension() in ["gd"] + Array(exclude_extensions)):
			response.send_raw(
				200, 
				_serve_file(serving_path), 
				_get_mime(serving_path.get_extension())
				)
		else:
			if not fallback_page.empty():
				serving_path = path + "/" + fallback_page
				response.send_raw(200 if index_page == fallback_page else 404, _serve_file(serving_path), _get_mime(fallback_page.get_extension()))
			else:
				response.send_raw(404)
	else:
		var file := File.new()
		file.open(serving_path, File.READ)
		var start := int(request.headers.Range.trim_prefix("bytes=").split("-")[0])
		var end := int(request.headers.Range.trim_prefix("bytes=").split("-")[1]) if request.headers.Range.trim_prefix("bytes=").split("-")[1] != "" else file.get_len()
		response.headers = {"Cache-Control":"public, max-age=31536000, immutable", "Content-Range": "bytes %s-%s/%s"%[start, end-1, file.get_len()]}
		if (file_exists and not serving_path.get_extension() in ["gd"] + Array(exclude_extensions)):
			response.send_raw(
				206, 
				_serve_part_file(serving_path, request.headers.Range), 
				_get_mime(serving_path.get_extension())
				)
		else:
			if not fallback_page.empty():
				serving_path = path + "/" + fallback_page
				response.send_raw(200 if index_page == fallback_page else 404, _serve_part_file(serving_path, request.headers.Range), _get_mime(fallback_page.get_extension()))
			else:
				response.send_raw(404)

# Reads a file as text
#
# #### Parameters
# - file_path: Full path to the file
func _serve_file(file_path: String) -> PoolByteArray:
	var content: PoolByteArray = []
	var file := File.new()
	var error: int = file.open(file_path, File.READ)
	if error:
		content = ("Couldn't serve file, ERROR = %s" % error).to_utf8()
	else:
		content = file.get_buffer(file.get_len())
	file.close()
	return content
	
func _serve_part_file(file_path: String, rng: String) -> PoolByteArray:

	var content: PoolByteArray = []
	var file := File.new()
	var error: int = file.open(file_path, File.READ)
	var start := int(rng.split("-")[0].trim_prefix("bytes="))
	var end := int(rng.split("-")[1]) if rng.split("-")[1] != "" else file.get_len()
	if error:
		content = ("Couldn't serve file, ERROR = %s" % error).to_utf8()
	else:
		content = file.get_buffer(file.get_len()).subarray(start, end-1)
	file.close()
	return content

# Check if a file exists
#
# #### Parameters
# - file_path: Full path to the file
func _file_exists(file_path: String) -> bool:
	return File.new().file_exists(file_path)

# Get the full MIME type of a file from its extension
#
# #### Parameters
# - file_extension: Extension of the file to be served
func _get_mime(file_extension: String) -> String:
	var type: String = "application"
	var subtype : String = "octet-stream"
	match file_extension:
		# Web files
		"css","html","csv","js","mjs":
			if not block_html_render:
				type = "text"
				subtype = "javascript" if file_extension in ["js","mjs"] else file_extension 
		"php":
			if not block_html_render:
				subtype = "x-httpd-php"
		"ttf","woff","woff2":
			type = "font"
			subtype = file_extension
		# Image
		"png","bmp","gif","png","webp":
			type = "image"
			subtype = file_extension
		"jpeg","jpg":
			type = "image"
			subtype = "jpg"
		"tiff", "tif":
			type = "image"
			subtype = "jpg"
		"svg":
			type = "image"
			subtype = "svg+xml"
		"ico":
			type = "image"
			subtype = "vnd.microsoft.icon"
		# Documents
		"doc":
			subtype = "msword"
		"docx":
			subtype = "vnd.openxmlformats-officedocument.wordprocessingml.document"
		"7z":
			subtype = "x-7x-compressed"
		"gz":
			subtype = "gzip"
		"tar":
			subtype = "application/x-tar"
		"json","pdf","zip":
			subtype = file_extension
		"txt":
			type = "text"
			subtype = "plain"
		"ppt":
			subtype = "vnd.ms-powerpoint"
		# Audio
		"midi","mp3","wav", "webm":
			type = "audio"
			subtype = file_extension
		"mp4","mpeg":
			type = "video"
			subtype = file_extension
		"oga","ogg":
			type = "audio"
			subtype = "ogg"
		"mpkg":
			subtype = "vnd.apple.installer+xml"
		# Video
		"ogv":
			type = "video"
			subtype = "ogg"
		"avi":
			type = "video"
			subtype = "x-msvideo"
		"ogx":
			subtype = "ogg"
	return type + "/" + subtype
