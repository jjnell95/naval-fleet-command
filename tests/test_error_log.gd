extends Logger
## Tests cannot report PASS after an engine/runtime failure. Mutex keeps asynchronous errors safe.
var errors: Array[String] = []
var _mutex := Mutex.new()

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	errors.append("%s:%d %s: %s %s" % [file, line, function, code, rationale])
	_mutex.unlock()

func take_errors() -> Array[String]:
	_mutex.lock()
	var found := errors.duplicate()
	errors.clear()
	_mutex.unlock()
	return found
