module rand;

public struct random {
    public struct seed {
        uint val;
    };
    public static uint pcg_hash(inout uint v) {
        v = v * 747796405u + 2891336453u;
        v = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
        v = (v >> 22u) ^ v;
        return v;
    }

    public static float unit(inout uint seed) {
        seed = pcg_hash(seed);
        let n = float(seed) / float(0xffffffffu);
        return n;
    }

    public static float from_range(inout uint seed, float min, float max) {
        seed = pcg_hash(seed);
        let n = float(seed) / float(0xffffffffu);

        return min + (max - min) * n;
    }

    public static float3 f3(inout uint seed) {
        return float3(unit(seed), unit(seed), unit(seed));
    }
};

// public uint pcg_hash(inout uint v) {
//     v = v * 747796405u + 2891336453u;
//     v = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
//     v = (v >> 22u) ^ v;
//     return v;
// }


// public float rand01(inout uint seed) {
//     seed = pcg_hash(seed);
//     let n = float(seed) / float(0xffffffffu);
//     return n;
// }
// public float rand(inout uint seed, float min, float max) {
//     seed = pcg_hash(seed);
//     let n = float(seed) / float(0xffffffffu);

//     return min + (max - min) * n;
// }

// public float3 rand_f3(inout uint seed) {
//     return float3(rand01(seed), rand01(seed), rand01(seed));
// }



