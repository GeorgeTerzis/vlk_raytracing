module mesh;

public struct Tri {
    public float3 v0;
    public float3 v1;
    public float3 v2;

    public float3 normal() {
        let e0 = v1 - v0;
        let e1 = v2 - v0;
        return normalize(cross(e0, e1));
    }

    public float3 interpolate(float2 bary) {
        return v0 * (1.0 - bary.x - bary.y) + v1 * bary.x + v2 * bary.y;
    }
};
public struct Normals {
    float3 n0;
    float3 n1;
    float3 n2;
}

public struct Mesh {

    public struct Pointers {
        float3* verts;
        uint* indices;

        public Tri get_tri(uint prim_index) {
            uint base = prim_index * 3;
            uint i0 = indices[base + 0];
            uint i1 = indices[base + 1];
            uint i2 = indices[base + 2];

            Tri tri;
            tri.v0 = verts[i0];
            tri.v1 = verts[i1];
            tri.v2 = verts[i2];
            return tri;
        }
    };
    public struct InstanceData{
        public Pointers pointers;
    };
};
