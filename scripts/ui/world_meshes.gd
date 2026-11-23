class_name WorldMeshes
## Procedural meshes for the world view that need no asset: the ocean disc, the flat ring
## drawn on the water under a contact, and the graded platform an installation stands on.

const OCEAN_RINGS := 72
const OCEAN_SEGMENTS := 96
const OCEAN_NEAR_M := 6.0
const OCEAN_FAR_M := 350000.0


## A disc of concentric rings whose spacing grows geometrically, so the water near the camera is
## dense enough to ride the swell and the far field still reaches the horizon in one mesh.
static func ocean() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	var growth := pow(OCEAN_FAR_M / OCEAN_NEAR_M, 1.0 / float(OCEAN_RINGS - 1))
	for ring in OCEAN_RINGS:
		var r := OCEAN_NEAR_M * pow(growth, float(ring))
		for s in OCEAN_SEGMENTS:
			var a := TAU * float(s) / float(OCEAN_SEGMENTS)
			vertices.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
			normals.append(Vector3.UP)
	for s in OCEAN_SEGMENTS:
		indices.append(0)
		indices.append(1 + (s + 1) % OCEAN_SEGMENTS)
		indices.append(1 + s)
	for ring in OCEAN_RINGS - 1:
		var inner := 1 + ring * OCEAN_SEGMENTS
		var outer := inner + OCEAN_SEGMENTS
		for s in OCEAN_SEGMENTS:
			var n := (s + 1) % OCEAN_SEGMENTS
			indices.append_array(PackedInt32Array([inner + s, outer + n, outer + s, inner + s, inner + n, outer + n]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-OCEAN_FAR_M, -50.0, -OCEAN_FAR_M), Vector3(OCEAN_FAR_M * 2.0, 100.0, OCEAN_FAR_M * 2.0))
	return mesh


static func ring() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 56
	for s in segments:
		var a := TAU * float(s) / float(segments)
		vertices.append(Vector3(cos(a) * 0.93, 0.0, sin(a) * 0.93))
		vertices.append(Vector3(cos(a), 0.0, sin(a)))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for s in segments:
		var i := s * 2
		var n := ((s + 1) % segments) * 2
		indices.append_array(PackedInt32Array([i, n, i + 1, i + 1, n, n + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A unit square platform, top face at y = 0 spanning -0.5..0.5, whose sides slope out and down to
## y = -1 like the batters of a cut-and-fill site. Scaled to a footprint and a depth where used.
static func plinth() -> ArrayMesh:
	const FLARE := 0.62  # how far out each side reaches at the bottom, beyond the top's half-width
	var top := [Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5)]
	var bottom := [Vector3(-FLARE, -1.0, -FLARE), Vector3(FLARE, -1.0, -FLARE), Vector3(FLARE, -1.0, FLARE), Vector3(-FLARE, -1.0, FLARE)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, top[0], top[1], top[2], top[3])
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, bottom[i], bottom[j], top[j], top[i])
	st.generate_normals()
	return st.commit()


## Two triangles of a quad whose corners run clockwise as seen from the side it faces, which is
## Godot's front.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(v)
