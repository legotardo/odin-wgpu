struct CameraUniform {
    view_proj: mat4x4<f32>,
    view_proj_inv: mat4x4<f32>,
    position: vec3<f32>,
    _pad: f32,
}

struct SunUniform {
    view_proj: mat4x4<f32>,
    direction: vec4<f32>,
}

struct RenderConfig {
    render_distance: i32,
    block_size: f32,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> VertexOutput {
    var out: VertexOutput;
    
    let x = f32((in_vertex_index << 1u) & 2u);
    let y = f32(in_vertex_index & 2u);
    
    // Entire screen
    out.clip_position = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    out.uv = vec2<f32>(x, y);
    
    return out;
}

@group(0) @binding(0) var g_albedo: texture_2d<f32>;
@group(0) @binding(1) var g_normal: texture_2d<f32>;
@group(0) @binding(2) var g_depth: texture_depth_2d;
@group(0) @binding(3) var g_sampler: sampler;
@group(0) @binding(4) var<uniform> camera: CameraUniform;
@group(0) @binding(5) var<uniform> render_config: RenderConfig;
@group(0) @binding(6) var<uniform> sun: SunUniform;
@group(0) @binding(7) var shadow_map: texture_depth_2d;
@group(0) @binding(8) var shadow_sampler: sampler;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let albedo = textureSample(g_albedo, g_sampler, in.uv).rgb;
    let normal = textureSample(g_normal, g_sampler, in.uv).rgb;
    let depth = textureSample(g_depth, g_sampler, in.uv);

    if (depth >= 1.0) {
        return vec4<f32>(albedo, 1.0);
    }

    let ndc_x = in.uv.x * 2.0 - 1.0;
    let ndc_y = 1.0 - in.uv.y * 2.0;
    let ndc_pos = vec4<f32>(ndc_x, ndc_y, depth, 1.0);

    let world_unprojected = camera.view_proj_inv * ndc_pos;
    let world_position = world_unprojected.xyz / world_unprojected.w;

    let sun_pos = sun.view_proj * vec4<f32>(world_position, 1.0);
    let sun_ndc = sun_pos.xyz / sun_pos.w;

    let shadow_uv = vec2<f32>(
        sun_ndc.x * 0.5 + 0.5,
        sun_ndc.y * -0.5 + 0.5,
    );

    var shadow_factor = 1.0;
    if (shadow_uv.x >= 0.0 && shadow_uv.x <= 1.0 &&
        shadow_uv.y >= 0.0 && shadow_uv.y <= 1.0 &&
        sun_ndc.z >= 0.0 && sun_ndc.z <= 1.0) {
        let sampled_depth = textureSample(shadow_map, shadow_sampler, shadow_uv);
        let bias = 0.001;
        
        if (sun_ndc.z - bias > sampled_depth) {
            shadow_factor = 0.0;
        }
    }

    let ambient_light = 0.4;
    let light_intensity = mix(ambient_light, 1.0, shadow_factor);
    let lit_albedo = albedo * light_intensity;
    
    let dist = length(camera.position - world_position);
    let fog_start = f32(render_config.render_distance * 9);
    let fog_end = fog_start + 10.0;
    let fog_factor = clamp((fog_end - dist) / (fog_end - fog_start), 0.0, 1.0);
    let fog_color = vec3<f32>(0.333, 0.721, 1.0);

    let final_color = mix(fog_color, lit_albedo, fog_factor);

    return vec4<f32>(final_color, 1.0);
}
