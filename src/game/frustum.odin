package game

import "core:math/linalg"

Plane :: struct {
	normal:   linalg.Vector3f32,
	distance: f32,
}

Frustum :: struct {
	planes: [6]Plane,
}

frustum_extract :: proc(vp: matrix[4, 4]f32) -> Frustum {
	f: Frustum

	f.planes[0] = {normal = {vp[3, 0] + vp[0, 0], vp[3, 1] + vp[0, 1], vp[3, 2] + vp[0, 2]}, distance = vp[3, 3] + vp[0, 3]}
	f.planes[1] = {normal = {vp[3, 0] - vp[0, 0], vp[3, 1] - vp[0, 1], vp[3, 2] - vp[0, 2]}, distance = vp[3, 3] - vp[0, 3]}
	f.planes[2] = {normal = {vp[3, 0] + vp[1, 0], vp[3, 1] + vp[1, 1], vp[3, 2] + vp[1, 2]}, distance = vp[3, 3] + vp[1, 3]}
	f.planes[3] = {normal = {vp[3, 0] - vp[1, 0], vp[3, 1] - vp[1, 1], vp[3, 2] - vp[1, 2]}, distance = vp[3, 3] - vp[1, 3]}
	f.planes[4] = {normal = {vp[2, 0], vp[2, 1], vp[2, 2]}, distance = vp[2, 3]}
	f.planes[5] = {normal = {vp[3, 0] - vp[2, 0], vp[3, 1] - vp[2, 1], vp[3, 2] - vp[2, 2]}, distance = vp[3, 3] - vp[2, 3]}

	for i in 0..<6 {
		length := linalg.length(f.planes[i].normal)
		f.planes[i].normal /= length
		f.planes[i].distance /= length
	}

	return f
}

aabb_in_frustum :: proc(aabb: AABB, frustum: Frustum) -> bool {
	for i in 0..<6 {
		plane := frustum.planes[i]
		
		p := aabb.min
		if plane.normal.x >= 0 do p.x = aabb.max.x
		if plane.normal.y >= 0 do p.y = aabb.max.y
		if plane.normal.z >= 0 do p.z = aabb.max.z

		if linalg.dot(plane.normal, p) + plane.distance < 0 {
			return false
		}
	}
	
	return true
}