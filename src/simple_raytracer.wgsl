@group(0) @binding(0)
var t_target: texture_storage_2d<rgba8unorm, write>;


struct InputData {
    @location(0) center: vec3<f32>,
    @location(1) radius: f32,
    @location(2) color: vec4<f32>,
}

@group(1) @binding(0)
var<storage, read> input: array<InputData>;

@compute
@workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) global_invocation_id: vec3<u32>
) {
    let texCoords = global_invocation_id.xy;

    let color = input[0].color;

    textureStore(t_target, texCoords, color);
}

