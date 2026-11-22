extends TestCase
## What ships in the repository and the browser pack is only what the game can reach. The art,
## model and audio loaders build every path from a catalogue id, a sound cue or a crew line, so a
## file whose name matches none of them is dead weight that every clone and import carries.

const SOUND := preload("res://scripts/ui/sound_fx.gd")


func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(dir):
		if name.get_extension() == ext:
			out.append(name)
	return out


## The catalogue id an art file is named after, and whether that id is in the catalogue under
## its own name (a retired id that DataDB maps onto its replacement does not count: the loaders
## ask for the replacement's art).
func _platform_listed(id: String) -> bool:
	var spec := DataDB.platform(id)
	return spec != null and spec.id == id


func _weapon_listed(id: String) -> bool:
	var spec := DataDB.weapon(id)
	return spec != null and spec.id == id


func test_every_model_belongs_to_a_platform_or_weapon_in_the_catalogue() -> void:
	var models := _files("res://assets/models", "glb")
	assert_true(models.size() > 100, "the model library is found")
	for name: String in models:
		var id := name.get_basename()
		assert_true(_platform_listed(id) or _weapon_listed(id), "%s is the model of a catalogue platform or weapon" % name)


func test_every_render_belongs_to_a_catalogue_entry_of_its_kind() -> void:
	var suffix := RegEx.create_from_string("_(beauty|thumb|plan|profile)$")
	var platforms := _files("res://assets/platforms", "png")
	var weapons := _files("res://assets/weapons", "png")
	assert_true(platforms.size() > 100 and weapons.size() > 100, "the render libraries are found")
	for name: String in platforms:
		var id := suffix.sub(name.get_basename(), "")
		assert_true(_platform_listed(id), "%s is the render of a catalogue platform" % name)
	for name: String in weapons:
		var id := suffix.sub(name.get_basename(), "")
		assert_true(_weapon_listed(id), "%s is the render of a catalogue weapon" % name)


func test_every_sound_file_is_a_cue_the_game_plays() -> void:
	var take := RegEx.create_from_string("^(.+)_(\\d+)$")
	for name: String in _files("res://assets/audio/effects", "ogg"):
		var m := take.search(name.get_basename())
		assert_true(m != null, "%s is a numbered take" % name)
		if m == null:
			continue
		var cue := m.get_string(1)
		var cues: Array = SOUND.CUE_DB.keys().filter(func(c: String) -> bool: return cue == ("complete" if c in ["victory", "defeat"] else c))
		assert_true(not cues.is_empty(), "%s belongs to a sound cue" % name)
		if not cues.is_empty():
			assert_true(int(m.get_string(2)) < int(SOUND.VARIANTS.get(cues[0], 1)), "%s is a take the cue rotates through" % name)
	for name: String in _files("res://assets/audio/ambient", "ogg"):
		var bed := name.get_basename()
		assert_true(bed == "sea" or SOUND.HUM_DB.has(bed), "%s is the sea or a machinery bed" % name)
	var phrases: Dictionary = CrewVoice.load_phrases()
	for profile: String in CrewVoice.PROFILES:
		for name: String in _files("res://assets/audio/crew/" + profile, "ogg"):
			var m := take.search(name.get_basename())
			assert_true(m != null and phrases.has(m.get_string(1)), "%s/%s is a crew event" % [profile, name])
			if m != null and phrases.has(m.get_string(1)):
				assert_true(int(m.get_string(2)) < (phrases[m.get_string(1)] as Array).size(), "%s/%s is a line the crew can speak" % [profile, name])
