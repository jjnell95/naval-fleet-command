class_name ConfirmDiscard
extends ConfirmationDialog
## The one question asked before a click throws work away: leaving a running engagement for
## another operation, restarting it, clearing a mission being built, deleting a saved engagement.
## The keeping answer holds the focus, so a stray Enter or Space keeps the work.

const NODE_NAME := "ConfirmDiscard"

var _on_confirm := Callable()


## Asks on `host`, reusing its one dialog, and calls `on_confirm` only if the commander agrees.
static func ask(host: Node, title_text: String, question: String, discard_text: String, on_confirm: Callable, keep_text := "KEEP IT") -> ConfirmDiscard:
	var dialog := host.get_node_or_null(NODE_NAME) as ConfirmDiscard
	if dialog == null:
		dialog = ConfirmDiscard.new()
		dialog.name = NODE_NAME
		host.add_child(dialog)
	dialog._on_confirm = on_confirm
	dialog.title = title_text.to_upper()
	dialog.dialog_text = question
	dialog.ok_button_text = discard_text.to_upper()
	dialog.cancel_button_text = keep_text.to_upper()
	dialog.popup_centered(Vector2i(480, 0))
	dialog.get_cancel_button().grab_focus.call_deferred()
	return dialog


## The dialog on `host` while it is asking, or null.
static func asking(host: Node) -> ConfirmDiscard:
	var dialog := host.get_node_or_null(NODE_NAME) as ConfirmDiscard
	return dialog if dialog != null and dialog.visible else null


func _init() -> void:
	dialog_autowrap = true
	exclusive = true
	transient = true
	confirmed.connect(_answer.bind(true))
	canceled.connect(_answer.bind(false))
	var ok := get_ok_button()
	ok.theme_type_variation = "DangerButton"
	for b: Button in [ok, get_cancel_button()]:
		b.custom_minimum_size = Vector2(130, 32)
		b.focus_mode = Control.FOCUS_ALL


func _answer(confirmed_now: bool) -> void:
	var action := _on_confirm
	_on_confirm = Callable()
	if confirmed_now and action.is_valid():
		action.call()
