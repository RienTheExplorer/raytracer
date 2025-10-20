@group(0) @binding(0)
var t_target: texture_storage_2d<rgba8unorm, write>;

@compute
@workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) global_invocation_id: vec3<u32>
) {
    let texCoords = global_invocation_id.xy;

    textureStore(t_target, texCoords, vec4(0.0, 1.0, 0.0, 1.0));
}

