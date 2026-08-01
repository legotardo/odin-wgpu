struct CameraUniform {
    view_proj: mat4x4<f32>,
}

struct PaletteUniform {
    color: array<vec4<f32>, 256>,
}

struct Light {
    position: vec3<f32>,
    light_type: u32,
    color: vec3<f32>,
    intensity: f32,
    range: f32,
    _pad1: f32,
    _pad2: f32,
    _pad3: f32,
}

struct LightBuffer {
    light_count: u32,
    _pad1: u32,
    _pad2: u32,
    _pad3: u32,
    lights: array<Light>,
}

struct InstanceBuffer {
    models: array<mat4x4<f32>>,
}

@group(0) @binding(0) var<uniform> camera: CameraUniform;
@group(0) @binding(1) var<storage, read> palette: PaletteUniform;
@group(0) @binding(2) var<storage, read> light_data: LightBuffer;
@group(0) @binding(3) var<storage, read> instance_data: InstanceBuffer;

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
    @location(3) world_position: vec3<f32>,
};

@vertex
fn vs_main(in: VertexInput, @builtin(instance_index) instance_idx: u32) -> VertexOutput {
    let model = instance_data.models[instance_idx];
    let world_pos = model * vec4<f32>(in.position, 1.0);

    var out: VertexOutput;

    out.clip_position = camera.view_proj * world_pos;
    out.material_id = in.material_id;
    out.normal_id = in.normal_id;
    out.world_position = world_pos.xyz;

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
    var final_light = vec3<f32>(0.05);

    for (var i: u32 = 0u; i < light_data.light_count; i += 1u) {
        let light = light_data.lights[i];

        let light_dir = light.position - in.world_position;
        let dist = length(light_dir);

        if (dist < light.range) {
            let attenuation = 1.0 - (dist / light.range);
            let n_dot_l = max(dot(normal, normalize(light_dir)), 0.0);

            final_light += light.color * light.intensity * n_dot_l * attenuation;
        }
    }

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

    return vec4<f32>(base_color.rgb * final_light, base_color.a);
}