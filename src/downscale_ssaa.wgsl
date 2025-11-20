
@group(0) @binding(0)
var hi_res: texture_2d<f32>;

@group(0) @binding(1)
var out_img: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dst_x = gid.x;
    let dst_y = gid.y;

    // Bounds check
    if dst_x >= 256u || dst_y >= 256u {
        return;
    }

    // 2×2 block in source texture
    let src_x = dst_x * 2u;
    let src_y = dst_y * 2u;

    let c0 = textureLoad(hi_res, vec2<i32>(i32(src_x), i32(src_y)), 0);
    let c1 = textureLoad(hi_res, vec2<i32>(i32(src_x + 1u), i32(src_y)), 0);
    let c2 = textureLoad(hi_res, vec2<i32>(i32(src_x), i32(src_y + 1u)), 0);
    let c3 = textureLoad(hi_res, vec2<i32>(i32(src_x + 1u), i32(src_y + 1u)), 0);

    let avg = (c0 + c1 + c2 + c3) * 0.25;

    textureStore(out_img, vec2<i32>(i32(dst_x), i32(dst_y)), avg);
}
