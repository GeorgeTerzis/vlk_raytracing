module state;

public struct State {
    public float3 pos;
    public half3 color;
    public half3 throughput;
    public half3 ray_dir;

    public uint norm_enc;
    public uint seed;

    public uint bounce_hit;

    static public uint new_bounce(uint n) {
        return n << 1;
    }
    public uint new_hit(bool b) {
        return (bounce_hit & ~1u) | ((b) ? 1u : 0u);
    }
    public uint get_bounce() {
        return bounce_hit >> 1;
    }
    public bool get_hit() {
        return (bounce_hit & 1u) != 0u;
    }
};
