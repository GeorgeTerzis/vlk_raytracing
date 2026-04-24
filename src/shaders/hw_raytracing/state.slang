module state;

public struct State{
    public RayDesc ray;

    public float3 color;
    public float3 throughput;

    public uint seed;
    public bool hit;

    public float medium_t = 0.0;
};
