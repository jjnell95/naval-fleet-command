class_name WorldEffects
extends Node3D
## Transient visuals for the world view: fireballs, smoke, splashes, chaff, launch flashes, and
## the emitters that ride with a burning ship or a missile. CPU particles only, so the same code
## runs in the browser build.
##
## Every emitter works in local coordinates, because the world slides under the floating origin
## and world-space particles would slide with it. A moving source hands its velocity in and the
## new particles are given the opposite, which leaves smoke standing in the sea's frame instead
## of the ship's. WorldScene owns positions; this class owns lifetimes and the pool.

const MAX_PARTICLE_NODES := 40
const MAX_FLASHES := 10

var daylight := 1.0
var wind := Vector3.ZERO  # downwind, metres per second

var _free: Array[CPUParticles3D] = []
var _busy: Array[CPUParticles3D] = []
var _flash_free: Array[MeshInstance3D] = []
var _flashes: Array[Dictionary] = []
var _plume_free: Array[Node3D] = []
var _quad: QuadMesh
var _smoke_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _spray_material: StandardMaterial3D
var _flare_material: StandardMaterial3D
var _smoke_ramp: Gradient
var _fire_ramp: Gradient
var _spray_ramp: Gradient
var _chaff_ramp: Gradient
var _grow: Curve
var _shrink: Curve
var _clock := 0.0


func _ready() -> void:
	name = "Effects"
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_smoke_material = _particle_material(false)
	_glow_material = _particle_material(true)
	_spray_material = _particle_material(false)
	_flare_material = StandardMaterial3D.new()
	_flare_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flare_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flare_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flare_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flare_material.albedo_texture = _radial_texture()
	_flare_material.albedo_color = Color(1.0, 0.86, 0.62, 0.9)
	_smoke_ramp = _ramp([0.0, 0.08, 0.55, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.0)])
	_fire_ramp = _ramp([0.0, 0.25, 0.6, 1.0], [Color(1.0, 0.97, 0.75, 1.0), Color(1.0, 0.55, 0.15, 0.9), Color(0.55, 0.12, 0.03, 0.5), Color(0.2, 0.05, 0.02, 0.0)])
	_spray_ramp = _ramp([0.0, 0.2, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	_chaff_ramp = _ramp([0.0, 0.1, 0.7, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	_grow = Curve.new()
	_grow.add_point(Vector2(0.0, 0.25))
	_grow.add_point(Vector2(1.0, 1.0))
	_shrink = Curve.new()
	_shrink.add_point(Vector2(0.0, 1.0))
	_shrink.add_point(Vector2(1.0, 0.15))


func _process(delta: float) -> void:
	_clock += delta
	for i in range(_flashes.size() - 1, -1, -1):
		var f := _flashes[i]
		var node: MeshInstance3D = f["node"]
		var p := (_clock - float(f["born"])) / float(f["life"])
		if p >= 1.0:
			node.visible = false
			_flash_free.append(node)
			_flashes.remove_at(i)
			continue
		var size: float = f["size"] * (0.6 + 1.2 * p)
		node.scale = Vector3.ONE * size
		var mat := node.material_override as StandardMaterial3D
		var color: Color = f["color"]
		mat.albedo_color = Color(color.r, color.g, color.b, color.a * (1.0 - p) * (1.0 - p))
	for i in range(_busy.size() - 1, -1, -1):
		var p := _busy[i]
		if p.has_meta("until") and float(p.get_meta("until")) <= _clock:
			_park(p)
			_busy.remove_at(i)


# --- One-shot effects --------------------------------------------------------------------

## Fire-and-forget bursts at a world position. Long-lived columns come back as nodes the caller
## re-anchors every frame, because the origin under them moves; each is {node, until}.
func burst(kind: String, at: Vector3, scale := 1.0) -> Array[Dictionary]:
	var anchored: Array[Dictionary] = []
	match kind:
		"hit", "destroyed":
			var big := kind == "destroyed"
			flash(at, (28.0 if big else 16.0) * scale, Color(1.0, 0.85, 0.6, 1.0), 0.5)
			_one_shot(_fireball(scale * (1.7 if big else 1.0)), at)
			var column := _column(scale * (1.8 if big else 1.0))
			column.position = at
			column.emitting = true
			anchored.append({"node": column, "until": _clock + (70.0 if big else 26.0)})
		"intercept":
			flash(at, 14.0 * scale, Color(1.0, 0.95, 0.85, 1.0), 0.35)
			_one_shot(_fireball(scale * 0.55), at)
			_one_shot(_puff(scale * 0.8, Color(0.55, 0.55, 0.58)), at)
		"decoy":
			flash(at, 6.0 * scale, Color(1.0, 1.0, 0.9, 0.8), 0.25)
			_one_shot(_chaff(scale), at)
		"launch":
			flash(at, 9.0 * scale, Color(1.0, 0.9, 0.7, 1.0), 0.3)
			_one_shot(_puff(scale, Color(0.82, 0.82, 0.80)), at)
		"refused":
			pass
		_:
			_one_shot(_splash(scale), at)
	return anchored


## A soft additive flash that grows and fades.
func flash(at: Vector3, size: float, color: Color, life: float) -> void:
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
	node.position = at
	_flashes.append({"node": node, "born": _clock, "life": life, "size": size, "color": color})


# --- Emitters that ride with something -------------------------------------------------

## A smoke column for a burning ship. The caller drives it every frame and releases it.
func acquire_smoke() -> CPUParticles3D:
	var p := _column(1.0)
	p.emitting = true
	p.restart()
	p.remove_meta("until")
	return p


## Position, source velocity and intensity for a column already acquired.
func drive_smoke(p: CPUParticles3D, at: Vector3, source_velocity: Vector3, intensity: float, width_m: float) -> void:
	p.position = at
	var drift := wind * 0.45 + Vector3(0.0, 1.6 + 1.5 * intensity, 0.0) - source_velocity
	p.direction = drift.normalized() if drift.length_squared() > 1e-6 else Vector3.UP
	p.initial_velocity_min = drift.length() * 0.85
	p.initial_velocity_max = drift.length() * 1.15
	p.emission_sphere_radius = maxf(width_m * 0.18, 3.0)
	p.scale_amount_min = 10.0 + 30.0 * intensity
	p.scale_amount_max = 16.0 + 44.0 * intensity
	var grey := 0.36 - 0.18 * intensity
	p.color = Color(grey * (0.3 + 0.7 * daylight), grey * (0.3 + 0.7 * daylight), (grey + 0.02) * (0.3 + 0.7 * daylight), 1.0)


## An exhaust plume for a missile: a flare at the nozzle and a short smoke trail.
func acquire_plume() -> Node3D:
	if not _plume_free.is_empty():
		var reused: Node3D = _plume_free.pop_back()
		reused.visible = true
		(reused.get_child(1) as CPUParticles3D).emitting = true
		return reused
	var plume := Node3D.new()
	var flare := MeshInstance3D.new()
	flare.mesh = _quad
	flare.material_override = _flare_material
	flare.scale = Vector3.ONE * 5.0
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.add_child(flare)
	var trail := CPUParticles3D.new()
	trail.mesh = _quad
	trail.material_override = _smoke_material
	trail.local_coords = true
	trail.amount = 36
	trail.lifetime = 4.0
	trail.explosiveness = 0.0
	trail.randomness = 0.3
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 1.0
	trail.spread = 6.0
	trail.gravity = Vector3(0.0, 0.4, 0.0)
	trail.damping_min = 0.4
	trail.damping_max = 0.8
	trail.scale_amount_min = 4.0
	trail.scale_amount_max = 7.0
	trail.scale_amount_curve = _grow
	trail.color_ramp = _smoke_ramp
	trail.color = Color(0.8, 0.8, 0.8)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.emitting = true
	plume.add_child(trail)
	add_child(plume)
	return plume


## `distance_m` is the camera's distance, so a plume miles off still reads as a point of light.
func drive_plume(plume: Node3D, at: Vector3, source_velocity: Vector3, glow: float, distance_m := 0.0) -> void:
	plume.position = at
	var flare := plume.get_child(0) as MeshInstance3D
	var flicker := 0.85 + 0.3 * sin(_clock * 37.0 + float(plume.get_instance_id() % 17))
	flare.scale = Vector3.ONE * maxf(3.0 + 4.0 * glow, distance_m * 0.0045) * flicker
	var trail := plume.get_child(1) as CPUParticles3D
	var back := -source_velocity
	trail.direction = back.normalized() if back.length_squared() > 1e-6 else Vector3.UP
	trail.initial_velocity_min = back.length() * 0.92
	trail.initial_velocity_max = back.length() * 1.0
	trail.color = Color(0.82, 0.82, 0.8, 1.0) * (0.35 + 0.65 * daylight)


func release_plume(plume: Node3D) -> void:
	if plume == null:
		return
	plume.visible = false
	(plume.get_child(1) as CPUParticles3D).emitting = false
	_plume_free.append(plume)


## Returns a particle node to the pool. Safe for a node that has already gone back.
func release(p: CPUParticles3D) -> void:
	if p == null or _free.has(p):
		return
	_busy.erase(p)
	_park(p)


# --- Building blocks ---------------------------------------------------------------------

func _one_shot(p: CPUParticles3D, at: Vector3) -> void:
	p.position = at
	p.one_shot = true
	p.emitting = true
	p.restart()
	p.set_meta("until", _clock + p.lifetime * (1.0 + p.lifetime_randomness) + 0.5)
	_busy.append(p)


func _park(p: CPUParticles3D) -> void:
	p.emitting = false
	p.visible = false
	p.remove_meta("until")
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
	p.speed_scale = 1.0
	p.preprocess = 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.direction = Vector3.UP
	p.spread = 20.0
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


func _column(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _smoke_material
	p.amount = int(60 * clampf(scale, 0.6, 2.0))
	p.lifetime = 22.0 * clampf(scale, 0.8, 1.6)
	p.preprocess = 8.0  # a column that already stands, not one that starts as a wisp
	p.emission_sphere_radius = 5.0 * scale
	p.spread = 16.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 5.5
	p.gravity = wind * 0.45 + Vector3(0.0, 1.4, 0.0) * 0.4
	p.damping_min = 0.15
	p.damping_max = 0.3
	p.scale_amount_min = 14.0 * scale
	p.scale_amount_max = 26.0 * scale
	p.scale_amount_curve = _grow
	p.color_ramp = _smoke_ramp
	var grey := 0.3 * (0.3 + 0.7 * daylight)
	p.color = Color(grey, grey, grey + 0.01, 1.0)
	return p


func _fireball(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _glow_material
	p.amount = 28
	p.lifetime = 1.6
	p.explosiveness = 0.95
	p.emission_sphere_radius = 3.0 * scale
	p.spread = 180.0
	p.initial_velocity_min = 6.0 * scale
	p.initial_velocity_max = 16.0 * scale
	p.gravity = Vector3(0.0, 3.0, 0.0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 8.0 * scale
	p.scale_amount_max = 20.0 * scale
	p.scale_amount_curve = _grow
	p.color_ramp = _fire_ramp
	return p


func _puff(scale: float, tint: Color) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _smoke_material
	p.amount = 22
	p.lifetime = 6.0
	p.explosiveness = 0.9
	p.emission_sphere_radius = 3.0 * scale
	p.spread = 60.0
	p.initial_velocity_min = 3.0 * scale
	p.initial_velocity_max = 8.0 * scale
	p.gravity = wind * 0.3 + Vector3(0.0, 0.6, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.scale_amount_min = 5.0 * scale
	p.scale_amount_max = 14.0 * scale
	p.scale_amount_curve = _grow
	p.color_ramp = _smoke_ramp
	p.color = tint * (0.35 + 0.65 * daylight)
	return p


func _splash(scale: float) -> CPUParticles3D:
	var p := _emitter()
	p.material_override = _spray_material
	p.amount = 34
	p.lifetime = 2.2
	p.explosiveness = 0.92
	p.emission_sphere_radius = 2.0 * scale
	p.spread = 22.0
	p.initial_velocity_min = 12.0 * scale
	p.initial_velocity_max = 24.0 * scale
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 3.0 * scale
	p.scale_amount_max = 8.0 * scale
	p.scale_amount_curve = _grow
	p.color_ramp = _spray_ramp
	p.color = Color(0.9, 0.93, 0.95) * (0.3 + 0.7 * daylight)
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


func _particle_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _radial_texture()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


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
