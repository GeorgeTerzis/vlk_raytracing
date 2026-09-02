module math;

import rand;

public static float PI = 3.14159265359;

public float3 cosine_hemisphere(float3 normal, inout uint seed) {
    let d = random_in_unit_disk(seed);
    let x = d.x;
    let y = d.y;
    let z = sqrt(max(0.0, 1.0 - x * x - y * y));

    let tangent = any_perpendicular(normal);
    let bitangent = normalize(cross(normal, tangent));

    return normalize(tangent * x + bitangent * y + normal * z);
}
public float3 cosine_hemisphere_u(float3 normal, float2 u) {
    let r = sqrt(u.x);
    let phi = 2.0 * PI * u.y;
    let lx = r * cos(phi);
    let ly = r * sin(phi);
    let lz = sqrt(max(0.0, 1.0 - u.x));

    float3 up = abs(normal.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
    let tangent = normalize(cross(up, normal));
    let bitangent = cross(normal, tangent);

    return normalize(tangent * lx + bitangent * ly + normal * lz);
}
float2 random_in_unit_disk(inout uint seed) {
    float r1 = random::unit(seed);
    float r2 = random::unit(seed);

    float theta = 2.0 * PI * r1;
    float radius = sqrt(r2);

    return float2(radius * cos(theta), radius * sin(theta));
}
public float3 random_in_unit_sphere(inout uint seed) {
    let theta = 2.0 * PI * random::unit(seed);
    let phi = acos(1.0 - 2.0 * random::unit(seed));
    let r = pow(random::unit(seed), 1.0 / 3.0);
    return float3(r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi));
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

public float3 bary_interpolate(float3 v0, float3 v1, float3 v2, float2 bary) {
    return v0 * (1.0 - bary.x - bary.y) + v1 * bary.x + v2 * bary.y;
}

public float schlick_weight(float cos_theta) {
    float m = saturate(1.0 - cos_theta);
    return m * m * m * m * m;
}

public float r0(float ior) {
    let n = (1.0 - ior) / (1.0 + ior);
    return n * n;
}

public T fresnel<T : IFloat>(T f0, float cos_theta) {
    return f0 + (T(1.0) - f0) * T(schlick_weight(cos_theta));
}

public float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float2 oct_wrap(float2 v) {
    return (float2(1.0) - abs(v.yx)) *
           float2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

public uint oct_encode(float3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    float2 enc = n.z >= 0.0 ? n.xy : oct_wrap(n.xy);
    enc = enc * 0.5 + 0.5;
    uint2 u = uint2(saturate(enc) * 65535.0 + 0.5);
    return u.x | (u.y << 16);
}

public float3 oct_decode(uint packed) {
    float2 enc = float2(packed & 0xFFFF, packed >> 16) / 65535.0 * 2.0 - 1.0;
    float3 n = float3(enc.x, enc.y, 1.0 - abs(enc.x) - abs(enc.y));
    float t = saturate(-n.z);
    n.xy += select(n.xy >= float2(0.0), float2(-t), float2(t));
    return normalize(n);
}

