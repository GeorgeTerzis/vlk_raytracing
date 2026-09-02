struct PC {
    struct Camera {
        float3 pos;
        float3x3 basis;
        float fov;
    };

    struct Textures {
        struct Temporal {
            uint col;
            uint norm;
            uint pos;
        };
        Temporal curr;
        Temporal hist;
    };

    uint frame;
    Camera cam;
    Camera prev_cam;
    uint2 res;
    Textures textures;
};

[[vk::push_constant]]
PC pc;

[[vk::binding(0, 0)]]
SamplerState samplers[];
[[vk::binding(1, 0)]]
Texture2D sampled_images[];
[[vk::binding(2, 0)]]
RWTexture2D storage_images[];

float2 reproject_to_prev(float3 world_pos) {
    let to_point = world_pos - pc.prev_cam.pos;
    let local_pt = mul(transpose(pc.prev_cam.basis), to_point);

    if (local_pt.z >= -1e-4) {
        return float2(-1, -1);
    }

    let t = -1.0 / local_pt.z;

    let uv = float2(local_pt.x, -local_pt.y) * t;
    let pixel_offset = (uv / pc.prev_cam.fov) * float(pc.res.y);
    return pixel_offset + float2(pc.res.xy) * 0.5;
}

static let MAX_HISTORY = 32.0;

struct TemporalResult {
    float3 color;
    float count;
};

float3
clamp_history(RWTexture2D<float4> color_tex, int2 pixel, uint2 res, float3 hist_color) {
    float3 min_c = float3(1e10);
    float3 max_c = float3(-1e10);
    [unroll]
    for (int dy = -1; dy <= 1; dy++) {
        [unroll]
        for (int dx = -1; dx <= 1; dx++) {
            int2 tap = pixel + int2(dx, dy);
            if (any(tap < int2(0, 0)) || any(tap >= int2(res)))
                continue;
            let c = color_tex[tap].rgb;
            min_c = min(min_c, c);
            max_c = max(max_c, c);
        }
    }
    return clamp(hist_color, min_c, max_c);
}

TemporalResult
accumulate_temporal(float3 src_color, float3 primary_pos, float3 primary_norm) {
    let prev_pix = reproject_to_prev(primary_pos);
    let in_bounds =
        all(prev_pix >= float2(0.0, 0.0)) && all(prev_pix < float2(pc.res.xy));

    float confidence = 0.0;
    float4 hist = float4(0.0);

    if (in_bounds) {
        int2 prev_pixel = int2(prev_pix);
        let hist_pos = sampled_images[pc.textures.hist.pos].Load(int3(prev_pixel, 0)).rgb;

        let hist_norm =
            sampled_images[pc.textures.hist.norm].Load(int3(prev_pixel, 0)).rgb;
        let hist_norm_len_sq = dot(hist_norm, hist_norm);

        if (hist_norm_len_sq > 1e-8) {
            float3 hnorm = hist_norm * rsqrt(hist_norm_len_sq);
            float3 cnorm = normalize(primary_norm);
            let pos_dist = length(hist_pos - primary_pos);
            let pos_threshold = max(0.01, length(primary_pos - pc.cam.pos) * 0.05);
            let pos_weight = saturate(1.0 - pos_dist / pos_threshold);
            let normal_similarity = dot(hnorm, cnorm);
            let normal_weight =
                smoothstep(cos(radians(60.0)), cos(radians(10.0)), normal_similarity);
            confidence = pos_weight * normal_weight;

            if (confidence > 0.01) {
                hist = sampled_images[pc.textures.hist.col].Load(int3(prev_pixel, 0));
            }
        }
    }

    float history_alpha = 0.0;
    float count = 1.0;
    if (confidence > 0.5) {
        count = min(hist.a + 1.0, MAX_HISTORY);
        history_alpha = (count - 1.0) / count;
    } else if (confidence > 0.01 && hist.a > 0.0) {
        count = max(hist.a * 0.5, 1.0);
        history_alpha = ((count - 1.0) / count) * confidence;
    }
    TemporalResult result;
    result.color = lerp(src_color, hist.rgb, history_alpha);
    result.count = count;
    return result;
}

[numthreads(8, 8, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    let pixel = dtid.xy;
    uint width, height;
    storage_images[pc.textures.curr.pos].GetDimensions(width, height);
    if (pixel.x >= width || pixel.y >= height)
        return;
    let uv = (float2(pixel) + 0.5) / float2(width, height);
    let src = storage_images[pc.textures.curr.col][pixel];
    let primary_pos = storage_images[pc.textures.curr.pos][pixel].rgb;
    let primary_norm = storage_images[pc.textures.curr.norm][pixel].rgb;

    var col = src.rgb;
    if (storage_images[pc.textures.curr.norm][pixel].w > 0.1) {
        let result = accumulate_temporal(src.rgb, primary_pos, primary_norm);
        col = result.color;
        storage_images[pc.textures.curr.col][pixel] = float4(col, result.count);
    } else {
        storage_images[pc.textures.curr.col][pixel] = float4(col, 1);
    }

    // io[pixel] = float4(col, 1.0);
}
