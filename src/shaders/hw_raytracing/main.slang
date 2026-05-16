import state;
import rand;
import math;
import surface;
import material;

import principled;
// import glass;
// import emission;

// adaptive sampling: https://cs184.eecs.berkeley.edu/sp21/docs/proj3-1-part-5
struct PC {
    struct Buffers {
        const Ptr<float3, Access.Read> verts;
        const Ptr<float3, Access.Read> norms;
        const Ptr<float2, Access.Read> uvs;
        const Ptr<uint, Access.Read> indicies;
        const Ptr<uint, Access.Read> normals_indicies;
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

    const Ptr<Buffers, Access.Read> buffers;
    const Ptr<Geometry, Access.Read> geometries;
    const Ptr<Range, Access.Read> ranges;
    const Ptr<Material, Access.Read> materials;

    // float3[3][2] some_array;
};

[[vk::push_constant]]
PC pc;

[[vk::binding(0, 0)]]
RaytracingAccelerationStructure tlas;

[[vk::binding(1, 0)]]
RWTexture2D<float4> output;

// [[vk::binding(2, 0)]]
// RWTexture2D<float3> normals;

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

struct ShadowState {
    bool hit;
};

interface Light {
    float3 sample_point(inout uint seed);
    float3 pos();
};

struct AreaLight : Light {
    float3 position;

    float3 normal;

    float width;
    float height;

    float3 color;

    float3 sample_point(inout uint seed) {
        float u = (random::unit(seed) - 0.5) * width;
        float v = (random::unit(seed) - 0.5) * height;

        float3 up = abs(normal.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);

        float3 tangent = normalize(cross(up, normal));
        float3 bitangent = cross(normal, tangent);

        return position + tangent * u + bitangent * v;
    }
    float area() {
        return width * height;
    }

    float3 pos() {
        return position;
    }

    float sample_pdf() {
        return 1 / area();
    }
};
struct PointLight : Light {
    float3 position;
    float3 color;

    float3 sample_point(inout uint seed) {
        return position;
    }
    float3 pos() {
        return position;
    }
};

[shader("raygeneration")]
void raygen_entry() {

    // use specialization constants for these 2
    //  or at least I think I can use them here
    static let SAMPLES_PER_PIXEL = 3;
    static let BOUNCES = 12;

    static let camera_position = float3(0, 2.2, 9.0);
    static let fov = 1;

    let screen = Screen::make(uint3(pc.pos, 0) + DispatchRaysIndex());

    let raw_uv = (float2(screen.coords.xy) - (pc.res.xy * 0.5)) / (pc.res.y);
    let norm_uv = float2(screen.coords.xy) / float2(pc.res.xy);

    let prev = output[screen.coords.xy];

    var sample_index = uint(0);
    var sample_accumilator = float3(0);

    for (; sample_index < SAMPLES_PER_PIXEL; sample_index++) {
        var seed = screen.coords.x * 1973 + screen.coords.y * 9277 + pc.frame * 26699;
        let jitter = random::f2(seed);
        let uv =
            ((float2(screen.coords.xy) + jitter - (pc.res.xy * 0.5)) / (pc.res.y)) * fov;
        let dir = normalize(float3(uv.x, -uv.y, -1.0));

        var ray = RayDesc(camera_position, 1e-5, dir, 1e+4);

        var bounce = 0;
        var payload = State(camera_position, ray.Direction, float3(0), float3(1), seed);
        for (; bounce < BOUNCES; bounce++) {
            payload.bounce = bounce;
            payload.hit = false;

            TraceRay(tlas, RAYQUERY_FLAG_NONE, 0xFF, 0, 0, 0, ray, payload);

            if (!payload.hit) {
                break;
            }

            let p = max(luminance(payload.throughput), 0.01);
            if (random::unit(payload.seed) > p) {
                break;
            }
            payload.throughput /= p;

            ray.Origin = payload.pos;
            ray.Direction = payload.ray_dir;
        }
        sample_accumilator += payload.color;
    }

    let color = sample_accumilator / max(sample_index, 1);
    let weight = 1.0 / float(pc.frame + 1);

    output[screen.coords.xy] = float4(lerp(prev.rgb, color, weight), 1.0);
    // output[screen.coords.xy] = float4(lerp(prev.rgb, color, 0.1), 1.0);
    // output[screen.coords.xy] = float4(color, 1.0);
}

[shader("miss")]
void shadow_miss_entry(inout ShadowState payload) {
    payload.hit = false;
}

[shader("miss")]
void miss_entry(inout State payload) {
    payload.color = payload.throughput * float3(0.9, 0.7, 0.95) * 0;
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

[shader("closesthit")]
void shadow_closest_hit_entry(inout ShadowState payload,
                              const BuiltInTriangleIntersectionAttributes attr) {
    payload.hit = true;
}

Principled get_material(uint index) {
    switch (index) {
    case 0:
        return Principled(float3(1, 1, 1), 0.0, 1.0, { 0 }, {}, {}, { 0 });
    case 1:
        return Principled(float3(0.6, 0.3, 0.3), 0.5, 0, {}, { 1, 0.0 });
    case 2:
        return Principled(float3(1), 0.4, 1, {}, {}, {});
    case 3:
        return Principled(float3(0.8),
                          0.3,
                          0.0,
                          {},
                          {},
                          Principled::clearcoat_params(0, 1.));
    case 4:
        return Principled(float3(1), 0.2, 1.0, {}, {}, {}, { 0.0, 1.5, 0.0 });
    default:
        return Principled(float3(1), 0.0, 0.0, {}, {}, { 0, 1.0 }, { 0, 1.5, 0.0 });
    }
}

float3 direct_lighting(Principled mat,
                       float3 pos,
                       Surface surface,
                       float3 ray_dir,
                       inout uint seed) {
    static let lights = AreaLight[](
        // AreaLight(float3(0, 10, 0), float3(0, -1, 0), 1.0, 1.0, float3(10, 10, 10)),
        // AreaLight(float3(0.2, 20, 3), float3(0, -1, 0), 1.0, 1.0, float3(10, 30, 0)),
        AreaLight(float3(-4.4, 6, -3), float3(1, 0, 0), 0.3, 0.3, float3(90, 20, 90)),
        AreaLight(float3(-4.4, 3, -3), float3(1, 0, 0), 0.3, 0.3, float3(30, 250, 300)),
        AreaLight(float3(4.4, 3, 0), float3(-1, 0, 0), 0.3, 0.3, 300),
        );
    static let light_count = lights.getCount();

    if (light_count == 0)
        return float3(0);

    var loop_seed = 0;
    let i = random::ifrom_range(seed, 0, light_count - 1);
    {
        let light = lights[i];
        let light_area = light.area();
        let light_point = light.sample_point(seed);
        let to_light = light_point - pos;

        let dist = length(to_light);
        let dist2 = dist * dist;

        let to_light_dir = normalize(to_light);
        let NoL_light = max(dot(light.normal, -to_light_dir), 0.0);

        let NoL = max(dot(surface.normal, to_light_dir), 0.0);

        let estimated_importance =
            luminance(light.color) * light_area * NoL * NoL_light / max(dist2, 1e-5);

        if (estimated_importance >= 0.001 && NoL_light > 0.0) {
            RayDesc shadow_ray;
            shadow_ray.Origin = pos;
            shadow_ray.Direction = to_light_dir;
            shadow_ray.TMin = 0.0001;
            shadow_ray.TMax = dist - 0.0001;

            var shadow = ShadowState(true);
            TraceRay(
                tlas,
                RAY_FLAG_SKIP_CLOSEST_HIT_SHADER | RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
                0xFF,
                1,
                0,
                1,
                shadow_ray,
                shadow);

            if (!shadow.hit) {
                let view = -ray_dir;

                let brdf = mat.eval(view, to_light_dir, surface);
                let area_pdf = light.sample_pdf();
                let solid_angle_pdf = area_pdf * dist2 / max(NoL_light, 1e-4);

                let contribution =
                    light.color * brdf * NoL * light_count / solid_angle_pdf;
                let lum = luminance(contribution);
                let clamped = contribution * min(1.0, 9.0 / max(lum, 1e-5));
                return clamped;
            }
        }
    }

    return 0;
}

[shader("closesthit")]
void closest_hit_entry(inout State payload,
                       const BuiltInTriangleIntersectionAttributes attr) {
    let hit = HitInfo::from_current_hit();

    let range = pc.ranges[hit.instance];
    let geometry = pc.geometries[range.begin + hit.geometry];
    let buffer = pc.buffers[geometry.buffer_index];
    let material = pc.materials[hit.instance];

    let primitive = Primitive::make(buffer, hit.primitive, attr.barycentrics);
    let surface = Surface::make(primitive.geometric_norm, primitive.norm);
    let safe_pos = hit.pos + (surface.normal * 1e-8);

    let mat = get_material(material.index);

    var Lindirect = float3(0);
    if (payload.bounce <= 5) {
        Lindirect =
            direct_lighting(mat, safe_pos, surface, payload.ray_dir, payload.seed);
    }

    let result = mat.scatter(surface, payload.ray_dir, payload.seed);

    payload.color += Lindirect;
    payload.throughput *= result.throughput;
    payload.ray_dir = result.direction;
    payload.hit = true;
    payload.pos = safe_pos;
}
