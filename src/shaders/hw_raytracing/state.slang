module state;

public struct State{
    public static uint BOUNCES = 12;

    public RayDesc ray;

    public float3 color;
    public float3 throughput;

    public uint seed;
    public bool hit;
};
