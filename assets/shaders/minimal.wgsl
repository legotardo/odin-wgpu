struct CameraUniform {
    view_proj: mat4x4<f32>,
}

@group(0) @binding(0)
var<uniform> camera: CameraUniform;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec3<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec3<f32>,
};

@vertex
fn vs_main(
    // model: VertexInput
    @builtin(vertex_index) in_vertex_index: u32,
) -> VertexOutput {
    // var out: VertexOutput;

    // out.color = model.color;
    // // out.clip_position = camera.view_proj * vec4<f32>(model.position, 1.0);
    // out.clip_position = vec4<f32>(model.position, 1.0);

    // return out;

    var out: VertexOutput;
    let x = f32(1 - i32(in_vertex_index)) * 0.5;
    let y = f32(i32(in_vertex_index & 1u) * 2 - 1) * 0.5;
    out.clip_position = vec4<f32>(x, y, 0.0, 1.0);
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // return vec4<f32>(in.color, 1.0);
    return vec4<f32>(0.3, 0.2, 0.1, 1.0);
}