package game

import "../../libs/vox"
import "../constants"
import "../shared"

vox_model_load :: proc(data: []u8) -> shared.VoxelPrefab {
    data, ok := vox.load_from_data(data, context.temp_allocator)

    assert(ok, "Failed to load voxel model")
	assert(len(data.models) >= 1, "No models found in vox file")

	main_model := data.models[0]

	w := i32(main_model.size[0])
	d := i32(main_model.size[1]) 
	h := i32(main_model.size[2]) 

	prefab := shared.VoxelPrefab{
		width = w,
		height = h,
		depth = d,
	}

	prefab.palette = make([]shared.Block, 256)
	max_valid_blocks := len(constants.BLOCK_PALETTE_MAP)

	for i in 0..<256 {
		vox_rgba := data.palette[i]

		if vox_rgba[3] == 0 {
			prefab.palette[i] = .Air
			continue
		}

		vox_hex := (u32(vox_rgba[0]) << 16) | (u32(vox_rgba[1]) << 8) | u32(vox_rgba[2])

		matched_block := shared.Block.Air

		for map_entry in constants.BLOCK_PALETTE_MAP {
			if map_entry.value == vox_hex {
				matched_block = shared.Block(map_entry.key)
				break
			}
		}

		prefab.palette[i] = matched_block
	}

	prefab.blocks = make([]u8, w * h * d)
	
	min_y := max(i32)

	for v in main_model.voxels {
		px := i32(v.pos[0])
		pz := i32(v.pos[1])
		py := i32(v.pos[2])

		if py < min_y do min_y = py

		idx := px + (py * w) + (pz * w * h)
		prefab.blocks[idx] = v.color_index - 1
	}

	prefab.min_y_offset = min_y == max(i32) ? 0 : min_y

	return prefab
}

@(private="file")
color_distance :: proc(vox_color: [4]u8, hex_color: u32) -> int {
	r1 := int(vox_color[0])
	g1 := int(vox_color[1])
	b1 := int(vox_color[2])

	r2 := int((hex_color >> 16) & 0xFF)
	g2 := int((hex_color >> 8) & 0xFF)
	b2 := int(hex_color & 0xFF)

	dr := r1 - r2
	dg := g1 - g2
	db := b1 - b2

	return (dr * dr) + (dg * dg) + (db * db)
}