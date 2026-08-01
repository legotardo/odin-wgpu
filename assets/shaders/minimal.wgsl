struct CameraUniform {
    view_proj: mat4x4<f32>,
}

struct PaletteUniform {
    color: array<vec4<f32>, 256>,
}

@group(0) @binding(0)
var<uniform> camera: CameraUniform;

@group(0) @binding(1)
var<storage, read> palette: PaletteUniform;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) material_id: u32,
    @location(2) normal_id: u32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) material_id: u32,
    @location(2) normal_id: u32,
};

@vertex
fn vs_main(
    in: VertexInput
) -> VertexOutput {
    var out: VertexOutput;

    out.clip_position = camera.view_proj * vec4<f32>(in.position, 1.0);
    out.material_id = in.material_id;
    out.normal_id = in.normal_id;

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

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let normal = calculate_normal(in.normal_id);
    let base_color = palette.color[in.material_id];

    // test normals
    // if in.normal_id == 0 {
    //     base_color = vec4<f32>(1.0, 0.0, 0.0, 1.0);
    // } else if in.normal_id == 1 {
    //     base_color = vec4<f32>(0.0, 1.0, 0.0, 1.0);
    // } else if in.normal_id == 2 {
    //     base_color = vec4<f32>(0.0, 0.0, 1.0, 1.0);
    // } else if in.normal_id == 3 {
    //     base_color = vec4<f32>(0.0, 1.0, 1.0, 1.0);
    // } else if in.normal_id == 4 {
    //     base_color = vec4<f32>(1.0, 1.0, 1.0, 1.0);
    // } else if in.normal_id == 5 {
    //     base_color = vec4<f32>(0.5, 1.0, 0.5, 1.0);
    // }

    return vec4<f32>(base_color);
}