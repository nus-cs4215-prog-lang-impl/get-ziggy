const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const TypeName = types.TypeName;

const StringHashMap = std.StringHashMap;

// TODO: account for functions
// TODO: ownership stuff should be here as well
pub const SymbolInfo = struct {
    type_name: TypeName,
    is_mut: bool,

    pub fn baseType(self: SymbolInfo) TypeName {
        return self.type_name; // Assumes type_name stores the underlying type T for &T, &mut T etc.
    }

    pub fn create(type_name: TypeName, is_mut: bool) SymbolInfo {
        return .{ .type_name = type_name, .is_mut = is_mut };
    }

    pub fn unit() SymbolInfo {
        return .{ .type_name = TypeName.Undefined, .is_mut = false };
    }
};

const TypeFrame = StringHashMap(SymbolInfo);

pub const TypeEnvironment = struct {
    alloc: Allocator,
    frames: std.ArrayList(TypeFrame),

    pub fn init(alloc: Allocator) TypeEnvironment {
        return .{
            .alloc = alloc,
            .frames = std.ArrayList(TypeFrame).init(alloc),
        };
    }

    pub fn deinit(self: *TypeEnvironment) void {
        for (self.frames.items) |*frame| {
            var iter = frame.keyIterator();
            while (iter.next()) |key_ptr| {
                self.alloc.free(key_ptr.*);
            }
            frame.deinit();
        }
        self.frames.deinit();
    }

    pub fn pushFrame(self: *TypeEnvironment) !void {
        try self.frames.append(TypeFrame.init(self.alloc));
        std.debug.print("Extend scope. Depth: {}\n", .{self.frames.items.len});
    }

    pub fn popFrame(self: *TypeEnvironment) void {
        if (self.frames.items.len > 0) {
            var frame = self.frames.pop();
            frame.deinit();
            std.debug.print("Reduce scope. Depth: {}\n", .{self.frames.items.len});
        } else {
            @panic("Attempted to pop frame from empty or global-only environment");
        }
    }

    pub fn addBinding(self: *TypeEnvironment, name: []const u8, type_name: TypeName, is_mut: bool) !void {
        const current_frame = self.currentFrame();
        const owned_name = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(owned_name); // Free if put fails

        const info = SymbolInfo{ .type_name = type_name, .is_mut = is_mut };

        if (current_frame.contains(owned_name)) {
            std.debug.print("Type Error: Redeclaration of '{s}' in the same scope.\n", .{owned_name});
            // No need to free owned_name here, errdefer handles it if put fails.
            // If contains() is true, put won't be called. We need to free manually.
            self.alloc.free(owned_name);
            return error.SymbolAlreadyDeclared;
        }

        // If put fails, errdefer will free owned_name.
        try current_frame.put(owned_name, info);
        std.debug.print("Declared '{s}' (type: {any}, mut: {any}) in current frame.\n", .{ owned_name, type_name, is_mut });
    }

    pub fn lookup(self: *const TypeEnvironment, name: []const u8) ?SymbolInfo {
        var i = self.frames.items.len;
        while (i > 0) {
            i -= 1;
            const frame = &self.frames.items[i];
            if (frame.get(name)) |typ| {
                return typ;
            }
        }
        return null;
    }

    fn currentFrame(self: *TypeEnvironment) *TypeFrame {
        if (self.frames.items.len == 0) {
            @panic("Attempted to access current frame from empty environment");
        }
        return &self.frames.items[self.frames.items.len - 1];
    }
};
