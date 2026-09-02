const vec_import = @import("./vec.zig");

const Vec = vec_import.Vec;

pub fn Mat(comptime Rows: usize, comptime Cols: usize, comptime Scalar: type) type {
    return extern struct {
        pub const __mthmat: bool = true;

        v: [Cols]Vec(Rows, Scalar),

        pub const rows = Rows;
        pub const cols = Cols;
        pub const T = Scalar;
        pub const ColVec = Vec(Rows, Scalar);
        pub const RowVec = Vec(Cols, Scalar);
        pub const Array = [Cols][Rows]Scalar;

        const Self = @This();

        pub inline fn from_columns(columns: [Cols]ColVec) Self {
            return .{ .v = columns };
        }

        pub inline fn identity() Self {
            comptime if (Rows != Cols) @compileError("identity requires a square matrix");
            var m: Self = undefined;
            inline for (0..Cols) |c| {
                var column = ColVec.zero();
                column.v[c] = 1; // was: `col.v[c] = 1` — `col` is undefined, you named the var `column`
                m.v[c] = column; // was: `m.v[c] = col`
            }
            return m;
        }
        pub inline fn col(self: Self, c: usize) ColVec {
            return self.v[c];
        }

        pub inline fn at(self: Self, r: usize, c: usize) Scalar {
            return self.v[c].v[r];
        }

        pub inline fn mul_vec(self: Self, v: RowVec) ColVec {
            var out = ColVec.zero();
            inline for (0..Cols) |c| {
                out = self.v[c].mul_scalar(v.v[c]).add(out);
            }
            return out;
        }

        pub inline fn mul_mat(a: Self, comptime OtherCols: usize, b: Mat(Cols, OtherCols, Scalar)) Mat(Rows, OtherCols, Scalar) {
            var result: Mat(Rows, OtherCols, Scalar) = undefined;
            inline for (0..OtherCols) |c| {
                result.v[c] = a.mul_vec(b.col(c));
            }
            return result;
        }

        pub inline fn to_array(self: Self) Array {
            var out: Array = undefined;
            inline for (0..Cols) |c| {
                out[c] = self.v[c].to_array();
            }
            return out;
        }

        pub inline fn add(a: Self, b: Self) Self {
            var out: Self = undefined;
            inline for (0..Cols) |c| out.v[c] = a.v[c].add(b.v[c]);
            return out;
        }

        pub inline fn sub(a: Self, b: Self) Self {
            var out: Self = undefined;
            inline for (0..Cols) |c| out.v[c] = a.v[c].sub(b.v[c]);
            return out;
        }

        pub inline fn mul_scalar(a: Self, s: Scalar) Self {
            var out: Self = undefined;
            inline for (0..Cols) |c| out.v[c] = a.v[c].mul_scalar(s);
            return out;
        }

        pub inline fn eql(a: Self, b: Self) bool {
            inline for (0..Cols) |c| {
                if (!a.v[c].eql(b.v[c])) return false;
            }
            return true;
        }

        pub inline fn transpose(self: Self) Mat(Cols, Rows, Scalar) {
            var out: Mat(Cols, Rows, Scalar) = undefined;
            inline for (0..Rows) |r| {
                inline for (0..Cols) |c| {
                    out.v[r].v[c] = self.v[c].v[r];
                }
            }
            return out;
        }

        pub inline fn translation(t: Vec(3, Scalar)) Self {
            comptime if (Rows != 4 or Cols != 4) @compileError("translation requires Mat4");
            var m = identity();
            m.v[3] = .{ .v = .{ t.x(), t.y(), t.z(), 1 } };
            return m;
        }

        pub inline fn scaling(s: Vec(3, Scalar)) Self {
            comptime if (Rows != 4 or Cols != 4) @compileError("scaling requires Mat4");
            var m = identity();
            m.v[0].v[0] = s.x();
            m.v[1].v[1] = s.y();
            m.v[2].v[2] = s.z();
            return m;
        }

        /// Right-handed rotation about an arbitrary normalized axis, angle in radians.
        pub inline fn rot_axis_angle(axis: Vec(3, Scalar), angle_rad: Scalar) Self {
            comptime if (Rows != 4 or Cols != 4) @compileError("rot_axis_angle requires Mat4");
            const c = @cos(angle_rad);
            const s = @sin(angle_rad);
            const t = 1 - c;
            const x = axis.x();
            const y = axis.y();
            const z = axis.z();

            var m = identity();
            m.v[0] = .{ .v = .{ t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0 } };
            m.v[1] = .{ .v = .{ t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0 } };
            m.v[2] = .{ .v = .{ t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0 } };
            return m;
        }

        pub inline fn look_at(eye: Vec(3, Scalar), target: Vec(3, Scalar), up: Vec(3, Scalar)) Self {
            comptime if (Rows != 4 or Cols != 4) @compileError("look_at requires Mat4");
            const f = target.sub(eye).normalize();
            const s = vec_import.cross(f, up).normalize();
            const u = vec_import.cross(s, f);

            var m = identity();
            m.v[0] = .{ .v = .{ s.x(), u.x(), -f.x(), 0 } };
            m.v[1] = .{ .v = .{ s.y(), u.y(), -f.y(), 0 } };
            m.v[2] = .{ .v = .{ s.z(), u.z(), -f.z(), 0 } };
            m.v[3] = .{ .v = .{ -s.dot(eye), -u.dot(eye), f.dot(eye), 1 } };
            return m;
        }

        pub inline fn to_mat3(self: Self) Mat(3, 3, Scalar) {
            comptime if (Rows != 4 or Cols != 4) @compileError("to_mat3 requires Mat4");
            var out: Mat(3, 3, Scalar) = undefined;
            inline for (0..3) |c| {
                out.v[c] = .{ .v = .{ self.v[c].v[0], self.v[c].v[1], self.v[c].v[2] } };
            }
            return out;
        }
    };
}

pub const float4x4 = Mat(4, 4, f32);
pub const float3x3 = Mat(3, 3, f32);
