// Instanced textured quads over a transparent surface. The atlas holds premultiplied colour
// and the pipeline blends with (ONE, ONE_MINUS_SRC_ALPHA), so everything stays premultiplied.

struct Uniforms {
    screen: vec2<f32>,
    _pad: vec2<f32>,
};

@group(0) @binding(0) var atlas_texture: texture_2d<f32>;
@group(0) @binding(1) var atlas_sampler: sampler;
@group(1) @binding(0) var<uniform> uniforms: Uniforms;

struct InstanceInput {
    @location(0) position: vec2<f32>,
    @location(1) size: vec2<f32>,
    // rotation, x scale, alpha, blend toward black
    @location(2) shape: vec4<f32>,
    // u, v, width, height of the leaf in the atlas
    @location(3) uv_rect: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) alpha: f32,
    @location(2) blend: f32,
};

@vertex
fn vs_main(@builtin(vertex_index) index: u32, instance: InstanceInput) -> VertexOutput {
    var corners = array<vec2<f32>, 6>(
        vec2<f32>(-0.5, -0.5), vec2<f32>(0.5, -0.5), vec2<f32>(0.5, 0.5),
        vec2<f32>(-0.5, -0.5), vec2<f32>(0.5, 0.5), vec2<f32>(-0.5, 0.5),
    );
    let corner = corners[index];
    let rotation = instance.shape.x;
    let x_scale = instance.shape.y;
    let local = vec2<f32>(corner.x * instance.size.x * x_scale, corner.y * instance.size.y);
    let c = cos(rotation);
    let s = sin(rotation);
    let world = instance.position + vec2<f32>(local.x * c - local.y * s, local.x * s + local.y * c);
    let ndc = world / uniforms.screen * 2.0 - vec2<f32>(1.0, 1.0);

    var out: VertexOutput;
    out.clip = vec4<f32>(ndc, 0.0, 1.0);
    // World y points up, texture v points down.
    out.uv = instance.uv_rect.xy + vec2<f32>(0.5 + corner.x, 0.5 - corner.y) * instance.uv_rect.zw;
    out.alpha = instance.shape.z;
    out.blend = instance.shape.w;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let texel = textureSample(atlas_texture, atlas_sampler, in.uv);
    let rgb = texel.rgb * (1.0 - in.blend);
    return vec4<f32>(rgb * in.alpha, texel.a * in.alpha);
}
