const std = @import("std");

// Define the Tag
const DataType = enum(u8) {
    StructA = 0x01,
    StructB = 0x02,
    StructC = 0x03,
};

// Struct Definitions (packed)
const StructA = struct {
    a: u8,
    b: u32,
};

const StructB = struct {
    c: u16,
    d: u8,
    e: u8,
};

const StructC = struct {
    f: u64,
};

// Error Type
const Error = error{
    InvalidTag,
    UnexpectedEndOfData,
    BufferTooSmall,
};

// Function to read the data from the byte array
fn readData(data: []const u8) !void {
    var offset: usize = 0;

    while (offset < data.len) {
        // Read Tag (DataType)
        if (offset + 1 > data.len) {
            return Error.UnexpectedEndOfData;
        }

        const tag: DataType = @enumFromInt(data[offset]);
        offset += 1;

        // Read Size (u16)
        if (offset + 2 > data.len) {
            return Error.UnexpectedEndOfData;
        }
        const ptr_size: *const [2]u8 = @ptrCast(data[offset .. offset + 2]);
        const size = std.mem.readInt(u16, ptr_size, std.builtin.Endian.little);
        offset += 2;

        // Check for size validity
        if (offset + size > data.len) {
            return Error.BufferTooSmall;
        }

        std.debug.print("Tag: {s}, Size: {}\n", .{ @tagName(tag), size });

        // Process Data based on Tag
        switch (tag) {
            DataType.StructA => {
                if (size != @sizeOf(StructA)) {
                    std.debug.print("Warning: Expected size {}, got {}.\n", .{ @sizeOf(StructA), size });
                    //Handle the error
                }
                var struct_a: StructA = undefined;
                const ptr_a: *const [@sizeOf(StructA)]u8 = @ptrCast(data[offset .. offset + size]);
                @memcpy(@as([*]u8, @ptrCast(&struct_a)), ptr_a);
                offset += size;
                std.debug.print("StructA: {any}\n", .{struct_a});
            },
            DataType.StructB => {
                if (size != @sizeOf(StructB)) {
                    std.debug.print("Warning: Expected size {}, got {}.\n", .{ @sizeOf(StructB), size });
                    //Handle the error
                }
                var struct_b: StructB = undefined;
                const ptr_b: *const [@sizeOf(StructB)]u8 = @ptrCast(data[offset .. offset + size]);
                @memcpy(@as([*]u8, @ptrCast(&struct_b)), ptr_b);
                offset += size;
                std.debug.print("StructB: {any}\n", .{struct_b});
            },
            DataType.StructC => {
                if (size != @sizeOf(StructC)) {
                    std.debug.print("Warning: Expected size {}, got {}.\n", .{ @sizeOf(StructC), size });
                    //Handle the error
                }
                var struct_c: StructC = undefined;
                const ptr_c: *const [@sizeOf(StructC)]u8 = @ptrCast(data[offset .. offset + size]);
                @memcpy(@as([*]u8, @ptrCast(&struct_c)), ptr_c);
                offset += size;
                std.debug.print("StructC: {any}\n", .{struct_c});
            },
        }
    }
}

pub fn main() !void {
    // Example Binary Data (replace with your actual data)
    const binary_data: []const u8 = &[_]u8{
        @intFromEnum(DataType.StructA), 5,    0,    0x10, 0x20, 0x30, 0x40, 0x50,
        @intFromEnum(DataType.StructB), 4,    0,    0x60, 0x70, 0x80, 0x90, @intFromEnum(DataType.StructC),
        8,                              0,    0xA0, 0xB0, 0xC0, 0xD0, 0xE0, 0xF0,
        0x01,                           0x02,
    };

    // Call the parsing function
    try readData(binary_data);
}
