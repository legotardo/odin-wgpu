package game

import "core:math/linalg"

Camera :: struct {
	eye:    linalg.Vector3f32,
	target: linalg.Vector3f32,
	up:     linalg.Vector3f32,
	aspect: f32,
	fovy:   f32,
	znear:  f32,
	zfar:   f32,
}

camera_new :: proc(width, height: u32) -> Camera {
	return {
		eye = {0, 1, 2},
		target = {0, 0, 0},
		up = {0, 1, 0},
		aspect = f32(width) / f32(height),
		fovy = 90 * linalg.RAD_PER_DEG,
		zfar = 100,
		znear = 0.1,
	}
}

camera_build_matrix :: proc(camera: ^Camera) -> linalg.Matrix4f32 {
	view := linalg.matrix4_look_at_f32(camera.eye, camera.target, camera.up)
	proj := linalg.matrix4_perspective_f32(camera.fovy, camera.aspect, camera.znear, camera.zfar)

	return proj * view
}
