package game

import "../renderer"
import "../../libs/rml-ui/Bindings/Odin/rmlui"

rml_file :: #load("../../assets/ui/hud.rml")

ui_hud_player: struct {
	player_health: u16,
}

ui_hud_model: rmlui.Data_Handle

ui_hud_init :: proc(state: ^GameState) -> ^renderer.UIDocument {
	ui_hud_player.player_health = 30
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

}
