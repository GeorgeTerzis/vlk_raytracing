import state;
import rand;
import math;
import surface;
import material;

import principled;
import glass;
import emission;

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
    };

    struct Material {
        uint index;
    }

    uint2 res;
    float time;
    uint frame;
    uint2 pos;
    float2 mouse;

    Buffers* buffers;
    Geometry* geometries;
    Range* ranges;
    Material* materials;
};

[[vk::push_constant]]
PC pc;

[[vk::binding(0, 0)]]
RaytracingAccelerationStructure tlas;

[[vk::binding(1, 0)]]
RWTexture2D<float4> output;

[[vk::binding(2, 0)]]
RWTexture2D<float3> normals;

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
        let base = primitive * 3;

        let i0 = base + 0;
        let i1 = base + 1;
        let i2 = base + 2;

        let vi0 = buffer.indicies[i0];
        let vi1 = buffer.indicies[i1];
        let vi2 = buffer.indicies[i2];

        let ni0 = buffer.normals_indicies[i0];
        let ni1 = buffer.normals_indicies[i1];
        let ni2 = buffer.normals_indicies[i2];

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

float3 sample_phase_function(float3 wo, float g, inout uint seed) {
    float u1 = random::unit(seed);
    float u2 = random::unit(seed);
    float cos_theta;

    if (abs(g) < 1e-3) {
        cos_theta = 1.0 - 2.0 * u1;
    } else {
        float sqr = (1.0 - g * g) / (1.0 - g + 2.0 * g * u1);
        cos_theta = (1.0 + g * g - sqr * sqr) / (2.0 * g);
    }

    float sin_theta = sqrt(max(0.0, 1.0 - cos_theta * cos_theta));
    float phi = 2.0 * PI * u2;

    float3 dir = float3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);

    float3 w = normalize(wo);
    float3 a = (abs(w.z) < 0.999) ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 v = normalize(cross(a, w));
    float3 u = cross(w, v);

    return normalize(u * dir.x + v * dir.y + w * dir.z);
}

[shader("raygeneration")]
void raygen_entry() {

    // use specialization constants for these 2
    //  or at least I think I can use them here

    static let SAMPLES_PER_PIXEL = 2;
    static let BOUNCES = 30;

    let ray_origin = float3(0, 2.0, 9.0);

    let screen = Screen::make(uint3(pc.pos, 0) + DispatchRaysIndex());
    let raw_uv = (float2(screen.coords.xy) - (pc.res.xy * 0.5)) / (pc.res.y);
    let norm_uv = float2(screen.coords.xy) / float2(pc.res.xy);

    var seed = screen.coords.x * 1973 + screen.coords.y * 9277 + pc.frame * 26699;

    var sample = uint(0);
    var sample_accumilator = float3(0);
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
        sample_accumilator += color;
    }
    let color = sample_accumilator / SAMPLES_PER_PIXEL;
    let prev = output[screen.coords.xy];

    let weight = 1.0 / float(pc.frame + 1);
    output[screen.coords.xy] = float4(lerp(prev.rgb, color, weight), 1.0);
    // output[screen.coords.xy] = float4(lerp(prev.rgb, color, 0.1), 1.0);
}

[shader("miss")]
void miss_entry(inout State payload) {
    payload.color = payload.throughput * float3(0.9, 0.7, 0.95) * 1;
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

void scatter(const uint material,
            const HitInfo hit,
            const Surface surface,
            inout State state) {
    let glass = Glass(float3(0.1, 0.9, 0.5), 2, 0.0, 0.01);

    let cloth_diffuse = Principled::diffuse_pararms(0);
    let cloth_sheen = Principled::sheen_params(10, 0);
    let cloth = Principled(hit.pos.x > 0 ? float3(0.8, 0.6, 0.2) : float3(0.2, 0.5, 0.8),
                           0.5,
                           0,
                           cloth_diffuse,
                           cloth_sheen);

    let x = hit.pos.x;
    let is_floor = hit.pos.y < 0.001;
    let diffuse_dif = Principled::diffuse_pararms(0);
    let diffuse_specular = Principled::specular_params(1, 1);
    let diffuse_clearcoat = Principled::clearcoat_params(0, 0);
    let diffuse = Principled(is_floor ? float3(0.8) : float3(0.8),
                             is_floor ? 0.3 : 0.8,
                             is_floor ? 1.0 : 0.0,
                             diffuse_dif,
                             {},
                             diffuse_specular,
                             diffuse_clearcoat);

    let mirror_specular = Principled::specular_params(0, 0);
    let mirror = Principled(float3(0.8, 0.8, 0.8), 0.0, 1, {}, {}, mirror_specular, {});
    let default_mat = Principled(float3(0.8, 0.1, 0.4), 0.8, 0.0);

    state.hit = true;
    switch (material) {
    case 0:
        return glass.scatter(surface, state);
    case 1:
        return cloth.scatter(surface, state);

    case 2:
        return mirror.scatter(surface, state);

    case 3:
        return diffuse.scatter(surface, state);

    default:
        return default_mat.scatter(surface, state);
    }
}

[shader("closesthit")]
void closest_hit_entry(inout State payload,
                       const BuiltInTriangleIntersectionAttributes attr) {
    let hit = HitInfo::from_current_hit();

    let range = pc.ranges[hit.instance];
    let geometry = pc.geometries[range.begin + hit.geometry];
    let buffer = pc.buffers[geometry.buffer_index];
    let material = pc.materials[hit.instance];

    let prim = Primitive::make(buffer, hit.primitive, attr.barycentrics);
    let surface = Surface::make(prim.geometric_norm, prim.norm);
    let safe_pos = hit.pos + (surface.normal * 1e-7);

    // uint seed = material.index * 2;
    // payload.color = random::f3(seed);
    // payload.hit = false;
    scatter(material.index, hit, surface, payload);
    payload.ray.Origin = safe_pos;
}
