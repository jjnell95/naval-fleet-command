class_name CdsMenus
extends Node
## Right-click menus for the command screen, in the manner of the late-1990s fleet-command games:
## the Orders menu on your own platform, Engage With on a contact, the route menu on a waypoint,
## and the CDS menu (symbols, overlays, boards, screens) with nothing hooked.
##
## The menu content is data: `orders_items`, `engage_items`, `waypoint_items` and `cds_items`
## return item dictionaries, which keeps the wording and the enabled/disabled rules testable
## without opening a window. `open` turns them into PopupMenus, and a chosen item's `action`
## dictionary goes back to Main through `action_chosen`, which is where orders are actually issued.
##
## Item: {text, action?, children?, disabled?, tooltip?, checked? (-1 none, 0 off, 1 on), separator?}
## Action kinds: order, unit_orders, formation, engage, close_in, palette, hook, waypoint_delete,
## layer, symbols, board, inspect.

signal action_chosen(action: Dictionary)
## The menu went away, chosen from or dismissed.
signal menu_closed

const SPEEDS_KN := [5.0, 10.0, 15.0, 20.0, 25.0]
const DEPTHS := [["Surface", 0.0], ["Periscope", 18.0], ["Shallow", 60.0], ["Patrol", -1.0], ["Deep", 200.0], ["Under the layer", -2.0]]
const ALTITUDES := [["Low", 150.0], ["Cruise", -1.0], ["High", -2.0]]

## The skin the menus wear. Popups are windows, and a plain Node parent breaks theme inheritance,
## so Main hands its theme over explicitly.
var theme_source: Theme
var _root: PopupMenu
var _actions: Dictionary = {}  # popup instance id -> {item id -> action}


# --- Menu content -------------------------------------------------------------------------

static func sep() -> Dictionary:
	return {"separator": true}


static func item(text: String, action: Dictionary, disabled := false, tooltip := "", checked := -1) -> Dictionary:
	return {"text": text, "action": action, "disabled": disabled, "tooltip": tooltip, "checked": checked}


static func submenu(text: String, children: Array, disabled := false, tooltip := "") -> Dictionary:
	return {"text": text, "children": children, "disabled": disabled or children.is_empty(), "tooltip": tooltip}


static func order_action(o: Order) -> Dictionary:
	return {"kind": "order", "order": o}


## The Orders menu for the hooked own units. `target` is the hooked contact, if any.
static func orders_items(units: Array, target: Track, controllable: bool, movable: bool, weapon_manager: WeaponManager = null) -> Array:
	var items: Array = []
	var ships: Array = []
	var aircraft: Array = []
	var diving: Array = []
	var any_radar := false
	var any_sonar := false
	var any_buoys := false
	var any_deck := false
	var any_route := false
	for u: Unit in units:
		if u.is_aircraft():
			if u.in_flight():
				aircraft.append(u)
		elif u.spec.max_speed_kn > 0.0:
			ships.append(u)
		if u.spec.max_depth_m > 0.0:
			diving.append(u)
		any_radar = any_radar or u.has_radar()
		any_sonar = any_sonar or u.has_sonar()
		any_buoys = any_buoys or (u.airborne() and u.sonobuoys > 0)
		any_deck = any_deck or u.spec.aircraft_capacity > 0 or u.is_aircraft()
		any_route = any_route or not u.waypoints.is_empty()
	var why := "" if controllable else "These platforms are not under your command."
	if target != null and controllable:
		items.append(item("Weapon control...  [Shift+E]", {"kind": "palette", "id": "weapon_control"}))
		items.append(submenu("Engage with", engage_weapon_items(units, target, weapon_manager), false, "Weapons that suit track %s." % DataDisplay.track_number_for_track(target)))
		items.append(item("Cancel queued fire for this contact", order_action(Order.cancel_fire(target)), false, "Refund unfired rounds for this contact. Weapons already away continue."))
	if movable:
		var speeds: Array = [item("Stop", order_action(Order.stop()))]
		for kn in SPEEDS_KN:
			speeds.append(item("%d knots" % int(kn), order_action(Order.set_speed(kn))))
		speeds.append(item("Flank", order_action(Order.set_speed(999.0))))
		items.append(submenu("Speed", speeds))
		items.append(item("Course...", {"kind": "board", "board": StatusBoards.BOARD_ORDERS, "tab": 0}, false, "Set an exact course on the orders board."))
	if not aircraft.is_empty():
		var alts: Array = []
		for a in ALTITUDES:
			alts.append(item(a[0], {"kind": "altitude", "metres": a[1]}))
		items.append(submenu("Altitude", alts, not controllable, why))
	if not diving.is_empty():
		var depths: Array = []
		var under := -1.0
		var floor_m := -1.0
		for u: Unit in diving:
			var d := Acoustics.below_layer_depth_m(u)
			if d > under:
				under = d
				floor_m = Acoustics.bottom_m(u)
			elif floor_m < 0.0:
				floor_m = Acoustics.bottom_m(u)
		for d in DEPTHS:
			var blocked: bool = d[1] == -2.0 and under < 0.0
			depths.append(item(d[0], {"kind": "depth", "metres": d[1]}, blocked, under_layer_reason(under, floor_m) if d[1] == -2.0 else ""))
		items.append(submenu("Depth", depths, not controllable, why))
	var sensors: Array = []
	if any_radar:
		sensors.append(item("Radar on", order_action(Order.activate_radar())))
		sensors.append(item("Radar off", order_action(Order.silence_radar())))
	if any_sonar:
		sensors.append(item("Sonar passive", order_action(Order.passive_sonar())))
		sensors.append(item("Sonar active", order_action(Order.active_sonar())))
	if any_buoys:
		sensors.append(item("Drop sonobuoy", order_action(Order.deploy_sonobuoy())))
	if not sensors.is_empty():
		items.append(submenu("Sensors", sensors, not controllable, why))
	items.append(submenu("EMCON", [
		item("Radiate", order_action(Order.set_emcon(false)), false, "", _all(units, func(u: Unit) -> bool: return u.emcon == Unit.Emcon.FREE)),
		item("Silent", order_action(Order.set_emcon(true)), false, "", _all(units, func(u: Unit) -> bool: return u.emcon == Unit.Emcon.SILENT)),
	], not controllable, why))
	items.append(submenu("Weapons state", [
		item("Free", order_action(Order.set_roe(Unit.Roe.FREE)), false, "", _all(units, func(u: Unit) -> bool: return u.roe == Unit.Roe.FREE)),
		item("Tight", order_action(Order.set_roe(Unit.Roe.TIGHT)), false, "", _all(units, func(u: Unit) -> bool: return u.roe == Unit.Roe.TIGHT)),
		item("Hold", order_action(Order.set_roe(Unit.Roe.HOLD)), false, "", _all(units, func(u: Unit) -> bool: return u.roe == Unit.Roe.HOLD)),
	], not controllable, why))
	items.append(submenu("Defence", defence_items(units, movable), not controllable, why))
	if any_deck:
		items.append(item("Flight deck...", {"kind": "palette", "id": "air_operations"}, false, "Launch aircraft, or choose where an aircraft lands."))
	if ships.size() >= 2:
		var forms: Array = []
		for pattern in ["screen", "column", "abreast"]:
			forms.append(item(pattern.capitalize(), {"kind": "formation", "pattern": pattern}))
		forms.append(item("Break", order_action(Order.break_formation())))
		items.append(submenu("Formation", forms, not controllable, why))
	elif ships.size() == 1 and (ships[0] as Unit).in_formation():
		items.append(item("Break formation", order_action(Order.break_formation()), not controllable, why))
	items.append(sep())
	if movable:
		items.append(item("Plot route  [W]", {"kind": "palette", "id": "plot_move"}))
		items.append(item("Assign patrol area  [Shift+W]", {"kind": "palette", "id": "plot_patrol"}, false, "Click two corners; repeat the circuit until retasked or returning for fuel."))
	if any_route:
		items.append(item("Clear route", order_action(Order.clear_waypoints()), not controllable, why))
	items.append(item("Follow  [F]", {"kind": "palette", "id": "follow_selection"}))
	items.append(item("Centre  [C]", {"kind": "palette", "id": "focus_selection"}))
	if units.size() == 1:
		items.append(item("Reference  [F7]", {"kind": "inspect", "id": (units[0] as Unit).spec.id}))
	items.append(item("Status boards  [A]", {"kind": "board", "board": StatusBoards.BOARD_ORDERS}))
	return items


## Defence actions sit beside navigation and attack in the own-platform menu. Mixed settings
## leave every policy unmarked instead of claiming that the first selected ship speaks for all.
static func defence_items(units: Array, movable: bool) -> Array:
	var items: Array = []
	for entry in [["radar", "Chaff / RF  [D]"], ["infrared", "Flares / IR"], ["acoustic", "Acoustic decoy"]]:
		var ready := 0
		for u: Unit in units:
			if DefensiveResponse.can_deploy(u, entry[0]):
				ready += 1
		items.append(item(entry[1], order_action(Order.deploy_countermeasures(entry[0])), ready == 0,
			"%d of %d platforms ready. One pack per eligible platform; 20 s active, 25 s between deployments." % [ready, units.size()]))
	var evading := units.any(func(u: Unit) -> bool: return u.evasion_remaining_s > 0.0)
	items.append(item("Evade  [V]", order_action(Order.evade()), not movable, "Requires a detected inbound weapon and room to turn; the route resumes after the maneuver."))
	items.append(item("Run away", order_action(Order.evade("away")), not movable, "Turn away from a detected inbound weapon; the route resumes after the maneuver."))
	items.append(item("Resume plan", order_action(Order.resume_plan()), not evading, "End temporary evasion and resume the existing route or formation."))
	var policies: Array = []
	for policy: String in ["conserve", "balanced", "saturation"]:
		policies.append(item(policy.capitalize(), order_action(Order.set_defence_policy(policy)), false, "", _all(units, func(u: Unit) -> bool: return u.defence_policy == policy)))
	items.append(submenu("Interceptor policy", policies))
	items.append(submenu("Countermeasures", [
		item("Automatic", order_action(Order.set_auto_countermeasures(true)), false, "", _all(units, func(u: Unit) -> bool: return u.auto_countermeasures)),
		item("Manual", order_action(Order.set_auto_countermeasures(false)), false, "", _all(units, func(u: Unit) -> bool: return not u.auto_countermeasures)),
	]))
	return items


## The orders board's wording for the under-the-layer preset, so the menu and the board agree.
static func under_layer_reason(under_m: float, floor_m: float) -> String:
	if under_m >= 0.0:
		return "Run at %d m, under the %d m layer." % [int(under_m), int(Acoustics.layer_depth_m())]
	if Acoustics.layer_depth_m() <= 0.0:
		return "No layer in this water: it is mixed from the surface down."
	return "The %d m layer is below what this boat can reach here (floor %s)." % [int(Acoustics.layer_depth_m()), Bathymetry.format_depth(floor_m)]


## 1 when every unit passes, 0 otherwise; used for the check marks on state submenus.
static func _all(units: Array, test: Callable) -> int:
	if units.is_empty():
		return -1
	for u: Unit in units:
		if not test.call(u):
			return 0
	return 1


## Weapons the hooked units carry that suit the target, each with its rounds and a salvo choice.
static func engage_weapon_items(units: Array, target: Track, weapon_manager: WeaponManager = null) -> Array:
	var items: Array = []
	var seen := {}
	for u: Unit in units:
		for spec: WeaponSpec in u.weapons_for_track(target):
			if seen.has(spec.id):
				continue
			seen[spec.id] = true
			var rounds := 0
			var ready := false
			var reason := ""
			for v: Unit in units:
				if v.get_weapon(spec.id) == null:
					continue
				rounds += v.magazine_count(spec.id)
				var check := weapon_manager.engagement_check(v, spec, target, weapon_manager.now_s) if weapon_manager != null else Combat.check_engagement(v, spec, target)
				if check["ok"]:
					ready = true
				else:
					reason = str(check["reason"])
			var salvos: Array = []
			var sizes := [1, spec.salvo_default, spec.salvo_default * 2]
			var added := {}
			for n: int in sizes:
				n = maxi(n, 1)
				if added.has(n):
					continue
				added[n] = true
				salvos.append(item("%d round%s%s%s" % [n, "" if n == 1 else "s", " per platform" if units.size() > 1 else "", "  (default)" if n == spec.salvo_default else ""],
					{"kind": "engage", "weapon": spec.id, "rounds": n, "track": target}, false,
					"Each eligible selected platform fires up to %d available rounds. Queued rounds are already reserved." % n))
			var entry := submenu("%s - %d" % [spec.display_name, rounds], salvos, not ready, "" if ready else reason.capitalize())
			items.append(entry)
	return items


## Right-click on a contact.
static func engage_items(units: Array, target: Track, controllable: bool, weapon_manager: WeaponManager = null) -> Array:
	var items: Array = []
	var number := DataDisplay.track_number_for_track(target)
	items.append({"text": "Track %s  %s" % [number, target.description().capitalize()], "disabled": true})
	if controllable and not units.is_empty():
		items.append(item("Weapon control...  [Shift+E]", {"kind": "palette", "id": "weapon_control"}))
		items.append(submenu("Engage with", engage_weapon_items(units, target, weapon_manager), false, "Weapons that suit this contact."))
		items.append(item("Cancel queued fire for this contact", order_action(Order.cancel_fire(target)), false, "Refund unfired rounds for this contact. Weapons already away continue."))
		if target.identity != "HOSTILE" and not target.is_bearing_only():
			items.append(item("Close to identify", {"kind": "close_in", "track": target}, false, "Steer the hooked units toward the contact to classify it."))
	elif units.is_empty():
		items.append({"text": "Hook a platform to engage", "disabled": true})
	items.append(sep())
	items.append(item("Follow  [F]", {"kind": "palette", "id": "follow_selection"}))
	items.append(item("Frame shooter and target  [C]", {"kind": "palette", "id": "focus_selection"}))
	items.append(item("Track file", {"kind": "board", "board": StatusBoards.BOARD_TRACKS}))
	return items


static func waypoint_items(u: Unit, index: int) -> Array:
	return [
		{"text": "%s  waypoint %d" % [u.callsign, index + 1], "disabled": true},
		item("Delete this leg", {"kind": "waypoint_delete", "unit": u, "index": index}),
		item("Clear route", {"kind": "unit_orders", "pairs": [[u, Order.clear_waypoints()]]}),
	]


## The CDS menu: display and screens, with nothing hooked. `state` holds the map's current
## layer states (from Main) so the check marks tell the truth.
static func cds_items(state: Dictionary) -> Array:
	var symbols: Array = []
	var names := ["NTDS", "Small graphic", "Medium graphic", "Large graphic"]
	for i in names.size():
		symbols.append(item(names[i], {"kind": "symbols", "mode": i}, false, "", 1 if int(state.get("symbol_mode", 0)) == i else 0))
	var controls: Array = [
		item("Velocity leaders  [Shift+V]", {"kind": "layer", "name": "leaders"}, false, "", _on(state, "leaders")),
		item("Track numbers  [Shift+K]", {"kind": "layer", "name": "track_numbers"}, false, "", _on(state, "track_numbers")),
		item("Tags  [Shift+I]", {"kind": "layer", "name": "tags"}, false, "", _on(state, "tags")),
		item("Trails  [F5]", {"kind": "layer", "name": "trails"}, false, "", _on(state, "trails")),
	]
	var overlays: Array = [
		item("Relief shading  [F6]", {"kind": "layer", "name": "relief"}, false, "", _on(state, "relief")),
		item("Lat/long readout  [Ctrl+L]", {"kind": "layer", "name": "latlon"}, false, "", _on(state, "latlon")),
		item("Scale  [Ctrl+S]", {"kind": "layer", "name": "scale"}, false, "", _on(state, "scale")),
		item("Weapon ranges by role  [Shift+R]", {"kind": "layer", "name": "weapon_ranges"}, false, "", _on(state, "weapon_ranges")),
		item("Sensor rings  [F4]", {"kind": "layer", "name": "sensors"}, false, "", _on(state, "sensors")),
		item("Graticule", {"kind": "layer", "name": "graticule"}, false, "", _on(state, "graticule")),
		item("Radar coverage  [Ctrl+W]", {"kind": "palette", "id": "radar_coverage"}, false, "", _on(state, "radar_coverage")),
		item("Symbol key  [F2]", {"kind": "layer", "name": "key"}, false, "", _on(state, "key")),
	]
	return [
		submenu("Symbols", symbols),
		submenu("Symbol controls", controls),
		submenu("Map", overlays),
		item("Range circle  [B]", {"kind": "palette", "id": "range_circle"}),
		sep(),
		item("Status boards  [A]", {"kind": "board", "board": StatusBoards.BOARD_ORDERS}),
		item("Air operations  [F3]", {"kind": "palette", "id": "air_operations"}),
		item("Orders and briefing  [F1]", {"kind": "palette", "id": "briefing"}),
		item("Reference  [F7]", {"kind": "palette", "id": "library"}),
		item("Swap 2D and 3D  [G]", {"kind": "palette", "id": "swap_views"}),
		item("3D full screen  [F10]", {"kind": "palette", "id": "world_full"}),
		sep(),
		item("Missions  [M]", {"kind": "palette", "id": "missions"}),
		item("Restart mission  [Ctrl+F10]", {"kind": "palette", "id": "restart"}),
		item("Actions...  [Ctrl+K]", {"kind": "palette", "id": "actions"}),
		item("Key commands  [H]", {"kind": "palette", "id": "key_commands"}),
	]


static func _on(state: Dictionary, key: String) -> int:
	if not state.has(key):
		return -1
	return 1 if bool(state[key]) else 0


# --- Popups -------------------------------------------------------------------------------

## Opens a menu of `items` at `screen_pos` (viewport coordinates).
func open(items: Array, screen_pos: Vector2) -> void:
	close()
	_actions.clear()
	_root = _build(items)
	_root.theme = theme_source
	add_child(_root)
	_root.reset_size()
	# Keep the whole menu on screen, like a desktop context menu near an edge.
	var room := get_viewport().get_visible_rect().size
	var at := screen_pos
	at.x = minf(at.x, room.x - float(_root.size.x))
	at.y = minf(at.y, room.y - float(_root.size.y))
	_root.position = Vector2i(maxf(at.x, 0.0), maxf(at.y, 0.0))
	_root.popup_hide.connect(func() -> void: menu_closed.emit())
	_root.popup()


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null


func is_open() -> bool:
	return _root != null and is_instance_valid(_root) and _root.visible


func _build(items: Array) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.theme_type_variation = "CdsMenu"
	var table := {}
	for i in items.size():
		var it: Dictionary = items[i]
		if it.get("separator", false):
			menu.add_separator()
			continue
		var text := str(it.get("text", ""))
		if it.has("children"):
			var child := _build(it["children"])
			menu.add_submenu_node_item(text, child, i)
		elif int(it.get("checked", -1)) >= 0:
			menu.add_check_item(text, i)
			menu.set_item_checked(menu.get_item_index(i), int(it["checked"]) == 1)
		else:
			menu.add_item(text, i)
		var index := menu.get_item_index(i)
		menu.set_item_disabled(index, bool(it.get("disabled", false)))
		if str(it.get("tooltip", "")) != "":
			menu.set_item_tooltip(index, str(it["tooltip"]))
		if it.has("action"):
			table[i] = it["action"]
	_actions[menu.get_instance_id()] = table
	menu.id_pressed.connect(func(id: int) -> void: _choose(menu, id))
	return menu


func _choose(menu: PopupMenu, id: int) -> void:
	var table: Dictionary = _actions.get(menu.get_instance_id(), {})
	if not table.has(id):
		return
	var action: Dictionary = table[id]
	close()
	action_chosen.emit(action)
