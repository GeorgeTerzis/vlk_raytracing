module principled;

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
        float dotNL = (BsdfNDot(wi));
        float dotNV = (BsdfNDot(wo));

        float denomC = sqrt(a2 + (1.0f - a2) * dotNV * dotNV) + dotNV;
        return 2.0f * dotNV / denomC;
    }
    static public float SmithGGXMaskingShadowing(float3 wi, float3 wo, float a2) {
        // do we allow negative value
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

// https://cseweb.ucsd.edu/~tzli/cse272/wi2022/homework1.pdf
public struct Principled : Material {
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

    public struct specular_params {
        public float weight = 0;
        public float tint = 0;
    };

    public struct clearcoat_params {
        public float weight = 0;
        public float gloss = 1;
    };

    public float3 color = 1;
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
        static float3 Ctint(float3 color) {
            let lum = luminance(color);
            return (lum > 0) ? (color / lum) : 1;
        }
        static float3 Csheen(float3 color, float3 tint) {
            return (1 - tint) + tint * Ctint(color);
        }

        static float3
        Fsheen(Surface surface, float3 color, sheen_params params, float HoV, float NoV) {
            return Csheen(color, params.tint) * pow(1 - HoV, 2)*NoV;
        }
    };

    public void scatter(Surface surface, inout State state) {
        let view = -state.ray.Direction;
        let NoV = max(dot(surface.normal, view), 1e-5);

        let lum = luminance(color);
        let F0 = lerp(float3(0.04), color, metallic);
        let spec_weight = luminance(F0);
        let es = spec_weight;
        let ed = (1.0 - metallic);

        let ec = 0.04 * pclearcoat.weight;
        let total = max(ed + es + ec, 1e-6);

        let pd = ed / total;
        let ps = es / total;
        let pc = ec / total;

        let r = random::unit(state.seed);
        let u = float2(random::unit(state.seed), random::unit(state.seed));

        let dcond = pd;
        let scond = pd + ps;
        let ccond = pd + ps + pc;

        if (r < dcond) {
            let dir = Diffuse::sample_direction(surface.normal, state.seed);
            let half = normalize(view + dir);

            let NoL = max(dot(surface.normal, dir), 1e-5);
            let diffuse =
                Diffuse::diffuse_bsdf(color, roughness, surface.normal, view, dir, half);
            let subsurface = Diffuse::subsurface_bsdf(color,
                                                      roughness,
                                                      surface.normal,
                                                      view,
                                                      dir,
                                                      half);
            let HoV = dot(half, view);
            let sheen = Sheen::Fsheen(surface, color, psheen, HoV, NoV);

            let f = (((1 - pdiffuse.subsurface) * diffuse) +
                    (pdiffuse.subsurface * subsurface) + (psheen.weight * sheen))/PI;
            let pdf = Diffuse::sample_pdf(NoL);
            if (pdf <= 1e-5f) {
                state.throughput = float3(0);
                return;
            }
            state.throughput *= f * NoL / (pdf * pd);
            state.ray.Direction = dir;
        } else if (r < scond) {
            let a = max(roughness * roughness, 0.0);
            let a2 = a * a;
            let wo_local = to_local_vndf(view, surface);

            let wm_local = VNDF::GgxVndf(wo_local, a, u);
            let wi_local = reflect(-wo_local, wm_local);
            let wi_world = to_world_vndf(wi_local, surface);

            let dir = wi_world;
            var throughput = float3(0);

            if (BsdfNDot(wi_local) <= 1e-5f) {
                state.throughput = float3(0);
                return;
            }
            let VoH = max(dot(wi_local, wm_local), 1e-5);
            float3 F = fresnel(F0, VoH);

            let G1 = VNDF::SmithGGXMasking(wi_local, wo_local, a2);
            let G2 = VNDF::SmithGGXMaskingShadowing(wi_local, wo_local, a2);
            throughput = (F * (G2 / G1)) / (ps);

            state.ray.Direction = dir;
            state.throughput *= throughput;
        } else {
            static let F0 = Clearcoat::R0(1.5);
            let a = max(Clearcoat::ag(pclearcoat.gloss), 0.02);
            let a2 = a * a;
            let wo_local = to_local_vndf(view, surface);
            let wm_local = VNDF::GgxVndf(wo_local, a, u);
            let wi_local = reflect(-wo_local, wm_local);
            let wi_world = to_world_vndf(wi_local, surface);
            state.ray.Direction = wi_world;

            if (BsdfNDot(wi_local) <= 1e-5f) {
                state.throughput = float3(0);
                return;
            }

            let VoH = max(dot(wi_local, wm_local), 1e-5);
            let F = fresnel(F0, VoH);

            let G1 = max(VNDF::SmithGGXMasking(wi_local, wo_local, a2), 1e-5);
            let G2 = VNDF::SmithGGXMaskingShadowing(wi_local, wo_local, a2);
            state.throughput *= (pclearcoat.weight * F * (G2 / G1)) / pc;
        }
        // else {
        // glass
        // scatter_glass(surface, state);
        // }
    }
}
