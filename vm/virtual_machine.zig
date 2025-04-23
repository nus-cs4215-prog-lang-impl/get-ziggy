const std = @import("std");
const assert = std.debug.assert;
const types = @import("types.zig");

const vm_addr = usize;

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

const nodeHeader = packed struct {
    tag: u8,
};
// Helper functions for heap allocation
fn heapAllocate(head: nodeHeader, comptime NodeType: type) !usize {
    const needed_bytes: usize = (@bitSizeOf(nodeHeader) / 8) + (@bitSizeOf(NodeType) / 8);
    if (heap_ptr + needed_bytes > HEAP_SIZE) {
        return error.OutOfMemory;
    }
    const address: usize = heap_ptr;
    heapSet(address, head, nodeHeader);
    heap_ptr += needed_bytes;
    return address;
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

// TODO: redo
fn heapSet(address: usize, value: anytype, comptime T: type) void {
    // const ptr: [*]u8 = @constCast(@ptrCast(&value));
    // @memcpy(HEAP[address..][0..@sizeOf(usize)], ptr);
    const size = @bitSizeOf(T) / 8;
    // const ptr: [*]u8 = @ptrCast(&value);
    // const slice: []u8 = @as([*]u8, ptr)[0..size];
    const s: [size]u8 = @bitCast(value);
    // const slice = std.mem.asBytes(s);
    @memcpy(HEAP[address..][0..size], &s);
}

fn heapGet(address: usize, comptime T: type) T {
    var value: T = undefined;
    const size = @bitSizeOf(T) / 8;
    const value_bytes = std.mem.asBytes(&value)[0..size];
    const source_bytes = HEAP[address..][0..size];
    @memcpy(value_bytes, source_bytes);

    return value;
}

fn heapGetChild(address: vm_addr, comptime T: type) T {
    return heapGet(address + (@bitSizeOf(nodeHeader) / 8), T);
}

fn heapSetChild(address: vm_addr, value: anytype) void {
    _ = value;
    _ = address;
}

fn heapGetSize(address: vm_addr) usize {
    _ = address;
    return 420420;
}

fn heapGetNumberOfChildren(address: usize) usize {
    // Assuming the number of children is stored at a fixed offset (e.g., offset 5)
    return truncate_priv(u16, heapGetByteAtOffset(address, 5) << 8 | heapGetByteAtOffset(address, 6));
}

// Canonical Values
var False: vm_addr = undefined;
var True: vm_addr = undefined;
var Null: vm_addr = undefined;
var Unassigned: vm_addr = undefined;
var Undefined: vm_addr = undefined;

fn initCanonicalValues() !void {
    False = try heapAllocate(nodeHeader{ .tag = @intFromEnum(Tag.False) }, void);
    True = try heapAllocate(nodeHeader{ .tag = @intFromEnum(Tag.True) }, void);
    Null = try heapAllocate(nodeHeader{ .tag = @intFromEnum(Tag.Null) }, void);
    Unassigned = try heapAllocate(nodeHeader{ .tag = @intFromEnum(Tag.Unassigned) }, void);
    Undefined = try heapAllocate(nodeHeader{ .tag = @intFromEnum(Tag.Undefined) }, void);
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
    heapSet(address + 1, env, void);
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
    heapSet(address + 1, env, void);
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
    heapSet(address + 1, env, void);
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
const numberNode = packed struct {
    num_type: u8,
    val: usize,
};

fn literalValToNum(n: types.LiteralVal) usize {
    var ret: usize = undefined;
    switch (n.type_name) {
        .i32 => {
            const tmp = std.fmt.parseInt(i32, n.val, 10) catch |err| {
                std.debug.print("error: {any}", .{err});
                return 0x4545;
            };
            const t: i32 = @bitCast(tmp);
            const t_big: i64 = @intCast(t);
            ret = @bitCast(t_big);
        },
        .u32 => {
            const tmp = std.fmt.parseInt(u32, n.val, 10) catch |err| {
                std.debug.print("error: {any}", .{err});
                return 0x4545;
            };
            ret = @intCast(tmp);
        },
        .i64 => {
            const tmp = std.fmt.parseInt(i64, n.val, 10) catch |err| {
                std.debug.print("error: {any}", .{err});
                return 0x4545;
            };
            ret = @bitCast(tmp);
        },
        .u64 => {
            const tmp = std.fmt.parseInt(u64, n.val, 10) catch |err| {
                std.debug.print("error: {any}", .{err});
                return 0x4545;
            };
            ret = @intCast(tmp);
        },
        .f64 => {
            const tmp = std.fmt.parseFloat(f64, n.val) catch |err| {
                std.debug.print("error: {any}", .{err});
                return 0x4545;
            };
            _ = tmp;
            // ret = @bitCast(tmp);
            // ret = @intCast(tmp);
        },
        else => {},
    }
    return ret;
}

fn heapAllocateNumber(n: types.LiteralVal) !usize {
    const val_as_num: usize = literalValToNum(n);

    const number_address = try heapAllocate(
        nodeHeader{ .tag = @intFromEnum(Tag.Number) },
        numberNode,
    );
    const node = numberNode{
        .num_type = @intFromEnum(n.type_name),
        .val = val_as_num,
    };
    heapSet(number_address + 1, node, numberNode);
    return number_address;
}

fn isNumber(address: usize) bool {
    return heapGetTag(address) == Tag.Number;
}

pub fn val_to_addr(val: types.LiteralVal) vm_addr {
    // TODO: implemenent proper
    var addr: vm_addr = 420420;
    switch (val.type_name) {
        .u32, .i32, .u64, .i64, .f64 => {
            addr = heapAllocateNumber(val) catch {
                return 0x4545;
            };
        },
        .Bool => {
            if (std.mem.eql(u8, "true", val.val)) {
                addr = True;
            } else if (std.mem.eql(u8, "false", val.val)) {
                addr = False;
            }
            std.debug.print("WARNING OTHER BOOLEAN TAGGED STRING PRODUCED\n", .{});
        },
        .String => {},
        .Undefined => {},
        // TODO: what about array literals and structs
    }
    return addr;
}

fn bytesGet(source_bytes: []u8, comptime T: type) T {
    var value: T = undefined;
    const size = @bitSizeOf(T) / 8;
    const value_bytes = std.mem.asBytes(&value)[0..size];
    @memcpy(value_bytes, source_bytes);

    return value;
}

fn bytesSet(comptime T: type, value: T, ret: []u8) void {
    // const ptr: [*]u8 = @constCast(@ptrCast(&value));
    // @memcpy(HEAP[address..][0..@sizeOf(usize)], ptr);
    const size = @bitSizeOf(T) / 8;
    // const ptr: [*]u8 = @ptrCast(&value);
    // const slice: []u8 = @as([*]u8, ptr)[0..size];
    const s: [size]u8 = @bitCast(value);
    // const slice = std.mem.asBytes(s);
    @memcpy(ret, &s);
}
// pub fn structToBytes(comptime T: type, struct_val: T) []const u8 {
//     const byte_ptr: [*]u8 = @ptrCast(&struct_val);
//     const byte_slice: []const u8 = @slice(byte_ptr, @sizeOf(T));
//     return byte_slice;
// }
pub fn numberNodeStr(body: numberNode, buffer: [20]u8) void {
    const nt: types.TypeName = @enumFromInt(body.num_type);
    switch (nt) {
        .u32 => {
            const val: u32 = @intCast(body.val);
            std.fmt.bufPrint(buffer, "{d}", .{val}) catch {};
        },
        .u64 => {
            const val: u64 = @intCast(body.val);
            std.fmt.bufPrint(buffer, "{d}", .{val}) catch {};
        },
        .i32 => {
            const b1: i64 = @bitCast(body.val);
            const val: i32 = @intCast(b1);
            std.fmt.bufPrint(buffer, "{d}", .{val}) catch {};
        },
        .i64 => {
            const val: i64 = @bitCast(body.val);
            std.fmt.bufPrint(buffer, "{d}", .{val}) catch {};
        },
        .f64 => {
            std.debug.print("no value here\n", .{});
        },
        else => {},
    }
}

pub fn addr_to_val(addr: vm_addr) void {
    const head: nodeHeader = heapGet(addr, nodeHeader);
    const tag: Tag = @enumFromInt(head.tag);
    switch (tag) {
        .Number => {},
        else => {},
    }
    return undefined;
}
const os_type = union(enum) {
    instr: types.Instruction,
    addr: vm_addr,
};

const VM = struct {
    PC: vm_addr,
    operand_stack: std.ArrayList(os_type),
    runtime_stack: std.ArrayList(u32),
    // TODO: Environment
    program: ?[]types.Instruction,
    // TODO: store allocators?
    // copy program with allocator

    pub fn init(os_alloc: std.mem.Allocator, rts_alloc: std.mem.Allocator) !VM {
        return .{
            .PC = 0,
            .operand_stack = std.ArrayList(os_type).init(os_alloc),
            .runtime_stack = std.ArrayList(u32).init(rts_alloc),
            .program = null,
        };
    }

    pub fn deinit(self: *VM) void {
        self.operand_stack.deinit();
        self.runtime_stack.deinit();
    }

    pub fn load_prog(self: *VM, prog: []types.Instruction) void {
        self.program = prog;
    }

    pub fn run(self: *VM) !void {
        self.PC = 0;
        self.runtime_stack.clearAndFree();
        self.operand_stack.clearAndFree();

        std.debug.print("running program {any}\n\n\n", .{self.program});
        while (self.program.?[self.PC] != types.Instruction.Done) {
            const instr = self.program.?[self.PC];
            std.debug.print("instr: {any}\n", .{self.program.?[self.PC]});

            _ = try self.eval_instruction(instr);

            self.PC += 1;
            assert(self.PC < self.program.?.len);
        }

        if (self.operand_stack.items.len > 0) {
            std.debug.print("\n\nTop of OS: {any}\n", .{self.operand_stack.getLast()});
        } else {
            std.debug.print("Operand stack is empty\n", .{});
        }

        std.debug.print("Done running\n\n", .{});
    }

    fn apply_unop(unop: types.UnaryOperator, addr: vm_addr) vm_addr {
        var ret_addr: vm_addr = undefined;
        const tag: Tag = heapGetTag(addr);
        switch (unop) {
            .neg => {
                switch (tag) {
                    .True => {
                        ret_addr = False;
                    },
                    .False => {
                        ret_addr = True;
                    },
                    .Number => {
                        const val = heapGetChild(addr, numberNode);
                        const buffer: [20]u8 = undefined;
                        const str = numberNodeStr(val, buffer);
                        ret_addr = val_to_addr(types.LiteralVal{ .type_name = @enumFromInt(@intFromEnum(val.num_type)), .val = str });
                    },
                    else => {},
                }
            },
            else => {},
        }
        return ret_addr;
    }

    fn apply_binop(op: types.BinaryOperator, left: vm_addr, right: vm_addr) vm_addr {
        _ = op;
        _ = left;
        _ = right;
        return 0;
    }

    fn is_False(val: vm_addr) bool {
        _ = val;
        std.debug.print("false heap object not implemented", .{});
        return true;
    }

    fn eval_instruction(self: *VM, instr: types.Instruction) !void {
        switch (instr) {
            .Ldc => |lit| {
                const addr = os_type{ .addr = val_to_addr(lit) };
                try self.operand_stack.append(addr);
            },
            .Unop => |unop| {
                assert(self.operand_stack.items.len >= 1);
                const addr = self.operand_stack.getLast().addr;
                const new_item = apply_unop(unop, addr);
                try self.operand_stack.append(os_type{ .addr = new_item });
            },
            .Binop => |binop| {
                assert(self.operand_stack.items.len >= 2);
                const addr_left = self.operand_stack.getLast().addr;
                const addr_right = self.operand_stack.getLast().addr;
                const new_item = apply_binop(binop, addr_left, addr_right);
                try self.operand_stack.append(os_type{ .addr = new_item });
            },
            .Pop => {
                assert(self.operand_stack.items.len >= 1);
                _ = self.operand_stack.getLast();
            },
            .Jof => |addr| {
                assert(self.operand_stack.items.len >= 1);
                const val = self.operand_stack.getLast();

                assert(addr < self.program.?.len);
                if (is_False(val.addr)) {
                    self.PC = addr;
                }
            },
            .Goto => |addr| {
                assert(addr < self.program.?.len);
                self.PC = addr;
            },
            .EnterScope => {},
            .ExitScope => {},
            .Ld => {},
            .Assign => {},
            .Ldf => {},
            .Call => {},
            .TailCall => {},
            .Reset => {},
            .Done => std.debug.print("Done instr doing\n", .{}),
        }
        // UNOP:
        //     instr =>
        //     push(OS, apply_unop(instr.sym, OS.pop())),
        // BINOP:
        //     instr =>
        //     push(OS,
        //          apply_binop(instr.sym, OS.pop(), OS.pop())),
        // POP:
        //     instr =>
        //     OS.pop(),
        // JOF:
        //     instr =>
        //     PC = is_True(OS.pop()) ? PC : instr.addr,
        // GOTO:
        //     instr =>
        //     PC = instr.addr,
        // ENTER_SCOPE:
        //     instr => {
        //         push(RTS, heap_allocate_Blockframe(E))
        //         const frame_address = heap_allocate_Frame(instr.num)
        //         E = heap_Environment_extend(frame_address, E)
        //         for (let i = 0; i < instr.num; i++) {
        //             heap_set_child(frame_address, i, Unassigned)
        //         }
        //     },
        // EXIT_SCOPE:
        //     instr =>
        //     E = heap_get_Blockframe_environment(RTS.pop()),
        // LD:
        //     instr => {
        //         const val = heap_get_Environment_value(E, instr.pos)
        //         if (is_Unassigned(val))
        //             error("access of unassigned variable")
        //         push(OS, val)
        //     },
        // ASSIGN:
        //     instr =>
        //     heap_set_Environment_value(E, instr.pos, peek(OS,0)),
        // LDF:
        //     instr => {
        //         const closure_address =
        //                   heap_allocate_Closure(
        //                       instr.arity, instr.addr, E)
        //         push(OS, closure_address)
        //     },
        // CALL:
        //     instr => {
        //         const arity = instr.arity
        //         const fun = peek(OS, arity)
        //         if (is_Builtin(fun)) {
        //             return apply_builtin(heap_get_Builtin_id(fun))
        //         }
        //         const frame_address = heap_allocate_Frame(arity)
        //         for (let i = arity - 1; i >= 0; i--) {
        //             const val = OS.pop()
        //             heap_set_child(frame_address, i, val)
        //         }
        //         OS.pop() // pop fun
        //         push(RTS, heap_allocate_Callframe(E, PC))
        //         E = heap_Environment_extend(
        //                 frame_address,
        //                 heap_get_Closure_environment(fun))
        //         PC = heap_get_Closure_pc(fun)
        //     },
        // TAIL_CALL:
        //     instr => {
        //         const arity = instr.arity
        //         const fun = peek(OS, arity)
        //         if (is_Builtin(fun)) {
        //             return apply_builtin(heap_get_Builtin_id(fun))
        //         }
        //         const frame_address = heap_allocate_Frame(arity)
        //         for (let i = arity - 1; i >= 0; i--) {
        //             heap_set_child(frame_address, i, OS.pop())
        //         }
        //         OS.pop() // pop fun
        //         // don't push on RTS here
        //         E = heap_Environment_extend(
        //                 frame_address,
        //                 heap_get_Closure_environment(fun))
        //         PC = heap_get_Closure_pc(fun)
        //     },
        // RESET :
        //     instr => {
        //         PC--;
        //         // keep popping...
        //         const top_frame = RTS.pop()
        //         if (is_Callframe(top_frame)) {
        //             // ...until top frame is a call frame
        //             PC = heap_get_Callframe_pc(top_frame)
        //             E = heap_get_Callframe_environment(top_frame)
        //         }
        //     }
    }
};

test "run prog" {
    const alloc = std.testing.allocator;

    const ldc = types.Instruction{ .Ldc = .{ .val = "10", .type_name = .u32 } };
    const done = types.Instruction.Done;
    var prog = [_]types.Instruction{ ldc, done };

    var vm = try VM.init(alloc, alloc);
    defer vm.deinit();

    vm.load_prog(&prog);
    _ = try vm.run();

    std.debug.print("size: {}\n", .{@sizeOf(numberNode)});
    std.debug.print("size: {}\n", .{@bitSizeOf(numberNode) / 8});

    _ = try initCanonicalValues();
    const num = types.LiteralVal{ .val = "-2222", .type_name = .i32 };
    const addr = try heapAllocateNumber(num);
    std.debug.print("Number header {}\n", .{heapGet(addr, nodeHeader)});
    std.debug.print("Number val {}\n", .{heapGetChild(addr, numberNode)});
    // std.debug.print("val val val: {any}\n", .{bytesGet(ret.*, numberNode)});

    for (0..40) |i| {
        const value = HEAP[i];
        std.debug.print("Heap[{}] = {}\n", .{ i, value });
    }
}
