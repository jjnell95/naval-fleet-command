class_name WorldScene
extends Node3D
## The 3D world behind the World View: sky and sun, the sea, land within sight, and a pool of
## entity nodes fed from the entries WorldPresentation produces. Nothing here decides what may be
## shown; it only draws what it is handed, at 1 unit per metre about a floating origin.
##
## The mood is the late-1990s fleet-command games' (a violet-blue sky over a dark, glinting sea,
## long white missile trails, black smoke over a burning ship) drawn with what a modern renderer
## can afford in the browser: shader sky, hand-lit sea, height-field land and pooled particles.

const ORIGIN_WRAP_M := 65536.0
const WAKE_SAMPLES := 26
const WAKE_LIFE_S := 150.0
const KELVIN_SPREAD := 0.09  # half-width growth per metre astern: the arms of the wake open out
## A round first seen younger than this (in simulation seconds, per unit of time compression)
## was seen leaving its launcher, so it gets a launch cloud and a trail from the launcher.
const FRESH_LAUNCH_S := 2.0
## One launch cloud per launcher this often, however big the salvo.
const LAUNCH_COOLDOWN_S := 0.7
const GUN_COOLDOWN_S := 0.09
const GUN_BURST_S := 1.5  # a gun round this fresh still flashes at its mount
## An aircraft of ours this close to its deck when it first appears has just launched.
const AIR_LAUNCH_NM := 1.5
const RECOVERY_WATCH_NM := 2.5
## Longest stretch of wake laid flat between two vertices near the eye; the vertex shader lifts each
## vertex onto the swell, so a longer one would cut through the crests between them.
const WAKE_SEGMENT_M := 12.0
const WAKE_DETAIL_M := 3000.0  # beyond this from the eye the swell is faded out and a wake needs no detail
## Navigation lights: the angle a lamp's glow spans, and below how much daylight they are lit.
const LAMP_SIZE := 0.016
const LAMPS_BELOW_DAYLIGHT := 0.6
## A lamp's arc: its centre in the model (+X the bow, +Z starboard) and the cosine of half its width.
const LAMP_MASTHEAD := Vector4(1.0, 0.0, 0.0, -0.3827)  # 225 degrees
const LAMP_PORT := Vector4(0.5556, 0.0, -0.8315, 0.5556)  # 112.5 degrees, centred 56.25 to port
const LAMP_STARBOARD := Vector4(0.5556, 0.0, 0.8315, 0.5556)
const LAMP_STERN := Vector4(-1.0, 0.0, 0.0, 0.3827)  # 135 degrees
## Sun shadows: the reach around the subject, as a multiple of its length.
const SHADOW_REACH := 4.0
## Sky, sea and light for day, twilight and night: [sky top, horizon, zenith, haze, fog].
const DAY := [Color("685cda"), Color("9d99cc"), Color("5a4ec8"), Color("aeaad6"), Color("938fbe")]
const TWILIGHT := [Color("2e2a66"), Color("8c6f86"), Color("1d1a48"), Color("a08492"), Color("3a3450")]
const NIGHT := [Color("05060f"), Color("141626"), Color("020308"), Color("1a1c2c"), Color("0b0c14")]

var origin_nm := Vector2.ZERO
var camera: Camera3D
var effects: WorldEffects
var land: WorldLand
var daylight := 1.0
var sea_state := -1
var anim := 0.0
var sim_now := 0.0
## Simulation seconds since the last tick, for drawing moving things where they are between ticks.
var lead_s := 0.0
var paused := false
## The simulation's time compression, for the pace of smoke and fire.
var time_rate := 1.0
## The pane turns shadows on only when it is big enough for them to show (full screen or swapped
## with the chart); the small always-on pane keeps its frame budget.
var shadows_allowed := false

var _env: Environment
var _sky_material: ShaderMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _ocean: MeshInstance3D
var _ocean_material: ShaderMaterial
var _wake_material: ShaderMaterial
var _entities: Node3D
var _records: Dictionary = {}
var _trails: Dictionary = {}  # key -> Array[Vector3] (nm x, nm y, sim time), oldest first
var _headings: Dictionary = {}  # key -> Vector3 (heading, sim time, bank)
var _models := WorldModels.new()
var _strip_pool: Array[MeshInstance3D] = []
var _swell := Vector4.ZERO
var _wind := Vector2.RIGHT
var _wind2 := Vector2(0.8, 0.6)
var _visibility_nm := WorldPresentation.DEFAULT_VISIBILITY_NM
var _ring_mesh: ArrayMesh
var _disc_mesh: PlaneMesh
var _disc_material: StandardMaterial3D
var _materials: Dictionary = {}
var _events: Array[Dictionary] = []
var _launch_clock: Dictionary = {}  # launcher key -> anim time of its last launch cloud or flash
var _flagged: Dictionary = {}  # aircraft key -> the last deck event reported for it: "launch" or "recovery"
var _ground: Dictionary = {}  # installation key -> ground height, computed once
var _warm := false
var _sun_key := Vector2(INF, INF)
var _sun_up := 0.0
var _bow_mesh: PlaneMesh
var _bow_material: ShaderMaterial
var _rotor_mesh: PlaneMesh
var _rotor_material: ShaderMaterial
var _lamp_mesh: QuadMesh
var _lamp_materials: Dictionary = {}
var _lamps_lit := false
var _focus_key := ""


# --- Construction --------------------------------------------------------------------------

func build() -> void:
	name = "WorldScene"
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = load("res://scripts/ui/world_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Linear, so the sky and sea land on their palette exactly; nothing here is bright enough to
	# need a curve.
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_sky_affect = 0.0
	_env.fog_sun_scatter = 0.08
	var env_node := WorldEnvironment.new()
	env_node.environment = _env
	add_child(env_node)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = false
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 900.0
	_sun.shadow_bias = 0.1
	_sun.shadow_normal_bias = 2.5
	_sun.light_angular_distance = 0.5
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.62, 0.68, 0.95)
	_moon.light_energy = 0.0
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = WorldCamera.FOV_DEG
	camera.near = 2.0
	camera.far = 420000.0
	add_child(camera)
	camera.current = true
	_ocean_material = ShaderMaterial.new()
	_ocean_material.shader = load("res://scripts/ui/world_ocean.gdshader")
	_ocean = MeshInstance3D.new()
	_ocean.name = "Ocean"
	_ocean.mesh = WorldMeshes.ocean()
	_ocean.material_override = _ocean_material
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ocean)
	_wake_material = ShaderMaterial.new()
	_wake_material.shader = load("res://scripts/ui/world_wake.gdshader")
	_wake_material.render_priority = 1
	land = WorldLand.new()
	add_child(land)
	land.build()
	_ocean_material.set_shader_parameter("coast_mask", land.coast_texture())
	_entities = Node3D.new()
	_entities.name = "Entities"
	add_child(_entities)
	effects = WorldEffects.new()
	add_child(effects)
	_ring_mesh = WorldMeshes.ring()
	_bow_mesh = PlaneMesh.new()
	_bow_mesh.size = Vector2.ONE
	_bow_mesh.subdivide_width = 23
	_bow_mesh.subdivide_depth = 11
	_bow_material = ShaderMaterial.new()
	_bow_material.shader = load("res://scripts/ui/world_bow.gdshader")
	_bow_material.render_priority = 1
	_rotor_mesh = PlaneMesh.new()
	_rotor_mesh.size = Vector2(2.0, 2.0)
	_rotor_material = ShaderMaterial.new()
	_rotor_material.shader = load("res://scripts/ui/world_rotor.gdshader")
	_rotor_material.render_priority = 2
	_lamp_mesh = QuadMesh.new()
	_lamp_mesh.size = Vector2(LAMP_SIZE, LAMP_SIZE)
	var lamp_shader: Shader = load("res://scripts/ui/world_light.gdshader")
	for lamp in [["white", Color(1.0, 0.96, 0.86), 0.0], ["red", Color(1.0, 0.16, 0.1), 0.0], ["green", Color(0.2, 1.0, 0.45), 0.0], ["beacon", Color(1.0, 0.12, 0.08), 1.1]]:
		var m := ShaderMaterial.new()
		m.shader = lamp_shader
		m.set_shader_parameter("color", lamp[1])
		m.set_shader_parameter("flash_period", lamp[2])
		m.render_priority = 3
		_lamp_materials[lamp[0]] = m
	_disc_mesh = PlaneMesh.new()
	_disc_mesh.size = Vector2(2.0, 2.0)
	_disc_material = StandardMaterial3D.new()
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_material.albedo_texture = WorldEffects._radial_texture()
	_disc_material.albedo_color = Color(0.9, 0.94, 0.96, 0.32)
	_disc_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_disc_material.render_priority = 1
	set_weather(0, WorldPresentation.DEFAULT_VISIBILITY_NM, {})
	set_time_of_day(Vector3(0.3, 0.6, 0.5).normalized(), 40.0)


## The chart box whose coast the polygons define; outside it the raster's land carries on.
func set_chart(charted: Rect2) -> void:
	if land != null and land.charted != charted:
		land.charted = charted
		land.reset()


## The pane stopped or started drawing. Nothing to do yet but keep the hook for the shell.
func set_running(_live: bool) -> void:
	pass


# --- Environment ---------------------------------------------------------------------------

## Sea state and visibility from the scenario. Cheap to call every frame; it only touches the
## renderer when something changed.
func set_weather(state: int, visibility_nm: float, env: Dictionary) -> void:
	if state == sea_state and is_equal_approx(visibility_nm, _visibility_nm):
		return
	sea_state = state
	_visibility_nm = visibility_nm
	_swell = WorldPresentation.swell_params(state)
	_wind = WorldPresentation.wind_direction(env)
	_wind2 = _wind.rotated(0.65)
	_ocean_material.set_shader_parameter("sea_state", float(state))
	_ocean_material.set_shader_parameter("swell_a", _swell)
	_ocean_material.set_shader_parameter("swell_dir", Vector4(_wind.x, _wind.y, _wind2.x, _wind2.y))
	RenderingServer.global_shader_parameter_set("world_swell_a", _swell if state > 0 else Vector4(0.0, _swell.y, 0.0, _swell.w))
	RenderingServer.global_shader_parameter_set("world_swell_dir", Vector4(_wind.x, _wind.y, _wind2.x, _wind2.y))
	# Thin haze: the sea stays dark to the horizon as the old games drew it, and the weather still
	# closes it in when the visibility drops. The sea lights itself and keeps the environment's fog
	# off, so it takes its own share, which is nothing on a clear day; the sky is washed toward the
	# fog colour as the visibility falls, so the horizon softens instead of standing out sharp.
	_env.fog_density = haze_density(visibility_nm)
	_env.fog_sky_affect = sky_murk(visibility_nm)
	_ocean_material.set_shader_parameter("fog_density", sea_fog_density(visibility_nm))
	var wind_kn := float(env.get("wind_kn", 8.0 + 4.0 * state))
	effects.wind = Vector3(_wind.x, 0.0, _wind.y) * wind_kn * 0.51


## Sky, sun, moon, ambient and haze for a solar elevation. Three palettes, night, twilight and
## day, are blended by elevation; the day is the violet-blue and lavender of the old games. Only
## touches the renderer when the sun has moved enough to matter.
func set_time_of_day(sun_dir: Vector3, elevation_deg: float) -> void:
	var key := Vector2(snappedf(elevation_deg, 0.05), snappedf(atan2(sun_dir.x, sun_dir.z), 0.002))
	if key == _sun_key:
		return
	_sun_key = key
	var twilight := smoothstep(-14.0, -3.0, elevation_deg)
	var day := smoothstep(-3.0, 10.0, elevation_deg)
	var pal: Array[Color] = []
	for i in DAY.size():
		pal.append((NIGHT[i] as Color).lerp(TWILIGHT[i], twilight).lerp(DAY[i], day))
	var top: Color = pal[0]
	var horizon: Color = pal[1]
	_sky_material.set_shader_parameter("top_color", top)
	_sky_material.set_shader_parameter("horizon_color", horizon)
	_sky_material.set_shader_parameter("zenith_color", pal[2])
	_sky_material.set_shader_parameter("haze_color", pal[3])
	_sky_material.set_shader_parameter("below_color", Color(0.075, 0.094, 0.137) * (0.3 + 0.7 * (0.08 + 0.42 * twilight + 0.5 * day)))
	_sky_material.set_shader_parameter("sun_dir", sun_dir)
	var sun_up := smoothstep(-1.0, 6.0, elevation_deg)
	var sun_color := Color(1.0, 0.76, 0.56).lerp(Color(1.0, 0.97, 0.92), clampf(elevation_deg / 14.0, 0.0, 1.0))
	_sky_material.set_shader_parameter("sun_color", sun_color)
	_sky_material.set_shader_parameter("sun_visible", smoothstep(-2.0, 0.5, elevation_deg))
	_sky_material.set_shader_parameter("sun_glow", lerpf(0.55, 0.22, day))
	_sky_material.set_shader_parameter("stars", 0.8 * (1.0 - twilight))
	_sun.light_color = sun_color
	_sun.light_energy = 1.15 * sun_up
	_sun_up = sun_up
	_apply_shadows()
	if sun_dir.length_squared() > 1e-6:
		var up := Vector3.UP if absf(sun_dir.y) < 0.999 else Vector3.FORWARD
		_sun.look_at_from_position(sun_dir * 1000.0, Vector3.ZERO, up)
	_moon.light_energy = 0.18 * (1.0 - twilight)
	var moon_dir := Vector3(-sun_dir.x, 0.65, -sun_dir.z).normalized()
	_moon.look_at_from_position(moon_dir * 1000.0, Vector3.ZERO, Vector3.UP)
	_env.ambient_light_color = Color(0.10, 0.11, 0.20).lerp(Color(0.44, 0.40, 0.60), twilight).lerp(Color(0.56, 0.56, 0.74), day)
	_env.ambient_light_energy = 0.28 + 0.14 * twilight + 0.1 * day
	_env.fog_light_color = pal[4]
	_env.fog_light_energy = 1.0
	_ocean_material.set_shader_parameter("fog_color", pal[4])
	daylight = 0.08 + 0.42 * twilight + 0.5 * day
	effects.daylight = daylight
	# The hull finishes' hemisphere: the sky's light from above, the sea's dark bounce from below,
	# and the horizon for what a glancing reflection sees. See world_hull.gdshader.
	RenderingServer.global_shader_parameter_set("world_sky_color", horizon.lerp(top, 0.3).lerp(Color(0.64, 0.68, 0.74), 0.65 * day))
	RenderingServer.global_shader_parameter_set("world_sea_color", Color(0.09, 0.1, 0.14).lerp(Color(0.2, 0.23, 0.3), day))
	RenderingServer.global_shader_parameter_set("world_horizon_color", horizon)
	RenderingServer.global_shader_parameter_set("world_ambient", 0.1 + 0.2 * twilight + 0.3 * day)
	RenderingServer.global_shader_parameter_set("world_daylight", daylight)
	_lamps_lit = daylight < LAMPS_BELOW_DAYLIGHT
	land.set_daylight(daylight)
	_ocean_material.set_shader_parameter("sky_top", top)
	_ocean_material.set_shader_parameter("sky_horizon", horizon)
	_ocean_material.set_shader_parameter("sun_color", sun_color)
	_ocean_material.set_shader_parameter("sun_dir", sun_dir)
	_ocean_material.set_shader_parameter("sun_strength", smoothstep(-1.5, 5.0, elevation_deg))
	_ocean_material.set_shader_parameter("daylight", daylight)


## Sun shadows on or off: WorldView asks for them when the pane is big enough to show them.
func set_shadows(on: bool) -> void:
	shadows_allowed = on
	_apply_shadows()


func _apply_shadows() -> void:
	_sun.shadow_enabled = shadows_allowed and _sun_up > 0.1


## The environment's fog per metre for a visibility: a thin haze that hulls, land and smoke fade
## into with distance.
static func haze_density(visibility_nm: float) -> float:
	return 0.45 / (maxf(visibility_nm, 0.1) * WorldPresentation.NM_TO_M)


## The sea's own fog per metre: none at a clear day's visibility or better, rising toward the
## environment's haze as the weather closes in.
static func sea_fog_density(visibility_nm: float) -> float:
	return maxf(haze_density(visibility_nm) - haze_density(WorldPresentation.DEFAULT_VISIBILITY_NM), 0.0)


## How far the sky is washed toward the fog colour: none on a clear day, most of the way in fog.
static func sky_murk(visibility_nm: float) -> float:
	return clampf(1.0 - visibility_nm / WorldPresentation.DEFAULT_VISIBILITY_NM, 0.0, 0.9)


func _origin_offset() -> Vector2:
	var m := origin_nm * WorldPresentation.NM_TO_M
	return Vector2(fposmod(m.x, ORIGIN_WRAP_M), fposmod(-m.y, ORIGIN_WRAP_M))


## Height of the water at a point in origin-relative metres, from the same swell as the shader.
func swell_at(p: Vector3) -> float:
	if sea_state <= 0:
		return 0.0
	var off := _origin_offset()
	return WorldPresentation.swell_height(Vector2(p.x + off.x, p.z + off.y), anim, _swell, _wind, _wind2)


## Height of the ground under a point in origin-relative metres, 0 at sea. Errs high, for the
## camera's clearance.
func ground_at(p: Vector3) -> float:
	if land == null:
		return 0.0
	var c := WorldCamera.to_chart(p, origin_nm)
	return land.height_at(Vector2(c.x, c.y))


# --- Entities ------------------------------------------------------------------------------

## Syncs the pool with this frame's entries. `entries` are WorldPresentation dictionaries; the
## ones missing since last frame are retired, which for a unit that has just died means sinking,
## and for a round means leaving its smoke behind.
func update(delta: float, entries: Array, focus_key: String) -> void:
	anim += delta
	_focus_key = focus_key
	effects.origin_nm = origin_nm
	effects.rate = 0.0 if paused else clampf(time_rate, 1.0, WorldEffects.MAX_RATE)
	land.update(origin_nm)
	var wanted: Dictionary = {}
	for e: Dictionary in entries:
		wanted[e["key"]] = true
		_apply_entry(e, focus_key)
	for key in _records.keys():
		if not wanted.has(key):
			_retire(key)
	for key in _flagged.keys():
		if not wanted.has(key):
			_flagged.erase(key)
	effects.tick(delta)
	_warm = true


## After the camera has been placed for the frame: the sea follows it, and the ribbons and glows
## that face it are rebuilt.
func camera_moved() -> void:
	if camera == null:
		return
	var eye := camera.global_position
	_ocean.position = Vector3(eye.x, 0.0, eye.z)
	_ocean_material.set_shader_parameter("origin_offset", _origin_offset())
	_ocean_material.set_shader_parameter("swell_time", anim)
	_ocean_material.set_shader_parameter("coast_window", land.coast_window())
	RenderingServer.global_shader_parameter_set("world_origin_offset", _origin_offset())
	RenderingServer.global_shader_parameter_set("world_swell_time", anim)
	if _sun.shadow_enabled:
		_fit_shadows(eye)
	effects.eye = eye
	effects.draw_trails()


## Shadows reach from the eye just past the subject and no further, so the shadow map is spent on
## what the camera is looking at.
func _fit_shadows(eye: Vector3) -> void:
	var rec: Dictionary = _records.get(_focus_key, {})
	var reach := 600.0
	if not rec.is_empty() and rec.get("root") != null:
		var length := float(rec["entry"]["length_m"])
		reach = eye.distance_to((rec["root"] as Node3D).position) + length * SHADOW_REACH * 0.5
	reach = clampf(reach, 150.0, 3000.0)
	if absf(reach - _sun.directional_shadow_max_distance) > reach * 0.1:
		_sun.directional_shadow_max_distance = reach


## Launches, aircraft leaving or reaching a deck: things the Action camera may cut to, since the
## last call. Each is {kind, at: Vector3 chart (nm, nm, m), key}.
func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func _model_for(e: Dictionary) -> String:
	if e["kind"] == "buoy":
		return "marker:buoy"
	if e["kind"] == "weapon" and e.get("gun", false):
		return "marker:tracer"
	var model: String = e["model"]
	if model != "" and ResourceLoader.exists("res://assets/models/%s.glb" % model):
		return model
	if e["kind"] == "weapon":
		return "marker:weapon"
	var domain: String = e["domain"]
	return "marker:" + (domain if domain in ["surface", "air", "subsurface"] else "surface")


## Where to draw an entry: what the simulation last said, carried on along its course for the
## part of a tick that has passed since, so nothing moves in quarter-second hops. Only things
## drawn at truth (ours, sighted, rounds) are carried on; a plotted contact stays on its plot.
func _render_position(e: Dictionary) -> Vector2:
	var pos: Vector2 = e["position"]
	if lead_s <= 0.0 or not e["has_heading"]:
		return pos
	var speed_nm_s := 0.0
	match e["kind"]:
		"own", "visual":
			var u: Unit = e.get("unit")
			speed_nm_s = u.speed_kn / 3600.0 if u != null else 0.0
		"weapon":
			var w: Weapon = e.get("weapon")
			speed_nm_s = w.speed_nm_per_s() if w != null else 0.0
	return pos + Geo.heading_to_vector(e["heading_deg"]) * speed_nm_s * lead_s


func _apply_entry(e: Dictionary, focus_key: String) -> void:
	var key: String = e["key"]
	var model_id := _model_for(e)
	var rec: Dictionary = _records.get(key, {})
	var fresh := rec.is_empty()
	if fresh:
		rec = {"key": key, "model_id": "", "ring": null, "disc": null, "bow": null, "wake": null, "fire": null, "plume": null, "glow": null, "dying_since": -1.0, "tint": "", "speed_set": -1.0, "lamps_on": false}
		_records[key] = rec
	if rec["model_id"] != model_id:
		if rec["model_id"] != "":
			_release_model(rec)
		var acquired := _models.acquire(model_id, _entities)
		rec["model_id"] = model_id
		rec["root"] = acquired["node"]
		rec["bounds"] = acquired["bounds"]
		rec["meshes"] = acquired["meshes"]
		rec["tint"] = ""
		rec["speed_set"] = -1.0
		rec["lamps_on"] = false
		_fit_out(rec, e)
	rec["entry"] = e
	rec["dying_since"] = -1.0
	var root: Node3D = rec["root"]
	var bounds: AABB = rec["bounds"]
	var length: float = e["length_m"]
	var scale := WorldPresentation.model_scale(length)
	var height_units := bounds.size.y
	rec["height_m"] = height_units * scale
	var pos := _render_position(e)
	rec["nm"] = pos
	var base := WorldPresentation.to_world(pos, origin_nm, float(e["height_m"]))
	var heading: float = e["heading_deg"] if e["has_heading"] else 0.0
	var yaw := WorldPresentation.heading_to_yaw(heading)
	var pitch := 0.0
	var roll := 0.0
	var lift := 0.0
	var domain: String = e["domain"]
	var unit: Unit = e.get("unit")
	root.visible = true
	root.scale = Vector3.ONE * scale
	match domain:
		"surface":
			lift = WorldPresentation.hull_lift_m(height_units, scale)
			var motion := _sea_motion(base, heading, length, scale)
			lift += motion.x
			pitch = motion.y
			roll = motion.z
			if unit != null:
				# Flooding settles a hull and lists it toward the side taking water.
				roll += deg_to_rad(13.0) * unit.flooding * (1.0 if unit.id % 2 == 0 else -1.0)
				pitch += deg_to_rad(2.5) * unit.flooding
				lift -= unit.flooding * rec["height_m"] * 0.12
		"land":
			lift = -bounds.position.y * scale + _ground_under(key, pos) - rec["height_m"] * 0.06
		"air":
			roll = _bank_for(key, heading)
		"subsurface":
			lift = 0.0
		"buoy":
			lift = swell_at(base) - 0.2 * scale
		"weapon":
			if e.get("torpedo", false):
				lift = 0.0
			elif e.get("ballistic", false):
				pitch = deg_to_rad(38.0) * (1.0 if _ballistic_climbing(e) else -1.0)
	root.position = base + Vector3(0.0, lift, 0.0)
	root.rotation = Vector3(roll, yaw, pitch)
	rec["anchor"] = root.position + Vector3(0.0, rec["height_m"] * 0.5 + 2.0, 0.0)
	_apply_look(rec, e, focus_key)
	_apply_way(rec, e, root, yaw, length, scale)
	_apply_lamps(rec, e)
	if fresh and e["kind"] == "weapon":
		_on_new_round(rec, e)
	_apply_trails(rec, e, base, heading, length)
	_apply_emitters(rec, e, root.position, heading)
	if e["kind"] == "own" and domain == "air":
		_air_events(rec, e, fresh)


## A model just taken from the pool for this record: whether its finishes meet the sea, and the
## fittings that go with the model wherever it is used (a rotor disc, navigation lights). The
## fittings are children of the model's node, so they stay with it in the pool.
func _fit_out(rec: Dictionary, e: Dictionary) -> void:
	var domain: String = e["domain"]
	var at_sea := 1.0 if domain in ["surface", "subsurface"] else 0.0
	for mi: MeshInstance3D in rec["meshes"]:
		if mi.has_meta("finish"):
			mi.set_instance_shader_parameter("at_sea", at_sea)
			mi.set_instance_shader_parameter("hull_speed", 0.0)
	var root: Node3D = rec["root"]
	var bounds: AABB = rec["bounds"]
	if rec["model_id"].begins_with("marker:"):
		return
	if domain == "air" and not root.has_meta("rotor"):
		var spec := DataDB.platform(rec["model_id"])
		if spec != null and spec.can_hover:
			var disc := MeshInstance3D.new()
			disc.name = "Rotor"
			disc.mesh = _rotor_mesh
			disc.material_override = _rotor_material
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var plane := WorldModels.rotor_plane(rec["model_id"], rec["meshes"], bounds)
			disc.position = Vector3(plane.x, plane.y + 0.02, plane.z)
			disc.scale = Vector3.ONE * plane.w
			root.add_child(disc)
		root.set_meta("rotor", true)
	if domain in ["surface", "air"] and not root.has_meta("lamps"):
		root.set_meta("lamps", _lamps_for(root, bounds, domain))


## Navigation lights on a model's node, placed from its bounds (bow along +X, starboard +Z).
func _lamps_for(root: Node3D, b: AABB, domain: String) -> Array:
	var c := b.get_center()
	var spots: Array = []
	if domain == "surface":
		# Arcs as the rules of the road give them: masthead over 225 degrees ahead, each sidelight from
		# dead ahead to 22.5 degrees abaft its beam, the stern light over the 135 degrees astern.
		spots = [
			["white", Vector3(c.x + b.size.x * 0.1, b.end.y - b.size.y * 0.03, c.z), LAMP_MASTHEAD],
			["red", Vector3(c.x + b.size.x * 0.12, b.position.y + b.size.y * 0.6, b.position.z + b.size.z * 0.06), LAMP_PORT],
			["green", Vector3(c.x + b.size.x * 0.12, b.position.y + b.size.y * 0.6, b.end.z - b.size.z * 0.06), LAMP_STARBOARD],
			["white", Vector3(b.position.x + b.size.x * 0.005, b.position.y + b.size.y * 0.42, c.z), LAMP_STERN],
		]
	else:
		spots = [
			["red", Vector3(c.x - b.size.x * 0.06, c.y, b.position.z)],
			["green", Vector3(c.x - b.size.x * 0.06, c.y, b.end.z)],
			["white", Vector3(b.position.x, c.y, c.z)],
			["beacon", Vector3(c.x, c.y + b.size.y * 0.3, c.z)],
		]
	var lamps: Array = []
	for spot: Array in spots:
		var lamp := MeshInstance3D.new()
		lamp.mesh = _lamp_mesh
		lamp.material_override = _lamp_materials[spot[0]]
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.position = spot[1]
		lamp.visible = false
		lamp.set_instance_shader_parameter("phase", randf())
		if spot.size() > 2:
			lamp.set_instance_shader_parameter("arc", spot[2])
		root.add_child(lamp)
		lamps.append(lamp)
	return lamps


## The hull's way through the water: its speed to the finishes (for the bow's spray) and the bow
## wave on the water around it.
func _apply_way(rec: Dictionary, e: Dictionary, root: Node3D, yaw: float, length: float, scale: float) -> void:
	var unit: Unit = e.get("unit")
	var domain: String = e["domain"]
	var speed := unit.speed_kn * 0.5144 if unit != null else 0.0
	if domain in ["surface", "subsurface"] and absf(speed - float(rec["speed_set"])) > 0.4:
		rec["speed_set"] = speed
		for mi: MeshInstance3D in rec["meshes"]:
			if mi.has_meta("finish"):
				mi.set_instance_shader_parameter("hull_speed", speed)
		if rec["bow"] != null:
			(rec["bow"] as MeshInstance3D).set_instance_shader_parameter("hull_speed", speed)
	var bow: MeshInstance3D = rec["bow"]
	var under_way: bool = domain == "surface" and unit != null and speed > 0.3 and e["kind"] in ["own", "visual"] and not rec["model_id"].begins_with("marker:")
	if not under_way:
		if bow != null:
			bow.visible = false
		return
	var bounds: AABB = rec["bounds"]
	var beam := minf(bounds.size.z * scale, length * 0.14)
	if bow == null:
		bow = MeshInstance3D.new()
		bow.mesh = _bow_mesh
		bow.material_override = _bow_material
		bow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bow.extra_cull_margin = 8.0
		_entities.add_child(bow)
		bow.set_instance_shader_parameter("hull_speed", speed)
		rec["bow"] = bow
	bow.set_instance_shader_parameter("hull_beam", beam)
	bow.visible = true
	bow.position = Vector3(root.position.x, 0.0, root.position.z)
	bow.rotation = Vector3(0.0, yaw, 0.0)
	bow.scale = Vector3(length * 1.5, 1.0, length * 0.5 + beam * 3.0)


## Navigation lights come on as the light goes, on ours and on anything sighted.
func _apply_lamps(rec: Dictionary, e: Dictionary) -> void:
	var root: Node3D = rec["root"]
	var lamps: Array = root.get_meta("lamps", [])
	if lamps.is_empty():
		return
	var want: bool = _lamps_lit and e["kind"] in ["own", "visual"] and rec["dying_since"] < 0.0
	var unit: Unit = e.get("unit")
	if want and unit != null and e["domain"] == "air" and not unit.in_flight():
		want = false
	if want == rec["lamps_on"]:
		return
	rec["lamps_on"] = want
	for lamp: MeshInstance3D in lamps:
		lamp.visible = want


## Ground height under an installation, worked out once: it does not move.
func _ground_under(key: String, pos: Vector2) -> float:
	if _ground.has(key):
		return _ground[key]
	var inland := Terrain.distance_to_land_nm(pos)
	var l := Terrain.land_at(pos)
	if l != null:
		inland = l.distance_to_shore_nm(pos)
	var h := land.height_at(pos, inland * WorldPresentation.NM_TO_M) if land != null else WorldLand.BASE_M
	h = maxf(h, WorldLand.BASE_M)
	_ground[key] = h
	return h


## Heave, pitch and roll from the swell under a hull. Big ships answer the sea less.
func _sea_motion(base: Vector3, heading: float, length: float, _scale: float) -> Vector3:
	if sea_state <= 0:
		return Vector3.ZERO
	var fwd := WorldPresentation.heading_vector(heading)
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var half := length * 0.5
	var beam := maxf(length * 0.12, 4.0)
	var h_c := swell_at(base)
	var h_bow := swell_at(base + fwd * half)
	var h_stern := swell_at(base - fwd * half)
	var h_stbd := swell_at(base + side * beam)
	var h_port := swell_at(base - side * beam)
	var response := clampf(140.0 / maxf(length, 20.0), 0.25, 1.0)
	var pitch := atan2(h_bow - h_stern, length) * response
	var roll := atan2(h_stbd - h_port, beam * 2.0) * response * 1.4
	return Vector3(h_c, pitch, roll)


## Aircraft bank into their turns. The heading rate comes from the last frame's heading.
func _bank_for(key: String, heading: float) -> float:
	var prev: Vector3 = _headings.get(key, Vector3(heading, sim_now, 0.0))
	var dt := sim_now - prev.y
	var bank: float = prev.z
	if dt > 0.05:
		var rate := Geo.heading_delta(prev.x, heading) / dt
		var target := clampf(-rate * 9.0, -50.0, 50.0)
		bank = lerpf(bank, target, clampf(dt * 1.5, 0.0, 1.0))
		_headings[key] = Vector3(heading, sim_now, bank)
	return deg_to_rad(bank)


func _ballistic_climbing(e: Dictionary) -> bool:
	var w: Weapon = e.get("weapon")
	return w != null and w.distance_flown_nm < w.spec.max_range_nm * 0.5


## Tint, translucency and the ring on the water for a contact drawn from the plot.
func _apply_look(rec: Dictionary, e: Dictionary, _focus_key: String) -> void:
	var kind: String = e["kind"]
	var color: Color = e["color"]
	var under := float(e["height_m"]) < -0.5
	var tint := ""
	if kind == "own" and under:
		tint = "ghost:%s" % Color(0.55, 0.75, 0.95).to_html(false)
	elif kind == "plotted":
		tint = ("ghost:%s" if under else "tint:%s") % color.to_html(false)
	elif kind == "weapon" and under:
		tint = "ghost:%s" % Color(0.7, 0.85, 0.95).to_html(false)
	elif rec["model_id"] == "marker:tracer":
		tint = "glow:%s" % Color(1.0, 0.78, 0.4).to_html(false)
	elif rec["model_id"].begins_with("marker:") and kind != "buoy":
		tint = "marker:%s" % color.to_html(false)
	if tint != rec["tint"]:
		_set_tint(rec, tint)
	# A plotted contact is an estimate; the ring on the water says how good one.
	var ring: MeshInstance3D = rec["ring"]
	if kind == "plotted":
		if ring == null:
			ring = MeshInstance3D.new()
			ring.mesh = _ring_mesh
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_entities.add_child(ring)
			rec["ring"] = ring
		var radius: float = maxf(float(e["length_m"]) * 0.8, 24.0)
		var track: Track = e.get("track")
		if track != null:
			radius = clampf(maxf(radius, track.position_error_nm * WorldPresentation.NM_TO_M), radius, 3.0 * WorldPresentation.NM_TO_M)
		ring.material_override = _flat_material("ring:%s:0.45" % color.to_html(false), Color(color, 0.45), false)
		var root: Node3D = rec["root"]
		var at := Vector3(root.position.x, 0.0, root.position.z)
		ring.position = Vector3(at.x, swell_at(at) + 0.6, at.z)
		ring.scale = Vector3.ONE * radius
		ring.visible = true
	elif ring != null:
		ring.visible = false


func _set_tint(rec: Dictionary, tint: String) -> void:
	rec["tint"] = tint
	var meshes: Array = rec["meshes"]
	var material: Material = null
	if tint != "":
		var kind := tint.get_slice(":", 0)
		var color := Color.html(tint.get_slice(":", 1))
		match kind:
			"ghost":
				material = _tint_material(tint, Color(color, 0.42), true)
			"tint":
				material = _tint_material(tint, Color(color, 0.72), false)
			"marker":
				material = _tint_material(tint, Color(color, 0.55), false)
			"glow":
				material = _flat_material(tint, Color(color, 0.95), false)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		if material == null and mi.has_meta("finish"):
			WorldMaterials.restore(mi)
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, material)


## The look of a model shown as something other than itself: a plotted contact in its identity
## colour, or (`xray`) something under the water seen through it. See world_tint.gdshaderinc.
func _tint_material(key: String, color: Color, xray: bool) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/ui/world_xray.gdshader" if xray else "res://scripts/ui/world_tint.gdshader")
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("sweep", 1.0 if xray else 0.0)
	m.render_priority = 3 if xray else 0
	_materials[key] = m
	return m


func _flat_material(key: String, color: Color, ghost: bool) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(color, 1.0)
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.6
	if ghost:
		m.no_depth_test = true
		m.render_priority = 3
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if key.begins_with("ring:"):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if key.begins_with("glow:"):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_materials[key] = m
	return m


# --- Launches and flight deck events -------------------------------------------------------

## A round seen for the first time. If it has only just left its launcher and the launcher is on
## the view (ours, or sighted), the launch is drawn there: a cloud of white smoke for a missile,
## a muzzle flash for a gun, a splash for a torpedo, and the trail starts at the launcher. Our own
## launches are offered to the Action camera whether or not the launcher is in view.
func _on_new_round(rec: Dictionary, e: Dictionary) -> void:
	var w: Weapon = e.get("weapon")
	if w == null or not _warm or w.shooter == null:
		return
	if w.time_alive_s > FRESH_LAUNCH_S * maxf(time_rate, 1.0) + 0.5:
		return
	var gun: bool = e.get("gun", false)
	var nm: Vector2 = rec["nm"]
	if e["own"] and not gun:
		_events.append({"kind": "launch", "at": Vector3(nm.x, nm.y, float(e["height_m"])), "key": e["key"]})
	var shooter_key := "u:%d" % w.shooter.id
	var srec: Dictionary = _records.get(shooter_key, {})
	if srec.is_empty() or srec.get("root") == null or not (srec["entry"]["kind"] in ["own", "visual"]):
		return
	var sroot: Node3D = srec["root"]
	var sentry: Dictionary = srec["entry"]
	var slen: float = sentry["length_m"]
	var aloft: bool = sentry["domain"] == "air"
	var at := sroot.position + Vector3(0.0, 0.0 if aloft else float(srec["height_m"]) * 0.12, 0.0)
	if gun:
		var toward := WorldPresentation.heading_vector(float(e["heading_deg"]))
		at += toward * slen * 0.3
	var at_nm := WorldCamera.to_chart(at, origin_nm)
	var last: float = _launch_clock.get(shooter_key, -INF)
	if gun:
		_gun_burst(e)
		return
	if e.get("torpedo", false):
		effects.burst("miss", Vector2(at_nm.x, at_nm.y), 0.0, 0.5)
		return
	if anim - last >= LAUNCH_COOLDOWN_S:
		effects.launch_puff(Vector2(at_nm.x, at_nm.y), at_nm.z, clampf(slen / 140.0, 0.35, 1.4) if not aloft else 0.35)
		_launch_clock[shooter_key] = anim
	# The smoke starts at the launcher; a vertical launch climbs before it turns.
	var seed := PackedVector3Array([at_nm])
	if not aloft and (w.is_interceptor() or float(e["height_m"]) > 40.0):
		seed.append(at_nm + Vector3(0.0, 0.0, 70.0))
	effects.trail_extend(e["key"], nm, float(e["height_m"]), _trail_spacing(e), seed)


## Muzzle flashes for as long as a gun's rounds are fresh: a close-in weapon's burst flickers at
## the mount. Only for a launcher that is on the view.
func _gun_burst(e: Dictionary) -> void:
	var w: Weapon = e.get("weapon")
	if w == null or w.shooter == null or w.time_alive_s > GUN_BURST_S:
		return
	var shooter_key := "u:%d" % w.shooter.id
	var srec: Dictionary = _records.get(shooter_key, {})
	if srec.is_empty() or srec.get("root") == null or not (srec["entry"]["kind"] in ["own", "visual"]):
		return
	if anim - float(_launch_clock.get(shooter_key + ":gun", -INF)) < GUN_COOLDOWN_S:
		return
	_launch_clock[shooter_key + ":gun"] = anim
	var sroot: Node3D = srec["root"]
	var slen: float = srec["entry"]["length_m"]
	var toward := WorldPresentation.heading_vector(float(e["heading_deg"]))
	var at := sroot.position + Vector3(0.0, float(srec["height_m"]) * 0.12, 0.0) + toward * slen * 0.3
	var at_nm := WorldCamera.to_chart(at, origin_nm)
	effects.gun_flash(Vector2(at_nm.x, at_nm.y), at_nm.z, clampf(slen / 120.0, 0.5, 1.5))


## An aircraft of ours leaving the deck or coming back to it, for the Action camera.
func _air_events(rec: Dictionary, e: Dictionary, fresh: bool) -> void:
	var u: Unit = e.get("unit")
	var seen: String = _flagged.get(e["key"], "")
	if u == null or seen == "recovery":
		return
	var base: Unit = u.recovery_base if u.recovery_base != null else u.home
	if base == null or not base.alive:
		return
	var d := u.position.distance_to(base.position)
	var nm: Vector2 = rec["nm"]
	# A sortie whose launch was shown still has its recovery to show.
	if seen == "" and fresh and _warm and d <= AIR_LAUNCH_NM and u.flight_state == Unit.FlightState.AIRBORNE:
		_flagged[e["key"]] = "launch"
		_events.append({"kind": "air_launch", "at": Vector3(nm.x, nm.y, float(e["height_m"])), "key": e["key"]})
	elif u.flight_state == Unit.FlightState.RECOVERING and d <= RECOVERY_WATCH_NM:
		_flagged[e["key"]] = "recovery"
		_events.append({"kind": "recovery", "at": Vector3(base.position.x, base.position.y, 20.0), "key": ""})


# --- Wakes and trails ----------------------------------------------------------------------

## Wakes, periscope feathers and torpedo tracks on the water; smoke trails for rounds in the air.
func _apply_trails(rec: Dictionary, e: Dictionary, base: Vector3, heading: float, length: float) -> void:
	var key: String = e["key"]
	var kind: String = e["kind"]
	var unit: Unit = e.get("unit")
	var moving := false
	var beam := 4.0
	var spread := 0.0
	var life := WAKE_LIFE_S
	var spacing_nm := maxf(length * 0.35, 12.0) / WorldPresentation.NM_TO_M
	if unit != null and (kind == "own" or kind == "visual"):
		if e["domain"] == "surface" and unit.speed_kn > 0.5:
			moving = true
			beam = maxf(length * 0.11, 3.0)
			spread = KELVIN_SPREAD
		elif e["domain"] == "subsurface" and unit.at_periscope_depth() and unit.speed_kn > 1.0:
			moving = true
			beam = 1.2
			spread = 0.006
			life = 60.0
			spacing_nm = 20.0 / WorldPresentation.NM_TO_M
	elif kind == "weapon" and e.get("torpedo", false):
		moving = true
		beam = 2.5
		spread = 0.005
		life = 45.0
		spacing_nm = 30.0 / WorldPresentation.NM_TO_M
	var pos: Vector2 = rec["nm"]
	if moving:
		if not _trails.has(key):
			_seed_trail(key, pos, heading, _speed_kn(e), spacing_nm)
		_sample_trail(key, pos, spacing_nm)
		var stern := base - WorldPresentation.heading_vector(heading) * length * 0.46
		stern.y = 0.0
		_build_wake(rec, stern, -WorldPresentation.heading_vector(heading), beam, spread, life)
	elif rec["wake"] != null:
		(rec["wake"] as MeshInstance3D).visible = false
	if kind == "weapon" and not e.get("torpedo", false) and not e.get("gun", false):
		effects.trail_extend(key, pos, float(e["height_m"]), _trail_spacing(e))
	elif kind == "weapon" and e.get("gun", false) and _warm:
		_gun_burst(e)


func _trail_spacing(e: Dictionary) -> float:
	return clampf(_speed_kn(e) * 0.5144 * 0.12, 25.0, 140.0)


func _sample_trail(key: String, pos: Vector2, spacing_nm: float) -> void:
	var trail: Array = _trails.get(key, [])
	if trail.is_empty() or Vector2(trail[-1].x, trail[-1].y).distance_to(pos) >= spacing_nm:
		trail.append(Vector3(pos.x, pos.y, sim_now))
		while trail.size() > WAKE_SAMPLES:
			trail.pop_front()
	_trails[key] = trail


func _speed_kn(e: Dictionary) -> float:
	var unit: Unit = e.get("unit")
	if unit != null:
		return unit.speed_kn
	var w: Weapon = e.get("weapon")
	return w.spec.speed_kn if w != null else 0.0


## The view often opens on something that has been under way for an hour. A wake laid straight
## back along the heading stands in for the history nobody recorded, and real samples replace it.
func _seed_trail(key: String, pos: Vector2, heading: float, speed_kn: float, spacing_nm: float) -> void:
	var trail: Array = []
	var back := Geo.heading_to_vector(heading)
	var per_sample := spacing_nm / maxf(speed_kn / 3600.0, 1.0e-4)
	for i in range(WAKE_SAMPLES - 2, 0, -1):
		trail.append(Vector3(pos.x - back.x * spacing_nm * i, pos.y - back.y * spacing_nm * i, sim_now - per_sample * i))
	_trails[key] = trail


func _acquire_strip(material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D
	if not _strip_pool.is_empty():
		mi = _strip_pool.pop_back()
	else:
		mi = MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4000.0
		_entities.add_child(mi)
	mi.material_override = material
	mi.visible = true
	return mi


func _release_strip(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	(mi.mesh as ImmediateMesh).clear_surfaces()
	mi.visible = false
	_strip_pool.append(mi)


## A strip from the stern back along the sampled track, widening as a Kelvin wake does and
## fading with distance and age. `astern` is the unit vector aft. The foam itself is the wake
## shader's business.
func _build_wake(rec: Dictionary, stern: Vector3, astern: Vector3, beam: float, spread: float, life: float) -> void:
	var trail: Array = _trails.get(rec["key"], [])
	var mi: MeshInstance3D = rec["wake"]
	if mi == null:
		mi = _acquire_strip(_wake_material)
		rec["wake"] = mi
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var points: Array[Vector3] = [stern]
	var times: Array[float] = [sim_now]
	for i in range(trail.size() - 1, -1, -1):
		var s: Vector3 = trail[i]
		var w := WorldPresentation.to_world(Vector2(s.x, s.y), origin_nm, 0.0)
		if w.distance_to(points[-1]) < 1.0 or (points.size() == 1 and (w - stern).dot(astern) < 1.0):
			continue  # too close, or a sample still under the hull, ahead of the stern
		points.append(w)
		times.append(s.z)
	if points.size() < 2:
		mi.visible = false
		return
	# Laid flat and lifted onto the swell by the wake shader, so near the eye no stretch between
	# two vertices may be long enough to cut through a crest.
	var eye := camera.global_position if camera != null else Vector3.ZERO
	var dense: Array[Vector3] = [points[0]]
	var dense_t: Array[float] = [times[0]]
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var steps := 1
		if minf(Vector2(a.x - eye.x, a.z - eye.z).length(), Vector2(b.x - eye.x, b.z - eye.z).length()) < WAKE_DETAIL_M:
			steps = clampi(ceili(a.distance_to(b) / WAKE_SEGMENT_M), 1, 48)
		for k in range(1, steps + 1):
			var f := float(k) / float(steps)
			dense.append(a.lerp(b, f))
			dense_t.append(lerpf(times[i - 1], times[i], f))
	points = dense
	times = dense_t
	var dists: Array[float] = [0.0]
	for i in range(1, points.size()):
		dists.append(dists[i - 1] + points[i].distance_to(points[i - 1]))
	var total: float = dists[-1]
	if total < 2.0:
		mi.visible = false
		return
	mi.visible = true
	var shade := 0.45 + 0.55 * daylight
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for j in points.size():
		var p := points[j]
		var ahead := points[maxi(j - 1, 0)]
		var behind := points[mini(j + 1, points.size() - 1)]
		var dir := (behind - ahead)
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
		var side := Vector3(-dir.z, 0.0, dir.x)
		var d := dists[j]
		var hw := beam * 0.6 + d * spread
		var fade := pow(1.0 - d / total, 1.3) * clampf(1.0 - (sim_now - times[j]) / life, 0.0, 1.0)
		var y := 0.0
		var c := Color(0.92 * shade, 0.95 * shade, 0.97 * shade, fade * 0.8)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(0.0, d))
		im.surface_set_normal(Vector3.UP)
		im.surface_add_vertex(Vector3(p.x - side.x * hw, y, p.z - side.z * hw))
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(1.0, d))
		im.surface_set_normal(Vector3.UP)
		im.surface_add_vertex(Vector3(p.x + side.x * hw, y, p.z + side.z * hw))
	im.surface_end()


# --- Emitters ------------------------------------------------------------------------------

## Fire and black smoke aboard, a missile's exhaust, an aircraft's engine glow and the downwash
## under a hovering helicopter.
func _apply_emitters(rec: Dictionary, e: Dictionary, at: Vector3, heading: float) -> void:
	var unit: Unit = e.get("unit")
	var kind: String = e["kind"]
	var length: float = e["length_m"]
	var fwd := WorldPresentation.heading_vector(heading)
	var speed_mps := 0.0
	var w: Weapon = e.get("weapon")
	if unit != null:
		speed_mps = unit.speed_kn * 0.5144
	elif w != null:
		speed_mps = w.spec.speed_kn * 0.5144
	var velocity := fwd * speed_mps
	var eye := camera.global_position if camera != null else Vector3.ZERO
	var burning: bool = unit != null and unit.fire > 0.0 and (kind == "own" or kind == "visual") and e["domain"] != "air"
	if burning:
		if rec["fire"] == null:
			rec["fire"] = effects.acquire_fire()
		effects.drive_fire(rec["fire"], at + Vector3(0.0, rec["height_m"] * 0.18, 0.0) - fwd * length * 0.1, velocity, unit.fire, length)
	elif rec["fire"] != null and rec["dying_since"] < 0.0:
		effects.release_fire(rec["fire"])
		rec["fire"] = null
	if kind == "weapon" and not e.get("torpedo", false) and not e.get("gun", false):
		if rec["plume"] == null:
			rec["plume"] = effects.acquire_plume()
		var nozzle := at - fwd * length * 0.5
		effects.drive_plume(rec["plume"], nozzle, velocity, eye.distance_to(nozzle))
	elif rec["plume"] != null:
		effects.release_plume(rec["plume"])
		rec["plume"] = null
	var jet: bool = unit != null and e["domain"] == "air" and (kind == "own" or kind == "visual") and not unit.spec.can_hover and not rec["model_id"].begins_with("marker:")
	if jet:
		if rec["glow"] == null:
			rec["glow"] = effects.acquire_glow()
		var tail := at - fwd * length * 0.5
		# A jet pipe is a faint warm glow by day and a bright one at night.
		effects.drive_glow(rec["glow"], tail, maxf(length * 0.045, 0.6) * lerpf(1.6, 0.7, daylight), eye.distance_to(tail))
	elif rec["glow"] != null:
		effects.release_glow(rec["glow"])
		rec["glow"] = null
	var disc: MeshInstance3D = rec["disc"]
	if unit != null and unit.is_hovering():
		if disc == null:
			disc = MeshInstance3D.new()
			disc.mesh = _disc_mesh
			disc.material_override = _disc_material
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_entities.add_child(disc)
			rec["disc"] = disc
		var sea := Vector3(at.x, 0.0, at.z)
		disc.position = Vector3(sea.x, swell_at(sea) + 0.4, sea.z)
		var pulse := 1.0 + 0.08 * sin(anim * 5.0)
		disc.scale = Vector3.ONE * maxf(length * 1.6, 10.0) * pulse
		disc.visible = true
	elif disc != null:
		disc.visible = false


# --- Retirement ----------------------------------------------------------------------------

## An entry that has gone. A unit that died on screen sinks or falls first; everything else,
## including a track that dropped and a round that hit, goes at once, a round leaving its smoke.
func _retire(key: String) -> void:
	var rec: Dictionary = _records[key]
	var e: Dictionary = rec["entry"]
	var unit: Unit = e.get("unit")
	if unit != null and not unit.alive and not unit.departed and e["kind"] in ["own", "visual"]:
		if rec["dying_since"] < 0.0:
			rec["dying_since"] = anim
		if _animate_dying(rec, e, unit):
			return
	_release(key)


## Returns true while the animation still runs. A ship settles by the stern, lists and goes down
## with its fire still burning; an aircraft tumbles into the sea.
func _animate_dying(rec: Dictionary, e: Dictionary, unit: Unit) -> bool:
	var root: Node3D = rec["root"]
	var aircraft: bool = e["domain"] == "air"
	var duration := WorldPresentation.FALL_DURATION_S if aircraft else WorldPresentation.SINK_DURATION_S
	var p := (anim - float(rec["dying_since"])) / duration
	var nm: Vector2 = rec.get("nm", e["position"])
	if p >= 1.0:
		var sea := WorldPresentation.to_world(nm, origin_nm, 0.0)
		effects.burst("splash", nm, 0.0, 1.5 if aircraft else 2.2)
		if not aircraft:
			effects.burst("miss", nm + Geo.heading_to_vector(float(e["heading_deg"])) * 0.02, swell_at(sea), 1.4)
		return false
	var base := WorldPresentation.to_world(nm, origin_nm, float(e["height_m"]))
	var heading: float = e["heading_deg"] if e["has_heading"] else 0.0
	var yaw := WorldPresentation.heading_to_yaw(heading)
	var sign := 1.0 if unit.id % 2 == 0 else -1.0
	root.visible = true
	if aircraft:
		var drop := float(e["height_m"]) * p * p
		root.position = base + WorldPresentation.heading_vector(heading) * p * 900.0 - Vector3(0.0, drop, 0.0)
		root.rotation = Vector3(sign * p * TAU * 1.5, yaw, deg_to_rad(-25.0) * p)
	else:
		var ease := p * p * (3.0 - 2.0 * p)
		var height: float = rec["height_m"]
		var lift := WorldPresentation.hull_lift_m(rec["bounds"].size.y, root.scale.x) - height * 0.85 * p * p
		root.position = base + Vector3(0.0, lift + swell_at(base), 0.0)
		root.rotation = Vector3(sign * deg_to_rad(38.0) * ease, yaw, deg_to_rad(-11.0) * ease)
		if rec["fire"] == null:
			rec["fire"] = effects.acquire_fire()
		effects.drive_fire(rec["fire"], root.position + Vector3(0.0, height * 0.15 * (1.0 - p), 0.0), Vector3.ZERO, maxf(0.95 - p, 0.1), float(e["length_m"]))
	if rec["ring"] != null:
		(rec["ring"] as MeshInstance3D).visible = false
	if rec["wake"] != null:
		(rec["wake"] as MeshInstance3D).visible = false
	if rec["bow"] != null:
		(rec["bow"] as MeshInstance3D).visible = false
	if rec["lamps_on"]:
		_apply_lamps(rec, e)
	if rec["glow"] != null:
		effects.release_glow(rec["glow"])
		rec["glow"] = null
	return true


func _release(key: String) -> void:
	var rec: Dictionary = _records[key]
	_release_model(rec)
	for field in ["ring", "disc", "bow"]:
		var node: Node3D = rec[field]
		if node != null:
			node.queue_free()
	_release_strip(rec["wake"])
	if rec["fire"] != null:
		effects.release_fire(rec["fire"])
	if rec["plume"] != null:
		effects.release_plume(rec["plume"])
	if rec["glow"] != null:
		effects.release_glow(rec["glow"])
	effects.trail_release(key)
	_records.erase(key)
	_trails.erase(key)
	_headings.erase(key)
	_ground.erase(key)


## Hands a record's model back to the pool, untinted.
func _release_model(rec: Dictionary) -> void:
	var node: Node3D = rec.get("root")
	if node == null:
		return
	if rec["tint"] != "":
		_set_tint(rec, "")
	for lamp: MeshInstance3D in node.get_meta("lamps", []):
		lamp.visible = false
	_models.release(rec["model_id"], node)
	rec["root"] = null


# --- Queries -------------------------------------------------------------------------------

## Where to put a label for each shown entity: {key, world, label, sublabel, color, kind, distance_m}.
func anchors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in _records:
		var rec: Dictionary = _records[key]
		if rec["dying_since"] >= 0.0 or rec.get("root") == null:
			continue
		var e: Dictionary = rec["entry"]
		if String(e["label"]).is_empty():
			continue
		var root: Node3D = rec["root"]
		out.append({"key": key, "world": rec["anchor"], "label": e["label"], "sublabel": e["sublabel"], "color": e["color"], "kind": e["kind"], "distance_m": root.position.length()})
	return out


## True while the view holds something for this key, alive or going down.
func has_record(key: String) -> bool:
	return _records.has(key)


## True while the entity with this key is going down: sinking, or falling into the sea.
func is_dying(key: String) -> bool:
	var rec: Dictionary = _records.get(key, {})
	return not rec.is_empty() and float(rec["dying_since"]) >= 0.0


## The world frame of an entity for the camera: position (a little above its middle), model
## length, height, heading, domain and speed. {} when it is not on the view.
func focus_frame(key: String) -> Dictionary:
	var rec: Dictionary = _records.get(key, {})
	if rec.is_empty() or rec.get("root") == null:
		return {}
	var e: Dictionary = rec["entry"]
	var root: Node3D = rec["root"]
	var height: float = rec["height_m"]
	return {"position": root.position + Vector3(0.0, height * 0.22, 0.0), "length": float(e["length_m"]), "height": height, "heading": float(e["heading_deg"]) if e["has_heading"] else 0.0, "domain": e["domain"], "speed_mps": _speed_kn(e) * 0.5144}


## The nearest own unit to a point on the view, within `radius_px`, for double-click selection.
func pick_own_unit(screen: Vector2, radius_px := 30.0) -> Unit:
	if camera == null:
		return null
	var best: Unit = null
	var best_d := radius_px
	for key in _records:
		var rec: Dictionary = _records[key]
		var e: Dictionary = rec["entry"]
		if e["kind"] != "own" or rec.get("root") == null:
			continue
		var root: Node3D = rec["root"]
		if camera.is_position_behind(root.position):
			continue
		var d := camera.unproject_position(root.position).distance_to(screen)
		if d < best_d:
			best_d = d
			best = e["unit"]
	return best


# --- Effects and reset ---------------------------------------------------------------------

## A simulation event at a chart position. `height_m` places an airburst; below zero means the
## surface. Returns the height it was drawn at.
func add_effect(pos_nm: Vector2, kind: String, _own: bool, height_m := -1.0) -> float:
	var h := height_m
	if h < 0.0:
		match kind:
			"intercept":
				h = 250.0
			"decoy":
				h = 60.0
			"launch":
				h = 14.0
			"hit", "destroyed":
				h = 9.0
			_:
				h = 0.0
	if h < 1.0:
		h += swell_at(WorldPresentation.to_world(pos_nm, origin_nm, 0.0))
	var scale := 1.0
	if kind == "intercept" and height_m > 2000.0:
		scale = 2.5
	effects.burst(kind, pos_nm, h, scale)
	return h


func reset() -> void:
	for key in _records.keys():
		_release(key)
	effects.reset()
	_trails.clear()
	_headings.clear()
	_ground.clear()
	_events.clear()
	_launch_clock.clear()
	_flagged.clear()
	_warm = false
	if land != null:
		land.reset()
