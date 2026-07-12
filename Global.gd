extends Node

var searches := {}
var img_colors := {}
func file_handler(path: String):
	var file := File.new()
	file.open(path, File.READ)
	var txt := file.get_as_text()
	file.close()
	return txt

func _ready():
	OS.window_minimized = true
	if !Directory.new().dir_exists("user://imgs"):
		Directory.new().make_dir("user://imgs")
	_load()
func _save():
	var file = File.new()
	file.open("user://searches.json", File.WRITE)
	file.store_var(searches)
	file.open("user://colors.json", File.WRITE)
	file.store_var(img_colors)
	file.close()
func _load():
	var file = File.new()
	if File.new().file_exists("user://searches.json"):
		file.open("user://searches.json", File.READ)
		searches = file.get_var()
	if File.new().file_exists("user://colors.json"):
		file.open("user://colors.json", File.READ)
		img_colors = file.get_var()
	file.close()

func send_err(response: HttpResponse, message: String):
	response.send(400, JSON.print({
		"message": message
	}), "application/json")
