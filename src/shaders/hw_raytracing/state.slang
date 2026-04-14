module state;

public struct State{
    public static uint BOUNCES = 10;

    public float3 color;
    public float3 throughput;

    public bool hit;

    public uint seed;

    public RayDesc ray;
    public uint bounce;
};
