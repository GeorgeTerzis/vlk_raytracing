module principled;

import lobe;
import surface;
import math;
import rand;
import material;
import state;

float3 to_local_vndf(float3 v, float3 n, float3 t, float3 b) {
    return float3(dot(v, t), dot(v, n), dot(v, b));
}
float3 to_world_vndf(float3 v, float3 n, float3 t, float3 b) {
    return t * v.x + n * v.y + b * v.z;
}
float3 to_local_vndf(float3 v, Surface surface) {
    return to_local_vndf(v, surface.normal, surface.tangent, surface.bitangent);
}
float3 to_world_vndf(float3 v, Surface surface) {
    return to_world_vndf(v, surface.normal, surface.tangent, surface.bitangent);
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
// static float ggx_D(Surface surface, float a, float3 h) {
//     let hl = to_local(h, surface.normal, surface.tangent, surface.bitangent);
//     float a2 = a * a;
//     float NdotH = max(hl.z, 1e-5);
//     float denom = PI * pow(NdotH * NdotH * (a2 - 1) + 1, 2);
//     return a2 / denom;
// }

// https://schuttejoe.github.io/post/ggximportancesamplingpart1/
// https://schuttejoe.github.io/post/ggximportancesamplingpart2/
float BsdfNDot(float3 w_local) {
    return w_local.y;
}
public struct VNDF {
    public static let XAxis_ = float3(1, 0, 0);
    public static let YAxis_ = float3(0, 1, 0);
    public static let ZAxis_ = float3(0, 0, 1);

    public static float ggx_D(float3 wm, float a2) {
        let NoH = max(wm.y, 1e-4);
        let NoH2 = NoH * NoH;
        let denom = NoH2 * (a2 - 1.0) + 1.0;
        return a2 / (PI * denom * denom);
    }

    public static float sample_pdf(float3 wo, float3 wi, float3 wm, float a2) {
        let NoV = max(wo.y, 1e-4);
        let NoL = wi.y;

        if (NoL <= 0.0f)
            return 0.0f;

        float VoH = max(dot(wo, wm), 1e-5);

        float D = ggx_D(wm, a2);
        float G1 = SmithGGXMasking(wo, wo, a2);

        return (D * G1) / (NoV * 4.0f);
    }

    static public float SmithGGXMasking(float3 wi, float3 wo, float a2) {
        float dotNL = (BsdfNDot(wi));
        float dotNV = (BsdfNDot(wo));

        float denomC = sqrt(a2 + (1.0f - a2) * dotNV * dotNV) + dotNV;
        return 2.0f * dotNV / denomC;
    }

    static public float SmithGGXMaskingShadowing(float3 wi, float3 wo, float a2) {
        float dotNL = max(BsdfNDot(wi), 1e-5);
        float dotNV = max(BsdfNDot(wo), 1e-5);
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
public struct Transmission : Lobe {
    public float3 color;
    public float ior = 1.4;
    public float roughness = 0.0;
    public float k = 1.0;

    float3 eval(float3 view, float3 light_dir, Surface surface) {
        return float3(0);
    }

    LobeResult sample_lobe(float3 view, Surface surface, float2 u, inout uint seed) {
        let I = normalize(-view);
        let is_backface = surface.is_backface;

        var eta = is_backface ? ior : (1.0 / ior);

        let cos_theta = min(dot(-I, surface.normal), 1.0);
        let sin_theta = sqrt(max(0.0, 1.0 - cos_theta * cos_theta));
        let R0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
        let F = fresnel(R0, cos_theta);
        let cannot_refract = eta * sin_theta > 1.0;
        let should_reflect = cannot_refract || (random::unit(seed) < F);

        if (should_reflect) {
            let F0 = pow((ior - 1.0) / (1.0 + ior), 2.0)*color;
            let ggx = GGXLobe(F0, roughness);
            var result = ggx.sample_lobe(view, surface, u, seed);
            result.throughput /= F;
            return result;
            // float3 reflected = reflect(I, surface.normal);
            // reflected = normalize(reflected + cosine_hemisphere(reflected, seed) * roughness);
            // return {color, reflected};
        } else {
            var refracted = refract(I, surface.normal, eta);
            let noise = cosine_hemisphere(refracted, seed) * roughness;
            return LobeResult((1-F)*color, normalize(refracted + noise));
        }
    }
};

struct DiffuseLobe : Lobe {
    float3 color;
    float roughness;
    float subsurface_weight = 0;

    float sheen_tint = 0;
    float sheen_weight = 0;

    struct Sheen {
        static float3 Ctint(float3 color) {
            let lum = luminance(color);
            return (lum > 0) ? (color / lum) : 1;
        }
        static float3 Csheen(float3 color, float3 tint) {
            return (1 - tint) + tint * Ctint(color);
        }

        static float3
        Fsheen(Surface surface, float3 color, float tint, float HoV, float NoV) {
            return Csheen(color, tint) * pow(1 - HoV, 2) * NoV;
        }
    };

    static float3 sample_direction(float3 normal, inout uint seed) {
        return cosine_hemisphere(normal, seed);
    }

    static float sample_pdf(float NoL) {
        return NoL / PI;
    }

    static float Fd_90(float roughness, float3 half, float3 dir) {
        return (1.0 / 2.0) + 2 * roughness * pow(dot(dir, half), 2);
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
        let f = albedo * fd_in * fd_out;
        return f;
    }

    static float Fss_90(float roughness, float3 view, float3 half) {
        return roughness * pow(dot(half, view), 2);
    }
    static float Fss(float3 normal, float roughness, float3 w, float3 view, float3 half) {
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

    float3 eval(float3 view, float3 light_dir, Surface surface) {
        let half = normalize(view + light_dir);
        let NoL = max(dot(surface.normal, light_dir), 0.0);

        let diffuse =
            diffuse_bsdf(color, roughness, surface.normal, view, light_dir, half);
        let subsurface = subsurface_bsdf(float3(1, 0, 0),
                                         roughness,
                                         surface.normal,
                                         view,
                                         light_dir,
                                         half);

        let HoV = dot(half, view);
        let NoV = dot(surface.normal, view);

        let sheen = Sheen::Fsheen(surface, color, sheen_tint, HoV, NoV);

        let f = (((1 - subsurface_weight) * diffuse) + (subsurface_weight * subsurface) +
                 (sheen_weight * sheen)) /
                PI;
        return f * NoL;
    }

    LobeResult sample_lobe(float3 view, Surface surface, float2 u, inout uint seed) {
        let dir = sample_direction(surface.normal, seed);
        let NoL = max(dot(surface.normal, dir), 1e-5);
        let pdf = sample_pdf(NoL);
        if (pdf <= 1e-5f)
            return { float3(0), dir };

        let brdf = eval(view, dir, surface);
        return { brdf / pdf, dir };
    }
};

struct Clearcoat {
    static float ag(float clearcoat_roughness) {
        let v = (1 - clearcoat_roughness) * 0.1 + clearcoat_roughness * 0.001;
        return max(v, 0.05);
    }
    static float R0(float ior) {
        let f = (ior - 1) / (ior + 1);
        return f * f;
    }
};

struct GGXLobe : Lobe {
    float3 F0;
    float roughness;
    float weight = 1;

    float3 eval(float3 view, float3 light_dir, Surface surface) {
        let a = max(roughness * roughness, 0.0);
        let a2 = a * a;

        let wo_local = to_local_vndf(view, surface);
        let wi_local = to_local_vndf(light_dir, surface);
        let wm_local = normalize(wo_local + wi_local);

        let NoL = max(BsdfNDot(wi_local), 1e-5);
        let NoV = max(BsdfNDot(wo_local), 1e-5);

        if (NoL <= 0.0 || NoV <= 0.0)
            return float3(0);

        let VoH = max(dot(wo_local, wm_local), 1e-5);
        let F = fresnel(F0, VoH);
        let D = VNDF::ggx_D(wm_local, a);
        let G2 = VNDF::SmithGGXMaskingShadowing(wi_local, wo_local, a2);
        return F * D * G2 / (4.0 * NoV * NoL) * weight;
    }

    LobeResult sample_lobe(float3 view, Surface surface, float2 u, inout uint seed) {
        let a = max(roughness * roughness, 0.0);
        let a2 = a * a;

        let wo_local = to_local_vndf(view, surface);
        let wm_local = VNDF::GgxVndf(wo_local, a, u);
        let wi_local = reflect(-wo_local, wm_local);

        let wi_world = to_world_vndf(wi_local, surface);

        if (BsdfNDot(wi_local) <= 1e-5f)
            return { float3(0), wi_world };

        let VoH = max(dot(wi_local, wm_local), 1e-5);
        let F = fresnel(F0, VoH);

        let G1 = VNDF::SmithGGXMasking(wi_local, wo_local, a2);
        let G2 = VNDF::SmithGGXMaskingShadowing(wi_local, wo_local, a2);
        let throughput = (F * (G2 / G1)) * weight;

        return { throughput, wi_world };
    }
};

// https://cseweb.ucsd.edu/~tzli/cse272/wi2022/homework1.pdf
public struct Principled : Material {
    struct LobeWeights {
        float3 F0;
        float pd;
        float pm;
        float pc;
        float pt;
    };

    LobeWeights compute_weights() {
        let F0 = lerp(float3(0.04), color, metallic);
        let et = ptransmission.weight;
        // let et = 0;

        let es = (1 - et) * luminance(F0);
        let ed = (1 - et) * (1.0 - metallic);
        let ec = 0.25 * pclearcoat.weight;
        let total = ed + es + ec + et;

        return {
            F0,
            ed / total,
            es / total,
            ec / total,
            et / total,
        };
    }

    public float3 eval(float3 view, float3 light_dir, Surface surface) {
        let w = compute_weights();
        let diffuse_lobe = DiffuseLobe(color,
                                       roughness,
                                       pdiffuse.subsurface,
                                       psheen.tint,
                                       psheen.weight);
        let spec_lobe = GGXLobe(w.F0, roughness);
        let coat_lobe = GGXLobe(Clearcoat::R0(1.5), Clearcoat::ag(pclearcoat.gloss));
        let t_lobe = Transmission(color, ptransmission.ior, ptransmission.roughness);
        return w.pd * diffuse_lobe.eval(view, light_dir, surface) +
               w.pm * spec_lobe.eval(view, light_dir, surface) +
               w.pc * coat_lobe.eval(view, light_dir, surface) +
               w.pt * t_lobe.eval(view, light_dir, surface);
    }

    public struct conductor_params {
        public float3 eta;
        public float3 k;
    };

    public struct diffuse_pararms {
        public float subsurface = 0;
    };

    public struct sheen_params {
        public float weight = 0;
        public float tint = 0;
    };

    public struct clearcoat_params {
        public float weight = 0;
        public float gloss = 1;
    };

    public struct transmission_params {
        public float weight = 0;
        public float ior = 1.45;
        public float roughness = 0;
    };

    public float3 color = 1;
    public float roughness = 0.5;
    public float metallic = 0;

    public diffuse_pararms pdiffuse;
    public sheen_params psheen;
    public clearcoat_params pclearcoat;
    public transmission_params ptransmission;

    public void scatter(Surface surface, inout State state) {
        let view = -state.ray.Direction;

        let w = compute_weights();

        let r = random::unit(state.seed);
        let u = random::f2(state.seed);

        var result = LobeResult(0, 0);
        if (r < w.pd) {
            let lobe = DiffuseLobe(color,
                                   roughness,
                                   pdiffuse.subsurface,
                                   psheen.tint,
                                   psheen.weight);
            result = lobe.sample_lobe(view, surface, u, state.seed);
            result.throughput /= w.pd;
        } else if (r < w.pd + w.pm) {
            let lobe = GGXLobe(w.F0, roughness);
            result = lobe.sample_lobe(view, surface, u, state.seed);
            result.throughput /= w.pm;
        } else if (r < w.pd + w.pm + w.pc) {
            let lobe = GGXLobe(Clearcoat::R0(1.5),
                               Clearcoat::ag(pclearcoat.gloss),
                               pclearcoat.weight);
            result = lobe.sample_lobe(view, surface, u, state.seed);
            result.throughput /= w.pc;
        } else {
            let lobe = Transmission(color, ptransmission.ior, ptransmission.roughness);
            result = lobe.sample_lobe(view, surface, u, state.seed);
            result.throughput /= w.pt;
        }
        result.throughput = min(result.throughput, float3(10.0));
        state.throughput *= result.throughput;
        state.ray.Direction = result.direction;
    }
};
