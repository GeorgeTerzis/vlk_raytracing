module material;

import surface;
import state;
import lobe;

public interface Material {
    public void scatter(Surface surface,
                        inout State payload);
    public float3 eval(float3 view, float3 light_dir, Surface surface);

};

