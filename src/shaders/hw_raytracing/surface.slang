module surface;

import math;

public struct Surface {
    public float3 raw_normal;
    public float3 normal;
    public float3 tangent;
    public float3 bitangent;
    public bool is_backface;

    public static Surface make(float3 n) {
        n = normalize(n);
        let raw_normal = n;
        let is_backface = dot(WorldRayDirection(), n) > 0.0;
        let normal = is_backface ? -n : n;
        let tangent = any_perpendicular(normal);
        let bitangent = normalize(cross(normal, tangent));
        return Surface (raw_normal, normal, tangent, bitangent, is_backface);
    }
};
