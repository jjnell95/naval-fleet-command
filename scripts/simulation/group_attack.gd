class_name GroupAttack
extends RefCounted
## A coordinated attack: several platforms, one or more held contacts, and one round budget the
## whole group shares. The record owns no weapon and no round. GroupAttackManager decides who fires
## what, fires it through ordinary crew ENGAGE orders tagged with this id, and steps the record;
## this is what the firing board, the orders line and the radio read.
##
## Everything here is plain data in parallel arrays, indexed by member or by target, so the record
## iterates in a fixed order and saves as it stands. A Unit is kept with its Unit.id, a Track with
## its contact key (owner faction and track number), so both can be found again after a reload.

## How one contact's attack stands, for the orders line and the board.
const FIRING := "firing"
const ASSESSING := "assessing"
const AWAITING := "awaiting solution"
const HOLDING := "holding"
const DONE := "done"

var id := -1
var faction := ""
## The platform the order was given to. It answers for the group on the radio; it has no other
## authority, and the attack carries on if it is lost.
var lead: Unit
var lead_id := -1
var members: Array[Unit] = []
var member_ids: Array[int] = []
## Rounds each member has fired for the group.
var member_fired: Array[int] = []
## "" while the member is in the attack; otherwise why it left: "lost", "fire cancelled".
var member_withdrawn: Array[String] = []
## [member index, target index] pairs a CANCEL_FIRE on one contact took out of the attack.
var excluded: Array = []
## The contacts, in the order the commander gave them: the first has priority for rounds.
var targets: Array[Track] = []
var target_keys: Array[String] = []  # WeaponManager.contact_key: owner faction and track number
var target_ids: Array[String] = []
## The most rounds each contact may take in all. The shares add up to the budget at most; a contact
## that drops out hands its unspent share on to the others still under attack.
var target_share: Array[int] = []
var target_fired: Array[int] = []
## The rounds at this contact (fired plus queued) the open volley fills up to, or -1 between
## volleys. A round that leaves the queue unfired is re-offered until the volley is full.
var target_mark: Array[int] = []
## Rounds fired in the open volley. A volley that has fired and has nothing left queued or in the
## air is over, and the shared assessment starts.
var target_volley_fired: Array[int] = []
## When the shared look at this contact ends, or -1 when no assessment is running.
var target_assess_until: Array[float] = []
## "" while the contact is under attack; otherwise why no more rounds go to it.
var target_done: Array[String] = []
## Rounds the whole group may fire, queued rounds included. Never exceeded.
var budget := 0
## Rounds per contact in one volley before the shared assessment; 0 sends a contact's whole share.
var volley := 0
var fired_total := 0
## Queued rounds that went back aboard (a cancel, a hold, a lost solution) and that died with a
## lost shooter. Neither was spent on the target, so both return to the pool.
var refunded_total := 0
var lost_total := 0
var volleys_opened := 0
var active := true
var ended_reason := ""
## The last thing worth telling the commander: an allocation, a refusal, a loss.
var note := ""
var created_at_s := 0.0
## Time with nothing in the air and nothing able to fire. Past the manager's limit the attack ends
## and says why, rather than holding a budget no one can spend.
var stall_s := 0.0


func member_index(u: Unit) -> int:
	return members.find(u)


func target_index_for_key(key: String) -> int:
	return target_keys.find(key)


## Whether a member may still be given rounds against this contact.
func member_available(mi: int, ti: int) -> bool:
	if member_withdrawn[mi] != "" or not members[mi].alive:
		return false
	return not excluded.has([mi, ti])


func live_targets() -> Array[int]:
	var out: Array[int] = []
	for ti in targets.size():
		if target_done[ti] == "":
			out.append(ti)
	return out


func members_in_attack() -> int:
	var n := 0
	for mi in members.size():
		if member_withdrawn[mi] == "" and members[mi].alive:
			n += 1
	return n


## The contacts as the chart numbers them: "1077", or "1077 +2" for several.
func target_label() -> String:
	if target_ids.is_empty():
		return "?"
	var first := track_number(target_ids[0])
	return first if target_ids.size() == 1 else "%s +%d" % [first, target_ids.size() - 1]


## A track id as the chart prints it: its four-digit number. The simulation keeps its own copy of
## the chart's rule so that no model code calls into the display.
static func track_number(track_id: String) -> String:
	var digits := ""
	for i in range(track_id.length() - 1, -1, -1):
		var ch := track_id[i]
		if ch < "0" or ch > "9":
			break
		digits = ch + digits
	return track_id if digits == "" else "%04d" % int(digits.right(4))
