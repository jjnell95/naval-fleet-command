class_name WorldEffects
extends Node3D
## Transient visuals for the world view: launch smoke, missile smoke trails, gun flashes,
## explosions with their fireball, debris and smoke, splashes, chaff, fires and black smoke on a
## burning ship, missile exhausts and aircraft engine glow. CPU particles, billboard quads and
## ribbons only, all pooled and bounded, so the same code runs in the browser build.
##
## Every emitter works in local coordinates, because the world slides under the floating origin
## and world-space particles would slide with it. One-shot effects are anchored to a chart
## position and re-placed every tick; an emitter riding a moving source is handed that source's
## velocity and gives its new particles the opposite, which leaves smoke standing in the sea's
## frame instead of the ship's. Smoke trails are kept in chart coordinates and rebuilt as ribbons
## each frame. WorldScene owns positions of moving things; this class owns lifetimes and pools.
##
## Effect time runs at `rate` seconds per real second: stopped while the simulation is paused,
## faster (up to a limit) under time compression, so smoke neither hangs through a pause nor
## vanishes in a blink at 60x.

const MAX_PARTICLE_NODES := 48
const MAX_FLASHES := 16
const MAX_TRAILS := 32
const TRAIL_SAMPLES := 160
const TRAIL_LIFE_S := 20.0
const TRAIL_HEAD_M := 1.6
const TRAIL_WIDTH_M := 26.0
const TRAIL_DRIFT := 0.45  # of the wind
const TRAIL_RISE_MPS := 0.3
const PIXEL_ANGLE := 0.0022  # radians per pane pixel, roughly: the thinnest a trail is drawn
const MAX_RATE := 4.0

var daylight := 1.0
var wind := Vector3.ZERO  # downwind, metres per second
var origin_nm := Vector2.ZERO
var eye := Vector3.ZERO
var rate := 1.0

var _clock := 0.0
var _applied_rate := 1.0
var _free: Array[CPUParticles3D] = []
var _busy: Array[CPUParticles3D] = []
var _flash_free: Array[MeshInstance3D] = []
var _flashes: Array[Dictionary] = []
var _plume_free: Array[Node3D] = []
var _plumes: Array[Node3D] = []
var _fire_free: Array[Node3D] = []
var _fires: Array[Node3D] = []
var _glow_free: Array[MeshInstance3D] = []
var _trails: Dictionary = {}  # key -> {pts: PackedVector4Array (nm x, nm y, h, born), s: PackedFloat32Array, head: Vector3, live: bool, mi: MeshInstance3D}
var _trail_pool: Array[MeshInstance3D] = []
var _bp := PackedVector3Array()  # ribbon scratch buffers, reused every frame
var _ba := PackedFloat32Array()
var _bs := PackedFloat32Array()
var _quad: QuadMesh
var _smoke_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _spray_material: StandardMaterial3D
var _debris_material: StandardMaterial3D
var _flare_material: StandardMaterial3D
var _engine_material: StandardMaterial3D
var _trail_material: ShaderMaterial
var _smoke_ramp: Gradient
var _black_ramp: Gradient
var _fire_ramp: Gradient
var _flame_ramp: Gradient
var _spray_ramp: Gradient
var _chaff_ramp: Gradient
var _grow: Curve
var _billow: Curve
var _puff_growth: Curve
var _shrink: Curve


func _ready() -> void:
	name = "Effects"
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_smoke_material = _particle_material(false, puff_texture())
	_glow_material = _particle_material(true, _radial_texture())
	_spray_material = _particle_material(false, puff_texture())
	_debris_material = _particle_material(false, _chunk_texture())
	_flare_material = _billboard_material(Color(1.0, 0.86, 0.62, 0.9))
	_engine_material = _billboard_material(Color(1.0, 0.72, 0.42, 0.85))
	_trail_material = ShaderMaterial.new()
	_trail_material.shader = load("res://scripts/ui/world_smoke.gdshader")
	_trail_material.render_priority = 2
	_smoke_ramp = _ramp([0.0, 0.06, 0.5, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.92), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	_black_ramp = _ramp([0.0, 0.05, 0.45, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	_fire_ramp = _ramp([0.0, 0.15, 0.45, 0.75, 1.0], [Color(1.0, 0.98, 0.85, 1.0), Color(1.0, 0.72, 0.25, 1.0), Color(0.95, 0.35, 0.06, 0.85), Color(0.35, 0.10, 0.03, 0.5), Color(0.1, 0.05, 0.03, 0.0)])
	_flame_ramp = _ramp([0.0, 0.3, 0.7, 1.0], [Color(1.0, 0.95, 0.7, 0.0), Color(1.0, 0.75, 0.3, 1.0), Color(0.95, 0.35, 0.05, 0.7), Color(0.4, 0.1, 0.02, 0.0)])
	_spray_ramp = _ramp([0.0, 0.15, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	_chaff_ramp = _ramp([0.0, 0.1, 0.7, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	_grow = _curve([Vector2(0.0, 0.3), Vector2(1.0, 1.0)])
	_billow = _curve([Vector2(0.0, 0.2), Vector2(0.25, 0.75), Vector2(1.0, 1.0)])
	_puff_growth = _curve([Vector2(0.0, 0.5), Vector2(0.12, 0.85), Vector2(1.0, 1.25)])
	_shrink = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.15)])


## Advances effect time and re-places everything anchored to the chart. WorldScene calls it once
## a frame, after setting `origin_nm`, `eye`, `rate` and `daylight`.
func tick(delta: float) -> void:
	_clock += delta * rate
	if not is_equal_approx(rate, _applied_rate):
		_applied_rate = rate
		for p in _busy:
			p.speed_scale = rate
		for plume in _plumes:
			(plume.get_child(1) as CPUParticles3D).speed_scale = rate
		for rig in _fires:
			(rig.get_child(0) as CPUParticles3D).speed_scale = rate
			(rig.get_child(1) as CPUParticles3D).speed_scale = rate
	for i in range(_flashes.size() - 1, -1, -1):
		var f := _flashes[i]
		var node: MeshInstance3D = f["node"]
		var p := (_clock - float(f["born"])) / float(f["life"])
		if p >= 1.0:
			node.visible = false
			_flash_free.append(node)
			_flashes.remove_at(i)
			continue
		node.position = WorldPresentation.to_world(f["nm"], origin_nm, float(f["h"]))
		var size: float = f["size"] * (0.5 + 1.1 * sqrt(p))
		node.scale = Vector3.ONE * maxf(size, node.position.distance_to(eye) * PIXEL_ANGLE * 3.0)
		var mat := node.material_override as StandardMaterial3D
		var color: Color = f["color"]
		mat.albedo_color = Color(color.r, color.g, color.b, color.a * (1.0 - p) * (1.0 - p))
	for i in range(_busy.size() - 1, -1, -1):
		var p := _busy[i]
		if p.has_meta("until") and float(p.get_meta("until")) <= _clock:
			_park(p)
			_busy.remove_at(i)
		elif p.has_meta("nm"):
			p.position = WorldPresentation.to_world(p.get_meta("nm"), origin_nm, float(p.get_meta("h")))


# --- One-shot effects ----------------------------------------------------------------------

## Fire-and-forget effects at a chart position and height, all anchored there until they end.
func burst(kind: String, nm: Vector2, h: float, scale := 1.0) -> void:
	var sea := h < 25.0
	match kind:
		"hit", "destroyed":
			var big := kind == "destroyed"
			var s := scale * (1.6 if big else 1.0)
			flash(nm, h, 34.0 * s, Color(1.0, 0.9, 0.7, 1.0), 0.45)
			flash(nm, h + 4.0, 70.0 * s, Color(1.0, 0.55, 0.2, 0.55), 0.9)
			_one_shot(_fireball(s), nm, h, 2.2)
			_one_shot(_debris(s), nm, h, 3.5)
			_one_shot(_dark_puff(s), nm, h + 6.0, 12.0)
			if sea:
				_one_shot(_splash(s * 1.3), nm, 0.0, 3.0)
			_one_shot(_column(s), nm, h, 70.0 if big else 30.0)
		"intercept":
			flash(nm, h, 20.0 * scale, Color(1.0, 0.95, 0.85, 1.0), 0.35)
			_one_shot(_fireball(scale * 0.6), nm, h, 2.0)
			_one_shot(_debris(scale * 0.5), nm, h, 3.0)
			_one_shot(_dark_puff(scale * 0.6, 0.42), nm, h, 9.0)
		"decoy":
			flash(nm, h, 7.0 * scale, Color(1.0, 1.0, 0.9, 0.8), 0.25)
			_one_shot(_chaff(scale), nm, h, 6.0)
		"launch":
			launch_puff(nm, h, scale)
		"gun":
			gun_flash(nm, h, scale)
		"refused":
			pass
		_:
			_one_shot(_splash(scale), nm, 0.0, 3.0)


## Billowing white smoke round a launcher, with the booster's flash at its heart.
func launch_puff(nm: Vector2, h: float, scale := 1.0) -> void:
	flash(nm, h, 14.0 * scale, Color(1.0, 0.88, 0.6, 1.0), 0.35)
	_one_shot(_puff(scale), nm, h, 16.0)


## A muzzle flash and a wisp of gun smoke.
func gun_flash(nm: Vector2, h: float, scale := 1.0) -> void:
	flash(nm, h, 9.0 * scale, Color(1.0, 0.85, 0.45, 1.0), 0.12)
	_one_shot(_gun_smoke(scale), nm, h, 5.0)


## A soft additive flash, anchored to the chart, that grows and fades.
func flash(nm: Vector2, h: float, size: float, color: Color, life: float) -> void:
	var node: MeshInstance3D
	if not _flash_free.is_empty():
		node = _flash_free.pop_back()
	elif _flashes.size() < MAX_FLASHES:
		node = MeshInstance3D.new()
		node.mesh = _quad
		node.material_override = _flare_material.duplicate()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	else:
		return
	node.visible = true
	node.position = WorldPresentation.to_world(nm, origin_nm, h)
	node.scale = Vector3.ONE * size * 0.5
	_flashes.append({"node": node, "born": _clock, "life": life, "size": size, "color": color, "nm": nm, "h": h})


# --- Smoke trails --------------------------------------------------------------------------

## Lays smoke behind a round in flight: `nm`/`h` is where it is now. A new sample is kept once the
## round has flown `spacing_m` from the last; between samples the ribbon runs to the round itself.
## `seed` is where the smoke starts (the launcher, a boost point) for a round seen from its launch.
func trail_extend(key: String, nm: Vector2, h: float, spacing_m: float, seed: PackedVector3Array = PackedVector3Array()) -> void:
	var t: Dictionary = _trails.get(key, {})
	if t.is_empty():
		if _trails.size() >= MAX_TRAILS and not _drop_oldest_trail():
			return
		t = {"pts": PackedVector4Array(), "s": PackedFloat32Array(), "head": Vector3(nm.x, nm.y, h), "live": true, "mi": null}
		_trails[key] = t
		for p in seed:
			_trail_append(t, Vector3(p.x, p.y, p.z))
	t["head"] = Vector3(nm.x, nm.y, h)
	t["live"] = true
	var pts: PackedVector4Array = t["pts"]
	if pts.is_empty() or _chart_distance_m(Vector3(pts[-1].x, pts[-1].y, pts[-1].z), t["head"]) >= spacing_m:
		_trail_append(t, t["head"])


## The round has gone; its smoke stays where it was laid until it fades.
func trail_release(key: String) -> void:
	var t: Dictionary = _trails.get(key, {})
	if not t.is_empty():
		t["live"] = false


func has_trail(key: String) -> bool:
	return _trails.has(key)


func trail_count() -> int:
	return _trails.size()


func _trail_append(t: Dictionary, p: Vector3) -> void:
	var pts: PackedVector4Array = t["pts"]
	var s: PackedFloat32Array = t["s"]
	var along := 0.0
	if not pts.is_empty():
		along = s[-1] + _chart_distance_m(Vector3(pts[-1].x, pts[-1].y, pts[-1].z), p)
	pts.append(Vector4(p.x, p.y, p.z, _clock))
	s.append(along)
	if pts.size() > TRAIL_SAMPLES:
		pts.remove_at(0)
		s.remove_at(0)
	t["pts"] = pts
	t["s"] = s


static func _chart_distance_m(a: Vector3, b: Vector3) -> float:
	var d := Vector2(b.x - a.x, b.y - a.y) * WorldPresentation.NM_TO_M
	return sqrt(d.length_squared() + (b.z - a.z) * (b.z - a.z))


func _drop_oldest_trail() -> bool:
	var oldest := ""
	var born := INF
	for key in _trails:
		var t: Dictionary = _trails[key]
		var pts: PackedVector4Array = t["pts"]
		if not t["live"] and not pts.is_empty() and pts[-1].w < born:
			born = pts[-1].w
			oldest = key
	if oldest == "":
		return false
	_retire_trail(oldest)
	return true


func _retire_trail(key: String) -> void:
	var t: Dictionary = _trails[key]
	var mi: MeshInstance3D = t["mi"]
	if mi != null:
		(mi.mesh as ImmediateMesh).clear_surfaces()
		mi.visible = false
		_trail_pool.append(mi)
	_trails.erase(key)


## Rebuilds every ribbon for this frame's origin and eye, and lets go of the ones that have faded.
func draw_trails() -> void:
	var gone: Array[String] = []
	var shade := 0.3 + 0.7 * daylight
	for key in _trails:
		var t: Dictionary = _trails[key]
		var pts: PackedVector4Array = t["pts"]
		if not t["live"] and (pts.is_empty() or _clock - pts[-1].w > TRAIL_LIFE_S):
			gone.append(key)
			continue
		var mi: MeshInstance3D = t["mi"]
		if mi == null:
			mi = _acquire_trail_mesh()
			t["mi"] = mi
		var im := mi.mesh as ImmediateMesh
		im.clear_surfaces()
		var n := _collect(t)
		mi.visible = n >= 2
		if n < 2:
			continue
		var head_s := _bs[0]
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for j in n:
			var p := _bp[j]
			var dir := _bp[mini(j + 1, n - 1)] - _bp[maxi(j - 1, 0)]
			var to_eye := eye - p
			var side := dir.cross(to_eye)
			side = side.normalized() if side.length_squared() > 1e-8 else Vector3.RIGHT
			var f := clampf(_ba[j] / TRAIL_LIFE_S, 0.0, 1.0)
			var hw := maxf(lerpf(TRAIL_HEAD_M, TRAIL_WIDTH_M, sqrt(f)), to_eye.length() * PIXEL_ANGLE * 0.8) * 0.5
			var alpha := 0.9 * pow(1.0 - f, 1.4) * clampf((head_s - _bs[j]) / 10.0 + 0.4, 0.0, 1.0)
			var c := Color(0.95 * shade, 0.95 * shade, 0.97 * shade, alpha)
			im.surface_set_color(c)
			im.surface_set_uv(Vector2(0.0, _bs[j]))
			im.surface_add_vertex(p - side * hw)
			im.surface_set_color(c)
			im.surface_set_uv(Vector2(1.0, _bs[j]))
			im.surface_add_vertex(p + side * hw)
		im.surface_end()
	for key in gone:
		_retire_trail(key)


## The ribbon's points for this frame, newest first, into the shared buffers: the round itself
## while it flies, then the laid smoke, drifted downwind and risen by its age. Returns the count.
func _collect(t: Dictionary) -> int:
	var pts: PackedVector4Array = t["pts"]
	var s: PackedFloat32Array = t["s"]
	if _bp.size() < TRAIL_SAMPLES + 2:
		_bp.resize(TRAIL_SAMPLES + 2)
		_ba.resize(TRAIL_SAMPLES + 2)
		_bs.resize(TRAIL_SAMPLES + 2)
	var n := 0
	var prev := Vector3.INF
	if t["live"]:
		var head: Vector3 = t["head"]
		prev = WorldPresentation.to_world(Vector2(head.x, head.y), origin_nm, head.z)
		_bp[0] = prev
		_ba[0] = 0.0
		_bs[0] = (s[-1] + _chart_distance_m(Vector3(pts[-1].x, pts[-1].y, pts[-1].z), head)) if not pts.is_empty() else 0.0
		n = 1
	for j in range(pts.size() - 1, -1, -1):
		var q := pts[j]
		var age := _clock - q.w
		if age > TRAIL_LIFE_S:
			break
		var p := WorldPresentation.to_world(Vector2(q.x, q.y), origin_nm, q.z) + wind * TRAIL_DRIFT * age + Vector3(0.0, TRAIL_RISE_MPS * age, 0.0)
		if prev != Vector3.INF and p.distance_squared_to(prev) < 0.25:
			continue
		_bp[n] = p
		_ba[n] = age
		_bs[n] = s[j]
		n += 1
		prev = p
	return n


func _acquire_trail_mesh() -> MeshInstance3D:
	var mi: MeshInstance3D
	if not _trail_pool.is_empty():
		mi = _trail_pool.pop_back()
	else:
		mi = MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.material_override = _trail_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16000.0
		add_child(mi)
	mi.visible = true
	return mi


func clear_trails() -> void:
	for key in _trails.keys():
		_retire_trail(key)


# --- Emitters that ride with something -----------------------------------------------------

## Fire aboard a ship: flames at the deck, a column of black smoke and a flickering light. The
## caller drives it every frame and releases it.
func acquire_fire() -> Node3D:
	var rig: Node3D
	if not _fire_free.is_empty():
		rig = _fire_free.pop_back()
	else:
		rig = Node3D.new()
		var flames := CPUParticles3D.new()
		flames.mesh = _quad
		flames.material_override = _glow_material
		flames.local_coords = true
		flames.amount = 32
		flames.lifetime = 0.9
		flames.lifetime_randomness = 0.4
		flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		flames.direction = Vector3.UP
		flames.spread = 22.0
		flames.initial_velocity_min = 3.0
		flames.initial_velocity_max = 8.0
		flames.gravity = Vector3(0.0, 3.0, 0.0)
		flames.scale_amount_curve = _shrink
		flames.color_ramp = _flame_ramp
		flames.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(flames)
		var smoke := CPUParticles3D.new()
		smoke.mesh = _quad
		smoke.material_override = _smoke_material
		smoke.local_coords = true
		smoke.amount = 72
		smoke.lifetime = 24.0
		smoke.lifetime_randomness = 0.3
		smoke.preprocess = 10.0
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		smoke.spread = 12.0
		smoke.damping_min = 0.05
		smoke.damping_max = 0.15
		smoke.angle_min = 0.0
		smoke.angle_max = 360.0
		smoke.angular_velocity_min = -8.0
		smoke.angular_velocity_max = 8.0
		smoke.scale_amount_curve = _billow
		smoke.color_ramp = _black_ramp
		smoke.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(smoke)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.shadow_enabled = false
		rig.add_child(light)
		add_child(rig)
	rig.visible = true
	var f := rig.get_child(0) as CPUParticles3D
	var sm := rig.get_child(1) as CPUParticles3D
	f.speed_scale = rate
	sm.speed_scale = rate
	f.emitting = true
	sm.emitting = true
	sm.restart()
	_fires.append(rig)
	return rig


## Position, source velocity (m/s), intensity 0..1 and the ship's length for a fire rig.
func drive_fire(rig: Node3D, at: Vector3, source_velocity: Vector3, intensity: float, length_m: float) -> void:
	rig.position = at
	var k := clampf(intensity, 0.05, 1.0)
	var flames := rig.get_child(0) as CPUParticles3D
	flames.emission_box_extents = Vector3(maxf(length_m * 0.09, 2.0), 1.5, maxf(length_m * 0.035, 1.5))
	flames.scale_amount_min = 4.0 + 8.0 * k
	flames.scale_amount_max = 8.0 + 16.0 * k
	flames.direction = (Vector3.UP * 6.0 - source_velocity * 0.4).normalized()
	var smoke := rig.get_child(1) as CPUParticles3D
	var drift := wind * 0.5 + Vector3(0.0, 5.0 + 6.0 * k, 0.0) - source_velocity
	smoke.direction = drift.normalized() if drift.length_squared() > 1e-6 else Vector3.UP
	smoke.initial_velocity_min = drift.length() * 0.85
	smoke.initial_velocity_max = drift.length() * 1.15
	smoke.gravity = wind * 0.12 + Vector3(0.0, 0.35, 0.0)
	smoke.emission_sphere_radius = maxf(length_m * 0.05, 3.0)
	smoke.scale_amount_min = 16.0 + 34.0 * k
	smoke.scale_amount_max = 28.0 + 62.0 * k
	var grey := 0.09 + 0.06 * (1.0 - k)
	var lit := 0.35 + 0.65 * daylight
	smoke.color = Color(grey * lit, grey * lit, grey * lit * 1.05, 1.0)
	var light := rig.get_child(2) as OmniLight3D
	light.omni_range = maxf(length_m * 0.9, 40.0)
	light.light_energy = (1.2 + 0.6 * sin(_clock * 23.0 + rig.get_instance_id() % 7) + 0.4 * sin(_clock * 37.0)) * k * (1.3 - daylight * 0.8)


func release_fire(rig: Node3D) -> void:
	if rig == null or _fire_free.has(rig):
		return
	rig.visible = false
	(rig.get_child(0) as CPUParticles3D).emitting = false
	(rig.get_child(1) as CPUParticles3D).emitting = false
	_fires.erase(rig)
	_fire_free.append(rig)


## A missile's exhaust: a flare at the nozzle and a short, thick smoke plume where the long trail
## begins.
func acquire_plume() -> Node3D:
	var plume: Node3D
	if not _plume_free.is_empty():
		plume = _plume_free.pop_back()
	else:
		plume = Node3D.new()
		var flare := MeshInstance3D.new()
		flare.mesh = _quad
		flare.material_override = _flare_material
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plume.add_child(flare)
		var trail := CPUParticles3D.new()
		trail.mesh = _quad
		trail.material_override = _smoke_material
		trail.local_coords = true
		trail.amount = 24
		trail.lifetime = 1.6
		trail.randomness = 0.3
		trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		trail.emission_sphere_radius = 0.6
		trail.spread = 5.0
		trail.damping_min = 0.4
		trail.damping_max = 0.8
		trail.scale_amount_min = 2.0
		trail.scale_amount_max = 3.5
		trail.scale_amount_curve = _grow
		trail.color_ramp = _smoke_ramp
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plume.add_child(trail)
		add_child(plume)
	plume.visible = true
	var t := plume.get_child(1) as CPUParticles3D
	t.speed_scale = rate
	t.emitting = true
	_plumes.append(plume)
	return plume


## `distance_m` is the camera's distance, so a plume miles off still reads as a point of light.
func drive_plume(plume: Node3D, at: Vector3, source_velocity: Vector3, distance_m := 0.0) -> void:
	plume.position = at
	var flare := plume.get_child(0) as MeshInstance3D
	var flicker := 0.85 + 0.3 * sin(_clock * 37.0 + float(plume.get_instance_id() % 17))
	flare.scale = Vector3.ONE * maxf(4.5, distance_m * PIXEL_ANGLE * 4.0) * flicker
	var trail := plume.get_child(1) as CPUParticles3D
	var back := -source_velocity
	trail.direction = back.normalized() if back.length_squared() > 1e-6 else Vector3.UP
	trail.initial_velocity_min = back.length() * 0.9
	trail.initial_velocity_max = back.length() * 1.0
	trail.color = Color(0.92, 0.92, 0.92, 1.0) * (0.35 + 0.65 * daylight)


func release_plume(plume: Node3D) -> void:
	if plume == null or _plume_free.has(plume):
		return
	plume.visible = false
	(plume.get_child(1) as CPUParticles3D).emitting = false
	_plumes.erase(plume)
	_plume_free.append(plume)


## An aircraft's engine glow: a warm point at the tail that holds a few pixels at any range.
func acquire_glow() -> MeshInstance3D:
	var node: MeshInstance3D
	if not _glow_free.is_empty():
		node = _glow_free.pop_back()
	else:
		node = MeshInstance3D.new()
		node.mesh = _quad
		node.material_override = _engine_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	node.visible = true
	return node


func drive_glow(node: MeshInstance3D, at: Vector3, size_m: float, distance_m: float) -> void:
	node.position = at
	var flicker := 0.9 + 0.1 * sin(_clock * 29.0 + float(node.get_instance_id() % 13))
	node.scale = Vector3.ONE * maxf(size_m, distance_m * PIXEL_ANGLE * 2.2) * flicker


func release_glow(node: MeshInstance3D) -> void:
	if node == null or _glow_free.has(node):
		return
	node.visible = false
	_glow_free.append(node)


## Returns a particle node to the pool. Safe for a node that has already gone back.
func release(p: CPUParticles3D) -> void:
	if p == null or _free.has(p):
		return
	_busy.erase(p)
	_park(p)


## Everything back to the pools: a new scenario.
func reset() -> void:
	for p in _busy.duplicate():
		release(p)
	for f in _flashes:
		(f["node"] as MeshInstance3D).visible = false
		_flash_free.append(f["node"])
	_flashes.clear()
	for plume in _plumes.duplicate():
		release_plume(plume)
	for rig in _fires.duplicate():
		release_fire(rig)
	clear_trails()


# --- Building blocks -----------------------------------------------------------------------

func _one_shot(p: CPUParticles3D, nm: Vector2, h: float, life: float) -> void:
	p.set_meta("nm", nm)
	p.set_meta("h", h)
	p.position = WorldPresentation.to_world(nm, origin_nm, h)
	p.one_shot = true
	p.emitting = true
	p.restart()
	p.set_meta("until", _clock + life)
	_busy.append(p)


func _park(p: CPUParticles3D) -> void:
	p.emitting = false
	p.visible = false
	p.remove_meta("until")
	p.remove_meta("nm")
	p.remove_meta("h")
	if not _free.has(p):
		_free.append(p)


func _emitter() -> CPUParticles3D:
	var p: CPUParticles3D
	if not _free.is_empty():
		p = _free.pop_back()
	elif _busy.size() < MAX_PARTICLE_NODES:
		p = CPUParticles3D.new()
		p.mesh = _quad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
	else:
		# Recycle the oldest burst rather than growing without bound.
		p = _busy.pop_front()
	p.visible = true
	p.local_coords = true
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.25
	p.lifetime_randomness = 0.25
	p.speed_scale = rate
	p.preprocess = 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.direction = Vector3.UP
	p.spread = 20.0
	p.flatness = 0.0
	p.gravity = Vector3.ZERO
	p.damping_min = 0.0
	p.damping_max = 0.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	p.scale_amount_curve = null
	p.color_ramp = null
	p.color = Color.WHITE
	p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	return p


## Black smoke standing over a wreck or a hit.
func _column(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _smoke_material
	p.amount = int(56 * clampf(scale, 0.7, 1.8))
	p.lifetime = 22.0 * clampf(scale, 0.8, 1.5)
	p.preprocess = 4.0
	p.emission_sphere_radius = 6.0 * scale
	p.spread = 14.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 7.0
	p.gravity = wind * 0.3 + Vector3(0.0, 0.3, 0.0)
	p.damping_min = 0.1
	p.damping_max = 0.25
	p.scale_amount_min = 16.0 * scale
	p.scale_amount_max = 34.0 * scale
	p.scale_amount_curve = _billow
	p.color_ramp = _black_ramp
	var grey := 0.12 * (0.3 + 0.7 * daylight)
	p.color = Color(grey, grey, grey * 1.05, 1.0)
	return p


func _fireball(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _glow_material
	p.amount = 36
	p.lifetime = 1.5
	p.explosiveness = 0.95
	p.emission_sphere_radius = 4.0 * scale
	p.spread = 180.0
	p.initial_velocity_min = 8.0 * scale
	p.initial_velocity_max = 22.0 * scale
	p.gravity = Vector3(0.0, 4.0, 0.0)
	p.damping_min = 3.0
	p.damping_max = 6.0
	p.scale_amount_min = 10.0 * scale
	p.scale_amount_max = 26.0 * scale
	p.scale_amount_curve = _grow
	p.color_ramp = _fire_ramp
	return p


func _debris(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _debris_material
	p.amount = 26
	p.lifetime = 3.0
	p.lifetime_randomness = 0.4
	p.explosiveness = 1.0
	p.emission_sphere_radius = 2.0 * scale
	p.spread = 70.0
	p.initial_velocity_min = 22.0 * scale
	p.initial_velocity_max = 58.0 * scale
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.8 * scale
	p.scale_amount_max = 2.6 * scale
	var g := 0.06 + 0.06 * daylight
	p.color = Color(g, g * 0.95, g * 0.9, 1.0)
	return p


func _dark_puff(scale: float, grey := 0.2) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _smoke_material
	p.amount = 26
	p.lifetime = 9.0
	p.explosiveness = 0.85
	p.emission_sphere_radius = 5.0 * scale
	p.spread = 90.0
	p.initial_velocity_min = 2.0 * scale
	p.initial_velocity_max = 7.0 * scale
	p.gravity = wind * 0.3 + Vector3(0.0, 0.9, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.0
	p.scale_amount_min = 12.0 * scale
	p.scale_amount_max = 30.0 * scale
	p.scale_amount_curve = _billow
	p.color_ramp = _black_ramp
	var g := grey * (0.3 + 0.7 * daylight)
	p.color = Color(g, g, g * 1.04, 1.0)
	return p


## The launch cloud: dense white billows that roll out along the deck and the water and climb.
func _puff(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _smoke_material
	p.amount = 44
	p.lifetime = 13.0
	p.lifetime_randomness = 0.3
	p.explosiveness = 0.92
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0 * scale
	p.direction = Vector3(0.0, 0.4, 0.0)
	p.spread = 180.0
	p.flatness = 0.45
	p.initial_velocity_min = 2.0 * scale
	p.initial_velocity_max = 7.5 * scale
	p.gravity = wind * 0.25 + Vector3(0.0, 0.35, 0.0)
	p.damping_min = 0.5
	p.damping_max = 1.1
	p.scale_amount_min = 11.0 * scale
	p.scale_amount_max = 21.0 * scale
	p.scale_amount_curve = _puff_growth
	p.color_ramp = _smoke_ramp
	var w := 0.35 + 0.65 * daylight
	p.color = Color(1.0 * w, 1.0 * w, 1.0 * w, 1.0)
	return p


func _gun_smoke(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _smoke_material
	p.amount = 8
	p.lifetime = 4.0
	p.explosiveness = 0.9
	p.emission_sphere_radius = 1.0 * scale
	p.spread = 40.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = wind * 0.3 + Vector3(0.0, 0.3, 0.0)
	p.damping_min = 0.8
	p.damping_max = 1.2
	p.scale_amount_min = 3.0 * scale
	p.scale_amount_max = 7.0 * scale
	p.scale_amount_curve = _billow
	p.color_ramp = _smoke_ramp
	var g := 0.62 * (0.35 + 0.65 * daylight)
	p.color = Color(g, g, g, 1.0)
	return p


func _splash(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _spray_material
	p.amount = 44
	p.lifetime = 2.6
	p.explosiveness = 0.92
	p.emission_sphere_radius = 3.0 * scale
	p.spread = 14.0
	p.initial_velocity_min = 16.0 * scale
	p.initial_velocity_max = 34.0 * scale
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 4.0 * scale
	p.scale_amount_max = 11.0 * scale
	p.scale_amount_curve = _grow
	p.color_ramp = _spray_ramp
	p.color = Color(0.9, 0.93, 0.96) * (0.3 + 0.7 * daylight)
	return p


func _chaff(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _glow_material
	p.amount = 110
	p.lifetime = 5.0
	p.explosiveness = 0.85
	p.emission_sphere_radius = 6.0 * scale
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.gravity = wind * 0.5 + Vector3(0.0, -1.1, 0.0)
	p.damping_min = 0.8
	p.damping_max = 1.4
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.7 * scale
	p.scale_amount_max = 1.4 * scale
	p.scale_amount_curve = _shrink
	p.color_ramp = _chaff_ramp
	p.color = Color(1.0, 0.98, 0.9)
	return p


func _particle_material(additive: bool, texture: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = texture
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _billboard_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_texture = _radial_texture()
	m.albedo_color = color
	m.render_priority = 3
	return m


static var _puff_tex: Texture2D = null
static var _chunk_tex: Texture2D = null


## A smoke puff generated in code: a lumpy ball lit from above and to one side, so billboards of
## it read as round billows. No image asset is needed.
static func puff_texture() -> Texture2D:
	if _puff_tex != null:
		return _puff_tex
	var size := 96
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.06
	noise.fractal_octaves = 4
	var light := Vector3(-0.45, 0.62, 0.64).normalized()
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - half, y - half) / half
			var r := d.length()
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var edge := clampf((1.0 - r) * 1.9 + (n - 0.5) * 0.7, 0.0, 1.0)
			var a := edge * edge * (3.0 - 2.0 * edge) * (0.82 + 0.18 * n)
			var nz := sqrt(maxf(0.0, 1.0 - minf(r * r, 1.0)))
			var lit := clampf(Vector3(d.x, -d.y, nz).dot(light) * 0.5 + 0.55, 0.0, 1.0)
			var shade := lerpf(0.6, 1.0, lit) * (0.9 + 0.1 * n)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex


static func _chunk_texture() -> Texture2D:
	if _chunk_tex != null:
		return _chunk_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.75])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 16
	tex.height = 16
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_chunk_tex = tex
	return tex


## A soft round sprite generated in code, so particles need no image asset.
static func _radial_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


static func _ramp(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	return c
