package input

Key :: enum u8 {
	Unkown,
	W,
	A,
	S,
	D,
	P,
	Space,
	LeftShift,
	Escape,
}


ButtonState :: struct {
	pressed:       bool,
	just_pressed:  bool,
	just_released: bool,
}

InputManager :: struct {
	keys:        [Key]ButtonState,
	first_mouse: bool,
	mouse_dx:    f32,
	mouse_dy:    f32,
	mouse_x:     f32,
	mouse_y:     f32,
}

input_init :: proc() -> InputManager {
	return {first_mouse = true}
}

input_update :: proc(manager: ^InputManager) {
	for &key in manager.keys {
		key.just_pressed = false
		key.just_released = false
	}

	manager.mouse_dx = 0
	manager.mouse_dy = 0
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

input_set_mouse_position :: proc(manager: ^InputManager, x, y: f32) {
	if manager.first_mouse {
		manager.mouse_x = x
		manager.mouse_y = y
		manager.first_mouse = false
	}

	manager.mouse_dx += x - manager.mouse_x
	manager.mouse_dy += y - manager.mouse_y

	manager.mouse_x = x
	manager.mouse_y = y
}

is_key_pressed :: proc(manager: ^InputManager, key: Key) -> bool {
	return manager.keys[key].pressed
}

is_key_just_pressed :: proc(manager: ^InputManager, key: Key) -> bool {
	return manager.keys[key].just_pressed
}
