// const std = @import("std");
//
// pub fn main() !void {
//     var buf: [8]u8 = undefined;
//     const value: usize = 99999999;
//
//     try toBytes(usize, value, &buf);
//
//     std.debug.print("{any}\n", .{buf});
// }
//
// pub fn toBytes(
//     comptime T: type,
//     value: T,
//     buf: []u8,
// ) !void {
//     const size = @sizeOf(T);
//     if (buf.len < size) {
//         return error.BufferTooSmall;
//     }
//     const ptr: [*]u8 = @constCast(@ptrCast(&value));
//     @memcpy(buf[0..size], ptr);
// }
//
const std = @import("std");
const allVal = union(enum) {
    number: i32,
    string: []const u8,
};

fn return_val(val: allVal) allVal {
    return switch (val) {
        .number => allVal{ .number = 1 },
        .string => allVal{ .string = "100"[0..] },
    };
}

test "test all val" {
    const val: allVal = return_val(allVal{ .number = 200 });
    std.debug.print("tag: {any}", .{val.number});
}

const kinds = enum {
    red,
    green,
};
const u_kinds = union {
    red: i32,
    green: f32,
};
const ball = struct {
    k: kinds,
    u: u_kinds,
};

test "numero dos" {
    const b1: ball = ball{
        .k = kinds.red,
        .u = u_kinds{ .red = 420 },
    };
    const b1k = b1.k;
    std.debug.print("b1: {}", .{b1.u.b1k});
}
// const std = @import("std");
// const native_endian = @import("builtin").target.cpu.arch.endian();
// const expect = std.testing.expect;
//
// const Full = packed struct {
//     number: u16,
// };
// const Divided = packed struct {
//     half1: u8,
//     quarter3: u4,
//     quarter4: u4,
// };
//
// test "@bitCast between packed structs" {
//     try doTheTest();
//     try comptime doTheTest();
// }
//
// fn doTheTest() !void {
//     try expect(@sizeOf(Full) == 2);
//     try expect(@sizeOf(Divided) == 2);
//     const full = Full{ .number = 0x1234 };
//     const divided: Divided = @bitCast(full);
//     try expect(divided.half1 == 0x34);
//     try expect(divided.quarter3 == 0x2);
//     try expect(divided.quarter4 == 0x1);
//
//     const ordered: [2]u8 = @bitCast(full);
//     switch (native_endian) {
//         .big => {
//             try expect(ordered[0] == 0x12);
//             try expect(ordered[1] == 0x34);
//         },
//         .little => {
//             try expect(ordered[0] == 0x34);
//             try expect(ordered[1] == 0x12);
//         },
//     }
// }
