const std = @import("std");
const json = std.json;
// Primitive Types
// We differentiate betweeen the primitive types in rust and zig
// by using PascalCase for the Rust types
pub const Value = union(enum) {
    // TODO: Might want to add char as primitive
    Int: i64,
    Float: f64,
    Bool: bool,
    String: []const u8, // TODO: Rust doesn't really have Strings as primitives, so this might not be needed
    Undefined: void,
};

// Enum Types
pub const UnaryOperator = enum {
    Negate, // -
    Not, // !

    pub fn jsonStringify(self: UnaryOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Negate => "-",
            .Not => "!",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !UnaryOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "-")) return .Negate;
        if (std.mem.eql(u8, str, "!")) return .Not;
        return error.InvalidEnumTag;
    }
};

pub const BinaryOperator = enum {
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /
    Mod, // %
    Eq, // ==
    Neq, // !=
    Lt, // <
    Lte, // <=
    Gt, // >
    Gte, // >=

    pub fn jsonStringify(self: BinaryOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Add => "+",
            .Sub => "-",
            .Mul => "*",
            .Div => "/",
            .Mod => "%",
            .Eq => "==",
            .Neq => "!=",
            .Lt => "<",
            .Lte => "<=",
            .Gt => ">",
            .Gte => ">=",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !BinaryOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "+")) return .Add;
        if (std.mem.eql(u8, str, "-")) return .Sub;
        if (std.mem.eql(u8, str, "*")) return .Mul;
        if (std.mem.eql(u8, str, "/")) return .Div;
        if (std.mem.eql(u8, str, "%")) return .Mod;
        if (std.mem.eql(u8, str, "==")) return .Eq;
        if (std.mem.eql(u8, str, "!=")) return .Neq;
        if (std.mem.eql(u8, str, "<")) return .Lt;
        if (std.mem.eql(u8, str, "<=")) return .Lte;
        if (std.mem.eql(u8, str, ">")) return .Gt;
        if (std.mem.eql(u8, str, ">=")) return .Gte;
        return error.InvalidEnumTag;
    }
};

pub const LogicalOperator = enum {
    And, // &&
    Or, // ||

    pub fn jsonStringify(self: LogicalOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .And => "&&",
            .Or => "||",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !LogicalOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "&&")) return .And;
        if (std.mem.eql(u8, str, "||")) return .Or;
        return error.InvalidEnumTag;
    }
};

pub const Param = struct {
    name: []const u8,
    // TODO: type_info?
};

// Explicit Error Set
pub const CompileErrors = error{
    UnimplementedAstNode,
    OutOfMemory,
};

// AstNode Declaration
pub const AstNode = union(enum) {
    Literal: Value,
    Name: []const u8,
    App: struct { func: *AstNode, args: []*AstNode },
    LogicalOp: struct { op: LogicalOperator, left: *AstNode, right: *AstNode },
    BinaryOp: struct { op: BinaryOperator, left: *AstNode, right: *AstNode },
    UnaryOp: struct { op: UnaryOperator, operand: *AstNode },
    Lambda: struct { params: []Param, body: *AstNode },
    Sequence: struct { statements: []*AstNode },
    Block: struct { body: *AstNode },
    VarDecl: struct { name: []const u8, value: *AstNode },
    Assignment: struct { name: []const u8, value: *AstNode },
    Conditional: struct { condition: *AstNode, cons: *AstNode, alt: *AstNode },
    FnDecl: struct { name: []const u8, params: []Param, body: *AstNode },
    Return: struct { value: ?*AstNode },
    WhileLoop: struct { condition: *AstNode, body: *AstNode },
};

pub const Instruction = union(enum) {
    Ldc: Value, // Load constant
    Ld: []const u8, // Load variable by name
    Assign: []const u8, // Assign to variable name
    Unop: UnaryOperator,
    Binop: BinaryOperator,
    Pop: void, // Pop top value from stack
    Jof: usize, // Jump if false: target instruction address/index
    Goto: usize, // Unconditional jump: target instruction address/index
    EnterScope: struct { locals: [][]const u8 }, // Names declared in the scope
    ExitScope: void,
    Ldf: struct { params: []Param, addr: usize }, // Load function: Addr of function body start
    Call: struct { arity: usize }, // Function call
    TailCall: struct { arity: usize }, // Tail call optimization
    Reset: void, // Return from function / unwind stack frame
    Done: void, // Program termination
};
