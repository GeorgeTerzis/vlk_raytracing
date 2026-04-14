module material;

import surface;
import state;

public interface Material {
    public void scatter(Surface surface,
                        inout State payload);
};

