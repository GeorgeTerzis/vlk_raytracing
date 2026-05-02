module rand;

public struct random {
    public static uint pcg_hash(inout uint v) {
        v = v * 747796405u + 2891336453u;
        v = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
        v = (v >> 22u) ^ v;
        return v;
    }

    public static float unit(inout uint seed) {
        seed = pcg_hash(seed);
        let n = float(seed) * (1.0 / 4294967296.0);
        return n;
    }

    public static float from_range(inout uint seed, float min, float max) {
        seed = pcg_hash(seed);
        let n = float(seed) / float(0xffffffffu);

        return min + (max - min) * n;
    }

    public static float2 f2(inout uint seed) {
        return { unit(seed), unit(seed) };
    }

    public static float3 f3(inout uint seed) {
        return { unit(seed), unit(seed), unit(seed) };
    }
};
