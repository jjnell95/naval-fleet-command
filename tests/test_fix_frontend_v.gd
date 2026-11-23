extends TestCase
## What the desk, the briefing, the reference book and the debrief tell the player agrees with what
## the game does: the rule of manual missile defence, a catalogue whose every row sits under its
## heading, and every hit on a neutral named in the debrief that charges for it.


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


# --- Manual missile defence as the desk and the briefing word it ----------------------------

func test_manual_defence_summary_says_point_defence_missiles_fire_by_themselves() -> void:
	var options := GameOptions.classic()
	assert_true(options.manual_missile_defence(), "the classic preset holds missile defence for orders")
	var line := ""
	for l: String in options.summary_lines():
		if l.begins_with("Missile defence:"):
			line = l
	assert_true(line != "", "the summary has a missile-defence line")
	assert_true(line.contains("area SAMs"), "the line says it is the area SAMs that wait for the order: %s" % line)
	assert_true(line.contains("point-defence missiles"), "the line says the point-defence missiles fire by themselves, as they do: %s" % line)
	assert_true(not line.contains("ships fire SAMs only when ordered"), "the line no longer says every SAM waits for the order")
	var tooltip := GameOptions.option_tooltip("manual_defence")
	assert_true(tooltip.contains("point-defence missiles fire by themselves"), "the summary and the option's own tooltip state the same rule")
