const std = @import("std");

fn truncate_priv(comptime T: type, val: anytype) T {
    const ret: T = @truncate(val);
    return ret;
}

// Constants (enums in Zig are more suitable)
const Tag = enum {
    EmptyHeap, // Used to mark zeroed out TAG byte with empty
    False,
    True,
    Null,
    Unassigned,
    Undefined,
    Environment,
    Blockframe,
    Callframe,
    Closure,
    Frame,
    Builtin,
    Number,
    // NOTE: unimplemented
    // String,
    // Pair,
};

// Configuration
const HEAP_SIZE: usize = 65536;

// Global heap
var HEAP: [HEAP_SIZE]u8 = undefined;
var heap_ptr: usize = 0;

const node_size_field_size = @sizeOf(usize);

// Helper functions for heap allocation
fn heapAllocate(tag: Tag, size: usize) !usize {
    const needed_bytes: usize = size * @sizeOf(u8) + node_size_field_size + 1;
    if (heap_ptr + needed_bytes > HEAP_SIZE) {
        return error.OutOfMemory;
    }
    const address: usize = heap_ptr;
    HEAP[address] = @intFromEnum(tag); // Store tag
    heapSet(address + 1, size);
    heap_ptr += needed_bytes;
    return address + node_size_field_size; // NOTE: account for size byte
}

fn heapGetTag(address: usize) Tag {
    return @enumFromInt(HEAP[address]);
}

fn heapSetByteAtOffset(address: usize, offset: usize, value: u8) void {
    HEAP[address + offset] = value;
}

fn heapGetByteAtOffset(address: usize, offset: usize) u8 {
    return HEAP[address + offset];
}

fn heapSet(address: usize, value: usize) void {
    const ptr: [*]u8 = @constCast(@ptrCast(&value));
    @memcpy(HEAP[address..][0..@sizeOf(usize)], ptr);
}

fn heapGet(address: usize, num: usize, comptime T: type) T {
    std.debug.assert(@sizeOf(T) >= num);

    var value: T = undefined;
    const value_bytes = std.mem.asBytes(&value)[0..num];
    const source_bytes = HEAP[address..][0..num];
    @memcpy(value_bytes, source_bytes);

    return value;
}

// TODO: This will be WRONG because of size packed field
fn heapSetChild(address: usize, index: usize, value: usize) void {
    heapSet(address + 1 + index * @sizeOf(usize), value);
}

// TODO: This will be WRONG because of size packed field
fn heapGetChild(address: usize, index: usize) usize {
    return heapGet(address + 1 + index * @sizeOf(usize), usize);
}

fn heapGetSize(address: usize) usize {
    var i: usize = 0;
    while (address + 1 + i * @sizeOf(usize) < heap_ptr) {
        i += 1;
    }
    return i;
}

fn heapGetNumberOfChildren(address: usize) usize {
    // Assuming the number of children is stored at a fixed offset (e.g., offset 5)
    return truncate_priv(u16, heapGetByteAtOffset(address, 5) << 8 | heapGetByteAtOffset(address, 6));
}

// Canonical Values
var False: usize = undefined;
var True: usize = undefined;
var Null: usize = undefined;
var Unassigned: usize = undefined;
var Undefined: usize = undefined;

fn initCanonicalValues() !void {
    False = try heapAllocate(Tag.False, 1);
    True = try heapAllocate(Tag.True, 1);
    Null = try heapAllocate(Tag.Null, 1);
    Unassigned = try heapAllocate(Tag.Unassigned, 1);
    Undefined = try heapAllocate(Tag.Undefined, 1);
}

fn isFalse(address: usize) bool {
    return heapGetTag(address) == Tag.False;
}

fn isTrue(address: usize) bool {
    return heapGetTag(address) == Tag.True;
}

fn isBoolean(address: usize) bool {
    return isTrue(address) or isFalse(address);
}

fn isNull(address: usize) bool {
    return heapGetTag(address) == Tag.Null;
}

fn isUnassigned(address: usize) bool {
    return heapGetTag(address) == Tag.Unassigned;
}

fn isUndefined(address: usize) bool {
    return heapGetTag(address) == Tag.Undefined;
}

// Builtins
fn heapAllocateBuiltin(id: u8) !usize {
    const address = try heapAllocate(Tag.Builtin, 1);
    heapSetByteAtOffset(address, 1, id);
    return address;
}

fn heapGetBuiltinId(address: usize) u8 {
    return heapGetByteAtOffset(address, 1);
}

fn isBuiltin(address: usize) bool {
    return heapGetTag(address) == Tag.Builtin;
}

// Closures
fn heapAllocateClosure(arity: u8, pc: u16, env: usize) !usize {
    const address = try heapAllocate(Tag.Closure, 2);
    heapSetByteAtOffset(address, 1, arity);
    heapSetByteAtOffset(address, 2, truncate_priv(u8, pc >> 8));
    heapSetByteAtOffset(address, 3, truncate_priv(u8, pc));
    heapSet(address + 1, env);
    return address;
}

fn heapGetClosureArity(address: usize) u8 {
    return heapGetByteAtOffset(address, 1);
}

fn heapGetClosurePC(address: usize) u16 {
    const high: u8 = heapGetByteAtOffset(address, 2);
    const low: u8 = heapGetByteAtOffset(address, 3);
    return @as(u16, high) << 8 | low;
}

fn heapGetClosureEnvironment(address: usize) usize {
    return heapGetChild(address, 0);
}

fn isClosure(address: usize) bool {
    return heapGetTag(address) == Tag.Closure;
}

// Blockframes
fn heapAllocateBlockframe(env: usize) !usize {
    const address = try heapAllocate(Tag.Blockframe, 2);
    heapSet(address + 1, env);
    return address;
}

fn heapGetBlockframeEnvironment(address: usize) usize {
    return heapGetChild(address, 0);
}

fn isBlockframe(address: usize) bool {
    return heapGetTag(address) == Tag.Blockframe;
}

// Callframes
fn heapAllocateCallframe(env: usize, pc: u16) !usize {
    const address = try heapAllocate(Tag.Callframe, 2);
    heapSetByteAtOffset(address, 2, truncate_priv(u8, pc >> 8));
    heapSetByteAtOffset(address, 3, truncate_priv(u8, pc));
    heapSet(address + 1, env);
    return address;
}

fn heapGetCallframeEnvironment(address: usize) usize {
    return heapGetChild(address, 0);
}

fn heapGetCallframePC(address: usize) u16 {
    const high: u8 = heapGetByteAtOffset(address, 2);
    const low: u8 = heapGetByteAtOffset(address, 3);
    return @as(u16, high) << 8 | low;
}

fn isCallframe(address: usize) bool {
    return heapGetTag(address) == Tag.Callframe;
}

// Frames
fn heapAllocateFrame(number_of_values: usize) !usize {
    return heapAllocate(Tag.Frame, number_of_values + 1);
}

// Environment
fn heapAllocateEnvironment(number_of_frames: usize) !usize {
    return heapAllocate(Tag.Environment, number_of_frames + 1);
}

fn heapEmptyEnvironment() !usize {
    return heapAllocateEnvironment(0);
}

fn heapGetEnvironmentValue(env_address: usize, position: [2]usize) usize {
    const frame_index = position[0];
    const value_index = position[1];
    const frame_address = heapGetChild(env_address, frame_index);
    return heapGetChild(frame_address, value_index);
}

fn heapSetEnvironmentValue(env_address: usize, position: [2]usize, value: usize) void {
    const frame_index = position[0];
    const value_index = position[1];
    const frame_address = heapGetChild(env_address, frame_index);
    heapSetChild(frame_address, value_index, value);
}

fn heapEnvironmentExtend(frame_address: usize, env_address: usize) !usize {
    const old_size = heapGetSize(env_address);
    const new_env_address = try heapAllocateEnvironment(old_size);
    var i: usize = 0;
    while (i < old_size - 1) : (i += 1) {
        heapSetChild(new_env_address, i, heapGetChild(env_address, i));
    }
    heapSetChild(new_env_address, i, frame_address);
    return new_env_address;
}

// Pairs
fn heapAllocatePair(hd: usize, tl: usize) !usize {
    const pair_address = try heapAllocate(Tag.Pair, 3);
    heapSetChild(pair_address, 0, hd);
    heapSetChild(pair_address, 1, tl);
    return pair_address;
}

fn isPair(address: usize) bool {
    return heapGetTag(address) == Tag.Pair;
}

// Numbers

// 1 byte tag, 8 byte size,
// 1 byte numtype, usize bytes value
fn heapAllocateNumber(n: anytype) !usize {
    const t: NumberTypes = @TypeOf(n);
    _ = t;

    const node_size = 1 + 2;
    const number_address = try heapAllocate(Tag.Number, node_size);
    const n_usize: usize = @bitCast(n);
    heapSet(number_address + 1, n_usize);
    return number_address;
}

fn getNumberType(address: usize) NumberTypes {
    std.debug.assert(isNumber(address));
    const a: NumberTypes = @enumFromInt(HEAP[address + node_size_field_size + 1]);
    return a;
}

// TODO: firgure out return type
fn getNumber(address: usize) void{}

fn isNumber(address: usize) bool {
    return heapGetTag(address) == Tag.Number;
}

// Conversions
const anyval = struct {
    t: NumberTypes,
    val: []u8,
};

// TODO: String handling requires a string pool
// TODO: Handle other types appropriately

fn addressToJSValue(address: usize) i32 {
    const tag = heapGetTag(address);
    return switch (tag) {
        // Tag.True => true,
        // Tag.False => false,
        Tag.Number => {
            const t = getNumberType(address);
            const raw_num = getNumber(address);
            numberTypesToNum(t, raw_num);
        },
        // Tag.Undefined => undefined,
        // Tag.Unassigned => "<unassigned>",
        // Tag.Null => null,
        // Tag.Pair => [
        //     addressToJSValue(heapGetChild(address, 0)),
        //     addressToJSValue(heapGetChild(address, 1)),
        // ],
        // Tag.Closure => "<closure>",
        // Tag.Builtin => "<builtin>",
        // else => "unknown word tag", //word_to_string(address),
        else => -1,
    };
}

// TODO: String handling requires a string pool
fn jsValueToAddress(x: anyopaque) !usize {
    _ = x;
    return error.NotImplemented;
}

// Binop Microcode

// fn applyBinop(op: [:0]const u8, v2: usize, v1: usize) !usize {
//     const binop = binopMicrocodeLookup(op) orelse return error.InvalidOperation;
//     return jsValueToAddress(binop(addressToJSValue(v1), addressToJSValue(v2)));
// }

// Unop Microcode

// fn applyUnop(op: [:0]const u8, v: usize) !usize {
//     const unop = unopMicrocodeLookup(op) orelse return error.InvalidOperation;
//     return jsValueToAddress(unop(addressToJSValue(v)));
// }

//const builtinArray: []fn() anyopaque = &.{ /* ... */ };

// fn applyBuiltin(builtin_id: u8) void {
//     const result = builtinArray[builtin_id]();
//     // OS.pop(); // pop fun
//     // push(OS, result);
// }

// // Global Runtime Environment
// const primitiveValues = .{ /* ... */ };

// var globalEnvironment: usize = undefined;

// fn createGlobalEnvironment() !void {
//     const frameAddress = try heapAllocateFrame(primitiveValues.len);
//     for (primitiveValues) |primitiveValue, i| {
//         if (@hasField(primitiveValue, "id")) {
//             heapSetChild(frameAddress, i, try heapAllocateBuiltin(primitiveValue.id));
//         } else if (primitiveValue == null) {
//             heapSetChild(frameAddress, i, Undefined);
//         } else {
//             heapSetChild(frameAddress, i, try heapAllocateNumber(primitiveValue));
//         }
//     }
//     globalEnvironment = try heapEnvironmentExtend(frameAddress, try heapEmptyEnvironment());
// }

// Machine Registers (using ArrayList)
var OS: std.ArrayList(usize) = undefined;
var PC: usize = 0;
var E: usize = undefined;
var RTS: std.ArrayList(usize) = undefined;

// // Microcode
// const Microcode = struct {
//     LDC: fn (instr: Instr) void = undefined,
//     UNOP: fn (instr: Instr) void = undefined,
//     BINOP: fn (instr: Instr) void = undefined,
//     POP: fn (instr: Instr) void = undefined,
//     JOF: fn (instr: Instr) void = undefined,
//     GOTO: fn (instr: Instr) void = undefined,
//     ENTER_SCOPE: fn (instr: Instr) void = undefined,
//     EXIT_SCOPE: fn (instr: Instr) void = undefined,
//     LD: fn (instr: Instr) void = undefined,
//     ASSIGN: fn (instr: Instr) void = undefined,
//     LDF: fn (instr: Instr) void = undefined,
//     CALL: fn (instr: Instr) void = undefined,
//     TAIL_CALL: fn (instr: Instr) void = undefined,
//     RESET: fn (instr: Instr) void = undefined,
// };

// fn run() !anyopaque {
//     OS = std.ArrayList(usize).init(std.heap.page_allocator);
//     defer OS.deinit();
//     PC = 0;
//     E = globalEnvironment;
//     RTS = std.ArrayList(usize).init(std.heap.page_allocator);
//     defer RTS.deinit();

//     while (instrs[PC].tag != .DONE) { // Assuming 'instrs' is defined
//         const instr = instrs[PC];
//         PC += 1;
//         // microcode[instr.tag](&instr); // Assuming 'microcode' is defined
//     }

//     // return addressToJSValue(OS.items[OS.items.len - 1]);
//     return undefined;
// }
//
//
const NumberTypes = enum {
    i32 = {num :i32},
    i64,
    u32,
    u64,
    f64,
};

const ZigNumber = struct {
    t: NumberTypes,
    number: NumberTypes,
};

fn numberTypesToNum(t: NumberTypes, val: anytype) !@TypeOf(val) {
    return switch (t) {
        .i32 => @as(i32, val),
        .i64 => @as(i64, val),
        .u32 => @as(u32, val),
        .u64 => @as(u64, val),
        .f64 => @as(f64, val),
    };
}

pub fn numberToNumberTypes(val: anytype) NumberTypes {
    const T = @TypeOf(val);
    return if (T == i32)
        .i32
    else if (T == i64)
        .i64
    else if (T == u32)
        .u32
    else if (T == u64)
        .u64
    else if (T == f64)
        .f64
    else
        .unknown;
}

fn numberOp(a_addr: usize, b_addr: usize){
    const a = addressToJSValue(a_addr);
    const b = addressToJSValue(b_addr);
    const a_type = @TypeOf(a);
    const b_type = @TypeOf(b);

    if (a_type != b_type) {
        return error.TypeMismatch;
    }

    a + b;
}
// fn add(a_type: NumberTypes, a: anytype, b_type: NumberTypes, b: anytype) !@TypeOf(a) {
//     return switch (a_type) {
//         .i32 => @as(i32, a) + @as(i32, b),
//         .i64 => @as(i64, a) + @as(i64, b),
//         .u32 => @as(u32, a) + @as(u32, b),
//         .u64 => @as(u64, a) + @as(u64, b),
//         .f64 => @as(f64, a) + @as(f64, b),
//     };
// }

pub fn main() !void {
    try initCanonicalValues();
    //
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    //
    // OS = std.ArrayList(usize).init(arena.allocator());
    // try OS.append(1234);
    // defer OS.deinit();
    //
    // // std.debug.print("ArrayList: {}\n", .{OS.items});
    // std.debug.print("True: {}\n", .{True});
    // std.debug.print("False: {}\n", .{False});
    //
    // _ = try heapAllocateNumber(42);
    // _ = try heapAllocateNumber(422);
    // // std.debug.print("Number Tag: {}\n", .{@intFromEnum(Tag.Number)});
    // // std.debug.print("Heap: {}\n", .{HEAP});
    // var i: usize = 0;
    // while (i < 100) {
    //     const tag: Tag = @enumFromInt(HEAP[i]);
    //     i += 1;
    //     const size: usize = heapGet(i, node_size_field_size, usize);
    //
    //     std.debug.print("{}", .{size});
    //     i += node_size_field_size;
    //     var val: i64 = 0;
    //     if (tag == Tag.Number) {
    //         val = heapGet(i, 2, i16);
    //     }
    //     i += size;
    //     // const val = 1;
    //     std.debug.print("Tag: {s} --- Val: {} ---- i {}\n", .{ @tagName(tag), val, i });
    // }
    // for (0..100) |j| {
    //     const value = HEAP[j];
    //     std.debug.print("Heap addr:{}, Heap val:{}\n", .{ j, value });
    // }
}
