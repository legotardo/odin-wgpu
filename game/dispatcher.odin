package game

SystemProc :: proc(state: ^GameState, dt: f32)

ECSDispatcher :: struct {
    tick_systems: [dynamic]SystemProc,
    frame_systems: [dynamic]SystemProc,

    tick_rate: f32,
    time_per_tick: f32,
    accumulator: f32,
}

ecs_dispatcher_init :: proc(tick_rate: f32) -> ECSDispatcher {
    return {
        tick_systems = make([dynamic]SystemProc),
        frame_systems = make([dynamic]SystemProc),

        tick_rate = tick_rate,
        time_per_tick = 1.0 / tick_rate,
        accumulator = 0.0,
    }
}

ecs_dispatcher_add_tick :: proc(dispatcher: ^ECSDispatcher, system: SystemProc) {
	append(&dispatcher.tick_systems, system)
}

ecs_dispatcher_add_frame :: proc(dispatcher: ^ECSDispatcher, system: SystemProc) {
	append(&dispatcher.frame_systems, system)
}

ecs_dispatcher_destroy :: proc(dispatcher: ^ECSDispatcher) {
	delete(dispatcher.tick_systems)
	delete(dispatcher.frame_systems)
}

ecs_dispatcher_update :: proc(dispatcher: ^ECSDispatcher, state: ^GameState, dt: f32) {
	dispatcher.accumulator += dt

	for dispatcher.accumulator >= dispatcher.time_per_tick {
		for system in dispatcher.tick_systems {
			system(state, dt)
		}
		
		dispatcher.accumulator -= dispatcher.time_per_tick
	}

	for system in dispatcher.frame_systems {
		system(state, dt)
	}
}
