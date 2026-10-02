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
## Action kinds: order, unit_orders, formation, engage, attack, investigate, palette, hook,
## waypoint_delete, layer, symbols, board, inspect, group_attack.

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
	var tasks: Array = []
	var navigation: Array = []
	var view: Array = []
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
		items.append(item("Cancel queued fire for this contact", order_action(Order.cancel_fire(target)), false, "Refund unfired rounds for this contact and end any standing attack on it. Weapons already away continue."))
	if movable:
		var speeds: Array = [item("Stop", order_action(Order.stop()))]
		for kn in SPEEDS_KN:
			speeds.append(item("%d knots" % int(kn), order_action(Order.set_speed(kn))))
		speeds.append(item("Flank", order_action(Order.set_speed(999.0))))
		navigation.append(submenu("Speed", speeds))
		navigation.append(item("Course...", {"kind": "board", "board": StatusBoards.BOARD_ORDERS, "tab": 0}, false, "Set an exact course on the orders board."))
	if not aircraft.is_empty():
		var alts: Array = []
		for a in ALTITUDES:
			alts.append(item(a[0], {"kind": "altitude", "metres": a[1]}))
		navigation.append(submenu("Altitude", alts, not controllable, why))
	if not diving.is_empty():
		var depths: Array = []
		var under := -1.0
		var floor_m := -1.0
		for u: Unit in diving:
			var d := Acoustics.below_layer_depth_m(u, true)
			if d > under:
				under = d
				floor_m = Acoustics.bottom_m(u, true)
			elif floor_m < 0.0:
				floor_m = Acoustics.bottom_m(u, true)
		for d in DEPTHS:
			var blocked: bool = d[1] == -2.0 and under < 0.0
			depths.append(item(d[0], {"kind": "depth", "metres": d[1]}, blocked, under_layer_reason(under, floor_m) if d[1] == -2.0 else ""))
		navigation.append(submenu("Depth", depths, not controllable, why))
	var sensors: Array = []
	if any_radar:
		sensors.append(item("Radar on", order_action(Order.activate_radar())))
		sensors.append(item("Radar off", order_action(Order.silence_radar())))
	if any_sonar:
		sensors.append(item("Sonar passive", order_action(Order.passive_sonar())))
		sensors.append(item("Sonar active", order_action(Order.active_sonar())))
	var dip_units := units.filter(func(u: Unit) -> bool: return DippingSonar.capable(u))
	if not dip_units.is_empty():
		var can_deploy := dip_units.any(func(u: Unit) -> bool: return DippingSonar.rejection(u) == "")
		var can_recover := dip_units.any(func(u: Unit) -> bool: return UnitManager.can_accept_order(u, Order.recover_dipping_sonar()))
		sensors.append(item("Deploy dipping sonar", order_action(Order.deploy_dipping_sonar()), not can_deploy, "Hover, lower the array, then listen. New navigation orders raise it first." if can_deploy else DippingSonar.rejection(dip_units[0])))
		sensors.append(item("Raise dipping sonar", order_action(Order.recover_dipping_sonar()), not can_recover, "Raise the array, then resume the current route or station."))
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
	if movable:
		tasks.append(item("Plot route  [W]", {"kind": "palette", "id": "plot_move"}))
		tasks.append(item("Assign patrol area  [Shift+W]", {"kind": "palette", "id": "plot_patrol"}, false, "Click two corners; repeat the circuit until retasked or returning for fuel."))
	var stationed := units.filter(func(u: Unit) -> bool: return u.has_station())
	if movable and not stationed.is_empty():
		var can_return := stationed.filter(func(u: Unit) -> bool: return UnitManager.station_rejection(u) == "")
		var reason := "" if not can_return.is_empty() else UnitManager.station_rejection(stationed[0])
		tasks.append(item("Return to station  [S]", order_action(Order.return_to_station()), can_return.is_empty(), reason if reason != "" else "Resume the patrol, screen or air station an investigation, attack or refuelling interrupted."))
	if any_deck:
		tasks.append(item("Flight deck...", {"kind": "palette", "id": "air_operations"}, false, "Launch aircraft, or choose where an aircraft lands."))
	if ships.size() >= 2:
		var forms: Array = []
		for pattern in ["screen", "column", "abreast"]:
			forms.append(item(pattern.capitalize(), {"kind": "formation", "pattern": pattern}))
		forms.append(item("Break", order_action(Order.break_formation())))
		tasks.append(submenu("Formation", forms, not controllable, why))
	elif ships.size() == 1 and (ships[0] as Unit).in_formation():
		tasks.append(item("Break formation", order_action(Order.break_formation()), not controllable, why))
	if movable:
		navigation.append(submenu("Auto-return to station", [
			item("On", order_action(Order.set_auto_return(true)), false, "Go back to station once an identification, interception or attack ends. A newer order always stands.", _all(units, func(u: Unit) -> bool: return u.auto_return)),
			item("Off", order_action(Order.set_auto_return(false)), false, "Hold where the task ends until ordered back with S.", _all(units, func(u: Unit) -> bool: return not u.auto_return)),
		], not controllable, why))
	if any_route:
		navigation.append(item("Clear route", order_action(Order.clear_waypoints()), not controllable, why))
	view.append(item("Follow  [F]", {"kind": "palette", "id": "follow_selection"}))
	view.append(item("Centre  [C]", {"kind": "palette", "id": "focus_selection"}))
	if units.size() == 1:
		view.append(item("Reference  [F7]", {"kind": "inspect", "id": (units[0] as Unit).spec.id}))
	view.append(item("Status boards  [A]", {"kind": "board", "board": StatusBoards.BOARD_ORDERS}))
	view.append(item("Fleet operations  [J]", {"kind": "palette", "id": "fleet_operations"}))
	if units.is_empty():
		return [item("Hook a platform to give orders", {}, true), view[-2], view[-1]]
	if not tasks.is_empty():
		tasks.append(sep())
	if not navigation.is_empty():
		tasks.append(submenu("Navigation", navigation))
	tasks.append_array(items)
	tasks.append(sep())
	tasks.append(submenu("View & status", view))
	return tasks


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
	var why := ""
	for u: Unit in units:
		why = AirDefence.intercept_rejection(u)
		if why == "":
			break
	items.append(item("Engage inbound weapons  [X]", order_action(Order.intercept()), why != "",
		why if why != "" else "Fire interceptors at every inbound round the hooked ships hold. With manual missile defence, the SAMs fire only on this order."))
	return items


## A detected inbound weapon under the cursor: intercept it with the hooked ships, or turn away.
static func weapon_items(w: Weapon, units: Array, controllable: bool, movable: bool) -> Array:
	var why := "Hook your ships first" if not controllable else ""
	if why == "":
		why = "No hooked ship can engage it"
		for u: Unit in units:
			if AirDefence.intercept_rejection(u) == "":
				why = ""
				break
	return [
		{"text": "Inbound #%d  %s" % [w.id, w.spec.display_name], "disabled": true},
		item("Engage with interceptors  [X]", order_action(Order.intercept(w)), why != "", why if why != "" else "Fire interceptors at this round from the hooked ships, within their channels and magazines."),
		item("Evade  [V]", order_action(Order.evade()), not movable, "Turn the hooked ships to open the round's approach; the route resumes after."),
		item("Defence commands", {"kind": "palette", "id": "open_defence"}, not controllable),
	]


## The gameplay options, as a menu: the two presets and the options one at a time. Shared by the
## command bar's chip and the CDS menu. `state["options"]` is the GameOptions in effect (Main's
## _cds_state); voice and ambient are checked as heard, like the Sound submenu.
static func options_items(state: Dictionary) -> Array:
	var o: GameOptions = state["options"] if state.get("options") is GameOptions else GameOptions.normal(bool(state.get("voice", false)), bool(state.get("ambient", true)))
	var preset := o.preset()
	var items: Array = [
		item("Normal", {"kind": "palette", "id": "preset_normal"}, false, GameOptions.preset_description(GameOptions.NORMAL) + ".", 1 if preset == GameOptions.NORMAL else 0),
		item("Classic", {"kind": "palette", "id": "preset_classic"}, false, GameOptions.preset_description(GameOptions.CLASSIC) + ".", 1 if preset == GameOptions.CLASSIC else 0),
		sep(),
	]
	for key: String in GameOptions.OPTION_KEYS:
		if key == "":
			items.append(sep())
			continue
		var sound := key in ["voice", "ambient"]
		var on := bool(state.get(key, o.option_on(key))) if sound else o.option_on(key)
		items.append(item(GameOptions.option_text(key), {"kind": "palette", "id": key if sound else "option_" + key}, false, GameOptions.option_tooltip(key), 1 if on else 0))
	items.append(sep())
	for percent: int in InterfaceScale.PERCENTAGES:
		items.append(item("Interface size: %d%%" % percent, {"kind": "palette", "id": "ui_scale_%d" % percent}, false, "Scale text, chart labels and controls together.", 1 if InterfaceScale.percent == percent else 0))
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


## A routine engagement is one visible choice. Use the same envelope, guidance and channel
## checks as the firing board; issue ordinary finite orders to only the ready selected shooters.
## Detailed weapon/salvo choices remain in Engage with and the firing board.
static func quick_engage_item(units: Array, target: Track, weapon_manager: WeaponManager = null) -> Dictionary:
	if units.is_empty():
		return item("Select a platform to engage", {}, true)
	if target == null:
		return item("Select a contact to engage", {}, true)
	var weapons: Array[WeaponSpec] = []
	var seen := {}
	for u: Unit in units:
		for spec: WeaponSpec in u.weapons:
			if Combat.suits_track(spec, target) and not seen.has(spec.id):
				weapons.append(spec)
				seen[spec.id] = true
	weapons.sort_custom(func(a: WeaponSpec, b: WeaponSpec) -> bool:
		if a.is_gun() != b.is_gun():
			return b.is_gun()
		if not is_equal_approx(a.max_range_nm, b.max_range_nm):
			return a.max_range_nm > b.max_range_nm
		return a.id < b.id)
	var reason := "Identify contact first" if target.domain == "" else "No suitable weapon aboard"
	var have_reason := false
	for spec: WeaponSpec in weapons:
		var pairs: Array = []
		var total := 0
		var details := PackedStringArray()
		for u: Unit in units:
			if u.get_weapon(spec.id) == null:
				continue
			var check := weapon_manager.engagement_check(u, spec, target, weapon_manager.now_s) if weapon_manager != null else Combat.check_engagement(u, spec, target)
			if not bool(check["ok"]):
				if not have_reason:
					reason = str(check["reason"]).capitalize()
					have_reason = true
				continue
			var rounds := mini(maxi(spec.salvo_default, 1), u.magazine_count(spec.id))
			pairs.append([u, Order.engage(target, spec.id, rounds)])
			total += rounds
			details.append("%s: %d round%s" % [u.callsign, rounds, "" if rounds == 1 else "s"])
		if not pairs.is_empty():
			var label := "Fire %d × %s" % [total, spec.compact_name()]
			if units.size() > 1:
				label += " from %d platform%s" % [pairs.size(), "" if pairs.size() == 1 else "s"]
			return item(label, {"kind": "unit_orders", "pairs": pairs}, false,
				"Track %s. %s. Other weapons and quantities: Engage with." % [DataDisplay.track_number_for_track(target), "; ".join(details)])
	return item("Cannot engage: " + reason, {}, true, reason)


## Several armed platforms hooked: one round budget they share on this contact. It opens the firing
## board set for the group, so the allocation can be read before it is committed. N is one ordinary
## salvo from each platform that can fire now. Empty with fewer than two armed platforms hooked.
static func group_attack_item(units: Array, target: Track, weapon_manager: WeaponManager = null) -> Dictionary:
	var shooters := units.filter(func(u: Unit) -> bool: return u.is_engageable() and not u.weapons.is_empty())
	if shooters.size() < 2 or target == null:
		return {}
	var rounds := GroupAttackManager.default_budget(shooters, target, weapon_manager)
	if rounds <= 0:
		return item("Group attack...", {}, true, "No hooked platform holds a solution on track %s" % DataDisplay.track_number_for_track(target))
	return item("Group attack (%d rounds)..." % rounds, {"kind": "group_attack", "track": target, "budget": rounds}, false,
		"Share %d rounds between the %d hooked platforms: each goes to the shooter that can put it on track %s first, and the group assesses each volley before it spends more." % [rounds, shooters.size(), DataDisplay.track_number_for_track(target)])


## The standing attack, the classic display's one-click engagement: the hooked platforms close
## to range, choose the weapon and keep firing. Greyed with the reason when none of them can.
static func attack_item(units: Array, target: Track) -> Dictionary:
	var number := DataDisplay.track_number_for_track(target)
	var reason := ""
	var able := 0
	for u: Unit in units:
		var rejection := UnitManager.attack_rejection(u, target)
		if rejection == "":
			able += 1
		elif reason == "":
			reason = rejection
	if able == 0:
		return item("Attack track %s" % number, {}, true, reason if reason != "" else "Select a platform to attack with")
	var who := "" if units.size() == 1 else " with %d of %d platforms" % [able, units.size()]
	return item("Attack track %s%s" % [number, who], {"kind": "attack", "track": target}, false,
		"Close to weapon range, fire the best weapon aboard and keep firing until the contact is destroyed or lost. A bare right-click on a hostile does the same.")


## Attack with a chosen weapon: the same standing task, holding that weapon's envelope.
static func attack_with_items(units: Array, target: Track) -> Array:
	var items: Array = []
	var seen := {}
	for u: Unit in units:
		for spec: WeaponSpec in u.weapons_for_track(target):
			if seen.has(spec.id):
				continue
			seen[spec.id] = true
			var able := 0
			var reason := ""
			for v: Unit in units:
				if v.get_weapon(spec.id) == null:
					continue
				var rejection := UnitManager.attack_rejection(v, target, spec.id)
				if rejection == "":
					able += 1
				elif reason == "":
					reason = rejection
			items.append(item(spec.display_name, {"kind": "attack", "track": target, "weapon": spec.id}, able == 0, reason if able == 0 else "Close inside %s range and keep firing it until the contact is destroyed or lost." % spec.compact_name()))
	return items


## Right-click on a contact.
static func engage_items(units: Array, target: Track, controllable: bool, weapon_manager: WeaponManager = null) -> Array:
	var items: Array = []
	var number := DataDisplay.track_number_for_track(target)
	items.append({"text": "Track %s  %s" % [number, target.description().capitalize()], "disabled": true})
	if controllable and not units.is_empty():
		# A hostile still leads with Attack, even before its exact class is established.
		if target.identity == "HOSTILE":
			items.append(attack_item(units, target))
		if target.classification < Track.Classification.CLASS_KNOWN:
			var can_investigate := false
			var reason := ""
			for u: Unit in units:
				var rejection := UnitManager.investigation_rejection(u, target)
				can_investigate = can_investigate or rejection == ""
				if reason == "" and rejection != "":
					reason = rejection
			items.append(item("Investigate contact", {"kind": "investigate", "track": target}, not can_investigate,
				"Follow the held contact until its class is identified. Weapons remain under your control." if can_investigate else reason))
		if target.identity != "HOSTILE":
			items.append(attack_item(units, target))
		var weapon_choices: Array = []
		var with_weapons := attack_with_items(units, target)
		if not with_weapons.is_empty():
			weapon_choices.append(submenu("Attack with", with_weapons, false, "The standing attack, holding a chosen weapon's envelope."))
		var quick := quick_engage_item(units, target, weapon_manager)
		if not bool(quick.get("disabled", false)):
			items.append(quick)
		else:
			weapon_choices.append(quick)
		var group := group_attack_item(units, target, weapon_manager)
		if not group.is_empty():
			items.append(group)
		weapon_choices.append(item("Weapon control...  [Shift+E]", {"kind": "palette", "id": "weapon_control"}))
		weapon_choices.append(submenu("Engage with", engage_weapon_items(units, target, weapon_manager), false, "Weapons that suit this contact."))
		weapon_choices.append(item("Cancel queued fire for this contact", order_action(Order.cancel_fire(target)), false, "Refund unfired rounds for this contact and end any standing attack on it. Weapons already away continue."))
		items.append(submenu("Weapon selection", weapon_choices, false, "Choose a weapon for a standing attack or a finite salvo; inspect firing limits and cancel queued fire."))
		if target.domain in ["surface", "land"] and not target.identity in ["NEUTRAL", "FRIENDLY"]:
			items.append(item("Air strike...", {"kind": "air_strike", "track": target}, false, "Open Air Operations set to strike this contact from a deck."))

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
	var sound: Array = [
		item("Sound  [Ctrl+M]", {"kind": "palette", "id": "sound"}, false, "", _on(state, "sound")),
		item("Crew voice", {"kind": "palette", "id": "voice"}, false, "", _on(state, "voice")),
		item("Ambient sea and machinery", {"kind": "palette", "id": "ambient"}, false, "", _on(state, "ambient")),
	]
	return [
		submenu("Symbols", symbols),
		submenu("Symbol controls", controls),
		submenu("Map", overlays),
		submenu("Sound", sound),
		submenu("Gameplay", options_items(state)),
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
