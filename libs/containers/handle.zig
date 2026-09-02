pub fn Handle(comptime ElmType: type) type {
    return extern struct {
        const Type = ElmType;
        slot: u32 = 0,
        gen: u32 = 0,

        pub fn unique(self: @This()) u64 {
            return @bitCast(self);
        }
    };
}
