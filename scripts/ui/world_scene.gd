class_name WorldScene
extends Node3D
## The 3D world behind the World View: sky and sun, the ocean, land within sight, and a pool of
## entity nodes fed from the entries WorldPresentation produces. Nothing here decides what may be
## shown; it only draws what it is handed, at 1 unit per metre about a floating origin.

const ORIGIN_WRAP_M := 65536.0
const WAKE_SAMPLES := 26
const WAKE_LIFE_S := 150.0
const RIBBON_SAMPLES := 40
const RIBBON_LIFE_S := 30.0
const LAND_REBUILD_NM := 8.0
const KELVIN_SPREAD := 0.035  # half-width growth per metre astern of the visible foam lane


var origin_nm := Vector2.ZERO
var camera: Camera3D
var effects: WorldEffects
var daylight := 1.0
var sea_state := -1
var anim := 0.0
var sim_now := 0.0
var shadows_allowed := true
var focus_ring := true  # the accent ring under the focus; off for the bridge camera

var _env: Environment
var _sky_material: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _ocean: MeshInstance3D
var _ocean_material: ShaderMaterial
var _wake_material: ShaderMaterial
var _ribbon_material: StandardMaterial3D
var _land_material: StandardMaterial3D
var _land_root: Node3D
var _land_origin_nm := Vector2(INF, INF)
var _land_generation := -1
var _entities: Node3D
var _records: Dictionary = {}
var _trails: Dictionary = {}  # key -> Array[Vector3] (nm x, nm y, sim time), oldest first
var _ribbons: Dictionary = {}  # key -> Array[Vector4] (nm x, nm y, height m, sim time)
var _headings: Dictionary = {}  # key -> Vector3 (heading, sim time, bank)
var _anchored: Array[Dictionary] = []  # {node, nm, height, until}
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


# --- Construction ------------------------------------------------------------------------

func build() -> void:
	name = "WorldScene"
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sun_angle_max = 3.0
	_sky_material.sun_curve = 0.1
	_sky_material.use_debanding = true
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_sky_affect = 0.25
	_env.fog_sun_scatter = 0.12
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
	_moon.light_color = Color(0.62, 0.72, 0.95)
	_moon.light_energy = 0.0
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 55.0
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
	_ribbon_material = StandardMaterial3D.new()
	_ribbon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_material.vertex_color_use_as_albedo = true
	_ribbon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_land_material = StandardMaterial3D.new()
	_land_material.vertex_color_use_as_albedo = true
	_land_material.roughness = 1.0
	_land_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_land_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_land_root = Node3D.new()
	_land_root.name = "Land"
	add_child(_land_root)
	_entities = Node3D.new()
	_entities.name = "Entities"
	add_child(_entities)
	effects = WorldEffects.new()
	add_child(effects)
	_ring_mesh = WorldMeshes.ring()
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


# --- Environment -------------------------------------------------------------------------

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
	_env.fog_density = 1.7 / (visibility_nm * WorldPresentation.NM_TO_M)
	var wind_kn := float(env.get("wind_kn", 8.0 + 4.0 * state))
	effects.wind = Vector3(_wind.x, 0.0, _wind.y) * wind_kn * 0.51


## Sky, sun, moon, ambient and fog for a solar elevation. Three keyframes, night, twilight and
## day, are blended by elevation. The warmth of dawn and dusk rides on the sun's own halo, so it
## sits toward the sun instead of all round the horizon, and the fog takes the horizon's colour
## at the scene's brightness so a dark dawn is not washed out by a bright haze.
func set_time_of_day(sun_dir: Vector3, elevation_deg: float) -> void:
	var twilight := smoothstep(-14.0, -3.0, elevation_deg)
	var day := smoothstep(-3.0, 12.0, elevation_deg)
	var top := Color(0.010, 0.018, 0.045).lerp(Color(0.10, 0.17, 0.34), twilight).lerp(Color(0.24, 0.45, 0.74), day)
	var horizon := Color(0.035, 0.050, 0.090).lerp(Color(0.74, 0.60, 0.52), twilight).lerp(Color(0.70, 0.79, 0.87), day)
	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = horizon
	_sky_material.sky_curve = 0.13
	_sky_material.sky_energy_multiplier = 0.7 + 0.5 * day
	_sky_material.ground_horizon_color = horizon.darkened(0.35)
	_sky_material.ground_bottom_color = Color(0.015, 0.030, 0.050).lerp(Color(0.07, 0.14, 0.20), day)
	_sky_material.sun_angle_max = lerpf(28.0, 6.0, day)
	_sky_material.sun_curve = lerpf(0.06, 0.12, day)
	var sun_up := smoothstep(-1.0, 8.0, elevation_deg)
	var sun_color := Color(1.0, 0.50, 0.24).lerp(Color(1.0, 0.96, 0.90), clampf(elevation_deg / 22.0, 0.0, 1.0))
	_sun.light_color = sun_color
	_sun.light_energy = 1.7 * sun_up
	_sun.shadow_enabled = shadows_allowed and sun_up > 0.1
	if sun_dir.length_squared() > 1e-6:
		var up := Vector3.UP if absf(sun_dir.y) < 0.999 else Vector3.FORWARD
		_sun.look_at_from_position(sun_dir * 1000.0, Vector3.ZERO, up)
	_moon.light_energy = 0.16 * (1.0 - twilight)
	var moon_dir := Vector3(-sun_dir.x, 0.65, -sun_dir.z).normalized()
	_moon.look_at_from_position(moon_dir * 1000.0, Vector3.ZERO, Vector3.UP)
	_env.ambient_light_color = Color(0.10, 0.13, 0.22).lerp(Color(0.42, 0.47, 0.60), twilight).lerp(Color(0.60, 0.70, 0.82), day)
	_env.ambient_light_energy = 0.28 + 0.22 * twilight + 0.15 * day
	var brightness := 0.15 + 0.4 * twilight + 0.45 * day
	_env.fog_light_color = horizon.lerp(Color(0.5, 0.5, 0.5), 0.2) * brightness
	_env.fog_light_energy = 1.0
	daylight = 0.08 + 0.42 * twilight + 0.5 * day
	effects.daylight = daylight
	_ocean_material.set_shader_parameter("sky_color", Vector3(horizon.r, horizon.g, horizon.b) * (0.35 + 0.65 * brightness))
	_ocean_material.set_shader_parameter("sun_color", Vector3(sun_color.r, sun_color.g, sun_color.b))
	_ocean_material.set_shader_parameter("sun_dir", sun_dir)
	_ocean_material.set_shader_parameter("sun_strength", smoothstep(-1.5, 5.0, elevation_deg))
	_ocean_material.set_shader_parameter("daylight", daylight)


func _origin_offset() -> Vector2:
	var m := origin_nm * WorldPresentation.NM_TO_M
	return Vector2(fposmod(m.x, ORIGIN_WRAP_M), fposmod(-m.y, ORIGIN_WRAP_M))


## Height of the water at a point in origin-relative metres, from the same swell as the shader.
func swell_at(p: Vector3) -> float:
	if sea_state <= 0:
		return 0.0
	var off := _origin_offset()
	return WorldPresentation.swell_height(Vector2(p.x + off.x, p.z + off.y), anim, _swell, _wind, _wind2)


# --- Land --------------------------------------------------------------------------------

func _update_land() -> void:
	if _land_generation != Terrain.generation or _land_origin_nm.distance_to(origin_nm) > LAND_REBUILD_NM:
		_rebuild_land()
	_land_root.position = WorldPresentation.to_world(_land_origin_nm, origin_nm, 0.0)


## Every landmass within LAND_RANGE_NM: a low coastal shelf, then two terraces whose height
## follows the landmass's elevation, so a headland has a silhouette against the sky.
func _rebuild_land() -> void:
	for child in _land_root.get_children():
		child.queue_free()
	_land_origin_nm = origin_nm
	_land_generation = Terrain.generation
	for l: Landmass in Terrain.landmasses:
		if not l.valid() or not l.bounds.grow(WorldPresentation.LAND_RANGE_NM).has_point(origin_nm):
			continue
		var mesh := WorldLand.build(l, _land_origin_nm)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _land_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_land_root.add_child(mi)


# --- Entities ----------------------------------------------------------------------------

## Syncs the pool with this frame's entries. `entries` are WorldPresentation dictionaries; the
## ones missing since last frame are retired, which for a unit that has just died means sinking.
func update(delta: float, entries: Array, focus_key: String) -> void:
	anim += delta
	if camera != null:
		_ocean.position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)
	_ocean_material.set_shader_parameter("origin_offset", _origin_offset())
	_update_land()
	var wanted: Dictionary = {}
	for e: Dictionary in entries:
		wanted[e["key"]] = true
		_apply_entry(e, focus_key)
	for key in _records.keys():
		if not wanted.has(key):
			_retire(key)
	for i in range(_anchored.size() - 1, -1, -1):
		var a := _anchored[i]
		var node: Node3D = a["node"]
		if float(a["until"]) <= anim or not is_instance_valid(node):
			if is_instance_valid(node):
				effects.release(node as CPUParticles3D)
			_anchored.remove_at(i)
			continue
		node.position = WorldPresentation.to_world(a["nm"], origin_nm, float(a["height"]))


func _model_for(e: Dictionary) -> String:
	if e["kind"] == "buoy":
		return "marker:buoy"
	var model: String = e["model"]
	if model != "" and ResourceLoader.exists("res://assets/models/%s.glb" % model):
		return model
	if e["kind"] == "weapon":
		return "marker:weapon"
	var domain: String = e["domain"]
	return "marker:" + (domain if domain in ["surface", "air", "subsurface"] else "surface")


func _apply_entry(e: Dictionary, focus_key: String) -> void:
	var key: String = e["key"]
	var model_id := _model_for(e)
	var rec: Dictionary = _records.get(key, {})
	if rec.is_empty():
		rec = {"key": key, "model_id": "", "ring": null, "disc": null, "wake": null, "ribbon": null, "smoke": null, "plume": null, "dying_since": -1.0, "tint": ""}
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
	rec["entry"] = e
	rec["dying_since"] = -1.0
	var root: Node3D = rec["root"]
	var bounds: AABB = rec["bounds"]
	var length: float = e["length_m"]
	var scale := WorldPresentation.model_scale(length)
	var height_units := bounds.size.y
	rec["height_m"] = height_units * scale
	var base := WorldPresentation.to_world(e["position"], origin_nm, float(e["height_m"]))
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
		"surface", "land":
			if domain == "land":
				lift = -bounds.position.y * scale + WorldLand.SHELF_M + 0.3
			else:
				lift = WorldPresentation.hull_lift_m(height_units, scale)
			if domain == "surface":
				var motion := _sea_motion(base, heading, length, scale)
				lift += motion.x
				pitch = motion.y
				roll = motion.z
			if unit != null:
				roll += deg_to_rad(13.0) * unit.flooding * (1.0 if unit.id % 2 == 0 else -1.0)
				lift -= unit.flooding * rec["height_m"] * 0.12
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
	_apply_trails(rec, e, base, heading, length, scale)
	_apply_emitters(rec, e, root.position, heading)


## Heave, pitch and roll from the swell under a hull. Big ships answer the sea less.
func _sea_motion(base: Vector3, heading: float, length: float, scale: float) -> Vector3:
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


## Tint, translucency and the ring on the water for anything that is not simply ours.
func _apply_look(rec: Dictionary, e: Dictionary, focus_key: String) -> void:
	var kind: String = e["kind"]
	var domain: String = e["domain"]
	var color: Color = e["color"]
	var under := float(e["height_m"]) < -0.5
	var tint := ""
	if kind == "own" and under:
		tint = "ghost:%s" % Color(0.55, 0.75, 0.95).to_html(false)
	elif kind == "plotted":
		tint = ("ghost:%s" if under else "tint:%s") % color.to_html(false)
	elif kind == "weapon" and under:
		tint = "ghost:%s" % Color(0.7, 0.85, 0.95).to_html(false)
	elif rec["model_id"].begins_with("marker:") and kind != "buoy":
		tint = "marker:%s" % color.to_html(false)
	if tint != rec["tint"]:
		_set_tint(rec, tint)
	var wants_ring: bool = kind == "plotted" or kind == "visual" or (kind == "own" and focus_ring and e["key"] == focus_key)
	var ring: MeshInstance3D = rec["ring"]
	if wants_ring:
		if ring == null:
			ring = MeshInstance3D.new()
			ring.mesh = _ring_mesh
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_entities.add_child(ring)
			rec["ring"] = ring
		var radius: float = maxf(float(e["length_m"]) * (0.7 if kind == "own" else 0.8), 24.0)
		var track: Track = e.get("track")
		if track != null and kind == "plotted":
			radius = clampf(maxf(radius, track.position_error_nm * WorldPresentation.NM_TO_M), radius, 3.0 * WorldPresentation.NM_TO_M)
		var ring_color := TacticalMap.COL_ACCENT if kind == "own" else color
		var ring_alpha := 0.3 if kind == "own" else 0.55
		ring.material_override = _flat_material("ring:%s:%.2f" % [ring_color.to_html(false), ring_alpha], Color(ring_color, ring_alpha), false)
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
				material = _flat_material(tint, Color(color, 0.38), true)
			"tint":
				material = _flat_material(tint, Color(color, 0.62), false)
			"marker":
				material = _flat_material(tint, Color(color, 0.42), false)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, material)


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
	_materials[key] = m
	return m


## Wakes, periscope feathers, torpedo tracks and missile ribbons.
func _apply_trails(rec: Dictionary, e: Dictionary, base: Vector3, heading: float, length: float, scale: float) -> void:
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
	if moving:
		if not _trails.has(key):
			_seed_trail(key, e["position"], heading, _speed_kn(e), spacing_nm)
		_sample_trail(key, e["position"], spacing_nm)
		var stern := base - WorldPresentation.heading_vector(heading) * length * 0.46
		stern.y = 0.0
		_build_wake(rec, stern, beam, spread, life)
	elif rec["wake"] != null:
		(rec["wake"] as MeshInstance3D).visible = false
	if kind == "weapon" and not e.get("torpedo", false):
		if not _ribbons.has(key):
			_seed_ribbon(key, e["position"], float(e["height_m"]), heading, _speed_kn(e))
		_sample_ribbon(key, e["position"], float(e["height_m"]))
		_build_ribbon(rec, base, e["color"])
	elif rec["ribbon"] != null:
		(rec["ribbon"] as MeshInstance3D).visible = false


func _sample_trail(key: String, pos: Vector2, spacing_nm: float) -> void:
	var trail: Array = _trails.get(key, [])
	if trail.is_empty() or Vector2(trail[-1].x, trail[-1].y).distance_to(pos) >= spacing_nm:
		trail.append(Vector3(pos.x, pos.y, sim_now))
		while trail.size() > WAKE_SAMPLES:
			trail.pop_front()
	_trails[key] = trail


func _sample_ribbon(key: String, pos: Vector2, height: float) -> void:
	var ribbon: Array = _ribbons.get(key, [])
	var spacing := 60.0 / WorldPresentation.NM_TO_M
	if ribbon.is_empty() or Vector2(ribbon[-1].x, ribbon[-1].y).distance_to(pos) >= spacing:
		ribbon.append(Vector4(pos.x, pos.y, height, sim_now))
		while ribbon.size() > RIBBON_SAMPLES:
			ribbon.pop_front()
	_ribbons[key] = ribbon


func _speed_kn(e: Dictionary) -> float:
	var unit: Unit = e.get("unit")
	if unit != null:
		return unit.speed_kn
	var w: Weapon = e.get("weapon")
	return w.spec.speed_kn if w != null else 0.0


## The view often opens on something that has been under way for an hour. A trail laid straight
## back along the heading stands in for the history nobody recorded, and real samples replace it.
func _seed_trail(key: String, pos: Vector2, heading: float, speed_kn: float, spacing_nm: float) -> void:
	var trail: Array = []
	var back := Geo.heading_to_vector(heading)
	var per_sample := spacing_nm / maxf(speed_kn / 3600.0, 1.0e-4)
	for i in range(WAKE_SAMPLES - 2, 0, -1):
		trail.append(Vector3(pos.x - back.x * spacing_nm * i, pos.y - back.y * spacing_nm * i, sim_now - per_sample * i))
	_trails[key] = trail


func _seed_ribbon(key: String, pos: Vector2, height: float, heading: float, speed_kn: float) -> void:
	var ribbon: Array = []
	var back := Geo.heading_to_vector(heading)
	var spacing := 60.0 / WorldPresentation.NM_TO_M
	var per_sample := spacing / maxf(speed_kn / 3600.0, 1.0e-4)
	for i in range(14, 0, -1):
		ribbon.append(Vector4(pos.x - back.x * spacing * i, pos.y - back.y * spacing * i, height, sim_now - per_sample * i))
	_ribbons[key] = ribbon


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
## fading with distance and age. The foam itself is the wake shader's business.
func _build_wake(rec: Dictionary, stern: Vector3, beam: float, spread: float, life: float) -> void:
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
		if w.distance_to(points[-1]) < 1.0:
			continue
		points.append(w)
		times.append(s.z)
	if points.size() < 2:
		mi.visible = false
		return
	var dists: Array[float] = [0.0]
	for i in range(1, points.size()):
		dists.append(dists[i - 1] + points[i].distance_to(points[i - 1]))
	var total: float = dists[-1]
	if total < 2.0:
		mi.visible = false
		return
	mi.visible = true
	var shade := 0.55 + 0.45 * daylight
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
		var y := swell_at(p) + 0.35
		var c := Color(shade, shade, shade, fade * 0.7)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(0.0, d))
		im.surface_set_normal(Vector3.UP)
		im.surface_add_vertex(Vector3(p.x - side.x * hw, y, p.z - side.z * hw))
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(1.0, d))
		im.surface_set_normal(Vector3.UP)
		im.surface_add_vertex(Vector3(p.x + side.x * hw, y, p.z + side.z * hw))
	im.surface_end()


## A camera-facing ribbon of a missile's recent positions, fading toward its tail.
func _build_ribbon(rec: Dictionary, head: Vector3, color: Color) -> void:
	var samples: Array = _ribbons.get(rec["key"], [])
	var mi: MeshInstance3D = rec["ribbon"]
	if mi == null:
		mi = _acquire_strip(_ribbon_material)
		rec["ribbon"] = mi
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var points: Array[Vector3] = [head]
	var times: Array[float] = [sim_now]
	for i in range(samples.size() - 1, -1, -1):
		var s: Vector4 = samples[i]
		var w := WorldPresentation.to_world(Vector2(s.x, s.y), origin_nm, s.z)
		if w.distance_to(points[-1]) < 2.0:
			continue
		points.append(w)
		times.append(s.w)
	if points.size() < 2 or camera == null:
		mi.visible = false
		return
	var dists: Array[float] = [0.0]
	for i in range(1, points.size()):
		dists.append(dists[i - 1] + points[i].distance_to(points[i - 1]))
	var total: float = dists[-1]
	if total < 5.0:
		mi.visible = false
		return
	mi.visible = true
	var eye := camera.global_position
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for j in points.size():
		var p := points[j]
		var dir := points[mini(j + 1, points.size() - 1)] - points[maxi(j - 1, 0)]
		var to_eye := eye - p
		var side := dir.cross(to_eye)
		side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
		var d := dists[j]
		var f := d / total
		var hw := maxf(1.2 + 5.0 * f, to_eye.length() * 0.0012)
		var fade := pow(1.0 - f, 1.6) * clampf(1.0 - (sim_now - times[j]) / RIBBON_LIFE_S, 0.0, 1.0)
		var c := Color(0.85, 0.85, 0.85).lerp(color, 0.35)
		c = Color(c.r * (0.4 + 0.6 * daylight), c.g * (0.4 + 0.6 * daylight), c.b * (0.4 + 0.6 * daylight), 0.55 * fade)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(0.0, d))
		im.surface_add_vertex(p - side * hw)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(1.0, d))
		im.surface_add_vertex(p + side * hw)
	im.surface_end()


## Fire aboard, a missile's plume, and the downwash under a hovering helicopter.
func _apply_emitters(rec: Dictionary, e: Dictionary, at: Vector3, heading: float) -> void:
	var unit: Unit = e.get("unit")
	var kind: String = e["kind"]
	var length: float = e["length_m"]
	var fwd := WorldPresentation.heading_vector(heading)
	var speed_mps := 0.0
	if unit != null:
		speed_mps = unit.speed_kn * 0.5144
	elif e.get("weapon") != null:
		speed_mps = (e["weapon"] as Weapon).spec.speed_kn * 0.5144
	var velocity := fwd * speed_mps
	if unit != null and unit.fire > 0.0 and (kind == "own" or kind == "visual"):
		if rec["smoke"] == null:
			rec["smoke"] = effects.acquire_smoke()
		effects.drive_smoke(rec["smoke"], at + Vector3(0.0, rec["height_m"] * 0.45, 0.0), velocity, unit.fire, length)
	elif rec["smoke"] != null and rec["dying_since"] < 0.0:
		effects.release(rec["smoke"])
		rec["smoke"] = null
	if kind == "weapon" and not e.get("torpedo", false):
		if rec["plume"] == null:
			rec["plume"] = effects.acquire_plume()
		var scale := WorldPresentation.model_scale(length)
		var nozzle := at - fwd * 4.6 * scale
		effects.drive_plume(rec["plume"], nozzle, velocity, 1.0, camera.global_position.distance_to(nozzle) if camera != null else 0.0)
	elif rec["plume"] != null:
		effects.release_plume(rec["plume"])
		rec["plume"] = null
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


# --- Retirement --------------------------------------------------------------------------

## An entry that has gone. A unit that died on screen sinks or falls first; everything else,
## including a track that dropped and a round that hit, goes at once.
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


## Returns true while the animation still runs.
func _animate_dying(rec: Dictionary, e: Dictionary, unit: Unit) -> bool:
	var root: Node3D = rec["root"]
	var aircraft: bool = e["domain"] == "air"
	var duration := WorldPresentation.FALL_DURATION_S if aircraft else WorldPresentation.SINK_DURATION_S
	var p := (anim - float(rec["dying_since"])) / duration
	if p >= 1.0:
		if aircraft:
			var sea := WorldPresentation.to_world(e["position"], origin_nm, 0.0)
			effects.burst("splash", Vector3(sea.x, swell_at(sea), sea.z), 1.5)
		return false
	var base := WorldPresentation.to_world(e["position"], origin_nm, float(e["height_m"]))
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
		var lift := WorldPresentation.hull_lift_m(rec["bounds"].size.y, root.scale.x) - height * 0.8 * p * p
		root.position = base + Vector3(0.0, lift + swell_at(base), 0.0)
		root.rotation = Vector3(sign * deg_to_rad(42.0) * ease, yaw, deg_to_rad(-9.0) * ease)
		if rec["smoke"] != null:
			effects.drive_smoke(rec["smoke"], root.position + Vector3(0.0, height * 0.3, 0.0), Vector3.ZERO, maxf(0.9 - p, 0.1), float(e["length_m"]))
	if rec["ring"] != null:
		(rec["ring"] as MeshInstance3D).visible = false
	if rec["wake"] != null:
		(rec["wake"] as MeshInstance3D).visible = false
	return true


func _release(key: String) -> void:
	var rec: Dictionary = _records[key]
	_release_model(rec)
	for field in ["ring", "disc"]:
		var node: Node3D = rec[field]
		if node != null:
			node.queue_free()
	_release_strip(rec["wake"])
	_release_strip(rec["ribbon"])
	if rec["smoke"] != null:
		effects.release(rec["smoke"])
	if rec["plume"] != null:
		effects.release_plume(rec["plume"])
	_records.erase(key)
	_trails.erase(key)
	_ribbons.erase(key)
	_headings.erase(key)


## Hands a record's model back to the pool, untinted.
func _release_model(rec: Dictionary) -> void:
	var node: Node3D = rec.get("root")
	if node == null:
		return
	if rec["tint"] != "":
		_set_tint(rec, "")
	_models.release(rec["model_id"], node)
	rec["root"] = null


# --- Queries for the HUD -----------------------------------------------------------------

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


## The world position, model length and heading of the focus entity, or {} before it exists.
func focus_frame(key: String) -> Dictionary:
	var rec: Dictionary = _records.get(key, {})
	if rec.is_empty() or rec.get("root") == null:
		return {}
	var e: Dictionary = rec["entry"]
	var root: Node3D = rec["root"]
	var height: float = rec["height_m"]
	return {"position": root.position + Vector3(0.0, height * 0.22, 0.0), "length": float(e["length_m"]), "height": height, "heading": float(e["heading_deg"]) if e["has_heading"] else 0.0, "domain": e["domain"]}


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


# --- Effects and reset -------------------------------------------------------------------

## A simulation event at a chart position. `height_m` places an airburst; below zero means the
## surface. Long-lived smoke is anchored to the chart position, not to the sliding origin.
func add_effect(pos_nm: Vector2, kind: String, own: bool, height_m := -1.0) -> void:
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
	var at := WorldPresentation.to_world(pos_nm, origin_nm, h)
	if h < 1.0:
		at.y += swell_at(at)
	var scale := 1.0
	if kind == "intercept" and height_m > 2000.0:
		scale = 2.5
	for anchored in effects.burst(kind, at, scale):
		_anchored.append({"node": anchored["node"], "nm": pos_nm, "height": h, "until": anim + float(anchored["until"]) - effects._clock})


func reset() -> void:
	for key in _records.keys():
		_release(key)
	for a in _anchored:
		if is_instance_valid(a["node"]):
			effects.release(a["node"] as CPUParticles3D)
	_anchored.clear()
	_trails.clear()
	_ribbons.clear()
	_headings.clear()
	_land_generation = -1
