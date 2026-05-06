import surface;

struct LobeResult {
    float3 throughput;
    float3 direction;
};

interface Lobe {
    LobeResult sample_lobe(float3 view, Surface surface, float2 u, inout uint seed);
};
