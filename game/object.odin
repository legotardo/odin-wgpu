package game

import "core:math/linalg"

Transform :: struct {
	position: linalg.Vector3f32,
	rotation: linalg.Vector3f32,
	scale:    linalg.Vector3f32,
}

transform_matrix :: proc(t: Transform) -> linalg.Matrix4f32 {
	m_pos := linalg.matrix4_translate_f32(t.position)
	m_scale := linalg.matrix4_scale(t.scale)

	return m_pos * m_scale
}

GameObject :: struct {
	id:        u64,
	transform: Transform,
	mesh:      MeshHandle,
	material:  MaterialHandle,
	active:    bool,
}

gameobject_create :: proc(
	id: u64,
	mesh: MeshHandle,
	material: MaterialHandle,
	pos: linalg.Vector3f32,
) -> GameObject {
	return {
		id = id,
		mesh = mesh,
		material = material,
		transform = {position = pos, scale = {1.0, 1.0, 1.0}},
		active = true,
	}
}
