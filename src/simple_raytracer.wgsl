@group(0) @binding(0)
var t_target: texture_storage_2d<rgba8unorm, write>;

const VIEWPORT_SIZE: vec2<f32> = vec2(8.0, 8.0);

struct Sphere {
    @location(0) center: vec3<f32>,
    @location(1) radius: f32,
    @location(2) color: vec4<f32>,
}

@group(1) @binding(0)
var<storage, read> input: array<Sphere>;

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
}

fn compute_orthographic_viewing_ray(texCoords: vec2<u32>) -> Ray {
    return Ray(
        vec3(
            ((f32(texCoords.x) / 256.0) - 0.5) * VIEWPORT_SIZE.x,
            ((f32(texCoords.y) / 256.0) - 0.5) * VIEWPORT_SIZE.y,
            0.0
        ),
        vec3(0.0, 0.0, 1.0),
    );
}

fn ray_intersects_sphere(ray: Ray, sphere: Sphere) -> f32 {
    // Given a ray p(t) = e + td and a sphere with center c and radius R.
    // We can compute the intersection by solving the quadratiic equation
    // (d . d)t² + 2d . (e - c)t + (e - c) . (e - c) - R² = 0
    // At² + Bt + C = 0
    let origin_center = ray.origin - sphere.center;
    let A: f32 = dot(ray.direction, ray.direction); // Could probably be simplified to 1 for normalized vectors
    let B: f32 = dot(ray.direction * 2, origin_center);
    let C: f32 = dot(origin_center, origin_center) - pow(sphere.radius, 2.0);

    let discriminant: f32 = pow(B, 2.0) - (4.0 * A * C);

    if discriminant < 0.0 {
        return -1.0;
    } else {
        let num1: f32 = (-B - sqrt(discriminant)) / (2.0 * A);
        let num2: f32 = (-B + sqrt(discriminant)) / (2.0 * A);
        if num1 >= 0.0 && num2 >= 0.0 {
            return min(num1, num2);
        } else {
            return max(num1, num2);
        }
    }
}

@compute
@workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) global_invocation_id: vec3<u32>
) {
    let texCoords = global_invocation_id.xy;

    let ray = compute_orthographic_viewing_ray(texCoords);

    var color = vec4(0.1, 0.1, 0.1, 1.0);

    let inputSize = arrayLength(&input);
    var closestZ = 99999.0;
    for (var i = 0u; i < inputSize; i++) {
        let sphere = input[i];
        let t = ray_intersects_sphere(ray, sphere);
        if t > 0.0 && t < closestZ {
            color = sphere.color;
            closestZ = t;
        }
    }

    textureStore(t_target, texCoords, color);
}

