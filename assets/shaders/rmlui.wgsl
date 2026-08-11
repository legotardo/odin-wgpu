struct DrawUniform {
    viewport: vec2<f32>,
    translation: vec2<f32>,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) tex_coord: vec2<f32>,
}

@group(0) @binding(0) var<uniform> draw: DrawUniform;
@group(1) @binding(0) var ui_sampler: sampler;
@group(1) @binding(1) var ui_texture: texture_2d<f32>;

@vertex
fn vs_main(
    @location(0) position: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) tex_coord: vec2<f32>,
) -> VertexOutput {
    let screen_position = position + draw.translation;
    let clip_position = vec2<f32>(
        screen_position.x / draw.viewport.x * 2.0 - 1.0,
        1.0 - screen_position.y / draw.viewport.y * 2.0,
    );

    var output: VertexOutput;
    output.position = vec4<f32>(clip_position, 0.0, 1.0);
    output.color = color;
    output.tex_coord = tex_coord;
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return input.color * textureSample(ui_texture, ui_sampler, input.tex_coord);
}
