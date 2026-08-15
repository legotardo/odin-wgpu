package game

import "../renderer"
import "../../libs/rml-ui/Bindings/Odin/rmlui"

rml_file :: #load("../../assets/ui/hud.rml")

ui_hud_player: struct {
	player_health: u16,
}

ui_hud_model: rmlui.Data_Handle

ui_hud_init :: proc(state: ^GameState) -> ^renderer.UIDocument {
	constructor := rmlui.rmlui_data_model_create(state.r.ui.ctx, "ui_hud")
	assert(constructor != nil)

	ui_hud_struct := rmlui.rmlui_data_model_register_struct(constructor, "ui_hud_state")
	assert(ui_hud_struct != nil)
	assert(rmlui.rmlui_data_struct_add_member(ui_hud_struct, "player_health", offset_of(type_of(ui_hud_player), player_health), .UInt16))
	assert(rmlui.rmlui_data_model_bind_struct(constructor, "player", ui_hud_struct, &ui_hud_player))

	ui_hud_player.player_health = 10
	ui_hud_model = rmlui.rmlui_data_model_get_handle(constructor)

	doc := renderer.ui_load_document(&state.r.ui, "assets/ui/hud.rml", rml_file)
	if doc == nil {
		rmlui.rmlui_data_handle_destroy(ui_hud_model)
		rmlui.rmlui_data_model_destroy_constructor(constructor)
		ui_hud_model = nil
		return nil
	}

	append(&doc.data_models, constructor)
	append(&doc.data_handles, ui_hud_model)

	return doc
}

ui_hud_update :: proc(state: ^GameState, dt: f32) {

}
