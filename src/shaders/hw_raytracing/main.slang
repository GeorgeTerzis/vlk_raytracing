import state;
import "../common/rand";
import "../common/math";
import "../common/inputs";
import surface;
import material;
import principled;

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
    };

    uint2 res;
    float time;
    uint frame;
    uint2 pos;

    Camera cam;
    Camera prev_cam;

    uint env_map;
    Textures textures;
    uint raw;

    const Ptr<Buffers, Access.Read> buffers;
    const Ptr<Geometry, Access.Read> geometries;
    const Ptr<Range, Access.Read> ranges;
    const Ptr<Material, Access.Read> materials;
};

[[vk::push_constant]]
PC pc;

[[vk::binding(0, 0)]]
SamplerState samplers[];
[[vk::binding(1, 0)]]
Texture2D sampled_images[];
[[vk::binding(2, 0)]]
RWTexture2D storage_images[];

[[vk::binding(0, 1)]]
RaytracingAccelerationStructure tlas;

struct Screen {
    uint3 resolution;
    uint3 coords;

    static Screen make(uint3 coords) {
        let resolution = DispatchRaysDimensions();
        return { resolution, coords };
    }
};

public struct reproject {
    public static let MAX_HISTORY = 1000000000.0;

    public static float2 reproject_to_prev(float3 world_pos, uint2 res) {
        let to_point = world_pos - pc.prev_cam.pos;
        let local_pt = mul(transpose(pc.prev_cam.basis), to_point);
        if (local_pt.z >= -1e-4) {
            return float2(-1, -1);
        }
        let t = -1.0 / local_pt.z;
        let uv = float2(local_pt.x, -local_pt.y) * t;
        let pixel_offset = (uv / pc.prev_cam.fov) * float(res.y);
        return pixel_offset + float2(res) * 0.5;
    }

    public struct TemporalResult {
        float3 color;
        float count;
    };

    static float sample_confidence(int2 tap, float3 primary_pos, float3 primary_norm) {
        let hist_pos = sampled_images[pc.textures.hist.pos].Load(int3(tap, 0)).rgb;
        let hist_norm = sampled_images[pc.textures.hist.norm].Load(int3(tap, 0)).rgb;
        let hist_norm_len_sq = dot(hist_norm, hist_norm);
        if (hist_norm_len_sq <= 1e-8)
            return 0.0;

        float3 hnorm = hist_norm * rsqrt(hist_norm_len_sq);
        float3 cnorm = normalize(primary_norm);
        let pos_dist = length(hist_pos - primary_pos);
        let view_dir = normalize(pc.cam.pos - primary_pos);
        let grazing = max(dot(primary_norm, view_dir), 0.05);
        let jitter_slack = pc.cam.fov / float(pc.res.y) *
                           length(primary_pos - pc.cam.pos) / max(grazing, 0.05);
        let pos_threshold =
            max(0.01, length(primary_pos - pc.cam.pos) * 0.05 / grazing) + jitter_slack;
        let pos_weight = saturate(1.0 - pos_dist / pos_threshold);
        let normal_similarity = dot(hnorm, cnorm);
        let normal_weight =
            smoothstep(cos(radians(80.0)), cos(radians(20.0)), normal_similarity);
        return pos_weight * normal_weight;
    }

    public static TemporalResult accumulate_temporal(const uint2 res,
                                                     float3 src_color,
                                                     float3 primary_pos,
                                                     float3 primary_norm) {
        let prev_pix = reproject_to_prev(primary_pos, res);
        let in_bounds = all(prev_pix >= float2(0.0, 0.0)) && all(prev_pix < float2(res));

        float confidence = 0.0;
        int2 best_pixel = int2(prev_pix);

        if (in_bounds) {
            int2 base = int2(prev_pix);
            let c = sample_confidence(base, primary_pos, primary_norm);
            if (c > confidence) {
                confidence = c;
                best_pixel = base;
            }
        }

        float4 hist = float4(0.0);
        if (confidence > 0.01) {
            hist = sampled_images[pc.textures.hist.col].Load(int3(best_pixel, 0));
        }

        let count = lerp(1.0, min(hist.a + 1.0, MAX_HISTORY), confidence);
        let history_alpha = max(0.01, confidence) * (count - 1.0) / count;
        TemporalResult result;
        result.color = lerp(src_color, hist.rgb, history_alpha);
        result.count = count;
        return result;
    }
};

static let BOUNCES = 2;
static let LIGHT_BOUNCES = min(2, BOUNCES);
static let SAMPLES = 1;
static let LIGHT_CANDIDATES = 3;

[shader("raygeneration")]
void raygen_entry() {

    let camera_position = pc.cam.pos;
    let screen = Screen::make(DispatchRaysIndex());

    var sample_accumilator = float3(0);

    var primary_pos = float3(0);
    var primary_norm = float3(0);
    var primary_hit = false;

    let base_seed = screen.coords.x * 2973u + screen.coords.y * 9277u + pc.frame * 26699u;

    for (var sample = 0; sample < SAMPLES; sample++) {
        let seed = random::hash_combine(base_seed, uint(sample));
        let jitter = random::shuffled_scrambled_sobol2d(uint(sample), seed);
        let uv = ((float2(screen.coords.xy) + jitter - (float2(pc.res.xy) * 0.5)) /
                  ((float)(pc.res.y))) *
                 pc.cam.fov;
        let local_dir = normalize(float3(uv.x, -uv.y, -1.0));
        let dir = normalize(mul(pc.cam.basis, local_dir));
        var ray = RayDesc(camera_position, 1e-5, dir, 1e+4);

        var payload = State();

        payload.pos = camera_position;
        payload.color = half3(0);
        payload.throughput = half3(1);
        payload.ray_dir = half3(ray.Direction);
        payload.norm_enc = 0;
        payload.seed = seed;
        payload.bounce_hit = 0;

        for (var bounce = 0; bounce < BOUNCES; bounce++) {

            let bounce_seed = random::hash_combine(seed, uint(bounce));

            payload.seed = bounce_seed;
            payload.bounce_hit = bounce << 1;

            TraceRay(tlas, RAYQUERY_FLAG_NONE, 0xFF, 0, 0, 0, ray, payload);

            // Save first-hit information.
            if (bounce == 0 && sample == 0) {
                primary_hit = payload.get_hit();
                primary_pos = payload.pos;
                primary_norm = oct_decode(payload.norm_enc);
            }

            if (!payload.get_hit())
                break;

            let p = max(luminance(payload.throughput), 0.001);

            if (random::unit(payload.seed) > p)
                break;

            payload.throughput /= half(p);

            ray.Origin = payload.pos;
            ray.Direction = payload.ray_dir;
        }

        sample_accumilator += float3(payload.color);
    }

    let inv_samples = 1.0 / float(SAMPLES);
    let color = sample_accumilator * inv_samples;
    storage_images[pc.raw][screen.coords.xy] = float4(color, 1);

    storage_images[pc.textures.curr.norm][screen.coords.xy] = float4(primary_norm, 1);
    storage_images[pc.textures.curr.pos][screen.coords.xy] = float4(primary_pos, 1);
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

    float3 sample_point(float2 s) {
        float u = (s.x - 0.5) * width;
        float v = (s.y - 0.5) * height;

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

[shader("miss")]
void shadow_miss_entry(inout ShadowState payload) {
    payload.hit = false;
}

static const float2 invAtan = float2(0.1591, 0.3183);
float2 SmpleSphericalMap(float3 v) {
    var uv = float2(atan2(v.z, v.x), asin(v.y));
    uv *= invAtan;
    uv += 0.5;
    return uv;
}

float2 dir_to_equirect_uv(float3 dir) {
    static let PI = 3.14159265;
    float u = atan2(dir.z, dir.x) / (2 * PI) + 0.5;
    float v = acos(clamp(dir.y, -1, 1)) / PI;
    return float2(u, v);
}

[shader("miss")]
void miss_entry(inout State payload) {
    // if (payload.bounce == 0) {
    //     payload.hit = false;
    //     return;
    // }

    let uv = dir_to_equirect_uv(WorldRayDirection());
    var env_color = sampled_images[pc.env_map].SampleLevel(samplers[0], uv, 0.0).rgb;
    // clamp firefly-prone high-luminance texels
    let lum = luminance(env_color);
    let max_lum = 1.0;
    if (lum > max_lum) {
        env_color *= max_lum / lum;
    }
    payload.color += payload.throughput * half3(env_color);
}
float3 HitPos() {
    return WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
}

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
    // return Principled(0.8, 0.3, 1.0, { 0 }, {}, {}, { 0 });
    case 1:
        return Principled(float3(0.8, 0.3, 0.3), 0.5, 0, {}, { 0, 1.0 });
    case 2:
        return Principled(float3(1), 0.2, 1, {}, {}, {}, { 0, 1.44, 0 });
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
        return Principled(float3(0.8), 0.0, 0.0, {}, {}, { 1, 1.0 }, { 0 });
    }
}

float3 direct_lighting(Principled mat,
                       float3 pos,
                       Surface surface,
                       float3 ray_dir,
                       inout uint seed) {
    static let lights = AreaLight[](
        AreaLight(float3(0, 10, 0), float3(0, -1, 0), 1.0, 1.0, float3(10, 10, 10)),
        AreaLight(float3(2.4, 6, 3), float3(1, 0, 0), 1, 0.3, float3(100, 40, 130)),
        AreaLight(float3(4.4, 6, 3), float3(1, 0, 0), 1, 0.3, float3(10, 140, 130)),
        AreaLight(float3(4, 23, 3), float3(1, 0, 0), 1, 0.3, float3(10, 140, 130)),
        AreaLight(float3(-4.4, 6, -3), float3(1, 0, 0), 0.3, 0.3, float3(90, 0, 0)),
        AreaLight(float3(-4.4, 3, -3), float3(1, 0, 0), 0.3, 0.3, float3(0, 0, 300)),
        AreaLight(float3(4.4, 3, 0), float3(-1, 0, 0), 1, 0.3, float3(300, 600, 1000)), );

    static let light_count = lights.getCount();
    if (light_count == 0)
        return float3(0);

    float w_sum = 0.0;
    uint chosen_idx = 0;
    float3 chosen_point = float3(0);
    float chosen_target_pdf = 0.0;

    for (uint m = 0; m < LIGHT_CANDIDATES; m++) {
        seed = random::hash_combine(m, seed);
        let i = random::ifrom_range(seed, 0, light_count - 1);

        let light = lights[i];
        let u = random::shuffled_scrambled_sobol2d(m, seed);
        let light_point = light.sample_point(u);

        let to_light = light_point - pos;
        let dist2 = max(dot(to_light, to_light), 1e-5);
        let to_light_dir = to_light * rsqrt(dist2);
        let NoL_light = max(dot(light.normal, -to_light_dir), 0.0);
        let NoL = max(dot(surface.normal, to_light_dir), 0.0);
        let area_pdf = max(light.sample_pdf(), 1e-8);

        let target_pdf = luminance(light.color) * NoL * NoL_light / (dist2 * area_pdf);
        let source_pdf = 1.0 / float(light_count);
        let w = target_pdf / max(source_pdf, 1e-8);

        w_sum += w;
        if (random::unit(seed) < w / w_sum) {
            chosen_idx = i;
            chosen_point = light_point;
            chosen_target_pdf = target_pdf;
        }
    }

    if (w_sum <= 0.0 || chosen_target_pdf <= 0.0)
        return float3(0);

    let light = lights[chosen_idx];
    let to_light = chosen_point - pos;
    let dist = length(to_light);
    let dist2 = max(dist * dist, 1e-5);
    let to_light_dir = to_light / dist;
    let NoL_light = max(dot(light.normal, -to_light_dir), 0.0);
    let NoL = max(dot(surface.normal, to_light_dir), 0.0);

    if (NoL <= 1e-4)
        return float3(0);

    RayDesc shadow_ray;
    shadow_ray.Origin = pos;
    shadow_ray.Direction = to_light_dir;
    shadow_ray.TMin = 0.0001;
    shadow_ray.TMax = dist - 0.0001;
    var shadow = ShadowState(true);
    TraceRay(tlas,
             RAY_FLAG_SKIP_CLOSEST_HIT_SHADER | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH |
                 RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
             0xFF,
             1,
             0,
             1,
             shadow_ray,
             shadow);
    if (shadow.hit)
        return float3(0);

    let view = -ray_dir;
    let brdf = mat.eval(view, to_light_dir, surface);
    let area_pdf = max(light.sample_pdf(), 1e-8);

    let full_integrand = light.color * brdf * NoL * NoL_light / (dist2 * area_pdf);

    let ris_weight = (w_sum / float(LIGHT_CANDIDATES)) / chosen_target_pdf;

    let contribution = full_integrand * ris_weight;

    let lum = luminance(contribution);
    let clamped = contribution * min(1.0, 9.0 / max(lum, 1e-5));
    return clamped;
}

[shader("closesthit")]
void closest_hit_entry(inout State payload,
                       const BuiltInTriangleIntersectionAttributes attr) {
    var seed = payload.seed;

    let hit = HitInfo::from_current_hit();

    let range = pc.ranges[hit.instance];
    let geometry = pc.geometries[range.begin + hit.geometry];
    let buffer = pc.buffers[geometry.buffer_index];
    let material = pc.materials[hit.instance];

    let primitive = Primitive::make(buffer, hit.primitive, attr.barycentrics);
    let surface = Surface::make(primitive.geometric_norm, primitive.norm);
    let safe_pos = hit.pos + surface.normal * 1e-6;

    var mat = get_material(material.index);
    mat.roughness += clamp(mat.roughness * payload.get_bounce() * 0.75, 0, 1);

    let bsdf_u = random::shuffled_scrambled_sobol4d(payload.get_bounce(), payload.seed);
    let light_u =
        random::shuffled_scrambled_sobol2d(payload.get_bounce(), payload.seed + 1);

    var Lindirect = float3(0);
    if (payload.get_bounce() < LIGHT_BOUNCES) {
        Lindirect = direct_lighting(mat, safe_pos, surface, payload.ray_dir, seed);
    }
    let result = mat.scatter(surface, payload.ray_dir, bsdf_u, seed);

    payload.seed = seed;
    payload.color += payload.throughput * half3(Lindirect);

    let new_throughput = clamp(result.throughput, float3(0), float3(10));
    payload.throughput *= half3(new_throughput);

    payload.ray_dir = half3(result.direction);
    // payload.hit = true;
    payload.bounce_hit = payload.new_hit(true);
    payload.pos = safe_pos;
    payload.norm_enc = oct_encode(surface.normal);
}
