module math;

import rand;

public static float PI = 3.14159265359;

public float3 cosine_hemisphere(float3 normal, inout uint seed) {
    let r1 = random::unit(seed);
    let r2 = random::unit(seed);

    let phi = 2.0 * PI * r1;
    let r = sqrt(r2);

    let x = r * cos(phi);
    let y = r * sin(phi);
    let z = sqrt(1.0 - r2);

    let tangent = any_perpendicular(normal);
    let bitangent = normalize(cross(normal, tangent));

    return normalize(tangent * x + bitangent * y + normal * z);
}

public float3 bias_vector(float3 vec, float3 vec_origin, float3 bias_point, float k) {
    float3 target_dir = normalize(bias_point - vec_origin);
    return normalize(vec + target_dir * k);
}

public float3 unit_vector(float3 v) {
    return v / length(v);
}

public float3 any_perpendicular(float3 n) {
    return normalize(abs(n.x) > abs(n.z) ? (float3(-n.y, n.x, 0.0))
                                         : (float3(0.0, -n.z, n.y)));
}


