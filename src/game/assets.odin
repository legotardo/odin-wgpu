package game

import "core:strings"
import "../logger"
import "../renderer"
import "../shared"

MaterialHandle :: distinct string
MeshHandle :: distinct string
VoxelPrefabHandle :: distinct string

Assets :: struct {
	materials:     map[string]renderer.Material,
	meshes:        map[string]renderer.Mesh,
	voxel_prefabs: map[string]shared.VoxelPrefab,
}

assets_init :: proc() -> Assets {
	return {
		materials     = make(map[string]renderer.Material),
		meshes        = make(map[string]renderer.Mesh),
		voxel_prefabs = make(map[string]shared.VoxelPrefab),
	}
}

assets_register_material :: proc(
	assets: ^Assets,
	name: string,
	material: renderer.Material,
) -> MaterialHandle {
	found_material, ok := assets.materials[name]
	if (ok) {
		renderer.material_destroy(&found_material)
	}

	assets.materials[name] = material

	return MaterialHandle(name)
}

assets_unregister_material :: proc(assets: ^Assets, name: string) {
	found_material, ok := assets.materials[name]
	if (ok) {
		renderer.material_destroy(&found_material)
		delete_key(&assets.materials, name)
	}
}

assets_get_material :: proc(assets: ^Assets, handle: MaterialHandle) -> ^renderer.Material {
	return &assets.materials[string(handle)]
}

assets_register_mesh :: proc(assets: ^Assets, name: string, mesh: renderer.Mesh) -> MeshHandle {
	found_mesh, ok := assets.meshes[name]
	if (ok) {
		renderer.mesh_destroy(&found_mesh)
	}

	c_name := strings.clone(name)

	assets.meshes[c_name] = mesh

	return MeshHandle(c_name)
}

assets_unregister_mesh :: proc(assets: ^Assets, name: string) {
	found_mesh, ok := assets.meshes[name]
	if (ok) {
		renderer.mesh_destroy(&found_mesh)
		delete_key(&assets.meshes, name)
	}
}

assets_get_mesh :: proc(assets: ^Assets, handle: MeshHandle) -> ^renderer.Mesh {
	return &assets.meshes[string(handle)]
}


assets_register_voxel_prefab :: proc(
	assets: ^Assets,
	name: string,
	prefab: shared.VoxelPrefab,
) -> VoxelPrefabHandle {
	found_prefab, ok := assets.voxel_prefabs[name]
	if (ok) {
		delete(found_prefab.blocks)
		delete(found_prefab.palette)
	}

	assets.voxel_prefabs[name] = prefab

	return VoxelPrefabHandle(name)
}

assets_unregister_voxel_prefab :: proc(assets: ^Assets, name: string) {
	found_prefab, ok := assets.voxel_prefabs[name]
	if (ok) {
		delete(found_prefab.blocks)
		delete(found_prefab.palette)
		delete_key(&assets.voxel_prefabs, name)
	}
}

assets_get_voxel_prefab :: proc(assets: ^Assets, handle: VoxelPrefabHandle) -> ^shared.VoxelPrefab {
	return &assets.voxel_prefabs[string(handle)]
}

assets_destroy :: proc(assets: ^Assets) {
	for _, &m in assets.meshes {
		renderer.mesh_destroy(&m)
	}
	for _, &m in assets.materials {
		renderer.material_destroy(&m)
	}
	for _, p in assets.voxel_prefabs {
		delete(p.blocks)
		delete(p.palette)
	}
	delete(assets.meshes)
	delete(assets.materials)
	delete(assets.voxel_prefabs)
}
