const std = @import("std");
const Alllocator = std.mem.Allocator;
const json = std.json;
const expect = std.testing.expect;

const Place = struct {
    location: Locs,
    const Locs = union(enum) { Singapore: u32, Campus: struct { floor: u32, building: ?*Locs }, COM3: struct { roomnumber: u32 } };
};

const AST = struct {
    tag: Node,
    const Node = union(enum) { lit: u32, nam: struct { sym: []u8 }, assign: struct { sym: []u8, val: *AST } };
};

test "singapore" {
    const test_allocator = std.heap.page_allocator;

    const parsed = try std.json.parseFromSlice(
        Place,
        test_allocator,
        \\{"location": {"Singapore": 1}}
    ,
        .{},
    );
    defer parsed.deinit();

    const place = parsed.value;

    try expect(place.location.Singapore == 1);
}

test "ast" {
    const test_allocator = std.heap.page_allocator;

    const parsed = try std.json.parseFromSlice(
        AST,
        test_allocator,
        \\{"tag": {"assign": {"sym": "x", "val": {"tag": {"lit": 1}}}}}
    ,
        .{},
    );
    defer parsed.deinit();

    const ast = parsed.value;

    try expect(std.mem.eql(ast.tag.assign.sym, "x"));
    try expect(ast.tag.assign.val.tag.lit == 1);
}
