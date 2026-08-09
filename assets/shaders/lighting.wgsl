struct CameraUniform {
    view_proj: mat4x4<f32>,
    view_proj_inv: mat4x4<f32>,
    position: vec3<f32>,
    _pad: f32,
}

struct SunUniform {
    view_proj: mat4x4<f32>,
    direction: vec4<f32>,
    sky_zenith:  vec4<f32>,
	sky_horizon: vec4<f32>,
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
@group(0) @binding(8) var shadow_sampler: sampler_comparison;

const SHADOW_MAP_SIZE: f32 = 4096.0;
const SHADOW_STRENGTH: f32 = 0.30;
const AMBIENT_SKY_TINT: f32 = 0.10;

fn sample_shadow(world_position: vec3<f32>, n_dot_l: f32) -> f32 {
    let sun_pos = sun.view_proj * vec4<f32>(world_position, 1.0);
    let sun_ndc = sun_pos.xyz / sun_pos.w;
    let shadow_uv = vec2<f32>(
        sun_ndc.x * 0.5 + 0.5,
        sun_ndc.y * -0.5 + 0.5,
    );

    if (shadow_uv.x < 0.0 || shadow_uv.x > 1.0 ||
        shadow_uv.y < 0.0 || shadow_uv.y > 1.0 ||
        sun_ndc.z < 0.0 || sun_ndc.z > 1.0) {
        return 1.0;
    }

    let receiver_bias = mix(0.000035, 0.00020, 1.0 - n_dot_l);
    let texel_size = 1.0 / SHADOW_MAP_SIZE;
    var visibility = 0.0;

    for (var y: i32 = -1; y <= 1; y += 1) {
        for (var x: i32 = -1; x <= 1; x += 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
            visibility += textureSampleCompare(
                shadow_map,
                shadow_sampler,
                shadow_uv + offset,
                sun_ndc.z - receiver_bias,
            );
        }
    }

    visibility /= 9.0;

    let edge_distance = min(
        min(shadow_uv.x, 1.0 - shadow_uv.x),
        min(shadow_uv.y, 1.0 - shadow_uv.y),
    );
    return mix(1.0, visibility, smoothstep(0.0, 0.02, edge_distance));
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let albedo = textureSample(g_albedo, g_sampler, in.uv).rgb;
    let normal = textureSample(g_normal, g_sampler, in.uv).rgb;
    let depth = textureSample(g_depth, g_sampler, in.uv);

    let ndc_x = in.uv.x * 2.0 - 1.0;
    let ndc_y = 1.0 - in.uv.y * 2.0;

    let ndc_far = vec4<f32>(ndc_x, ndc_y, 1.0, 1.0);
    let world_far_unprojected = camera.view_proj_inv * ndc_far;
    let world_far_pos = world_far_unprojected.xyz / world_far_unprojected.w;
    let view_dir = normalize(world_far_pos - camera.position);

    let sky_zenith = sun.sky_zenith.rgb;
    let sky_horizon = sun.sky_horizon.rgb;

    let sky_blend = clamp(max(view_dir.y, 0.0), 0.0, 1.0);
    let sky_color = mix(sky_horizon, sky_zenith, sky_blend);

    if (depth >= 1.0) {
        return vec4<f32>(sky_color, 1.0);
    }

    let ndc_pos = vec4<f32>(ndc_x, ndc_y, depth, 1.0);
    let world_unprojected = camera.view_proj_inv * ndc_pos;
    let world_position = world_unprojected.xyz / world_unprojected.w;

    let sun_height = sun.direction.w;
    let daylight = smoothstep(-0.12, 0.22, sun_height);
    let twilight_rise = smoothstep(-0.32, -0.02, sun_height);
    let twilight_fall = 1.0 - smoothstep(0.08, 0.38, sun_height);
    let twilight = twilight_rise * twilight_fall;
    let ambient_intensity = max(daylight, twilight * 0.45);
    let direct_intensity = smoothstep(0.0, 0.16, sun_height);
    var world_normal = vec3<f32>(0.0, 1.0, 0.0);
    if (dot(normal, normal) > 0.001) {
        world_normal = normalize(normal);
    }
    let light_direction = normalize(sun.direction.xyz);
    let n_dot_l = max(dot(world_normal, light_direction), 0.0);

    var shadow_visibility = 1.0;
    if (direct_intensity > 0.001 && n_dot_l > 0.0) {
        let sampled_visibility = sample_shadow(world_position, n_dot_l);
        shadow_visibility = mix(1.0, sampled_visibility, SHADOW_STRENGTH);
    }

    let sky_ambient = mix(sky_horizon, sky_zenith, 0.35) * 0.58;
    let ambient_day = mix(vec3<f32>(0.52), sky_ambient, AMBIENT_SKY_TINT);
    let ambient_night = vec3<f32>(0.08, 0.08, 0.035);
    let ambient_light = mix(ambient_night, ambient_day, ambient_intensity);

    let warm_sun = vec3<f32>(1.0, 0.32, 0.08);
    let noon_sun = vec3<f32>(1.0, 0.97, 0.88);
    let sun_color = mix(warm_sun, noon_sun, smoothstep(0.02, 0.35, sun_height));

    let ambient_color = albedo * ambient_light;
    let direct_color = albedo * sun_color * n_dot_l * direct_intensity * shadow_visibility;
    let lit_albedo = ambient_color + direct_color;
    
    let dist = length(camera.position - world_position);
    let fog_start = f32(render_config.render_distance * 9);
    let fog_end = fog_start + 10.0;
    let fog_factor = clamp((fog_end - dist) / (fog_end - fog_start), 0.0, 1.0);
    // let fog_color = vec3<f32>(0.333, 0.721, 1.0);

    let final_color = mix(sky_horizon, lit_albedo, fog_factor);

    return vec4<f32>(final_color, 1.0);
}
