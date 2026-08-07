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

@group(0) @binding(0) var<uniform> camera: CameraUniform;
@group(0) @binding(1) var<uniform> render_config: RenderConfig;
@group(0) @binding(2) var<storage, read> palette: PaletteUniform;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) @interpolate(flat) material_id: u32,
    @location(2) @interpolate(flat) normal_id: u32,
    @location(3) ao: f32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) @interpolate(flat) material_id: u32,
    @location(2) @interpolate(flat) normal_id: u32,
    @location(3) world_position: vec3<f32>,
    @location(4) ao: f32,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    let world_pos = vec4<f32>(in.position * render_config.block_size, 1.0);

    var out: VertexOutput;

    out.clip_position = camera.view_proj * world_pos;
    out.material_id = in.material_id;
    out.normal_id = in.normal_id;
    out.world_position = world_pos.xyz;
    out.ao = in.ao;

    return out;
}

fn calculate_normal(normal_id: u32) -> vec3<f32> {
    var normals = array<vec3<f32>, 6>(
        vec3<f32>( 1.0,  0.0,  0.0),
        vec3<f32>(-1.0,  0.0,  0.0),
        vec3<f32>( 0.0,  1.0,  0.0),
        vec3<f32>( 0.0, -1.0,  0.0),
        vec3<f32>( 0.0,  0.0,  1.0),
        vec3<f32>( 0.0,  0.0, -1.0)
    );

    return normals[normal_id];
}

struct GBufferOutput {
    @location(0) albedo: vec4<f32>,
    @location(1) normal: vec4<f32>,
}

@fragment
fn fs_main(in: VertexOutput) -> GBufferOutput {
    let normal = calculate_normal(in.normal_id);
    let base_color = palette.color[in.material_id];

    let shadow_strength = 0.6;
    let shadow_floor = 0.35;
    let ao_clamped = mix(1.0, shadow_floor, (1.0 - in.ao) * shadow_strength);

    var out: GBufferOutput;
    
    out.albedo = vec4<f32>(base_color.rgb * ao_clamped, base_color.a);
    out.normal = vec4<f32>(normal, 1.0);

    return out;
}