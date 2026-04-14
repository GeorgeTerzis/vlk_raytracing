module principled;

import surface;
import math;
import rand;
import material;
import state;

public float schlick_weight(float cos_theta, float p) {
    float m = saturate(1.0 - cos_theta);
    return pow(m, p);
}
public float schlick_weight(float cos_theta) {
    float m = saturate(1.0 - cos_theta);
    return pow(m, 5);
}
public float3 fresnel(float3 f0, float cos_theta) {
    return f0 + (1.0 - f0) * pow(1.0 - cos_theta, 5.0);
}
public float fresnel(float f0, float cos_theta) {
    return f0 + (1.0 - f0) * pow(1.0 - cos_theta, 5.0);
}

public float3 fresnel_conductor(float cosTheta, float3 eta, float3 k) {
    cosTheta = clamp(cosTheta, 0.0, 1.0);

    float cos2 = cosTheta * cosTheta;
    float sin2 = 1.0 - cos2;

    float3 eta2 = eta * eta;
    float3 k2 = k * k;

    float3 t0 = eta2 - k2 - float3(sin2);
    float3 a2plusb2 = sqrt(t0 * t0 + 4.0 * eta2 * k2);
    float3 t1 = a2plusb2 + float3(cos2);
    float3 a = sqrt(0.5 * (a2plusb2 + t0));
    float3 t2 = 2.0 * cosTheta * a;

    float3 Rs = (t1 - t2) / (t1 + t2);

    float3 t3 = cos2 * a2plusb2 + float3(sin2 * sin2);
    float3 t4 = t2 * sin2;

    float3 Rp = Rs * (t3 - t4) / (t3 + t4);

    return 0.5 * (Rs + Rp);
}

public float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float3 to_local_vndf(float3 v, float3 n, float3 t, float3 b) {
    return float3(dot(v, t), dot(v, n), dot(v, b));
}
float3 to_world_vndf(float3 v, float3 n, float3 t, float3 b) {
    return t * v.x + n * v.y + b * v.z;
}
// float3 to_local(float3 v, float3 n, float3 t, float3 b) {
//     return float3(dot(v, t), dot(v, b), dot(v, n));
// }
// float3 to_world(float3 v, float3 normal, float3 tangent, float3 bitangent) {
//     return tangent * v.x + bitangent * v.y + normal * v.z;
// }

// float3 to_local(float3 v, Surface surface) {
//     return to_local(v, surface.normal, surface.tangent, surface.bitangent);
// }
// float3 to_world(float3 v, Surface surface) {
//     return to_world(v, surface.normal, surface.tangent, surface.bitangent);
// }
float3 to_local_vndf(float3 v, Surface surface) {
    return to_local_vndf(v, surface.normal, surface.tangent, surface.bitangent);
}
float3 to_world_vndf(float3 v, Surface surface) {
    return to_world_vndf(v, surface.normal, surface.tangent, surface.bitangent);
}

// static float ggx_D(Surface surface, float a, float3 h) {
//     let hl = to_local(h, surface.normal, surface.tangent, surface.bitangent);
//     float a2 = a * a;
//     float NdotH = max(hl.z, 1e-5);
//     float denom = PI * pow(NdotH * NdotH * (a2 - 1) + 1, 2);
//     return a2 / denom;
// }
float3 sample_GGX_VNDF(Surface surface, float3 view, float2 alpha, float2 u) {
    float3 V = to_local_vndf(view, surface);
    float3 Vh = normalize(float3(alpha.x * V.x, alpha.y * V.y, V.z));
    float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
    float3 T1 =
        lensq > 0.0 ? float3(-Vh.y, Vh.x, 0.0) / sqrt(lensq) : float3(1.0, 0.0, 0.0);
    float3 T2 = cross(Vh, T1);

    float r = sqrt(u.x);
    float phi = 2.0 * PI * u.y;

    float t1 = r * cos(phi);
    float t2 = r * sin(phi);

    float s = 0.5 * (1.0 + Vh.z);
    t2 = (1.0 - s) * sqrt(max(0.0, 1.0 - t1 * t1)) + s * t2;

    float3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * Vh;
    float3 H = normalize(float3(alpha.x * Nh.x, alpha.y * Nh.y, max(0.0, Nh.z)));

    return to_world_vndf(H, surface);
}
float BsdfNDot(float3 w_local) {
    return w_local.y;
}

public struct VNDF {
    // https://schuttejoe.github.io/post/ggximportancesamplingpart2/
    public static let XAxis_ = float3(1, 0, 0);
    public static let YAxis_ = float3(0, 1, 0);
    public static let ZAxis_ = float3(0, 0, 1);

    float ggx_D(float3 wm, float a2) {
        float NoH = max(wm.y, 1e-5);
        float NoH2 = NoH * NoH;

        float denom = NoH2 * (a2 - 1.0f) + 1.0f;
        return a2 / (PI * denom * denom);
    }

    float sample_pdf(float3 wo, float3 wi, float3 wm, float a2) {
        float NoV = max(wo.y, 1e-5);
        float NoL = wi.y;

        // must be same hemisphere
        if (NoL <= 0.0f)
            return 0.0f;

        float VoH = max(dot(wo, wm), 1e-5);

        float D = ggx_D(wm, a2);
        float G1 = SmithGGXMasking(wo, wo, a2);

        return (D * G1) / (NoV * 4.0f);
    }
    static public float SmithGGXMasking(float3 wi, float3 wo, float a2) {
        float dotNL = BsdfNDot(wi);
        float dotNV = BsdfNDot(wo);

        float denomC = sqrt(a2 + (1.0f - a2) * dotNV * dotNV) + dotNV;
        return 2.0f * dotNV / denomC;
    }
    static public float SmithGGXMaskingShadowing(float3 wi, float3 wo, float a2) {
        float dotNL = BsdfNDot(wi);
        float dotNV = BsdfNDot(wo);
        float denomA = dotNV * sqrt(a2 + (1.0f - a2) * dotNL * dotNL);
        float denomB = dotNL * sqrt(a2 + (1.0f - a2) * dotNV * dotNV);

        return 2.0f * dotNL * dotNV / (denomA + denomB);
    }
    static public float3 GgxVndf(float3 wo, float roughness, float2 u) {
        float3 v = normalize(float3(wo.x * roughness, wo.y, wo.z * roughness));

        float3 t1 = (v.y < 0.999f) ? normalize(cross(v, YAxis_)) : XAxis_;
        float3 t2 = cross(t1, v);
        float a = 1.0f / (1.0f + v.y);
        float r = sqrt(u.x);
        float phi = (u.y < a) ? (u.y / a) * PI : PI + (u.y - a) / (1.0f - a) * PI;
        float p1 = r * cos(phi);
        float p2 = r * sin(phi) * ((u.y < a) ? 1.0f : v.y);
        float3 n = p1 * t1 + p2 * t2 + sqrt(max(0.0f, 1.0f - p1 * p1 - p2 * p2)) * v;
        return normalize(float3(roughness * n.x, max(0.0f, n.y), roughness * n.z));
    }
};

public struct Principled : Material {
    public struct conductor_params {
        public float3 eta;
        public float3 k;
    };

    public struct diffuse_pararms {
        public float3 color = float3(0.8);
        public float subsurface = 0;
    };

    public struct sheen_params {
        public float weight = 0;
        public float tint = 0;
    };

    public struct specular_params {
        public float weight = 0;
        public float tint = 0;
        public float3 tint_color = 0;
    };

    public struct clearcoat_params {
        public float weight = 0;
        public float gloss = 1;
    };

    public float roughness = 0.5;
    public float metallic = 0;

    public diffuse_pararms pdiffuse;
    public sheen_params psheen;
    public specular_params pspecular;
    public clearcoat_params pclearcoat;


    struct Diffuse {
        static float3 sample_direction(float3 normal, inout uint seed) {
            return cosine_hemisphere(normal, seed);
        }
        static float sample_pdf(float NoL) {
            return NoL / PI;
        }
        static float Fd_90(float roughness, float3 half, float3 dir) {
            return (1.0 / 2.0) + 2 * roughness* pow(dot(dir, half), 2);
        }
        static float Fd(float roughness, float3 n, float3 w, float3 h, float3 wo) {
            float ndw = abs(dot(n, w));
            float fd90 = Fd_90(roughness, h, wo);
            return 1.0 + (fd90 - 1.0) * pow(1.0 - ndw, 5);
        }
        static float3 diffuse_bsdf(float3 albedo,
                                   float roughness,
                                   float3 n,
                                   float3 view,
                                   float3 dir,
                                   float3 half) {
            let fd_out = Fd(roughness, n, view, half, dir);
            let fd_in = Fd(roughness, n, dir, half, view);
            let f = (albedo)*fd_in * fd_out;
            return f;
        }

        static float Fss_90(float roughness, float3 view, float3 half) {
            return roughness * pow(dot(half, view), 2);
        }
        static float
        Fss(float3 normal, float roughness, float3 w, float3 view, float3 half) {
            return 1 + (1 + (Fss_90(roughness, view, half) - 1) * (1 - dot(normal, w)));
        }

        static float3 subsurface_bsdf(float3 albedo,
                                      float roughness,
                                      float3 normal,
                                      float3 view,
                                      float3 dir,
                                      float3 half) {
            let fss = Fss(normal, roughness, dir, view, half) *
                      Fss(normal, roughness, view, view, half);
            let denom = max(dot(normal, dir) + dot(normal, view), 1e-5);
            let absorption = (1.0 / denom) - 0.5;
            let f = ((1.25 * albedo) / PI) * (fss * absorption + 0.5);
            return f;
        }
    };

    struct Clearcoat {
        static float ag(float clearcoat_roughness) {
            return (1 - clearcoat_roughness) * 0.1 + clearcoat_roughness * 0.001;
        }
        static float R0(float ior) {
            let f = (ior - 1) / (ior + 1);
            return f * f;
        }
    };

    struct Sheen {
        static float3 Csheen(float3 albedo, float sheen_tint) {
            let ctint = luminance(albedo) > 0.0 ? albedo / luminance(albedo) : float3(1);
            return (1.0 - sheen_tint) + sheen_tint * ctint;
        }

        static float3 bsdf(float3 albedo, float sheen_tint, float HoV) {
            let schlick = pow(1.0 - HoV, 5.0);
            return Csheen(albedo, sheen_tint) * schlick;
        }

        static float3 eval(float3 albedo,
                           float sheen_weight,
                           float sheen_tint,
                           float3 normal,
                           float3 half,
                           float3 view,
                           float3 dir) {
            if (sheen_weight <= 0.0)
                return float3(0);
            let NoL = max(dot(normal, dir), 1e-5);
            let HoL = max(dot(half, dir), 1e-5);
            return (sheen_weight)*bsdf(albedo, sheen_tint, HoL);
        }
    };

    public void scatter(Surface surface, inout State state) {
        let view = -state.ray.Direction;
        let NoV = max(dot(surface.normal, view), 1e-5);


        let lum = dot(pdiffuse.color, float3(0.2126, 0.7152, 0.0722));
        let ed = (1.0 - metallic) * lum;
        let es = lerp(0.04, 1.0, metallic);
        let ec = 0.04 * pclearcoat.weight;
        let total = max(ed + es + ec, 1e-6);

        let pd = ed / total;
        let ps = es / total;
        let pc = ec / total;

        let r = random::unit(state.seed);
        let u = float2(random::unit(state.seed), random::unit(state.seed));
        if (r < pd) {
            let dir = Diffuse::sample_direction(surface.normal, state.seed);
            let half = normalize(view + dir);

            let NoL = max(dot(surface.normal, dir), 1e-5);
            let diffuse = Diffuse::diffuse_bsdf(pdiffuse.color,
                                                roughness,
                                                surface.normal,
                                                view,
                                                dir,
                                                half);
            let subsurface = Diffuse::subsurface_bsdf(pdiffuse.color,
                                                      roughness,
                                                      surface.normal,
                                                      view,
                                                      dir,
                                                      half);
            let sheen = Sheen::eval(pdiffuse.color,
                                    psheen.weight,
                                    psheen.tint,
                                    surface.normal,
                                    half,
                                    view,
                                    dir);

            let d =
                (1 - pdiffuse.subsurface) * diffuse + pdiffuse.subsurface * subsurface;

            let base = d;
            let sheen_term = psheen.weight * sheen;

            let f = (base + sheen_term) / PI;

            let pdf = Diffuse::sample_pdf(NoL);
            if (pdf < 1e-6) {
                state.throughput = float3(0);
                return;
            }

            state.throughput *= f * NoL / (pdf * pd);
            state.ray.Direction = dir;
        } else if (r < pd + ps) {
            let a = roughness;
            let a2 = a * a;
            let wo_local = to_local_vndf(view, surface);
            let wm_local = VNDF::GgxVndf(wo_local, a, u);
            let wi_local = reflect(-wo_local, wm_local);
            let wi_world = to_world_vndf(wi_local, surface);

            state.ray.Direction = wi_world;
            if (BsdfNDot(wi_local) <= 0.0f) {
                state.throughput *= float3(0);
                return;
            }
            let VoH = max(dot(wi_local, wm_local), 1e-5);
            let specular_color = float3(1.0, 0.71, 0.29);

            float3 F0 = lerp(float3(0.04), pspecular.tint_color, metallic);
            float3 F = fresnel(F0, VoH);

            let G1 = VNDF::SmithGGXMasking(wi_local, wo_local, a2);
            let G2 = VNDF::SmithGGXMaskingShadowing(wi_local, wo_local, a2);
            state.throughput *= (F * (G2 / G1)) / ps;
        } else  {
            let a = Clearcoat::ag(pclearcoat.gloss);
            let a2 = a * a;
            let wo_local = to_local_vndf(view, surface);
            let wm_local = VNDF::GgxVndf(wo_local, a, u);
            let wi_local = reflect(-wo_local, wm_local);
            let wi_world = to_world_vndf(wi_local, surface);
            state.ray.Direction = wi_world;
            if (BsdfNDot(wi_local) <= 0.0f) {
                state.throughput *= float3(0);
                return;
            }

            let VoH = max(dot(wo_local, wm_local), 1e-5);
            static let F0 = Clearcoat::R0(1.5);
            let F = fresnel(F0, VoH);

            let G1 = VNDF::SmithGGXMasking(wi_local, wo_local, a2);
            let G2 = VNDF::SmithGGXMaskingShadowing(wi_local, wo_local, a2);
            state.throughput *= (pclearcoat.weight * F * (G2 / G1)) / pc;
        }
        // else {
        // glass
        // scatter_glass(surface, state);
        // }
    }
}
