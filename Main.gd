extends Control



func _ready():
	var server = HttpServer.new()
	server.port = 8080
	add_child(server)
	server.register_router("/", Main.new())
	server.register_router("/manifest.json", Manifest.new())
	var files_router = HttpFileRouter.new("user://songs")
	var assets = HttpFileRouter.new("res://assets")
	var imgs = HttpFileRouter.new("user://imgs")
	server.register_router("/songs", files_router)
	server.register_router("/assets", assets)
	server.register_router("/imgs", imgs)
	server.register_router("/search", APISearch.new())
	server.register_router("/get", APIGet.new())
	server.start()

class Main extends HttpRouter:
	func handle_get(_request: HttpRequest, response: HttpResponse) -> void:
		response.send(200, Global.file_handler("res://index.html"))

class Manifest extends HttpRouter:
	func handle_get(_request: HttpRequest, response: HttpResponse) -> void:
		response.send(200, Global.file_handler("res://manifest.json"), "application/json")


class APISearch extends HttpRouter:
	var queue := []
	func handle_get(request: HttpRequest, response: HttpResponse) -> void:
		if request.query.has("q"):
			if request.query.q.lstrip(" ") == "":
				response.json(200, {
					"songs": []
				})
				return
			var t := Thread.new()
			queue.append(t)
			t.start(self, "search_youtube", [request.query.q, response])
		else:
			Global.send_err(response, "'q' query not found.")

	func search_youtube(pass_args = []):
		var q: String = pass_args[0]
		var response: HttpResponse = pass_args[1]
		var k = q.to_lower().replace("%20", "")
		if Global.searches.has(k):
			k = Global.searches[q.to_lower().replace("%20", "")]
			if k["expires"] > Time.get_unix_time_from_system():
				response.json(200, {"songs": k["results"]})
				return
		response.headers = {"Cache-Control":"public, max-age=50400, immutable"}
		var args := [
#			"--print", "%(title)s|%(id)s|%(uploader)s<[]>", 
			"--print", "%(title)s|%(id)s<[]>", 
			"--no-update", 
			"-i", 
			"-q", 
			"--no-warnings", 
			"--skip-download", 
			"--flat-playlist", 
			"--playlist-end", "6",
			"--user-agent", "'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'", 
			'"https://music.youtube.com/search?q=%s&params=egWKAQIIAWoGEAMQBBAF"'%q
#			"ytsearch8:the song: %s"%q.http_unescape()
		]
		var oo = []
		var o = []
		var e := OS.execute("yt-dlp", args, true, o)
		if e == -1:
			Global.send_err(response, "Unknown yt-dlp error.")
			return
		while o != oo:
			oo = o
			var outs: String = o[-1]
			var out := outs.split("<[]>")
			out.resize(out.size()-1)
			var data := []
			for vid in out:
				var splitted = vid.split("|")
				var title: String = splitted[0].lstrip("\n")
				title = title.trim_suffix(title.substr(title.to_lower().find("(official")))
				var vid_data := {
					"title": title, 
					"id": splitted[1].rstrip("\n"),
					"url": "https://music.youtube.com/watch?v=%s"%splitted[1].rstrip("\n"),
					"thumbnail": "https://i.ytimg.com/vi/%s/maxresdefault.jpg"%splitted[1].rstrip("\n"),
#					"uploader": splitted[2].rstrip("\n").trim_suffix(" - Topic")
#					"thumbnail": splitted[3].rstrip("\n")
				}
				if !vid_data.title == "NA" and str(vid_data.id).find(" ") == -1:
					data.append(vid_data)
			Global.searches[q.to_lower().replace("%20", "")] = {"results": data, "expires": Time.get_unix_time_from_system() + 50400}
			Global._save()
			response.json(200, {"songs": data})
			return

class APIGet extends HttpRouter:
	var queue := []
	func handle_get(request: HttpRequest, response: HttpResponse) -> void:
		if request.query.has("id"):
			var t := Thread.new()
			queue.append(t)
			t.start(self, "download_song", [request.query.id, response])
		else:
			Global.send_err(response, "'id' query not found.")
	func download_song(pass_args = []):
		var user_path = ProjectSettings.globalize_path("user://")
		var url = "https://www.youtube.com/watch?v="+pass_args[0]
		var response: HttpResponse = pass_args[1]
		response.headers = {"Cache-Control":"public, max-age=31536000, immutable"}
		var img = Image.new()
		if !File.new().file_exists("user://imgs/%s.jpg"%pass_args[0]):
			var http := HTTPRequest.new()
			REQ.add_child(http)
			http.request("https://i.ytimg.com/vi/%s/sddefault.jpg"%pass_args[0])
			var res = yield(http, "request_completed")[3]
			http.queue_free()
			REQ.remove_child(http)
			img.load_jpg_from_buffer(res)
			img.lock()
			var color: Color = img.get_pixel(1, 60)
#			color.r = abs(0.205 - color.r)
#			color.g = abs(0.225 - color.g)
#			color.b = abs(0.24 - color.b)
#			color.r = (int(abs(0.1 * color.r)*1000) % 1000)/1000.0
#			color.g = (int(abs(0.2 * color.g)*1000) % 1000)/1000.0
#			color.b = (int(abs(0.6 * color.b)*1000) % 1000)/1000.0
			color.from_hsv(
				color.h,
				clamp(color.s * 0.7, 0.15, 0.55),
				0.5
			)
			Global.img_colors[pass_args[0]] = color
			img.unlock()
			img = img.get_rect(Rect2(((img.get_size().x-img.get_size().y)/2)+60, 60, img.get_size().y-120,img.get_size().y-120))
			img.save_png("user://imgs/%s.jpg"%pass_args[0])
			Global._save()
		var color = Global.img_colors[pass_args[0]]
		var file = File.new()
		if file.file_exists("user://songs/%s.webm"%pass_args[0]):
			response.send(200,JSON.print({"path":"/songs/%s.webm"%pass_args[0], "img": "/imgs/%s.jpg"%pass_args[0], "color": color.to_html(false)}), "application/json")
			file.close()
			return
		file.close()
#		"--cookies", user_path+"cookies.txt", "-x", "--audio-format", "webm",
		var args := [
			"-f", '"ba[ext=webm]"', "-P", user_path, "-o", "songs/%(id)s.webm", '"%s"'%url
		]
		var o := []
		var oo := []
		var e := OS.execute("yt-dlp", args, true, o)
		if e == -1:
			Global.send_err(response, "Unknown yt-dlp error.")
			return
		while o != oo:
			oo = o
			response.send(200,JSON.print({"path":"/songs/%s.webm"%pass_args[0], "img": "/imgs/%s.jpg"%pass_args[0], "color": color.to_html(false)}), "application/json")
