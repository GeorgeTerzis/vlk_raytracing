module rand;

public struct random {

    public static uint hash(uint x) {
        x ^= x >> 16;
        x *= 0x7feb352du;
        x ^= x >> 15;
        x *= 0x846ca68bu;
        x ^= x >> 16;
        return x;
    }

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

    public static int ifrom_range(inout uint seed, int min, int max) {
        seed = pcg_hash(seed);

        let range_length = max - min;
        let n : int = max - (seed % (range_length + 1));
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
    public static float4 f4(inout uint seed) {
        return { unit(seed), unit(seed), unit(seed), unit(seed) };
    }

    public static uint32_t laine_karras_permutation(uint32_t x, uint32_t seed) {
        x += seed;
        x ^= x * 0x6c50b47c;
        x += x << 2;
        x ^= x * 0xb82f1e52;
        x += x << 3;
        x ^= x * 0xc7afe638;
        x += x << 5;
        x ^= x * 0x8d22f6e6;
        x += x << 1;
        return x;
    }
    public static uint reverse_bits(uint x) {
        x = (x << 16u) | (x >> 16u);
        x = ((x & 0x55555555u) << 1u) | ((x & 0xAAAAAAAAu) >> 1u);
        x = ((x & 0x33333333u) << 2u) | ((x & 0xCCCCCCCCu) >> 2u);
        x = ((x & 0x0F0F0F0Fu) << 4u) | ((x & 0xF0F0F0F0u) >> 4u);
        x = ((x & 0x00FF00FFu) << 8u) | ((x & 0xFF00FF00u) >> 8u);
        return x;
    }
    public static uint32_t nested_uniform_scramble(uint32_t x, uint32_t seed) {
        x = reverse_bits(x);
        x = laine_karras_permutation(x, seed);
        x = reverse_bits(x);
        return x;
    }
    public static float halton(uint index, uint base) {
        float result = 0.0;
        float f = 1.0 / float(base);
        uint i = index;

        // 32 iterations is overkill for any base >= 2 given uint range,
        // but cheap and safe. Loop naturally terminates early via the
        // `i == 0` check for smaller indices.
        for (uint bit = 0; bit < 32 && i > 0; bit++) {
            result += f * float(i % base);
            i /= base;
            f /= float(base);
        }

        return result;
    }

    public static float2 halton2d(uint index, uint base_x, uint base_y) {
        return float2(halton(index, base_x), halton(index, base_y));
    }
    public static float3 halton3d(uint index, uint base_x, uint base_y, uint base_z) {
        return float3(halton(index, base_x),
                      halton(index, base_y),
                      halton(index, base_z));
    }
    public static float4
    halton4d(uint index, uint base_x, uint base_y, uint base_z, uint base_w) {
        return float4(halton(index, base_x),
                      halton(index, base_y),
                      halton(index, base_z),
                      halton(index, base_w));
    }
    public static void sobol_direction_numbers(uint dim, out uint v[32]) {
        if (dim == 0u) {
            // van der Corput base 2
            for (uint i = 0; i < 32; i++) {
                v[i] = 1u << (31u - i);
            }
            return;
        }

        uint s;
        uint a;
        uint m[3];
        if (dim == 1u) {
            s = 1u;
            a = 0u;
            m[0] = 1u;
        } else if (dim == 2u) {
            s = 2u;
            a = 1u;
            m[0] = 1u;
            m[1] = 3u;
        } else {
            s = 3u;
            a = 1u;
            m[0] = 1u;
            m[1] = 3u;
            m[2] = 1u;
        }

        for (uint i = 0; i < s; i++) {
            v[i] = m[i] << (31u - i);
        }
        for (uint i = s; i < 32u; i++) {
            uint vi = v[i - s] ^ (v[i - s] >> s);
            for (uint k = 1; k < s; k++) {
                uint ak = (a >> (s - 1u - k)) & 1u;
                vi ^= ak * v[i - k];
            }
            v[i] = vi;
        }
    }

    public static uint sobol(uint index, uint dim) {
        uint v[32];
        sobol_direction_numbers(dim, v);
        uint x = 0u;
        for (uint bit = 0; bit < 32; bit++) {
            if (((index >> bit) & 1u) != 0u) {
                x ^= v[bit];
            }
        }
        return x;
    }

    public static uint4 sobol4d(uint index) {
        return uint4(sobol(index, 0u),
                     sobol(index, 1u),
                     sobol(index, 2u),
                     sobol(index, 3u));
    }

    public static uint hash_combine(uint seed, uint v) {
        uint h = v;
        pcg_hash(h);
        seed ^= h + 0x9e3779b9u + (seed << 6u) + (seed >> 2u);
        return seed;
    }

    public static float4 shuffled_scrambled_sobol4d(uint index, uint seed) {
        index = nested_uniform_scramble(index, seed);
        uint4 X = sobol4d(index);
        float4 result;
        for (int i = 0; i < 4; i++) {
            uint scrambled = nested_uniform_scramble(X[i], hash_combine(seed, uint(i)));
            result[i] = float(scrambled) * (1.0 / 4294967296.0);
        }
        return result;
    }

    public static uint2 sobol2d(uint index) {
        return uint2(sobol(index, 0u), sobol(index, 1u));
    }

    public static float2 shuffled_scrambled_sobol2d(uint index, uint seed) {
        index = nested_uniform_scramble(index, seed);
        let X = sobol2d(index);
        float2 result;
        for (int i = 0; i < 2; i++) {
            uint scrambled = nested_uniform_scramble(X[i], hash_combine(seed, uint(i)));
            result[i] = float(scrambled) * (1.0 / 4294967296.0);
        }
        return result;
    }
};
