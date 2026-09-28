extends SceneTree
## Renders the front end's backdrop from the game's own 3D world: a task group at sea at dusk,
## drawn by WorldView exactly as the command screen draws it, then darkened, softly blurred and
## vignetted so menus read over it. Needs a window, so run it under a virtual display:
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##       --script tools/art/render_backdrop.gd -- --scenario=res://data/scenarios/carrier_qualification.json
##
## Options after `--`, all optional:
##   --scenario=res://…        the scenario whose force is posed (default: Carrier Qualification)
##   --subject=CALLSIGN        the ship the camera tethers to (default: the first own carrier)
##   --sun=DEG                 the sun's height above the horizon, found in the evening (default 2.5)
##   --hours=H                 or: move the sun exactly H hours on from the scenario's start
##   --sun-side=DEG            look this far to the right of the sun (default 32)
##   --look=DEG                or: look along this true bearing
##   --pitch=DEG --range=F     the tether's height angle and range multiple (defaults 5, 1.6);
##                             not --zoom, which is the game's own chart flag
##   --spacing=NM              the scale of the escorts' stations beyond the subject (default 0.45)
##   --raw=PATH                also save the untreated render
##   --out=PATH                where the treated JPEG goes (default res://assets/ui/frontend_backdrop.jpg)
##   --quality=Q               JPEG quality 0–1 (default 0.82)
##   --frames=N                frames to run before the picture, so wakes are laid (default 90)
## The pose moves the player's own ships into a close formation in this throwaway process only;
## nothing is saved but the picture.

const OUT_DEFAULT := "res://assets/ui/frontend_backdrop.jpg"
## How the render is treated: brightness kept, the blur's downsample factor, the vignette depth.
const DARKEN := 0.62
const BLUR_DOWNSAMPLE := 6
const VIGNETTE := 0.45

var _args: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			_args[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
	call_deferred("_run")


func _arg(key: String, fallback: float) -> float:
	return float(_args[key]) if _args.has(key) else fallback


func _run() -> void:
	# Untyped on purpose: naming the game's classes here would compile them before the autoloads
	# they use exist.
	var main = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var scenario := str(_args.get("scenario", "res://data/scenarios/carrier_qualification.json"))
	main.start_scenario(scenario)
	main._hide_screens()
	main.simulation.ai_enabled = false
	# Autoloads are not compile-time names in a --script run; reach them through the tree.
	root.get_node("SoundFx").set("enabled", false)
	var clock: Node = root.get_node("SimClock")
	var own: Array = main.simulation.unit_manager.get_faction_units(main.simulation.player_faction)
	var ships: Array = []
	for u in own:
		if u.alive and u.spec.domain == "surface" and not u.is_aircraft():
			ships.append(u)
	if ships.is_empty():
		push_error("render_backdrop: the scenario has no own surface ships")
		quit(1)
		return
	var subject = ships[0]
	for u in ships:
		if u.callsign == str(_args.get("subject", "")) or (not _args.has("subject") and u.spec.aircraft_capacity > 0 and subject.spec.aircraft_capacity <= 0):
			subject = u
	var view = main._world_view
	var wp: GDScript = load("res://scripts/ui/world_presentation.gd")
	var start_unix := float(clock.get("start_unix_time"))
	if start_unix <= 0.0:
		start_unix = float(view._default_unix)
	var latlon: Vector2 = wp.latlon_of(subject.position, main.simulation.scenario.get("map", {}))
	var hours := _arg("hours", -1.0)
	if hours < 0.0:
		hours = _evening_hours(wp, start_unix + float(clock.get("sim_time")), latlon, _arg("sun", 2.5))
	var sun: Vector2 = wp.sun_angles(start_unix + float(clock.get("sim_time")) + hours * 3600.0, latlon.x, latlon.y)
	var look := _arg("look", sun.y + _arg("sun-side", 32.0))
	print("[Backdrop] sun %.1f deg up at %.0f deg, %.2f h on; looking %.0f" % [sun.x, sun.y, hours, look])
	_pose(subject, ships, _arg("spacing", 0.45), look)
	main.map.select_units([subject])
	# The pane leaves the command screen and fills the window; its camera label is not wanted.
	view.get_parent().remove_child(view)
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view._hud.visible = false
	main.visible = false
	view.set_mode(2)  # WorldView.Mode.FULL
	view.set_suspended(false)
	view.sun_offset_s = hours * 3600.0
	view.set_camera_mode(0)  # WorldView.CAM_TETHER
	# The tether's azimuth is measured from the bow; this one looks along `look`.
	view.set_orbit(look + 180.0 - float(subject.heading_deg), _arg("pitch", 5.0), _arg("range", 1.6))
	# Let the ships run a little so wakes and bow waves are laid before the picture is taken.
	clock.call("set_speed_index", 0)
	clock.call("set_paused", false)
	# Software renderers are slow at this size, so count frames and report progress.
	var started := Time.get_ticks_msec()
	for i in int(_arg("frames", 90)):
		await process_frame
		if i % 15 == 0:
			print("[Backdrop] frame %d, %.1f s" % [i, (Time.get_ticks_msec() - started) / 1000.0])
	clock.call("set_paused", true)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = view._viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("render_backdrop: nothing rendered (is a display available?)")
		quit(1)
		return
	image.convert(Image.FORMAT_RGB8)
	if _args.has("raw"):
		image.save_png(ProjectSettings.globalize_path(str(_args["raw"])))
	var treated := treat(image)
	var out := ProjectSettings.globalize_path(str(_args.get("out", OUT_DEFAULT)))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := treated.save_jpg(out, _arg("quality", 0.82))
	print("[Backdrop] %s %dx%d -> %s (%s)" % [subject.callsign, treated.get_width(), treated.get_height(), out, error_string(err)])
	quit(0 if err == OK else 1)


## The own ships posed for the picture: the subject in front, the rest spread out beyond it along
## the line of sight, all steaming one course across the frame.
static func _pose(subject, ships: Array, spacing_nm: float, look_deg: float) -> void:
	var heading := wrapf(look_deg - 70.0, 0.0, 360.0)
	var ahead := Vector2(sin(deg_to_rad(look_deg)), cos(deg_to_rad(look_deg)))
	var side := Vector2(ahead.y, -ahead.x)
	var stations := [Vector2(-1.3, 1.6), Vector2(1.5, 2.8), Vector2(-1.7, 4.6), Vector2(2.9, 5.6), Vector2(-0.4, 7.2), Vector2(4.0, 8.4)]
	var n := 0
	for u in ships:
		u.heading_deg = heading
		u.ordered_heading_deg = heading
		u.speed_kn = maxf(u.speed_kn, 14.0)
		u.ordered_speed_kn = u.speed_kn
		u.waypoints.clear()
		if u == subject:
			continue
		var s: Vector2 = stations[n % stations.size()] * spacing_nm
		u.position = subject.position + side * s.x + ahead * s.y
		n += 1


## Hours after `unix` until the sun sinks through `elevation_deg` in the evening.
static func _evening_hours(wp: GDScript, unix: float, latlon: Vector2, elevation_deg: float) -> float:
	var step := 0.02
	var h := 0.0
	var before: float = wp.sun_angles(unix, latlon.x, latlon.y).x
	while h < 30.0:
		h += step
		var now: float = wp.sun_angles(unix + h * 3600.0, latlon.x, latlon.y).x
		if before >= elevation_deg and now < elevation_deg:
			return h
		before = now
	return 0.0


## Darkens the render, blurs it softly (a smooth downsample and back), and pulls the corners down.
static func treat(source: Image) -> Image:
	var w := source.get_width()
	var h := source.get_height()
	var small := source.duplicate() as Image
	small.resize(maxi(w / BLUR_DOWNSAMPLE, 1), maxi(h / BLUR_DOWNSAMPLE, 1), Image.INTERPOLATE_LANCZOS)
	small.resize(w, h, Image.INTERPOLATE_CUBIC)
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	var centre := Vector2(w, h) * 0.5
	var reach := centre.length()
	for y in h:
		for x in w:
			# A little of the sharp render survives under the blur, so silhouettes still read.
			var c := small.get_pixel(x, y).lerp(source.get_pixel(x, y), 0.12)
			var d := Vector2(x, y).distance_to(centre) / reach
			var shade := DARKEN * (1.0 - VIGNETTE * smoothstep(0.35, 1.0, d))
			out.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade))
	return out
