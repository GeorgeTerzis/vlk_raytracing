import "../common/inputs.slang";
import "../common/math.slang";
import "../common/tonemapping.slang";

struct PC {
    uint col_input;  // sampled index — color to filter this pass
    uint norm_input; // sampled index — stable G-buffer normal (same every pass)
    uint pos_input;  // sampled index — stable G-buffer position (same every pass)
    uint output;     // storage index — this pass's output target
    float stepwidth;
    uint do_tonemap;
};

[[vk::push_constant]]
PC pc;

[[vk::binding(0, 0)]]
SamplerState samplers[];
[[vk::binding(1, 0)]]
Texture2D sampled_images[];
[[vk::binding(2, 0)]]
RWTexture2D storage_images[];

public struct atrous {
    // public static const float kernel[25] = {
    //     0.00390625, 0.015625,  0.0234375, 0.015625,  0.00390625, 0.015625, 0.0625,
    //     0.09375,    0.0625,    0.015625,  0.0234375, 0.09375,    0.140625, 0.09375,
    //     0.0234375,  0.015625,  0.0625,    0.09375,   0.0625,     0.015625, 0.00390625,
    //     0.015625,   0.0234375, 0.015625,  0.00390625
    // };

    public static const float c_phi = 0.2;
    public static const float n_phi = 0.1;
    public static const float p_phi = 1.0;
    static const float b3[5] = { 1.0 / 16.0,
                                 4.0 / 16.0,
                                 6.0 / 16.0,
                                 4.0 / 16.0,
                                 1.0 / 16.0 };

    public static float3 filter(float2 uv, uint2 res, float stepwidth) {
        let sampler = samplers[3];
        let colorMap = sampled_images[pc.col_input];
        let normalMap = sampled_images[pc.norm_input];
        let posMap = sampled_images[pc.pos_input];

        let step = float2(1.0 / float(res.x), 1.0 / float(res.y));

        let cval = colorMap.SampleLevel(sampler, uv, 0).rgb;
        let nval = normalMap.SampleLevel(sampler, uv, 0).rgb;
        let pval = posMap.SampleLevel(sampler, uv, 0).rgb;

        var sum = float3(0.0);
        var cum_w = 0.0;

        [[unroll]]
        for (var x = -2; x <= 2; x++) {
            [[unroll]]
            for (var y = -2; y <= 2; y++) {
                let offset = float2(x, y);
                let suv = uv + offset * step * stepwidth;

                let ctmp = colorMap.SampleLevel(sampler, suv, 0).rgb;
                let ntmp = normalMap.SampleLevel(sampler, suv, 0).rgb;
                let ptmp = posMap.SampleLevel(sampler, suv, 0).rgb;

                let tc = cval - ctmp;
                let c_w = min(exp(-dot(tc, tc) / c_phi), 1.0);

                let tn = nval.xyz - ntmp.xyz;
                let n_dist2 = max(dot(tn, tn) / (stepwidth * stepwidth), 0.0);
                let n_w = min(exp(-n_dist2 / n_phi), 1.0);

                let tp = pval.xyz - ptmp.xyz;
                let p_w = min(exp(-dot(tp, tp) / p_phi), 1.0);

                let bw = b3[x + 2] * b3[y + 2];
                let w = c_w * n_w * p_w;
                sum += ctmp * w * bw;
                cum_w += w * bw;
            }
        }

        return sum.rgb / max(cum_w, 1e-6);
    }
};

[numthreads(8, 8, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    let pixel = dtid.xy;
    uint width, height;
    let colTex = sampled_images[pc.col_input];
    colTex.GetDimensions(width, height);
    if (pixel.x >= width || pixel.y >= height)
        return;

    let normalMap = sampled_images[pc.norm_input];
    let res = uint2(width, height);
    let uv = (float2(pixel) + 0.5) / float2(res);

    let sampler = samplers[3];
    let cval = colTex.SampleLevel(sampler, uv, 0);

    let center_count = cval.a;
    let converged = saturate(center_count / 16.0);

    let filtered = atrous.filter(uv, res, pc.stepwidth);
    let result = lerp(filtered, cval.rgb, converged);
    let out_color = pc.do_tonemap != 0 ? tonemapping.aces(result) : result;
    storage_images[pc.output][pixel] = float4(colTex[pixel].rgb, 1);
}
