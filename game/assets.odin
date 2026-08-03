package game

import "../logger"
import "../renderer"

MaterialHandle :: distinct string
MeshHandle :: distinct string

Assets :: struct {
	materials: map[string]renderer.Material,
	meshes:    map[string]renderer.Mesh,
}

assets_init :: proc() -> Assets {
	return {
		materials = make(map[string]renderer.Material),
		meshes    = make(map[string]renderer.Mesh), //
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

assets_unregister_material :: proc(
	assets: ^Assets,
	name: string,
) {
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

assets_unregister_mesh :: proc(
	assets: ^Assets,
	name: string,
) {
	found_mesh, ok := assets.meshes[name]
	if (ok) {
		renderer.mesh_destroy(&found_mesh)
		delete_key(&assets.meshes, name)
	}
}

assets_get_mesh :: proc(assets: ^Assets, handle: MeshHandle) -> ^renderer.Mesh {
	return &assets.meshes[string(handle)]
}

assets_destroy :: proc(assets: ^Assets) {
	for _, &m in assets.meshes {
		renderer.mesh_destroy(&m)
	}
	for _, &m in assets.materials {
		renderer.material_destroy(&m)
	}
}
