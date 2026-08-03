struct CameraUniform {
    view_proj: mat4x4<f32>,
    position: vec3<f32>,
    _pad: f32,
}

struct PaletteUniform {
    color: array<vec4<f32>, 256>,
}

struct Light {
    position: vec3<f32>,
    light_type: u32,

    direction: vec3<f32>,
    intensity: f32,

    color: vec3<f32>,
    range: f32,
}

struct LightBuffer {
    light_count: u32,
    _pad: vec3<u32>,
    lights: array<Light>,
}

@group(0) @binding(0) var<uniform> camera: CameraUniform;
@group(0) @binding(1) var<storage, read> palette: PaletteUniform;
@group(0) @binding(2) var<storage, read> light_data: LightBuffer;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) material_id: u32,
    @location(2) normal_id: u32,
    @location(3) ao: f32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) material_id: u32,
    @location(2) normal_id: u32,
    @location(3) world_position: vec3<f32>,
    @location(4) ao: f32,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    let world_pos = vec4<f32>(in.position, 1.0);

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

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let normal = calculate_normal(in.normal_id);
    let base_color = palette.color[in.material_id];
    var final_light = vec3<f32>(0.05);

    // for (var i: u32 = 0u; i < light_data.light_count; i += 1u) {
    //     let light = light_data.lights[i];
    //     var L: vec3<f32>;
    //     var attenuation = 1.0;

    //     if (light.light_type == 0u) {
    //         let light_vec = light.position - in.world_position;
    //         let dist = length(light_vec);

    //         if (dist >= light.range) {
    //             continue;
    //         }

    //         L = normalize(light_vec);
    //         attenuation = pow(max(1.0 - dist / light.range, 0.0), 2.0);
    //     } else {
    //         L = normalize(light.direction);
    //     }

    //     let diffuse = max(dot(normal, L), 0.0);

    //     final_light += light.color * 1 * diffuse * attenuation;
    //     // return vec4(vec3(diffuse), 1.0);
    // }

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

    let shadow_strength = 0.6;
    let shadow_floor = 0.35;
    let ao_clamped = mix(1.0, shadow_floor, (1.0 - in.ao) * shadow_strength);

    var final_color = vec3<f32>(base_color.rgb * ao_clamped);

    let dist = length(camera.position - in.world_position);
    let fog_start = 30.0;
    let fog_end = 50.0;
    let fog_factor = clamp((fog_end - dist) / (fog_end - fog_start), 0.0, 1.0);
    let fog_color = vec3<f32>(0.45, 0.68, 0.87);

    final_color = mix(fog_color, final_color, fog_factor);

    return vec4<f32>(final_color, base_color.a);
}