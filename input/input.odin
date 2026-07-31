package input

Key :: enum {
	Unkown,
	W,
	A,
	S,
	D,
}


ButtonState :: struct {
	pressed:       bool,
	just_pressed:  bool,
	just_released: bool,
}

InputManager :: struct {
	keys: [Key]ButtonState,
}

input_update :: proc(manager: ^InputManager) {
	for &key in manager.keys {
		key.just_pressed = false
		key.just_released = false
	}
}

input_set_key_state :: proc(manager: ^InputManager, key: Key, down: bool) {
	state := &manager.keys[key]

	if down && !state.pressed {
		state.just_pressed = true
	} else if !down && state.pressed {
		state.just_released = true
	}

	state.pressed = down
}

is_key_pressed :: proc(manager: ^InputManager, key: Key) -> bool {
	return manager.keys[key].pressed
}

is_key_just_pressed :: proc(manager: ^InputManager, key: Key) -> bool {
	return manager.keys[key].just_pressed
}
