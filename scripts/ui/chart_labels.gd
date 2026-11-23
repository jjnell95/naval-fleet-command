class_name ChartLabels
extends RefCounted
## Places track labels and chart captions in one collision grid. The inspected contact gets
## first choice, followed by the selected platforms. A crowded primary label can move farther
## from its symbol and connect to it with a leader. Other labels need a clear adjacent space.
## Obstacles are screen rectangles nothing may print over (the radio line's plate). A caption may
## offer alternative places (`alts`, offsets of its rect) for when its first place is taken.

## Offset signs (x, y) tried in order: lower right, upper right, lower left, upper left.
const OFFSETS: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)]
const HIDDEN := -1
## Grid owners for the reservations that belong to no label.
const _OWNER_PLACED := -1
const _OWNER_CAPTION := -2
const _OWNER_OBSTACLE := -3
## The classic place: the number's left edge and baseline this far from the centre of a 16 px
## symbol; a larger graphic symbol pushes it out a little further.
const OFFSET_PX := Vector2(7.0, 17.0)
const EXTENT_PUSH := 0.4
const REPLACE_S := 0.25
const CELL_PX := 48.0
const GAP_PX := 2.0
const CALLOUT_STEP := Vector2(20, 15)
const CALLOUT_LEVELS := 6

var _slots: Dictionary = {}  # key -> offset index, or HIDDEN
var _last_s := -INF
var _last_count := -1
var _last_obstacles: Array = []
var _last_captions := PackedStringArray()


## True when the assignment should be remade: a quarter second on, a changed number of labels, an
## obstacle that came, went or changed size (a radio line arriving clears its band at once), or a
## different caption at some index. Captions are keyed by their place in the frame's queue, so one
## that takes another's index must not inherit a place it does not have.
func due(now: float, count: int, obstacles: Array = [], captions: Array = []) -> bool:
	return now - _last_s >= REPLACE_S or now < _last_s or count != _last_count or obstacles != _last_obstacles or _signature(captions) != _last_captions


func assign(labels: Array, now: float, bounds := Rect2(), captions: Array = [], obstacles: Array = []) -> void:
	_slots = place(labels, bounds, captions, obstacles)
	_last_s = now
	_last_count = labels.size() + captions.size()
	_last_obstacles = obstacles.duplicate()
	_last_captions = _signature(captions)


## The offset index a label was given (the classic place for one not yet assigned), or HIDDEN.
func slot(key: Variant) -> int:
	return int(_slots.get(key, 0))


func clear() -> void:
	_slots.clear()
	_last_s = -INF
	_last_count = -1
	_last_obstacles = []
	_last_captions = PackedStringArray()


## A caption's rect in the place it was given: slot 0 is its own place, slot k its (k-1)th
## alternative. A slot it has no alternative for is its own place.
static func caption_rect(caption: Dictionary, slot_index: int) -> Rect2:
	var rect: Rect2 = caption.rect
	var alts: Array = caption.get("alts", [])
	if slot_index > 0 and slot_index <= alts.size():
		rect.position += alts[slot_index - 1] as Vector2
	return rect


static func _signature(captions: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for caption: Dictionary in captions:
		out.append("%s|%d" % [caption.get("text", ""), (caption.get("alts", []) as Array).size()])
	return out


## The text block's box for one offset. `at` is the symbol's centre, `extent` its half-size, `size`
## the block's width and height, `ascent` the first line's ascent above its baseline. `hook` is the
## half-size of the brackets round a hooked symbol: the block starts beyond them, at the same
## height, so the brackets never cut into the number.
static func box(at: Vector2, extent: float, size: Vector2, ascent: float, offset: Vector2, hook := 0.0) -> Rect2:
	var push := OFFSET_PX + Vector2.ONE * (extent - MapSymbols.RADIUS) * EXTENT_PUSH
	push.x = maxf(push.x, hook + GAP_PX)
	var gap := push.y - ascent  # the block's edge this far past the centre, above or below
	var left := at.x + push.x if offset.x > 0.0 else at.x - push.x - size.x
	var top := at.y + gap if offset.y > 0.0 else at.y - gap - size.y
	return Rect2(left, top, size.x, size.y)


## The first line's baseline for a box.
static func baseline(rect: Rect2, ascent: float) -> Vector2:
	return Vector2(rect.position.x, rect.position.y + ascent)


## The first four slots sit beside the symbol. Higher slots move the block farther along the
## same diagonal so the inspected number can clear a cluster without moving its marker.
static func slot_box(label: Dictionary, slot_index: int) -> Rect2:
	var direction := OFFSETS[slot_index % OFFSETS.size()]
	var rect := box(label.at, label.extent, label.size, label.ascent, direction, label.get("hook", 0.0))
	rect.position += direction * CALLOUT_STEP * floorf(float(slot_index) / OFFSETS.size())
	return rect


static func place(labels: Array, bounds := Rect2(), captions: Array = [], obstacles: Array = []) -> Dictionary:
	var slots := {}
	var grid := {}
	var rects: Array[Rect2] = []
	var owners := PackedInt32Array()
	var order := PackedInt32Array()
	var ordinary := PackedInt32Array()
	for obstacle: Rect2 in obstacles:
		_insert(grid, rects, owners, obstacle, _OWNER_OBSTACLE)
	for i in labels.size():
		var l: Dictionary = labels[i]
		var e := maxf(l.extent, l.get("hook", 0.0))
		_insert(grid, rects, owners, Rect2(l.at - Vector2.ONE * e, Vector2.ONE * 2.0 * e), i)
		slots[l.key] = HIDDEN
		if l.size == Vector2.ZERO or (bounds.has_area() and not bounds.has_point(l.at)):
			continue
		if l.get("priority", false):
			order.append(i)
		else:
			ordinary.append(i)
	var primary := order[0] if not order.is_empty() else -1
	order.append_array(ordinary)
	for i in order:
		var l: Dictionary = labels[i]
		var limit := OFFSETS.size() * (CALLOUT_LEVELS + 1 if i == primary else 1)
		var inside := HIDDEN
		for k in limit:
			var r := slot_box(l, k)
			if bounds.has_area() and not bounds.encloses(r.grow(GAP_PX)):
				continue
			if inside == HIDDEN:
				inside = k
			if _clear(grid, rects, owners, r.grow(GAP_PX), i):
				slots[l.key] = k
				_insert(grid, rects, owners, r, _OWNER_PLACED)
				break
		if i == primary and int(slots[l.key]) == HIDDEN and inside != HIDDEN:
			slots[l.key] = inside
			_insert(grid, rects, owners, slot_box(l, inside), _OWNER_PLACED)
	for caption: Dictionary in captions:
		slots[caption.key] = HIDDEN
		var places := 1 + (caption.alts as Array).size() if caption.has("alts") else 1
		for k in places:
			var rect := caption_rect(caption, k)
			if (not bounds.has_area() or bounds.encloses(rect)) and _clear(grid, rects, owners, rect.grow(GAP_PX), _OWNER_CAPTION):
				slots[caption.key] = k
				_insert(grid, rects, owners, rect, _OWNER_PLACED)
				break
	return slots


static func _cells(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := floori(r.position.x / CELL_PX)
	var x1 := floori(r.end.x / CELL_PX)
	var y0 := floori(r.position.y / CELL_PX)
	var y1 := floori(r.end.y / CELL_PX)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out


static func _insert(grid: Dictionary, rects: Array[Rect2], owners: PackedInt32Array, r: Rect2, owner: int) -> void:
	var id := rects.size()
	rects.append(r)
	owners.append(owner)
	for cell in _cells(r):
		if not grid.has(cell):
			grid[cell] = PackedInt32Array()
		var entries: PackedInt32Array = grid[cell]
		entries.append(id)
		grid[cell] = entries


## True when nothing in the grid but the label's own symbol intersects `r`.
static func _clear(grid: Dictionary, rects: Array[Rect2], owners: PackedInt32Array, r: Rect2, self_index: int) -> bool:
	for cell in _cells(r):
		if not grid.has(cell):
			continue
		for id in grid[cell]:
			if owners[id] == self_index:
				continue
			if rects[id].intersects(r):
				return false
	return true
