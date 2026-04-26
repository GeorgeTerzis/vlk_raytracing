module emission;

import material;
import math;
import state;
import surface;

public struct Emission : Material {
    public float3 color;
    public float strength;

    public void scatter(Surface surface, inout State payload) {
        payload.color += payload.throughput * (color * strength);
        payload.hit = false;
    }
};
