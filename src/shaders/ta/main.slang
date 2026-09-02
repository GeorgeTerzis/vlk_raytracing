import "../common/rand";
import "../common/math";
import "../common/inputs";

struct PC {
    Camera cam;
    Camera prev_cam;
    Textures textures;
    uint raw;
};

[[vk::push_constant]]
PC pc;

[[vk::binding(0, 0)]]
SamplerState samplers[];
[[vk::binding(1, 0)]]
Texture2D sampled_images[];
[[vk::binding(2, 0)]]
RWTexture2D storage_images[];

// public struct reproject {
//     public static let MAX_HISTORY = 32.0;

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

//     public struct TemporalResult {
//         float3 color;
//         float count;
//     };

//     static float sample_confidence(int2 tap, float3 primary_pos, float3 primary_norm) {
//         let hist_pos = sampled_images[pc.textures.hist.pos].Load(int3(tap, 0)).rgb;
//         let hist_norm = sampled_images[pc.textures.hist.norm].Load(int3(tap, 0)).rgb;
//         let hist_norm_len_sq = dot(hist_norm, hist_norm);
//         if (hist_norm_len_sq <= 1e-8)
//             return 0.0;

//         float3 hnorm = hist_norm * rsqrt(hist_norm_len_sq);
//         float3 cnorm = normalize(primary_norm);
//         let view_dir = normalize(pc.cam.pos - primary_pos);
//         let grazing = max(dot(cnorm, view_dir), 0.05);
//         let pos_dist = length(hist_pos - primary_pos);
//         let pos_threshold = max(0.01, length(primary_pos - pc.cam.pos) * 0.05 /
//         grazing); let pos_weight = saturate(1.0 - pos_dist / pos_threshold); let
//         normal_similarity = dot(hnorm, cnorm); let normal_weight =
//             smoothstep(cos(radians(60.0)), cos(radians(20.0)), normal_similarity);
//         return pos_weight * normal_weight;
//     }
//     static void sample_neighborhood_stats(uint2 center_pixel,
//                                           uint2 res,
//                                           out float3 nmin,
//                                           out float3 nmax) {
//         float3 sum = float3(0.0);
//         float3 sum_sq = float3(0.0);

//         [[unroll]]
//         for (int dy = -1; dy <= 1; dy++) {
//             [[unroll]]
//             for (int dx = -1; dx <= 1; dx++) {
//                 int2 tap =
//                     clamp(int2(center_pixel) + int2(dx, dy), int2(0, 0), int2(res) -
//                     1);
//                 let c = sampled_images[pc.raw].Load(int3(tap, 0)).rgb;
//                 sum += c;
//                 sum_sq += c * c;
//             }
//         }

//         let n = 9.0;
//         let mean = sum / n;
//         let variance = max(sum_sq / n - mean * mean, float3(0.0));
//         let stddev = sqrt(variance);

//         static let GAMMA =
//             5.0; // widen/tighten the box; higher = more tolerant, less aggressive
//             clamp
//         nmin = max(mean - GAMMA * stddev, float3(0.0));
//         nmax = mean + GAMMA * stddev;
//     }
//     static void sample_neighborhood_min_max(uint2 center_pixel,
//                                             uint2 res,
//                                             out float3 nmin,
//                                             out float3 nmax) {
//         let center_col = sampled_images[pc.raw].Load(int3(center_pixel, 0)).rgb;
//         nmin = center_col;
//         nmax = center_col;

//         [[unroll]]
//         for (int dy = -1; dy <= 1; dy++) {
//             [[unroll]]
//             for (int dx = -1; dx <= 1; dx++) {
//                 // if (dx == 0 && dy == 0)
//                 //     continue;
//                 int2 tap =
//                     clamp(int2(center_pixel) + int2(dx, dy), int2(0, 0), int2(res) -
//                     1);
//                 let tap_col = sampled_images[pc.raw].Load(int3(tap, 0)).rgb;
//                 nmin = min(nmin, tap_col);
//                 nmax = max(nmax, tap_col);
//             }
//         }
//     }

//     public static TemporalResult accumulate_temporal(const uint2 res,
//                                                      uint2 pixel,
//                                                      float3 src_color,
//                                                      float3 primary_pos,
//                                                      float3 primary_norm) {
//         let prev_pix = reproject_to_prev(primary_pos, res);
//         let in_bounds = all(prev_pix >= float2(0.0, 0.0)) && all(prev_pix <
//         float2(res));

//         float confidence = 0.0;
//         int2 best_pixel = int2(prev_pix);

//         if (in_bounds) {
//             int2 base = int2(prev_pix);
//             let c = sample_confidence(base, primary_pos, primary_norm);
//             if (c > confidence) {
//                 confidence = c;
//                 best_pixel = base;
//             }
//         }

//         float4 hist = float4(0.0);
//         if (confidence > 0.01) {
//             hist = sampled_images[pc.textures.hist.col].Load(int3(best_pixel, 0));

//             if (confidence < 0.9) { // only clamp when reprojection is uncertain
//                 float3 nmin, nmax;
//                 sample_neighborhood_stats(pixel, res, nmin, nmax);
//                 hist.rgb = clamp(hist.rgb, nmin, nmax);
//             }
//         }

//         let count = lerp(1.0, min(hist.a + 1.0, MAX_HISTORY), confidence);
//         let history_alpha = max(0.01, confidence) * (count - 1.0) / count;

//         TemporalResult result;
//         result.color = lerp(src_color, hist.rgb, history_alpha);
//         result.count = count;
//         return result;
//     }
// };

float2 CameraReproject(const Texture2D pos_tex,
                       const float2 uv,
                       const uint2 res,
                       const uint2 pixel) {
    let primary_pos = pos_tex.Load(int3(pixel, 0)).rgb;

    let to_point = primary_pos - pc.prev_cam.pos;
    let local_pt = mul(transpose(pc.prev_cam.basis), to_point);

    if (local_pt.z >= -1e-4) {
        return float2(-1, -1);
    }

    let t = -1.0 / local_pt.z;
    let proj_uv = float2(local_pt.x, -local_pt.y) * t;

    let pixel_offset = (proj_uv / pc.prev_cam.fov) * float(res.y);
    let prev_pixel = pixel_offset + float2(res) * 0.5;

    return prev_pixel / float2(res);
}

[numthreads(8, 8, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    let pixel = dtid.xy;
    uint width, height;

    let CurrentTexture = sampled_images[pc.raw];
    CurrentTexture.GetDimensions(width, height);

    let res = uint2(width, height);
    let uv = (float2(pixel) + 0.5) / float2(res);

    if (pixel.x >= res.x || pixel.y >= res.y)
        return;

    let reprojectedUV =
        CameraReproject(sampled_images[pc.textures.curr.pos], uv, res, pixel);
    let currentColor = CurrentTexture.Sample(samplers[0], uv, 0).rgb;

    let previousColor =
        sampled_images[pc.textures.hist.col].Sample(samplers[0], reprojectedUV, 0).rgb;

    var minColor = float3(9999.0);
    var maxColor = float3(-9999.0);

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            let color =
                CurrentTexture.Sample(samplers[0], uv + float2(x, y) / (res.x + res.y), 0)
                    .rgb;

            minColor = min(minColor, color);
            maxColor = max(maxColor, color);
        }
    }

    let previousColorClamped = clamp(previousColor, minColor, maxColor);

    let in_bounds =
        all(reprojectedUV >= float2(0.0, 0.0)) && all(reprojectedUV < float2(1.0, 1.0));

    let currentLuminance = luminance(currentColor);
    let previousLuminance = luminance(previousColorClamped);
    let currentLuminanceWeight = 1.0 / (1.0 + currentLuminance);
    let previousLuminanceWeight = 1.0 / (1.0 + previousLuminance);

    static let currentStaticWeight = 0.1;
    static let previousStaticWeight = 1.0 - currentStaticWeight;

    let currentWeight = currentStaticWeight * currentLuminanceWeight;
    let previousWeight = previousStaticWeight * previousLuminanceWeight;

    var output = float3(0);
    if (in_bounds) {
        output = (currentColor * currentWeight + previousColorClamped * previousWeight) /
                 (currentWeight + previousWeight);
    } else {
        output = currentColor;
    }

    storage_images[pc.textures.curr.col][pixel] = float4(output, 1);
}
