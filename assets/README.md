# assets

Empty by design so far. Everything on screen is drawn in code: the tactical symbols in
`scripts/ui/map_symbols.gd`, the map itself in `TacticalMap._draw()`, and the interface theme in
`scripts/ui/ui_theme.gd`.

If the presentation pass adds files here, two rules hold.

1. **Original work only.** No downloaded sprites, icons, fonts or sounds whose licence is unclear,
   and nothing lifted from an existing game. Generate art programmatically or author it fresh.
2. **Keep it small and vector-like.** The look is a command display, not a painting. A file here
   should be justified by something that genuinely cannot be drawn in code.

Anything added must load through Godot's importer and be referenced by `res://assets/...`.
