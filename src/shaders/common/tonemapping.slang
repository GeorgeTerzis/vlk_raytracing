public struct tonemapping {
    public static float3 aces(float3 x) {
        let a = 2.51;
        let b = 0.03;
        let c = 2.43;
        let d = 0.59;
        let e = 0.14;
        return (x * (a * x + b)) / (x * (c * x + d) + e);
    }
}
