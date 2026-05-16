module state;

public struct State{
    public float3 pos;
    public float3 ray_dir;

    public float3 color;
    public float3 throughput;

    public uint seed;
    public uint bounce;
    public bool hit;
};
