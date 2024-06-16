const std = @import("std");
const Allocator = std.mem.Allocator;
const out = std.io.getStdOut().writer();

const Opcode = enum(u8) {
    const Self = @This();

    OP_RETURN,
    OP_CONST,

    pub fn toString(self: Self) []const u8 {
        return @tagName(self);
    }
};

const Value = union(enum) {
    const Self = @This();

    int: i64,
    unit,

    pub fn print(self: Self) !void {
        switch (self) {
            .int => |val| {
                try out.print("{d}", .{val});
            },
            .unit => {
                try out.print("none", .{});
            },
        }
    }
};

pub fn Chunk() type {
    return struct {
        const Self = @This();

        code: std.ArrayList(u8),
        pool: std.ArrayList(Value),
        name: []const u8,
        allocator: Allocator,

        pub fn init(allocator: Allocator, name: []const u8) Self {
            return Self{
                .allocator = allocator,
                .name = name,
                .code = std.ArrayList(u8).init(allocator),
                .pool = std.ArrayList(Value).init(allocator),
            };
        }
        pub fn deinit(self: *Self) void {
            self.code.deinit();
            self.pool.deinit();
        }
        pub fn reset(self: *Self) !void {
            self.deinit();
            self.code.init(self.allocator);
            self.pool.init(self.allocator);
        }
        pub fn writeOpcode(self: *Self, opcode: Opcode) !void {
            try self.code.append(@as(u8, @intFromEnum(opcode)));
        }
        pub fn writeByte(self: *Self, byte: u8) !void {
            try self.code.append(byte);
        }
        pub fn writeBytes(self: *Self, bytes: []const u8) !void {
            try self.code.appendSlice(bytes);
        }
        pub fn addConstant(self: *Self, value: Value) !u8 {
            try self.pool.append(value);
            const len: u8 = @intCast(self.pool.items.len);
            return len - 1;
        }
        pub fn getConstant(self: *Self, index: u8) !Value {
            return self.pool.items[index];
        }
        pub fn disassembly(self: *Self) !void {
            try out.print("=== {s} ===\n", .{self.name});

            var offset: u64 = 0;
            while (offset < self.code.items.len) {
                offset = try self.disassemblyInstruction(offset);
            }
        }
        pub fn disassemblyInstruction(self: *Self, offset: u64) !u64 {
            try out.print("{d:0>8}", .{offset});

            const byte = self.code.items[offset];
            const instruction = @as(Opcode, @enumFromInt(byte));
            switch (instruction) {
                Opcode.OP_RETURN => {
                    try out.print(" {s}\n", .{instruction.toString()});
                    return offset + 1;
                },
                Opcode.OP_CONST => {
                    const arg = self.code.items[offset + 1];
                    const val = try self.getConstant(arg);
                    try out.print(" {s} [{d}]; ", .{ instruction.toString(), arg });
                    try val.print();
                    try out.print("\n", .{});
                    return offset + 2;
                },
            }
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var chunk = Chunk().init(allocator, "main");
    defer chunk.deinit();

    try chunk.writeOpcode(Opcode.OP_CONST);
    try chunk.writeByte(
        try chunk.addConstant(Value{ .int = 10 }),
    );
    try chunk.writeOpcode(Opcode.OP_RETURN);

    try chunk.disassembly();
}
