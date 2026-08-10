package game

import "core:math/linalg"
import "../ecs"

AABB :: struct {
    min: linalg.Vector3f32,
    max: linalg.Vector3f32,
}

aabb_from_center_extends :: proc(center, extents: linalg.Vector3f32) -> AABB {
    return AABB{min = center - extents, max = center + extents}
}

aabb_intersects :: proc(a, b: AABB) -> bool {
    return a.min.x <= b.max.x && a.max.x >= b.min.x &&
           a.min.y <= b.max.y && a.max.y >= b.min.y &&
           a.min.z <= b.max.z && a.max.z >= b.min.z
}

aabb_contains_point :: proc(a: AABB, p: linalg.Vector3f32) -> bool {
    return p.x >= a.min.x && p.x <= a.max.x &&
           p.y >= a.min.y && p.y <= a.max.y &&
           p.z >= a.min.z && p.z <= a.max.z
}

aabb_transform :: proc(a: AABB, model: linalg.Matrix4f32) -> AABB {
    corners := [8]linalg.Vector3f32{
        {a.min.x, a.min.y, a.min.z}, {a.max.x, a.min.y, a.min.z},
        {a.min.x, a.max.y, a.min.z}, {a.max.x, a.max.y, a.min.z},
        {a.min.x, a.min.y, a.max.z}, {a.max.x, a.min.y, a.max.z},
        {a.min.x, a.max.y, a.max.z}, {a.max.x, a.max.y, a.max.z},
    }

    new_min := linalg.Vector3f32{max(f32), max(f32), max(f32)}
    new_max := linalg.Vector3f32{min(f32), min(f32), min(f32)}

    for c in corners {
        transformed := (model * linalg.Vector4f32{c.x, c.y, c.z, 1.0}).xyz
        new_min = linalg.min(new_min, transformed)
        new_max = linalg.max(new_max, transformed)
    }

    return AABB{min = new_min, max = new_max}
}

aabb_by_collider :: proc(pos: linalg.Vector3f32, col: ^ecs.ColliderComponent) -> AABB {
    center := pos + col.offset
    half_size := col.size * 0.5

    return {
        min = center - half_size,
        max = center + half_size
    }
}