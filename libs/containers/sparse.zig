const std = @import("std");
const handle_mod = @import("handle.zig");
const Handle = handle_mod.Handle;

pub fn MultiSparseSet(comptime MappedType: type, comptime StorageElm: type, comptime IndexType: type) type {
    const fields = std.meta.fields(StorageElm);
    const len = fields.len + 1;

    // this can be kinda replaced by this std.meta.FieldEnum(comptime T: type)
    var field_names: [len][]const u8 = undefined;
    var field_types: [len]type = undefined;
    var field_attributes: [len]std.builtin.Type.StructField.Attributes = undefined;
    const tag_int: type = u32;
    var field_values: [len]tag_int = undefined;

    {
        field_names[0] = "dense_entity";
        field_types[0] = u32;
        field_attributes[0] = .{
            .@"comptime" = false,
            .@"align" = @alignOf(u32),
        };
        field_values[0] = 0;
    }

    for (fields, 1..) |f, i| {
        const name = f.name;
        const T = f.type;
        const TT = T;
        field_names[i] = name;
        field_types[i] = TT;
        field_attributes[i] = .{
            .@"comptime" = false,
            .@"align" = @alignOf(TT),
        };
        field_values[i] = i;
    }

    const T = @Struct(.auto, null, &field_names, &field_types, &field_attributes);
    const E = @Enum(tag_int, .nonexhaustive, &field_names, &field_values);

    return struct {
        const Self = @This();
        const Tag = E;
        const Elm = T;
        const Index = IndexType;
        const MultiArrayList = std.MultiArrayList(T);

        sparse: []Index,
        dense: MultiArrayList,

        pub fn init_buffer(sparse: []Index, dense: MultiArrayList) !Self {
            return .{
                .sparse = sparse,
                .dense = dense,
            };
        }

        pub fn init_alloc(allocator: std.mem.Allocator, entity_count: usize) !Self {
            const sparse_entities = try allocator.alloc(Index, entity_count);
            @memset(sparse_entities, std.math.maxInt(IndexType));

            var dense = MultiArrayList.empty;
            try dense.ensureTotalCapacity(allocator, entity_count / 4);

            return .{ .sparse = sparse_entities, .dense = dense };
        }

        fn make_elm(entity: u32, elm: StorageElm) T {
            var result: T = undefined;
            result.dense_entity = entity;
            inline for (std.meta.fields(StorageElm)) |f| {
                @field(result, f.name) = @field(elm, f.name);
            }
            return result;
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, handle: Handle(MappedType), elm: StorageElm) !void {
            const index = self.dense.len;
            try self.dense.append(allocator, make_elm(handle.slot, elm));
            self.sparse[handle.slot] = @intCast(index);
        }

        pub fn erase(self: *Self, handle: Handle(MappedType)) void {
            const remove_index = self.sparse[handle.slot];
            const last_index = self.dense.len - 1;

            self.dense.swapRemove(remove_index);
            if (remove_index != last_index) {
                const last_entity = self.dense.items(.dense_entity)[remove_index];
                self.sparse[last_entity] = remove_index;
            }

            self.sparse[handle.slot] = std.math.maxInt(IndexType);
        }

        pub fn contains(self: *const Self, handle: Handle(MappedType)) bool {
            return self.sparse[handle.slot] != std.math.maxInt(IndexType);
        }

        pub fn get(self: *const Self, handle: Handle(MappedType)) ?T {
            if (!self.contains(handle)) return null;
            return self.dense.get(self.sparse[handle.slot]);
        }

        pub fn index_of(self: *const Self, handle: Handle(MappedType)) ?Index {
            if (!self.contains(handle)) return null;
            return self.sparse[handle.slot];
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.sparse);
            self.dense.deinit(allocator);
        }
    };
}

pub fn Sparse(comptime Entity: type, comptime StorageElm: type, comptime IndexType: type) type {
    const Internal = struct {
        val: StorageElm,
    };
    return MultiSparseSet(Entity, Internal, IndexType);
}
