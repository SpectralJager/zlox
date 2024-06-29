const std = @import("std");
const Allocator = std.mem.Allocator;
const out = std.io.getStdOut().writer();

const InterpreterErrors = error{
    InterpreterCompilerError,
    InterpreterRuntimeError,
};

const Opcode = enum(u8) {
    const Self = @This();

    OP_RETURN,
    OP_CONST,
    OP_NEGATE,
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_DIV,

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
                Opcode.OP_RETURN, Opcode.OP_NEGATE, Opcode.OP_ADD, Opcode.OP_SUB, Opcode.OP_MUL, Opcode.OP_DIV => {
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

pub fn VM() type {
    return struct {
        const Self = @This();

        chunks: std.ArrayList(Chunk()),
        currentChunk: u64,

        stack: std.ArrayList(Value),

        ip: u64,

        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .chunks = std.ArrayList(Chunk()).init(allocator),
                .stack = std.ArrayList(Value).init(allocator),
                .currentChunk = 0,
                .ip = 0,
            };
        }
        pub fn deinit(self: *Self) void {
            self.chunks.deinit();
            self.stack.deinit();
        }
        pub fn trace(self: *Self) !void {
            try out.print("=== Stack ===\n", .{});
            for (self.stack.items, 0..) |item, i| {
                try out.print("{d:0>8} ", .{i});
                try item.print();
                try out.print("\n", .{});
            }
            try out.print("\n", .{});
        }
        pub fn pushValue(self: *Self, value: Value) !void {
            try self.stack.append(value);
        }
        pub fn popValue(self: *Self) !Value {
            return self.stack.pop();
        }
        pub fn readByte(self: *Self) u8 {
            const code = self.chunks.items[self.currentChunk].code.items[self.ip];
            self.ip += 1;
            return code;
        }
        pub fn readConst(self: *Self) Value {
            const arg = self.readByte();
            return self.chunks.items[self.currentChunk].pool.items[arg];
        }
        pub fn interpret(self: *Self, chunk: Chunk()) !void {
            self.currentChunk = self.chunks.items.len;
            self.ip = 0;
            try self.chunks.append(chunk);

            return self.run();
        }
        pub fn run(self: *Self) !void {
            var instruction: u8 = undefined;
            while (true) {
                instruction = self.readByte();
                switch (@as(Opcode, @enumFromInt(instruction))) {
                    Opcode.OP_RETURN => {
                        const val = try self.popValue();
                        try val.print();
                        try out.print("\n", .{});
                        return;
                    },
                    Opcode.OP_CONST => {
                        const value = self.readConst();
                        try self.pushValue(value);
                    },
                    Opcode.OP_NEGATE => {
                        const value = try self.popValue();
                        try self.pushValue(.{ .int = -value.int });
                    },
                    Opcode.OP_ADD => {
                        const a = try self.popValue();
                        const b = try self.popValue();
                        try self.pushValue(.{ .int = a.int + b.int });
                    },
                    Opcode.OP_SUB => {
                        const a = try self.popValue();
                        const b = try self.popValue();
                        try self.pushValue(.{ .int = a.int - b.int });
                    },
                    Opcode.OP_DIV => {
                        const a = try self.popValue();
                        const b = try self.popValue();
                        try self.pushValue(.{ .int = @divTrunc(a.int, b.int) });
                    },
                    Opcode.OP_MUL => {
                        const a = try self.popValue();
                        const b = try self.popValue();
                        try self.pushValue(.{ .int = a.int * b.int });
                    },
                }
            }
        }
    };
}

const Token = union(enum) {};

pub fn Compiler() type {
    return struct {
        const Self = @This();

        fn compile(src: []const u8) !void {
            _ = src;
        }
    };
}

pub fn Scanner() type {
    return struct {
        const Self = @This();

        buff: std.ArrayList(u8),
        tokens: std.ArrayList(Token),
        line: i64,

        fn init(allocator: Allocator) Self {
            return .{
                .buff = std.ArrayList(u8).init(allocator),
                .tokens = std.ArrayList(Token).init(allocator),
                .line = 0,
            };
        }
        fn scanString(self: Self, src: []const u8) std.ArrayList(Token) {
            while (self.buff.re)
                return self.tokens;
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var vm = VM().init(allocator);
    defer vm.deinit();

    var chunk = Chunk().init(allocator, "main");
    defer chunk.deinit();

    try chunk.writeOpcode(Opcode.OP_CONST);
    try chunk.writeByte(
        try chunk.addConstant(Value{ .int = 10 }),
    );
    try chunk.writeOpcode(Opcode.OP_CONST);
    try chunk.writeByte(
        try chunk.addConstant(Value{ .int = 10 }),
    );
    try chunk.writeOpcode(Opcode.OP_ADD);
    try chunk.writeOpcode(Opcode.OP_RETURN);

    try chunk.disassembly();

    try vm.interpret(chunk);
    try vm.trace();
}
