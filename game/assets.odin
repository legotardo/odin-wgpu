package game

import "../logger"
import "../renderer"

MaterialHandle :: distinct string
MeshHandle :: distinct string
VoxelPrefabHandle :: distinct string

Assets :: struct {
	materials:     map[string]renderer.Material,
	meshes:        map[string]renderer.Mesh,
	voxel_prefabs: map[string]VoxelPrefab,
}

assets_init :: proc() -> Assets {
	return {
		materials     = make(map[string]renderer.Material),
		meshes        = make(map[string]renderer.Mesh),
		voxel_prefabs = make(map[string]VoxelPrefab),
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

	logger.info("[ASSETS] Material %s registered", name)

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

	assets.meshes[name] = mesh

	logger.info("[ASSETS] Mesh %s registered", name)

	return MeshHandle(name)
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
	prefab: VoxelPrefab,
) -> VoxelPrefabHandle {
	found_prefab, ok := assets.voxel_prefabs[name]
	if (ok) {
		delete(found_prefab.blocks)
		delete(found_prefab.palette)
	}

	assets.voxel_prefabs[name] = prefab

	logger.info("[ASSETS] Voxel Prefab %s registered", name)

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

assets_get_voxel_prefab :: proc(assets: ^Assets, handle: VoxelPrefabHandle) -> ^VoxelPrefab {
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
