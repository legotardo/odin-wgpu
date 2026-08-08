struct CameraUniform {
    view_proj: mat4x4<f32>,
}

struct RenderConfig {
    render_distance: i32,
}

struct PaletteUniform {
    color: array<vec4<f32>, 256>,
}

@group(0) @binding(0) var<uniform> camera: CameraUniform;
@group(0) @binding(1) var<uniform> render_config: RenderConfig;
@group(0) @binding(2) var<storage, read> palette: PaletteUniform;
@group(0) @binding(3) var<storage, read> instances: array<mat4x4<f32>>;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) @interpolate(flat) material_id: u32,
    @location(2) @interpolate(flat) normal_id: u32,
    @builtin(instance_index) instance_idx: u32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) @interpolate(flat) material_id: u32,
    @location(2) @interpolate(flat) normal_id: u32,
    @location(3) world_position: vec3<f32>,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    let model = instances[in.instance_idx];
    let world_pos = model * vec4<f32>(in.position, 1.0);

    var out: VertexOutput;

    out.clip_position = camera.view_proj * world_pos;
    out.material_id = in.material_id;
    out.normal_id = in.normal_id;
    out.world_position = world_pos.xyz;

    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(1.0);
}