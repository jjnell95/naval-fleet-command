class_name AIPlan
extends RefCounted
## An opposing force's mission: what a group of enemy units is trying to achieve, as the scenario
## author wrote it, and how far its commander has got. AIController steps every plan once per
## decision cycle, before any unit decides, and each member then acts on its part of it. A plan
## knows nothing the faction's own track picture does not hold: it searches where it expects the
## carrier to be, it waits for its scouts to say what a contact is, and it can be wrong.
##
## Plans are opt-in. A scenario without "ai_plans" plays exactly as before.
##
## Scenario schema: a top-level "ai_plans" array of objects. Only id, faction and kind are required.
##   "id": "raid"                     unique text; a unit joins with a unit-level "ai_plan": "raid"
##   "faction": "RED"                 the side that runs it
##   "kind": "threaten_carrier"       protect_breakout | attack_shipping | threaten_carrier |
##                                    defend_installation
##   "units": ["Slava", "Badger 1"]   callsigns in the plan from the start (scenario units and
##                                    reinforcements). A deck or airfield listed brings its air wing,
##                                    and the plan then decides its launches; one element of a wing
##                                    joins by an "ai_plan" tag on its air-wing entry instead
##   "priorities": ["carrier", ...]   target words, most wanted first, matched against what a track
##                                    reports once it is classified (Track.known_category and
##                                    known_class). Until then a contact is only a contact. Defaults
##                                    by kind: see DEFAULT_PRIORITIES
##   "objective_nm": [x, y]           where the plan is about: the area the carrier or the convoy is
##                                    expected in, the installation to defend. An expectation, never
##                                    a fix: the plan still has to find what is there
##   "area_radius_nm": 40             the search area round the objective; for defend_installation the
##                                    defended area, whatever enters it is engaged
##   "protect": ["Admiral Gorshkov"]  protect_breakout: the units breaking out (their own route is the
##                                    axis). defend_installation: the installations; the first one's
##                                    position is the objective when none is given
##   "recon": ["Admiral Vinogradov", {"base": "Khmeimim Air Base", "platform": "rfn_mpa_il38n", "count": 1}]
##                                    scouts: own units by callsign, which close on contacts to
##                                    classify them (aircraft are launched to do it), or an air
##                                    reconnaissance mission over the objective flown from a deck
##   "assembly_nm": [x, y]            where strikers gather once the target is found
##   "assembly_window_s": 900         the longest the strike waits, at the assembly point for the
##                                    package and then on its axes for shooters to be in position
##   "package": 3                     shooters that must be ready before weapons are free (0: all)
##   "axes_deg": [-40, 0, 40]         attack bearings relative to the line from the target back to the
##                                    strike's own side; or "spread_deg": 90 spreads them evenly
##   "salvo": 4                       rounds per shooter per salvo (0: the AI's usual salvo)
##   "budget": 12                     rounds the side may have on the way to one plan target, flying
##                                    and queued, before it stops to assess
##   "assess_s": 300                  the shared pause after a volley before anyone fires at it again
##   "threat_nm": 15                  a contact outside the plan's targets is engaged only when it
##                                    comes this close to a member
##   "screen_nm": 8                   protect_breakout: escorts' distance from the protected unit
##   "engage_within_nm": 30           protect_breakout: escorts engage contacts this close to it
##   "leash_nm": 50                   defend_installation: defenders never go further from it
##   "start_s": 0                     the plan takes effect at this mission time
## Unit-level keys, on a unit, an air-wing entry or a reinforcement: "ai_plan" (a plan id) and
## "ai_role" (strike | recon | escort | defender | protected | installation) when the kind's default
## role is not the one wanted.

enum Kind { PROTECT_BREAKOUT, ATTACK_SHIPPING, THREATEN_CARRIER, DEFEND_INSTALLATION }
enum Phase { WAITING, RECON, ASSEMBLE, ATTACK, SCREEN, DEFEND }

const KIND_NAMES := ["protect_breakout", "attack_shipping", "threaten_carrier", "defend_installation"]
const PHASE_NAMES := ["WAITING", "RECON", "ASSEMBLE", "ATTACK", "SCREEN", "DEFEND"]
const ROLES := ["strike", "recon", "escort", "defender", "protected", "installation"]
## Members the plan exists for rather than members it steers: a ship breaking out keeps its own
## breakout posture and an installation keeps its own fire. Their decks still launch for the plan.
const SELF_DIRECTED_ROLES := ["protected", "installation"]
const DEFAULT_PRIORITIES := {
	"protect_breakout": [],
	"attack_shipping": ["merchant", "tanker", "replenishment", "auxiliary", "amphibious"],
	"threaten_carrier": ["carrier", "amphibious"],
	"defend_installation": [],
}
const NUMBER_KEYS := ["area_radius_nm", "assembly_window_s", "package", "spread_deg", "salvo", "budget", "assess_s", "threat_nm", "screen_nm", "engage_within_nm", "leash_nm", "start_s"]

## The defaults below are GAMEPLAY_ESTIMATE values: tuned for play, not doctrine.
const DEFAULT_AREA_RADIUS_NM := 40.0
const DEFAULT_ASSEMBLY_WINDOW_S := 900.0
const DEFAULT_SPREAD_DEG := 90.0
const DEFAULT_BUDGET := 12
const DEFAULT_ASSESS_S := 300.0
const DEFAULT_THREAT_NM := 15.0
const DEFAULT_SCREEN_NM := 8.0
const DEFAULT_ENGAGE_WITHIN_NM := 30.0
## Other members may join a volley this long after its first salvo; after that the plan waits for
## the assessment before anyone fires at that contact again. GAMEPLAY_ESTIMATE.
const VOLLEY_S := 60.0
## Escort stations round the protected unit, relative to its heading: the van first, then the bows,
## the wake and the quarters. GAMEPLAY_ESTIMATE.
const SCREEN_AXES_DEG: Array[float] = [0.0, -60.0, 60.0, 180.0, -120.0, 120.0]
const UNSET_TIME := -1.0e9

# --- As authored (not changed in play) ------------------------------------------------------
var id := ""
var faction := ""
var kind: Kind = Kind.THREATEN_CARRIER
var unit_callsigns := PackedStringArray()
var priorities := PackedStringArray()
var objective := Vector2.INF
var area_radius_nm := DEFAULT_AREA_RADIUS_NM
var protect_callsigns := PackedStringArray()
var recon_callsigns := PackedStringArray()
## Air reconnaissance missions to request: {base: callsign, platform: id, count: int}.
var recon_air: Array[Dictionary] = []
var assembly := Vector2.INF
var assembly_window_s := DEFAULT_ASSEMBLY_WINDOW_S
var package := 0
var axes_deg: Array[float] = []
var spread_deg := DEFAULT_SPREAD_DEG
var salvo := 0
var budget := DEFAULT_BUDGET
var assess_s := DEFAULT_ASSESS_S
var threat_nm := DEFAULT_THREAT_NM
var screen_nm := DEFAULT_SCREEN_NM
var engage_within_nm := DEFAULT_ENGAGE_WITHIN_NM
var leash_nm := 0.0
var start_s := 0.0

# --- Commander's state (changes in play; plain data, units by object and by Unit.id) ----------
var phase: Phase = Phase.WAITING
var phase_since := 0.0
var members: Array[Unit] = []  # adoption order, which is unit-list order
var member_ids: Array[int] = []  # Unit.id of each member, same order
var roles: Dictionary = {}  # Unit.id -> role
## The contact the strike is for: the object in the faction picture and its track id.
var target: Track
var target_track_id := ""
## When the present target was taken on, for the weapons-free window.
var window_since := 0.0
var weapons_free := false
## Bearing from the target back toward the strike's own side, fixed when a target is taken on.
var base_axis_deg := 0.0
var axes: Dictionary = {}  # Unit.id -> attack bearing from the target (strike) or screen offset
var goals: Dictionary = {}  # Unit.id -> where the plan last wanted that unit
## Where defenders are anchored this cycle: the objective, or the installation's own position.
var anchor := Vector2.INF
## The strike's own side of the target, which attack bearings are measured from: the authored
## assembly point, or where the strike stood when the plan first ran.
var own_side := Vector2.INF
var volley_until: Dictionary = {}  # track id -> end of the open volley
var assess_until: Dictionary = {}  # track id -> end of the shared assessment pause
var recon_requested: Array[float] = []  # per recon_air entry: when last requested, or UNSET_TIME
var salvos := 0


static func kind_from_name(name: String) -> int:
	return KIND_NAMES.find(name)


func kind_name() -> String:
	return KIND_NAMES[kind]


func phase_name() -> String:
	return PHASE_NAMES[phase]


func is_strike_kind() -> bool:
	return kind == Kind.ATTACK_SHIPPING or kind == Kind.THREATEN_CARRIER


## Before its start time a plan is only a record; its members fight as they would without it.
func running() -> bool:
	return phase != Phase.WAITING


func set_phase(next: Phase, now: float) -> void:
	if next != phase:
		phase = next
		phase_since = now


# --- Parsing ------------------------------------------------------------------------------------

## Every well-formed plan for `faction`. A malformed entry is reported and left out rather than
## allowed to stop the scenario loading: a mistake in a plan should cost the plan, not the mission.
static func parse_all(defs, for_faction: String) -> Array[AIPlan]:
	var out: Array[AIPlan] = []
	if typeof(defs) != TYPE_ARRAY:
		push_warning("AIPlan: ai_plans must be an array")
		return out
	var seen: Dictionary = {}
	for d in defs:
		var p := from_definition(d)
		if p == null:
			continue
		if seen.has(p.id):
			push_warning("AIPlan: duplicate plan id '%s' ignored" % p.id)
			continue
		seen[p.id] = true
		if p.faction == for_faction:
			out.append(p)
	return out


## One plan from its scenario entry, or null with a warning when it cannot be used.
static func from_definition(d) -> AIPlan:
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("AIPlan: every plan must be an object")
		return null
	var problem := definition_problem(d)
	if problem != "":
		push_warning("AIPlan: %s; plan ignored" % problem)
		return null
	var p := AIPlan.new()
	p.id = str(d["id"])
	p.faction = str(d["faction"])
	p.kind = kind_from_name(str(d["kind"])) as Kind
	p.unit_callsigns = PackedStringArray(d.get("units", []))
	var words: Array = d.get("priorities", DEFAULT_PRIORITIES[p.kind_name()])
	for w in words:
		p.priorities.append(str(w).strip_edges().to_lower())
	if d.has("objective_nm"):
		p.objective = Vector2(float(d["objective_nm"][0]), float(d["objective_nm"][1]))
	if d.has("assembly_nm"):
		p.assembly = Vector2(float(d["assembly_nm"][0]), float(d["assembly_nm"][1]))
	p.protect_callsigns = PackedStringArray(d.get("protect", []))
	for entry in d.get("recon", []):
		if typeof(entry) == TYPE_STRING:
			p.recon_callsigns.append(entry)
		else:
			p.recon_air.append({"base": str(entry["base"]), "platform": str(entry["platform"]), "count": maxi(int(entry.get("count", 1)), 1)})
			p.recon_requested.append(UNSET_TIME)
	p.area_radius_nm = maxf(float(d.get("area_radius_nm", DEFAULT_AREA_RADIUS_NM)), 1.0)
	p.assembly_window_s = float(d.get("assembly_window_s", DEFAULT_ASSEMBLY_WINDOW_S))
	p.package = int(d.get("package", 0))
	for a in d.get("axes_deg", []):
		p.axes_deg.append(float(a))
	p.spread_deg = clampf(float(d.get("spread_deg", DEFAULT_SPREAD_DEG)), 0.0, 360.0)
	p.salvo = int(d.get("salvo", 0))
	p.budget = maxi(int(d.get("budget", DEFAULT_BUDGET)), 1)
	# The pause cannot end before the volley it follows has closed.
	p.assess_s = maxf(float(d.get("assess_s", DEFAULT_ASSESS_S)), VOLLEY_S)
	p.threat_nm = float(d.get("threat_nm", DEFAULT_THREAT_NM))
	p.screen_nm = maxf(float(d.get("screen_nm", DEFAULT_SCREEN_NM)), 1.0)
	p.engage_within_nm = float(d.get("engage_within_nm", DEFAULT_ENGAGE_WITHIN_NM))
	# A defender may go a little beyond the edge of what it defends to meet what is crossing it.
	p.leash_nm = maxf(float(d.get("leash_nm", p.area_radius_nm * 1.25)), 1.0)
	p.start_s = float(d.get("start_s", 0.0))
	return p


## Why an entry cannot be a plan, or "". Shared with ScenarioWorkshop, which reports it to the
## author; the loader only warns and skips.
static func definition_problem(d: Dictionary) -> String:
	for key: String in ["id", "faction", "kind"]:
		if typeof(d.get(key)) != TYPE_STRING or str(d.get(key)).strip_edges() == "":
			return "An AI plan needs text for %s" % key
	if kind_from_name(str(d["kind"])) < 0:
		return "AI plan %s has unknown kind '%s'" % [d["id"], d["kind"]]
	for key: String in ["units", "priorities", "protect"]:
		if typeof(d.get(key, [])) != TYPE_ARRAY:
			return "AI plan %s: %s must be an array" % [d["id"], key]
		for entry in d.get(key, []):
			if typeof(entry) != TYPE_STRING:
				return "AI plan %s: %s entries must be text" % [d["id"], key]
	if typeof(d.get("recon", [])) != TYPE_ARRAY:
		return "AI plan %s: recon must be an array" % d["id"]
	for entry in d.get("recon", []):
		if typeof(entry) == TYPE_STRING:
			continue
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("base")) != TYPE_STRING or typeof(entry.get("platform")) != TYPE_STRING:
			return "AI plan %s: a recon entry is a callsign or {base, platform, count}" % d["id"]
		if entry.has("count") and (not _number(entry["count"]) or float(entry["count"]) < 1):
			return "AI plan %s: a recon count must be at least 1" % d["id"]
	for key: String in ["objective_nm", "assembly_nm"]:
		if d.has(key) and not _pair(d[key]):
			return "AI plan %s: %s needs two finite numbers" % [d["id"], key]
	for key: String in NUMBER_KEYS:
		if d.has(key) and (not _number(d[key]) or float(d[key]) < 0):
			return "AI plan %s: %s needs a non-negative finite number" % [d["id"], key]
	if typeof(d.get("axes_deg", [])) != TYPE_ARRAY:
		return "AI plan %s: axes_deg must be an array" % d["id"]
	for a in d.get("axes_deg", []):
		if not _number(a):
			return "AI plan %s: axes_deg needs finite numbers" % d["id"]
	return ""


static func _number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _pair(value) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 2 and _number(value[0]) and _number(value[1])


# --- Membership ---------------------------------------------------------------------------------

## The role `u` would have in this plan, or "" when it does not belong. A unit tagged for another
## plan never joins this one. An aircraft joins with the deck it calls home.
func role_for(u: Unit) -> String:
	if u.faction != faction or (u.ai_plan_id != "" and u.ai_plan_id != id):
		return ""
	var listed := u.ai_plan_id == id or unit_callsigns.has(u.callsign) or protect_callsigns.has(u.callsign) or recon_callsigns.has(u.callsign)
	var via_base := u.is_aircraft() and u.home != null and has_member(u.home)
	if not listed and not via_base:
		return ""
	if ROLES.has(u.ai_role):
		return u.ai_role
	if protect_callsigns.has(u.callsign):
		return "protected" if kind == Kind.PROTECT_BREAKOUT else "installation"
	if recon_callsigns.has(u.callsign) or (via_base and u.is_sensor_aircraft()):
		return "recon"
	match kind:
		Kind.PROTECT_BREAKOUT:
			return "escort"
		Kind.DEFEND_INSTALLATION:
			return "defender"
	return "strike"


func add_member(u: Unit, role: String) -> void:
	if roles.has(u.id):
		return
	members.append(u)
	member_ids.append(u.id)
	roles[u.id] = role


func has_member(u: Unit) -> bool:
	return u != null and roles.has(u.id)


func role_of(u: Unit) -> String:
	return str(roles.get(u.id, ""))


func members_in(role: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in members:
		if u.alive and role_of(u) == role:
			out.append(u)
	return out


## The protected unit an escort keeps station on: the first one still afloat.
func guard() -> Unit:
	for u in members:
		if u.alive and role_of(u) == "protected":
			return u
	return null


## Whether a position is within `radius_nm` of any unit the plan protects (own units, own truth).
func near_protected(pos: Vector2, radius_nm: float) -> bool:
	for u in members:
		if u.alive and role_of(u) == "protected" and u.position.distance_to(pos) <= radius_nm:
			return true
	return false


# --- What the plan wants hit --------------------------------------------------------------------

## Where a contact stands in the plan's priorities: 0 for the first word, -1 for none of them. Only
## a classified contact has a category to match, and only the category its track reports. An empty
## priority list takes any classified contact.
func priority_rank(t: Track) -> int:
	if t == null or t.classification < Track.Classification.CLASS_KNOWN:
		return -1
	if priorities.is_empty():
		return 0
	var category := t.known_category.to_lower()
	var cls := t.known_class.to_lower()
	for i in priorities.size():
		var word := priorities[i]
		if word != "" and (category.contains(word) or cls.contains(word)):
			return i
	return -1


## The attack bearing offset for the i-th of n shooters: the authored axes in turn, else n bearings
## spread evenly across `spread_deg` and centred on the strike's own side.
func axis_offset(i: int, n: int) -> float:
	if not axes_deg.is_empty():
		return axes_deg[i % axes_deg.size()]
	if n <= 1:
		return 0.0
	return -spread_deg * 0.5 + spread_deg * float(i) / float(n - 1)


# --- The shared volley and assessment -----------------------------------------------------------

## A member's salvo at a contact: it opens a volley the others may join for VOLLEY_S, after which the
## whole plan waits for the assessment before firing at that contact again.
func note_salvo(track_id: String, flight_s: float, now: float) -> void:
	salvos += 1
	var settle := now + maxf(assess_s, 1.5 * flight_s)
	if now < float(volley_until.get(track_id, UNSET_TIME)):
		assess_until[track_id] = maxf(float(assess_until.get(track_id, UNSET_TIME)), settle)
		return
	volley_until[track_id] = now + VOLLEY_S
	assess_until[track_id] = settle


## True while the plan is waiting to see what its last volley at this contact did.
func assessing(track_id: String, now: float) -> bool:
	return now >= float(volley_until.get(track_id, UNSET_TIME)) and now < float(assess_until.get(track_id, UNSET_TIME))
