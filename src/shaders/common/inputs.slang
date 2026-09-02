public struct Camera {
    public float3 pos;
    public float3x3 basis;
    public float fov;
};

public struct Textures {
    public struct Temporal {
        public uint col;
        public uint norm;
        public uint pos;
    };
    public Temporal curr;
    public Temporal hist;
};
