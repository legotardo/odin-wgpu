package game

import "../renderer"
import "../../libs/rml-ui/Bindings/Odin/rmlui"

rml_file :: #load("../../assets/ui/hud.rml")

ui_hud_player: struct {
	player_health: u16,
}

ui_hud_model: rmlui.Data_Handle

ui_hud_init :: proc(state: ^GameState) -> ^renderer.UIDocument {
	doc, model := renderer.ui_load_document_with_model(
		&state.r.ui,
		"assets/ui/hud.rml",
		rml_file,
		"ui_hud",
		"player",
		&ui_hud_player,
	)
	ui_hud_model = model
	return doc
}

ui_hud_update :: proc(state: ^GameState, dt: f32) {
	player_health := state.world.healths[state.player_idx]

	new_player_health := (player_health.max_value / player_health.value) * 100
	if ui_hud_player.player_health != new_player_health {
		ui_hud_player.player_health = new_player_health
		rmlui.rmlui_data_handle_dirty_variable(ui_hud_model, "player")
	}
}
