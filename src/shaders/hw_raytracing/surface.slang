module surface;

import math;

public struct Surface {
    public float3 geometric_normal;
    public float3 raw_normal;
    public float3 normal;
    public float3 tangent;
    public float3 bitangent;
    public bool is_backface;

public static Surface make(float3 geometric_normal, float3 raw_normal) {
    float3 geoN = normalize(geometric_normal);
    float3 n = normalize(raw_normal);
    let is_backface = dot(WorldRayDirection(), geoN) > 0.0;
    if (dot(n, geoN) < 0.0)
        n = -n;

    let normal = is_backface ? -n : n;

    let tangent = any_perpendicular(normal);
    let bitangent = normalize(cross(normal, tangent));

    return Surface(geoN, raw_normal, normal, tangent, bitangent, is_backface);
}};
