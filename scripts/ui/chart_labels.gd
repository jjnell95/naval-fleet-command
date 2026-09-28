class_name ChartLabels
extends RefCounted
## Where the chart prints its track numbers and tags. Every symbol asks for its label at the
## classic place, the lower right; where that would print over another label or another symbol,
## the label moves to the upper right, the lower left or the upper left, and where none of those is
## clear it is left off, so a close formation never smears its numbers into one another. The hooked
## platform's label is placed first and always printed at the classic place.
##
## The assignment is remade a few times a second rather than every frame (labels follow their
## symbols in between, and a settled plot does not flicker), and the collision test walks a coarse
## grid, so a busy plot costs a fraction of a millisecond. The placement itself is a pure function,
## so the tests can pin it.

## Offset signs (x, y) tried in order: lower right, upper right, lower left, upper left.
const OFFSETS: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)]
const HIDDEN := -1
## The classic place: the number's left edge and baseline this far from the centre of a 16 px
## symbol; a larger graphic symbol pushes it out a little further.
const OFFSET_PX := Vector2(7.0, 17.0)
const EXTENT_PUSH := 0.4
const REPLACE_S := 0.25
const CELL_PX := 48.0
const GAP_PX := 2.0

var _slots: Dictionary = {}  # key -> offset index, or HIDDEN
var _last_s := -INF
var _last_count := -1


## True when the assignment should be remade: a quarter second on, or a changed number of labels.
func due(now: float, count: int) -> bool:
	return now - _last_s >= REPLACE_S or now < _last_s or count != _last_count


func assign(labels: Array, now: float) -> void:
	_slots = place(labels)
	_last_s = now
	_last_count = labels.size()


## The offset index a label was given (the classic place for one not yet assigned), or HIDDEN.
func slot(key: Variant) -> int:
	return int(_slots.get(key, 0))


func clear() -> void:
	_slots.clear()
	_last_s = -INF
	_last_count = -1


## The text block's box for one offset. `at` is the symbol's centre, `extent` its half-size, `size`
## the block's width and height, `ascent` the first line's ascent above its baseline.
static func box(at: Vector2, extent: float, size: Vector2, ascent: float, offset: Vector2) -> Rect2:
	var push := OFFSET_PX + Vector2.ONE * (extent - MapSymbols.RADIUS) * EXTENT_PUSH
	var gap := push.y - ascent  # the block's edge this far past the centre, above or below
	var left := at.x + push.x if offset.x > 0.0 else at.x - push.x - size.x
	var top := at.y + gap if offset.y > 0.0 else at.y - gap - size.y
	return Rect2(left, top, size.x, size.y)


## The first line's baseline for a box.
static func baseline(rect: Rect2, ascent: float) -> Vector2:
	return Vector2(rect.position.x, rect.position.y + ascent)


## Assigns every label an offset index, or HIDDEN. `labels` are dictionaries with `key`, `at`
## (Vector2), `extent`, `size` (Vector2), `ascent` and `priority`. Priority labels (the hook's) are
## placed first and never left off; the rest follow in the order given, each clear of every symbol
## but its own and of every label already placed, or left off where none of the four places is.
static func place(labels: Array) -> Dictionary:
	var slots := {}
	var grid := {}  # Vector2i cell -> PackedInt32Array of entries
	var rects: Array[Rect2] = []
	var owners := PackedInt32Array()  # the label whose symbol a rect is, or -1 for a placed label
	for i in labels.size():
		var l: Dictionary = labels[i]
		var e: float = l["extent"]
		_insert(grid, rects, owners, Rect2((l["at"] as Vector2) - Vector2.ONE * e, Vector2.ONE * 2.0 * e), i)
	var order := PackedInt32Array()
	for i in labels.size():
		if bool(labels[i].get("priority", false)):
			order.append(i)
	for i in labels.size():
		if not bool(labels[i].get("priority", false)):
			order.append(i)
	for i in order:
		var l: Dictionary = labels[i]
		var at: Vector2 = l["at"]
		var priority := bool(l.get("priority", false))
		slots[l["key"]] = HIDDEN
		for k in OFFSETS.size():
			var r := box(at, l["extent"], l["size"], l["ascent"], OFFSETS[k])
			if _clear(grid, rects, owners, r.grow(GAP_PX), i):
				slots[l["key"]] = k
				_insert(grid, rects, owners, r, -1)
				break
		if priority and int(slots[l["key"]]) == HIDDEN:
			# The hook's number is never left off: it takes the classic place, clear or not.
			slots[l["key"]] = 0
			_insert(grid, rects, owners, box(at, l["extent"], l["size"], l["ascent"], OFFSETS[0]), -1)
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
