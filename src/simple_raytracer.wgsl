@group(0) @binding(0)
var t_target: texture_storage_2d<rgba8unorm, write>;

const VIEWPORT_SIZE: vec2<f32> = vec2(8.0, 8.0);
const MISS = -1.0;
const MAXT = 9999.0;

struct Surface {
    diffuse_color: vec4<f32>,
    specular_color: vec4<f32>,
    specular_intensity: f32,
}

struct Sphere {
    center: vec4<f32>,
    surface: Surface,
    radius: f32,
}

struct Triangle {
    vertex1: vec4<f32>,
    vertex2: vec4<f32>,
    vertex3: vec4<f32>,
    surface: Surface,
}

@group(1) @binding(0)
var<storage, read> spheres: array<Sphere>;
@group(1) @binding(1)
var<storage, read> triangles: array<Triangle>;

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
}
struct Hit {
    intersection_point: vec3<f32>,
    normal: vec3<f32>,
    surface: Surface,
}

struct Light {
    position: vec3<f32>,
    intensity: f32,
}

fn compute_orthographic_viewing_ray(texCoords: vec2<u32>) -> Ray {
    return Ray(
        vec3(
            ((f32(texCoords.x) / (256.0 * 2.0)) - 0.5) * VIEWPORT_SIZE.x,
            ((f32(texCoords.y) / (256.0 * 2.0)) - 0.5) * VIEWPORT_SIZE.y,
            0.0
        ),
        vec3(0.0, 0.0, 1.0),
    );
}

fn compute_perspective_viewing_ray(texCoords: vec2<u32>, focalLength: f32) -> Ray {
    let image_plane_coord = vec3(
        ((f32(texCoords.x) / (256.0 * 2.0)) - 0.5) * VIEWPORT_SIZE.x,
        ((f32(texCoords.y) / (256.0 * 2.0)) - 0.5) * VIEWPORT_SIZE.y,
        0.0
    );
    let origin = vec3(0.0, 0.0, -focalLength);
    return Ray(
        origin,
        normalize(image_plane_coord - origin)
    );
}

fn ray_intersects_sphere(ray: Ray, sphere: Sphere, t0: f32, t1: f32) -> f32 {
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
        let num = select(
            max(num1, num2),
            min(num1, num2),
            num1 >= t0 && num2 >= t0
        );
        return select(-1.0, num, num < t1);
    }
}

fn surface_normal_sphere(intersection_point: vec3<f32>, sphere: Sphere) -> vec3<f32> {
    return normalize(intersection_point - sphere.center.xyz);
}

fn ray_intersects_triangle(ray: Ray, triangle: Triangle, t0: f32, t1: f32) -> f32 {
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
    if t < t0 || t > t1 {
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

fn surface_normal_triangle(intersection_point: vec3<f32>, triangle: Triangle) -> vec3<f32> {
    return normalize(cross(triangle.vertex2.xyz - triangle.vertex1.xyz, triangle.vertex3.xyz - triangle.vertex1.xyz));
}

fn shade_lambert(hit: Hit, light: Light) -> vec4<f32> {
    return vec4(hit.surface.diffuse_color.xyz * light.intensity * max(0.0,
        dot(hit.normal, normalize(light.position - hit.intersection_point))), hit.surface.diffuse_color.w);
}

fn shade_blinn_phong(hit: Hit, light: Light, viewing_ray: Ray) -> vec4<f32> {
    let light_direction = normalize(light.position - hit.intersection_point);
    let half_vector = normalize(light_direction - viewing_ray.direction);
    return vec4(hit.surface.diffuse_color.xyz * light.intensity * max(0.0, dot(hit.normal, light_direction)) + hit.surface.specular_color.xyz * light.intensity * pow(max(0.0, dot(hit.normal, half_vector)), hit.surface.specular_intensity), hit.surface.diffuse_color.w);
}

@compute
@workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) global_invocation_id: vec3<u32>
) {
    let texCoords = global_invocation_id.xy;

    let light = Light(
        vec3(-5.0, -4.0, -8.0),
        0.8,
    );

    //let ray = compute_orthographic_viewing_ray(texCoords);
    let ray = compute_perspective_viewing_ray(texCoords, 20.0);

    var color = vec4(0.1, 0.1, 0.1, 1.0);

    let spheresSize = arrayLength(&spheres);
    var t1 = MAXT;
    var hit = Hit(
        vec3(0.0, 0.0, 0.0),
        vec3(0.0, 0.0, 0.0),
        Surface(
            vec4(0.0, 0.0, 0.0, 1.0),
            vec4(0.0, 0.0, 0.0, 1.0),
            0.0,
        ),
    );
    for (var i = 0u; i < spheresSize; i++) {
        let sphere = spheres[i];
        let t = ray_intersects_sphere(ray, sphere, 0.0, t1);
        if t > 0.0 && t < t1 {
            hit.surface = sphere.surface;
            t1 = t;
            hit.intersection_point = ray.origin + ray.direction * t;
            hit.normal = surface_normal_sphere(hit.intersection_point, sphere);
        }
    }
    let trianglesSize = arrayLength(&triangles);
    for (var i = 0u; i < trianglesSize; i++) {
        let triangle = triangles[i];
        let t = ray_intersects_triangle(ray, triangle, 0.0, t1);
        if t > 0.0 && t < t1 {
            hit.surface = triangle.surface;
            t1 = t;
            hit.intersection_point = ray.origin + ray.direction * t;
            hit.normal = surface_normal_triangle(hit.intersection_point, triangle);
        }
    }
    if t1 != MAXT {
        //color = shade_lambert(hit, light);
        color = shade_blinn_phong(hit, light, ray);
    }

    textureStore(t_target, texCoords, color);
}

