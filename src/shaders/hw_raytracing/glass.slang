module glass;

import material;
import surface;
import state;
import math;
import rand;

public struct Glass : Material {
    public float3 absorbtion;
    public float ior = 1.4;
    public float roughness = 0.0;
    public float k = 1.0;

    float3 specular(float3 I, float3 N, float roughness, inout uint seed) {
        float3 reflected = reflect(I, N);
        reflected = normalize(reflected + cosine_hemisphere(reflected, seed) * roughness);
        return reflected ;
    }

    float3 refraction(float3 I, float3 N, float eta, float roughness, inout uint seed) {
        var refracted = refract(I, N, eta);
        let noise = cosine_hemisphere(refracted, seed) * roughness;
        return normalize(refracted + noise);
    }

    public void scatter(Surface surface, inout State payload) {
        let N = surface.normal;
        let I = normalize(payload.ray.Direction);
        let is_backface = surface.is_backface;

        var eta = is_backface ? ior : (1.0 / ior);

        if (!is_backface) {
            payload.inside_medium = true;
            payload.medium_t = RayTCurrent();
        } else if (payload.inside_medium) {
            payload.inside_medium = false;
            let dist = RayTCurrent() - payload.medium_t;
            payload.throughput *= exp(-(absorbtion * k) * dist);
        }

        let cos_theta = min(dot(-I, N), 1.0);
        let sin_theta = sqrt(max(0.0, 1.0 - cos_theta * cos_theta));
        let R0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
        let reflect_prob = fresnel(R0, cos_theta);
        let cannot_refract = eta * sin_theta > 1.0;
        let should_reflect = cannot_refract || (random::unit(payload.seed) < reflect_prob);

        if (should_reflect) {
            payload.ray.Direction = specular(I, N, roughness, payload.seed);
        } else {
            payload.ray.Direction = refraction(I, N, eta, roughness, payload.seed);
        }
    }
};
