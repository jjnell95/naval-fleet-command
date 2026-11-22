extends TestCase
## The catalogue as a naval reader would check it: shells on the missiles' damage scale, torpedoes
## that swim at torpedo speeds and arm before their minimum range, rocket-thrown weapons that fly,
## ships that carry the sonars they are built with and sound like what they are, and sonar ranges
## long enough for an anti-submarine fight to start outside gun range.


func _weapons(type: String) -> Array:
	return DataDB.all_weapons().filter(func(w: WeaponSpec) -> bool: return w.type == type)


func _unit(platform_id: String, faction := "RED") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(platform_id)
	u.faction = faction
	u.callsign = u.spec.short_name
	u.health = u.spec.health
	u.id = 1
	return u


# --- Guns -------------------------------------------------------------------------------------

## Calibre in millimetres of every gun in the catalogue. A new gun has to be entered here, which
## is the point: its damage is then checked against its calibre.
const GUN_CALIBRE_MM := {
	"mk45_mod4_gun": 127, "cw90_mk45": 127, "a192_130mm_gun": 130, "ak130_gun": 130, "cw90_ak130": 130,
	"pla_hpj45_130mm": 130, "mk8_114mm_gun": 114, "a190_100mm_gun": 100, "ak100_gun": 100, "cw90_ak100": 100,
	"oto_76mm_gun": 76, "cw90_mk75": 76, "cw90_ak176": 76, "pla_hpj26_76mm": 76, "mk110_57mm_gun": 57,
}


func test_gun_damage_is_on_the_missile_scale_by_calibre() -> void:
	var guns := _weapons("gun")
	assert_true(guns.size() >= 15, "the catalogue's guns are found")
	for w: WeaponSpec in guns:
		assert_true(GUN_CALIBRE_MM.has(w.id), "%s has a calibre entered for the damage check" % w.id)
		var mm := int(GUN_CALIBRE_MM.get(w.id, 0))
		if mm >= 127:
			assert_true(w.damage >= 2.0 and w.damage <= 3.0, "%s: a 127-130 mm shell does 2 to 3, not %.1f" % [w.id, w.damage])
		elif mm >= 76:
			assert_true(w.damage >= 1.0 and w.damage <= 2.2, "%s: a 76-114 mm shell does 1 to about 2, not %.1f" % [w.id, w.damage])
		else:
			assert_true(w.damage > 0.0 and w.damage < 1.0, "%s: a shell under 76 mm does less than 1, not %.1f" % [w.id, w.damage])
	# The scale is the anti-ship missiles': a 5-inch shell is a small fraction of a Harpoon.
	assert_true(DataDB.weapon("mk45_mod4_gun").damage * 12.0 <= DataDB.weapon("rgm_84_harpoon").damage, "twelve 5-inch hits do no more than one Harpoon")


func test_twenty_shell_hits_leave_a_destroyer_afloat() -> void:
	var gun := DataDB.weapon("mk45_mod4_gun")
	for trial in 40:
		Damage.rng.seed = 2000 + trial
		var burke := _unit("usn_ddg_arleigh_burke_iia")
		for hit in 20:
			Damage.apply(burke, gun.damage, gun.type, "BLUE")
		assert_true(burke.alive, "twenty 5-inch hits do not sink a Burke outright (seed %d)" % (2000 + trial))
		assert_true(Damage.health_fraction(burke) >= 0.5, "and leave it at least half its hull (%.2f)" % Damage.health_fraction(burke))
	Damage.rng.seed = 2100
	var six := _unit("usn_ddg_arleigh_burke_iia")
	for hit in 6:
		Damage.apply(six, gun.damage, gun.type, "BLUE")
	assert_true(Damage.health_fraction(six) >= 0.85, "six shells used to leave a Burke at 40 percent; now %.2f" % Damage.health_fraction(six))


func test_guns_that_bombard_may_be_laid_on_a_contact_ashore() -> void:
	var ashore := Track.new()
	ashore.domain = "land"
	for w: WeaponSpec in _weapons("gun"):
		var mm := int(GUN_CALIBRE_MM.get(w.id, 0))
		assert_true(w.target_types.has("surface"), "%s still engages ships" % w.id)
		assert_eq(Combat.suits_track(w, ashore), mm >= 100, "%s (%d mm) %s a contact ashore" % [w.id, mm, "suits" if mm >= 100 else "does not suit"])
