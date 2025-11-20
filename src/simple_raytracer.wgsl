@group(0) @binding(0)
var t_target: texture_storage_2d<rgba8unorm, write>;

const VIEWPORT_SIZE: vec2<f32> = vec2(8.0, 8.0);
const MISS = -1.0;

struct Sphere {
    center: vec4<f32>,
    color: vec4<f32>,
    radius: f32,
}

struct Triangle {
    vertex1: vec4<f32>,
    vertex2: vec4<f32>,
    vertex3: vec4<f32>,
    color: vec4<f32>,
}

@group(1) @binding(0)
var<storage, read> spheres: array<Sphere>;
@group(1) @binding(1)
var<storage, read> triangles: array<Triangle>;

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
    let origin_center = ray.origin - sphere.center.xyz;
    let A: f32 = dot(ray.direction, ray.direction); // Could probably be simplified to 1 for normalized vectors
    let B: f32 = dot(ray.direction * 2, origin_center);
    let C: f32 = dot(origin_center, origin_center) - pow(sphere.radius, 2.0);

    let discriminant: f32 = pow(B, 2.0) - (4.0 * A * C);

    if discriminant < 0.0 {
        return MISS;
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

fn ray_intersects_triangle(ray: Ray, triangle: Triangle) -> f32 {
    // Given a ray p(t) = e + td and a triangle with vertices as vectors a, b, c.
    // The ray intersects with the triangle if there exists beta and gamma for which
    // e + td = a + beta * (b - a) + gamma * (c - a)
    // => mat3x3(a - b, a - c, d) * vec3(beta, gamma, t) = a - e
    // and beta + gamma <= 1.0
    //
    // [ a, d, g ]   [ beta  ]   [ j ]
    // [ b, e, h ] * [ gamma ] = [ k ]
    // [ c, f, i ]   [   t   ]   [ l ]
    let a = triangle.vertex1.x - triangle.vertex2.x;
    let b = triangle.vertex1.y - triangle.vertex2.y;
    let c = triangle.vertex1.z - triangle.vertex2.z;
    let d = triangle.vertex1.x - triangle.vertex3.x;
    let e = triangle.vertex1.y - triangle.vertex3.y;
    let f = triangle.vertex1.z - triangle.vertex3.z;
    let g = ray.direction.x;
    let h = ray.direction.y;
    let i = ray.direction.z;
    let j = triangle.vertex1.x - ray.origin.x;
    let k = triangle.vertex1.y - ray.origin.y;
    let l = triangle.vertex1.z - ray.origin.z;

    let ei_minus_hf = e * i - h * f;
    let gf_minus_di = g * f - d * i;
    let dh_minus_eg = d * h - e * g;
    let ak_minus_jb = a * k - j * b;
    let jc_minus_al = j * c - a * l;
    let bl_minus_kc = b * l - k * c;

    let M = a * ei_minus_hf + b * gf_minus_di + c * dh_minus_eg;

    let t = -(f * ak_minus_jb + e * jc_minus_al + d * bl_minus_kc) / M;
    if t < 0.0 {
        return MISS;
    }
    let gamma = (i * ak_minus_jb + h * jc_minus_al + g * bl_minus_kc) / M;
    if gamma < 0.0 || gamma > 1.0 {
        return MISS;
    }
    let beta = (j * ei_minus_hf + k * gf_minus_di + l * dh_minus_eg) / M;
    if beta < 0.0 || beta > 1.0 - gamma {
        return MISS;
    }
    return t;
}

@compute
@workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) global_invocation_id: vec3<u32>
) {
    let texCoords = global_invocation_id.xy;

    let ray = compute_orthographic_viewing_ray(texCoords);

    var color = vec4(0.1, 0.1, 0.1, 1.0);

    let spheresSize = arrayLength(&spheres);
    var closestZ = 99999.0;
    for (var i = 0u; i < spheresSize; i++) {
        let sphere = spheres[i];
        let t = ray_intersects_sphere(ray, sphere);
        if t > 0.0 && t < closestZ {
            color = sphere.color * (1.0 - t / 6.0);
            closestZ = t;
        }
    }
    let trianglesSize = arrayLength(&triangles);
    for (var i = 0u; i < trianglesSize; i++) {
        let triangle = triangles[i];
        let t = ray_intersects_triangle(ray, triangle);
        if t > 0.0 && t < closestZ {
            color = triangle.color * (1.0 - t / 6.0);
            closestZ = t;
        }
    }

    textureStore(t_target, texCoords, color);
}

