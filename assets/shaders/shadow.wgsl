struct SunUniform {
    view_proj: mat4x4<f32>,
    direction: vec4<f32>,
}

struct CameraUniform {
    view_proj: mat4x4<f32>,
    view_proj_inv: mat4x4<f32>,
    position: vec3<f32>,
    _pad: f32,
}

struct RenderConfig {
    render_distance: i32,
    block_size: f32,
}

struct PaletteUniform {
    color: array<vec4<f32>, 256>,
}

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) @interpolate(flat) material_id: u32,
    @location(2) @interpolate(flat) normal_id: u32,
    @location(3) ao: f32,
    @builtin(instance_index) instance_idx: u32,
};

@group(0) @binding(0) var<uniform> camera: CameraUniform;
@group(0) @binding(1) var<uniform> render_config: RenderConfig;
@group(0) @binding(2) var<storage, read> palette: PaletteUniform;
@group(0) @binding(3) var<storage, read> instances: array<mat4x4<f32>>;

@group(1) @binding(0) var<uniform> sun: SunUniform;

@vertex
fn vs_main(in: VertexInput) -> @builtin(position) vec4<f32> {
    // TODO: Find a way to handle shadows of normal objects too
    let world_pos = vec4<f32>(in.position * render_config.block_size, 1.0);

    return sun.view_proj * world_pos;
}
