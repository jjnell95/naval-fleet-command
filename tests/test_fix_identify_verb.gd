extends TestCase
## The bare right-click on a contact: identify anything whose allegiance is still unknown.


func _track(identity: String, classification: Track.Classification) -> Track:
	var t := Track.new()
	t.id = "T1"
	t.owner_faction = "BLUE"
	t.identity = identity
	t.classification = classification
	t.position = Vector2(12.0, 3.0)
	t.domain = "surface"
	return t


func test_a_classified_contact_of_unknown_allegiance_is_identified_by_a_right_click() -> void:
	var merchant := _track("UNKNOWN", Track.Classification.CLASS_KNOWN)
	assert_eq(TacticalMap.default_contact_verb(merchant), "investigate", "a class from an emitter or a sound is not an identity")
	assert_eq(TacticalMap.default_contact_verb(_track("UNKNOWN", Track.Classification.UNKNOWN)), "investigate")


func test_identified_contacts_keep_their_verbs() -> void:
	assert_eq(TacticalMap.default_contact_verb(_track("HOSTILE", Track.Classification.CLASS_KNOWN)), "attack")
	assert_eq(TacticalMap.default_contact_verb(_track("NEUTRAL", Track.Classification.CLASS_KNOWN)), "", "a neutral opens the menu")
	assert_eq(TacticalMap.default_contact_verb(_track("FRIENDLY", Track.Classification.CLASS_KNOWN)), "")
