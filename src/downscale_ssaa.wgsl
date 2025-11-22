
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
    let src_x = dst_x * 4u;
    let src_y = dst_y * 4u;

    let c00 = textureLoad(hi_res, vec2<i32>(i32(src_x + 0u), i32(src_y + 0u)), 0);
    let c01 = textureLoad(hi_res, vec2<i32>(i32(src_x + 1u), i32(src_y + 0u)), 0);
    let c02 = textureLoad(hi_res, vec2<i32>(i32(src_x + 2u), i32(src_y + 0u)), 0);
    let c03 = textureLoad(hi_res, vec2<i32>(i32(src_x + 3u), i32(src_y + 0u)), 0);
    let c10 = textureLoad(hi_res, vec2<i32>(i32(src_x + 0u), i32(src_y + 1u)), 0);
    let c11 = textureLoad(hi_res, vec2<i32>(i32(src_x + 1u), i32(src_y + 1u)), 0);
    let c12 = textureLoad(hi_res, vec2<i32>(i32(src_x + 2u), i32(src_y + 1u)), 0);
    let c13 = textureLoad(hi_res, vec2<i32>(i32(src_x + 3u), i32(src_y + 1u)), 0);
    let c20 = textureLoad(hi_res, vec2<i32>(i32(src_x + 0u), i32(src_y + 2u)), 0);
    let c21 = textureLoad(hi_res, vec2<i32>(i32(src_x + 1u), i32(src_y + 2u)), 0);
    let c22 = textureLoad(hi_res, vec2<i32>(i32(src_x + 2u), i32(src_y + 2u)), 0);
    let c23 = textureLoad(hi_res, vec2<i32>(i32(src_x + 3u), i32(src_y + 2u)), 0);
    let c30 = textureLoad(hi_res, vec2<i32>(i32(src_x + 0u), i32(src_y + 3u)), 0);
    let c31 = textureLoad(hi_res, vec2<i32>(i32(src_x + 1u), i32(src_y + 3u)), 0);
    let c32 = textureLoad(hi_res, vec2<i32>(i32(src_x + 2u), i32(src_y + 3u)), 0);
    let c33 = textureLoad(hi_res, vec2<i32>(i32(src_x + 3u), i32(src_y + 3u)), 0);

    let avg = (c00 + c01 + c02 + c03 + c10 + c11 + c12 + c13 + c20 + c21 + c22 + c23 + c30 + c31 + c32 + c33) * 0.0625;

    textureStore(out_img, vec2<i32>(i32(dst_x), i32(dst_y)), avg);
}
