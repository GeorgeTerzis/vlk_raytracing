const std = @import("std");

pub const Component = enum(u32) { x = 0, y = 1, z = 2, w = 3 };

pub fn Vec(comptime Len: usize, comptime Scalar: type) type {
    return extern struct {
        pub const __mthvec: bool = true;
        pub const length = Len;
        pub const T = Scalar;
        pub const Vector = @Vector(length, Scalar);
        pub const Array = [length]Scalar;
        const Self = @This();

        v: Vector,

        pub inline fn init(components: anytype) Self {
            comptime if (components.len != length)
                @compileError(std.fmt.comptimePrint(
                    "Vec({d}, {s}).init expects {d} components, got {d}",
                    .{ length, @typeName(Scalar), length, components.len },
                ));
            var out: Self = undefined;
            inline for (components, 0..) |c, i| {
                out.v[i] = c;
            }
            return out;
        }
        pub inline fn splat(s: Scalar) Self {
            return .{ .v = @splat(s) };
        }
        pub inline fn zero() Self {
            return splat(0);
        }
        pub inline fn from_slice(a: []Scalar) Self {
            return .{ .v = a };
        }
        pub inline fn from_array(a: Array) Self {
            return .{ .v = a };
        }
        pub inline fn to_array(self: Self) Array {
            return self.v;
        }
        pub inline fn x(self: Self) Scalar {
            return self.v[0];
        }
        pub inline fn y(self: Self) Scalar {
            comptime if (length < 2) @compileError("Vec has no y component");
            return self.v[1];
        }
        pub inline fn z(self: Self) Scalar {
            comptime if (length < 3) @compileError("Vec has no z component");
            return self.v[2];
        }
        pub inline fn w(self: Self) Scalar {
            comptime if (length < 4) @compileError("Vec has no w component");
            return self.v[3];
        }
        pub inline fn add(a: Self, b: Self) Self {
            return .{ .v = a.v + b.v };
        }
        pub inline fn sub(a: Self, b: Self) Self {
            return .{ .v = a.v - b.v };
        }
        pub inline fn mul(a: Self, b: Self) Self {
            return .{ .v = a.v * b.v };
        }
        pub inline fn div(a: Self, b: Self) Self {
            return .{ .v = a.v / b.v };
        }
        pub inline fn mul_scalar(a: Self, s: Scalar) Self {
            return .{ .v = a.v * splat(s).v };
        }
        pub inline fn add_scalar(a: Self, s: Scalar) Self {
            return .{ .v = a.v + splat(s).v };
        }
        pub inline fn mul_add(a: Self, b: Self, c: Self) Self {
            return .{ .v = switch (@typeInfo(Scalar)) {
                .float => @mulAdd(Vector, a.v, b.v, c.v),
                .int => a.v * b.v + c.v,
                else => @compileError("mul_add requires a float or int scalar, found '" ++ @typeName(Scalar) ++ "'"),
            } };
        }
        /// a * s + c, scalar variant
        pub inline fn smul_add(a: Self, s: Scalar, c: Self) Self {
            return mul_add(a, splat(s), c);
        }
        pub inline fn lerp(a: Self, b: Self, t: Scalar) Self {
            return b.sub(a).smul_add(t, a);
        }
        pub inline fn negate(a: Self) Self {
            return .{ .v = -a.v };
        }
        pub inline fn dot(a: Self, b: Self) Scalar {
            return @reduce(.Add, a.v * b.v);
        }
        pub inline fn len2(a: Self) Scalar {
            return dot(a, a);
        }
        pub inline fn len(a: Self) Scalar {
            return @sqrt(len2(a));
        }
        pub inline fn normalize(a: Self) Self {
            const l = len(a);
            return if (l == 0) a else a.mul_scalar(1.0 / l);
        }
        pub inline fn eql(a: Self, b: Self) bool {
            return @reduce(.And, a.v == b.v);
        }
        pub inline fn add_comp(self: *Self, comptime c: Component, delta: Scalar) void {
            comptime if (@intFromEnum(c) >= length) @compileError("component out of range");
            self.v[@intFromEnum(c)] += delta;
        }
        pub inline fn mul_comp(self: *Self, comptime c: Component, delta: Scalar) void {
            comptime if (@intFromEnum(c) >= length) @compileError("component out of range");
            self.v[@intFromEnum(c)] *= delta;
        }
        pub inline fn swizzle(self: Self, comptime components: anytype) Vec(components.len, Scalar) {
            comptime var mask: [components.len]i32 = undefined;
            inline for (components, 0..) |c, i| {
                comptime if (@intFromEnum(c) >= length)
                    @compileError("swizzle component out of range for this vector's length");
                mask[i] = @intFromEnum(c);
            }
            return .{ .v = @shuffle(Scalar, self.v, undefined, mask) };
        }

        pub fn cross(a: Vec(3, Scalar), b: Vec(3, Scalar)) Vec(3, Scalar) {
            return .{
                .v = .{
                    a.y() * b.z() - a.z() * b.y(),
                    a.z() * b.x() - a.x() * b.z(),
                    a.x() * b.y() - a.y() * b.x(),
                },
            };
        }
    };
}

pub const float2 = Vec(2, f32);
pub const float3 = Vec(3, f32);
pub const float4 = Vec(4, f32);

pub const double2 = Vec(2, f64);
pub const double3 = Vec(3, f64);
pub const double4 = Vec(4, f64);

pub const int2 = Vec(2, i32);
pub const int3 = Vec(3, i32);
pub const int4 = Vec(4, i32);

pub const uint2 = Vec(2, u32);
pub const uint3 = Vec(3, u32);
pub const uint4 = Vec(4, u32);
