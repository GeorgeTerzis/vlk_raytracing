import state;
import rand;
import math;
import principled;
import surface;
import material;

float3 bary_interpolate(float3 v0, float3 v1, float3 v2, float2 bary) {
    return v0 * (1.0 - bary.x - bary.y) + v1 * bary.x + v2 * bary.y;
}

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
struct Normal {
    float3 n;
};

struct Primitive {
    Tri tri;
    Normal norm;

    static Primitive make(PC_.Buffers buffer, uint primitive, float2 bary) {
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

        let smooth_normal =
            normalize(n0 * (1.0 - bary.x - bary.y) + n1 * bary.x + n2 * bary.y);

        return Primitive(Tri(v0, v1, v2), Normal(smooth_normal));
    }
};

struct PC_ {
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

    Buffers* buffers;
    Geometry* geometries;
    Range* ranges;
};

struct Emision : Material {
    float3 albedo;
    float strength;

    void scatter(Surface surface, inout State payload) {
        payload.color += payload.throughput * albedo * strength;
    }
};

struct Glass2 : Material {
    float3 ior;
    float roughness;
    void scatter(Surface surface, inout State payload) {
        let red = Glass(float3(1, 0, 0), ior.x, roughness);
        let green = Glass(float3(0, 1, 0), ior.y, roughness);
        let blue = Glass(float3(0, 0, 1), ior.z, roughness);

        let r = random::unit(payload.seed);
        if (r < 1.0 / 3.0) {
            red.scatter(surface, payload);
        } else if (r < 2.0 / 3.0) {
            blue.scatter(surface, payload);
        } else {
            green.scatter(surface, payload);
        }
    }
};

struct Glass : Material {
    float3 absorbtion;
    float ior;
    float roughness;

    void scatter(Surface surface, inout State payload) {
        var N = surface.normal;
        var I = normalize(payload.ray.Direction);

        let is_backface = surface.is_backface;
        var eta = ior;

        if (!is_backface) {
            eta = 1.0 / ior;
        } else {
            let distance = 1 - RayTCurrent();
            // payload.throughput *= exp(-absorbtion * distance );
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
            var reflected = reflect(I, N);
            reflected = normalize(reflected +
                                  cosine_hemisphere(reflected, payload.seed) * roughness);
            payload.ray.Direction = reflected;
        } else {
            var refracted = refract(I, N, eta);
            refracted = normalize(refracted +
                                  cosine_hemisphere(refracted, payload.seed) * roughness);
            payload.ray.Direction = refracted;
        }
        payload.throughput /= prob;
    }
};

[[vk::push_constant]]
PC_ pc;

[[vk::binding(0, 0)]]
RaytracingAccelerationStructure tlas;

[[vk::binding(1, 0)]]
RWTexture2D<float4> output;

[shader("raygeneration")]
void raygen_entry() {
    let coord = DispatchRaysIndex().xy;
    uint seed = coord.x * 1973 + coord.y * 9277 + (pc.frame) * 26699;
    static let SPP = 4;
    var s = uint(0);
    var accumilator = float3(0);
    for (; s < SPP; s++) {
        let jitter = float2(random::unit(seed), random::unit(seed));
        let uv = (float2(coord) + jitter - (pc.res * 0.5)) / (pc.res.y);

        let ray_origin = float3(-1.3, 1.5, 9.0);
        let dir = normalize(float3(uv.x, -uv.y, -1.0));

        RayDesc ray;
        ray.Origin = ray_origin;
        ray.Direction = dir;
        ray.TMin = 0.00001;
        ray.TMax = 10000.0;

        var payload = State(0, 1, false, seed, ray, 0);
        for (; payload.bounce < State::BOUNCES; payload.bounce++) {
            payload.hit = false;
            TraceRay(tlas, RAY_FLAG_NONE, 0xFF, 0, 0, 0, payload.ray, payload);

            if (!payload.hit)
                break;
            let p = max(luminance(payload.throughput), 0.01);
            if (random::unit(payload.seed) > p)
                break;
            payload.throughput /= p;
        }
        let color = payload.color;
        accumilator += color;
    }

    let color = accumilator / SPP;

    float4 prev = output[coord];
    float weight = 1.0 / float(pc.frame + 1);
    output[coord] = float4(lerp(prev.rgb, color, weight), 1.0);
}

[shader("miss")]
void miss_entry(inout State payload) {
    payload.color += payload.throughput * (float3(0.6, 0.8, 1) * 2);
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
    let glass = Glass(float3(1), 1.5, 0.0);

    let cloth_diffuse = Principled::diffuse_pararms(float3(1, 0.1, 0.1), 0);
    let cloth_sheen = Principled::sheen_params(10, 0);
    let cloth = Principled(0.5, 0, cloth_diffuse, cloth_sheen);

    let diffuse_dif = Principled::diffuse_pararms(float3(1), 0);
    let diffuse_specular = Principled::specular_params(1, 1, float3(1, 0, 0));
    let diffuse = Principled(0.5, 0, diffuse_dif, {}, diffuse_specular, {});

    let mirror_specular= Principled::specular_params(0, 0, float3(1));
    let mirror = Principled(0.0, 1, {}, {}, mirror_specular, {});

    if (hit.instance == 0 || hit.instance == 5)
        mirror.scatter(surface, state);
    else if (hit.instance == 3)
        glass.scatter(surface, state);
    else if (hit.instance == 1)
        cloth.scatter(surface, state);
    else
        diffuse.scatter(surface, state);
}

[shader("closesthit")]
void closest_hit_entry(inout State payload, BuiltInTriangleIntersectionAttributes attr) {
    let hit = HitInfo::from_current_hit();
    let range = pc.ranges[hit.instance];
    let geometry = pc.geometries[range.begin + hit.geometry];
    let buffer = pc.buffers[geometry.buffer_index];

    let prim = Primitive::make(buffer, hit.primitive, attr.barycentrics);
    let surface = Surface::make(prim.norm.n);
    let safe_pos = hit.pos + (surface.normal * 1e-7);

    mat(hit, surface, payload);
    payload.ray.Origin = safe_pos;
    payload.hit = true;
}
