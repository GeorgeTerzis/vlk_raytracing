import state;
import rand;
import math;
import principled;
import surface;
import material;

struct PC {
    struct Buffers {
        float3* verts;
        float3* norms;
        float2* uvs;
        uint* indicies;
        uint* normals_indicies;
    };

    struct Geometry {
        uint buffer_index;
    };

    struct Range {
        uint begin;
        uint len;
    };

    struct Instance {
        uint range_index;
    }

    uint2 res;
    float time;
    uint frame;
    uint2 pos;

    Buffers* buffers;
    Geometry* geometries;
    Range* ranges;
};
[[vk::push_constant]]
PC pc;

[[vk::binding(0, 0)]]
RaytracingAccelerationStructure tlas;

[[vk::binding(1, 0)]]
RWTexture2D<float4> output;

struct Screen {
    uint3 resolution;
    uint3 coords;

    static Screen make(uint3 coords) {
        let resolution = DispatchRaysDimensions();
        return { resolution, coords };
    }
};

struct Tri {
    float3 v0;
    float3 v1;
    float3 v2;

    float3 normal() {
        let e0 = v1 - v0;
        let e1 = v2 - v0;
        return normalize(cross(e0, e1));
    }
};

struct Primitive {
    Tri tri;
    float3 norm;
    float3 geometric_norm;

    static Primitive make(PC.Buffers buffer, uint primitive, float2 bary) {
        uint base = primitive * 3;

        let vi0 = buffer.indicies[base + 0];
        let vi1 = buffer.indicies[base + 1];
        let vi2 = buffer.indicies[base + 2];

        let ni0 = buffer.normals_indicies[base + 0];
        let ni1 = buffer.normals_indicies[base + 1];
        let ni2 = buffer.normals_indicies[base + 2];

        let v0 = buffer.verts[vi0];
        let v1 = buffer.verts[vi1];
        let v2 = buffer.verts[vi2];

        let n0 = buffer.norms[ni0];
        let n1 = buffer.norms[ni1];
        let n2 = buffer.norms[ni2];

        float3 smooth_normal = bary_interpolate(n0, n1, n2, bary);
        let tri = Tri(v0, v1, v2);
        return Primitive(tri, smooth_normal, tri.normal());
    }
};

struct Emission : Material {
    float3 color;
    float strength;

    void scatter(Surface surface, inout State payload) {
        payload.color += payload.throughput * (color * strength);
        payload.hit = false;
    }
};

struct Glass : Material {
    float3 absorbtion;
    float ior = 1.4;
    float roughness = 0.0;
    float k = 1.0;

    float3 specular(float3 I, float3 N, float roughness, inout uint seed) {
        float3 reflected = reflect(I, N);
        reflected = normalize(reflected + cosine_hemisphere(reflected, seed) * roughness);
        return reflected;
    }

    float3 refraction(float3 I, float3 N, float eta, float roughness, inout uint seed) {
        var refracted = refract(I, N, eta);
        let noise = cosine_hemisphere(refracted, seed) * roughness;
        return normalize(refracted + noise);
    }

    void scatter(Surface surface, inout State payload) {
        var N = surface.normal;
        var I = normalize(payload.ray.Direction);

        let is_backface = surface.is_backface;
        var eta = ior;

        if (!is_backface) {
            eta = 1.0 / ior;
            payload.inside_medium = true;
            payload.medium_t = RayTCurrent();
        } else {
            let exit_t = RayTCurrent();
            let dist = exit_t - payload.medium_t;
            let absorb = exp(-(absorbtion * k) * dist);

            payload.throughput *= absorb;

            payload.inside_medium = false;
        }

        let cos_theta = min(dot(-I, N), 1.0);
        let sin_theta = sqrt(max(0.0, 1.0 - cos_theta * cos_theta));
        let cannot_refract = eta * sin_theta > 1.0;

        let R0 = (1.0 - ior) / (1.0 + ior);
        let reflect_prob = fresnel(R0 * R0, cos_theta);

        let should_reflect =
            cannot_refract || (random::unit(payload.seed) < reflect_prob);
        let prob = should_reflect ? reflect_prob : (1.0 - reflect_prob);

        if (should_reflect) {
            payload.ray.Direction = specular(I, N, roughness, payload.seed);
        } else {
            payload.ray.Direction = refraction(I, N, eta, roughness, payload.seed);
        }
        payload.throughput /= prob;
    }
};

[shader("raygeneration")]
void raygen_entry() {
    static let SAMPLES_PER_PIXEL = 3;
    static let BOUNCES = 30;
    let ray_origin = float3(0, 2.0, 9.0);

    let screen = Screen::make(uint3(pc.pos, 0) + DispatchRaysIndex());
    let raw_uv = (float2(screen.coords.xy) - (pc.res.xy * 0.5)) / (pc.res.y);
    let norm_uv = float2(screen.coords.xy) / float2(pc.res.xy);

    var seed = screen.coords.x * 1973 + screen.coords.y * 9277 + pc.frame * 26699;
    var sample = uint(0);
    var accumilator = float3(0);
    for (; sample < SAMPLES_PER_PIXEL; sample++) {
        let jitter = random::f2(seed);
        let uv = (float2(screen.coords.xy) + jitter - (pc.res.xy * 0.5)) / (pc.res.y);

        let dir = normalize(float3(uv.x, -uv.y, -1.0));

        RayDesc ray;
        ray.Origin = ray_origin;
        ray.Direction = dir;
        ray.TMin = 0.00001;
        ray.TMax = 10000.0;

        var bounce = 0;
        var payload = State(ray, float3(0), float3(1), seed, false);

        for (; bounce < BOUNCES; bounce++) {
            payload.hit = false;

            TraceRay(tlas, RAY_FLAG_NONE, 0xFF, 0, 0, 0, payload.ray, payload);

            if (!payload.hit) {
                break;
            }

            let p = max(luminance(payload.throughput), 0.01);
            if (random::unit(payload.seed) > p) {
                break;
            }
            payload.throughput /= p;
        }
        let color = payload.color;
        accumilator += color;
    }
    let color = accumilator / SAMPLES_PER_PIXEL;

    // if (norm_uv.y < 1. / 3.) {
    //     output[screen.coords.xy] = float4(color, 1.0);
    // } else if (norm_uv.y < 2. / 3.) {
    float4 prev = output[screen.coords.xy];
    float weight = 1.0 / float(pc.frame + 1);
    output[screen.coords.xy] = float4(lerp(prev.rgb, color, weight), 1.0);
    // } else {
    //     float4 prev = output[screen.coords.xy];
    //     output[screen.coords.xy] = float4(lerp(prev.rgb, color, 0.1), 1.0);
    // }
}

[shader("miss")]
void miss_entry(inout State payload) {
    payload.color = payload.throughput * float3(0.9, 0.7, 0.95) * 2;
    payload.hit = false;
}

float3 HitPos() {
    return WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
}

struct HitInfo {
    uint geometry;
    uint instance;
    uint primitive;
    float3 pos;

    static HitInfo make(uint g, uint i, uint p, float3 pos) {
        HitInfo h;
        h.geometry = g;
        h.instance = i;
        h.primitive = p;
        h.pos = pos;
        return h;
    }

    static HitInfo from_current_hit() {
        return make(GeometryIndex(), InstanceIndex(), PrimitiveIndex(), HitPos());
    }
};

void mat(const HitInfo hit, const Surface surface, inout State state) {
    let frosted_glass = Glass(float3(1), 1.5, 0.2);
    let glass = Glass(float3(0.4, 0.9, 0.5), 2, 0.0, 0.02);

    let cloth_diffuse = Principled::diffuse_pararms(0.8);
    let cloth_sheen = Principled::sheen_params(10, 0);
    let cloth = Principled(hit.pos.x > 0 ? float3(0.8, 0.6, 0.2) : float3(0.2, 0.5, 0.8),
                           0.5,
                           0,
                           cloth_diffuse,
                           cloth_sheen);

    let diffuse_dif = Principled::diffuse_pararms(0);
    let diffuse_specular = Principled::specular_params(1, 1);

    let is_floor = hit.pos.y < 0.001;
    let is_left = hit.pos.x > 0.0;
    let is_metallic = is_floor && is_left;
    let diffuse_clearcoat =
        Principled::clearcoat_params((!is_floor) || is_left ? 0 : 1, 1);
    let diffuse = Principled((!is_floor) || is_left ? float3(0.8) : float3(0.8, 0.6, 0.2),
                             is_metallic ? 0.3 : 0.6,
                             is_metallic ? 1.0 : 0.0,
                             diffuse_dif,
                             {},
                             diffuse_specular,
                             diffuse_clearcoat);

    let mirror_specular = Principled::specular_params(0, 0);
    let mirror = Principled(float3(0.8, 0.8, 0.8), 0.0, 1, {}, {}, mirror_specular, {});

    let light = Emission(float3(0.1, 0.2, 0.9), 30);

    if (hit.instance == 0)
        glass.scatter(surface, state);
    else if (hit.instance == 4) {
        glass.scatter(surface, state);
    } else if (hit.instance == 1)
        cloth.scatter(surface, state);
    else if (hit.instance == 5)
        mirror.scatter(surface, state);
    else if (hit.instance == 3)
        glass.scatter(surface, state);
    else
        diffuse.scatter(surface, state);
    state.hit = true;
}

[shader("closesthit")]
void closest_hit_entry(inout State payload,
                       const BuiltInTriangleIntersectionAttributes attr) {
    let hit = HitInfo::from_current_hit();
    let range = pc.ranges[hit.instance];
    let geometry = pc.geometries[range.begin + hit.geometry];
    let buffer = pc.buffers[geometry.buffer_index];

    let prim = Primitive::make(buffer, hit.primitive, attr.barycentrics);
    let surface = Surface::make(prim.geometric_norm, prim.norm);
    let safe_pos = hit.pos + (surface.normal * 1e-7);

    mat(hit, surface, payload);
    payload.ray.Origin = safe_pos;
}
