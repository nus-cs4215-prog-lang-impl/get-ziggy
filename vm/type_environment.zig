const std = @import("std");
const Allocator = std.mem.Allocator;
const TypeName = types.TypeName;

const StringHashMap = std.StringHashMap;

// TODO: account for functions
// TODO: ownership stuff should be here as well
const SymbolInfo = struct {
    type_name: TypeName,
    is_mut: bool,
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
        for (self.frames.items) |frame| {
            frame.deinit();
        }
        self.frames.deinit();
    }

    pub fn pushFrame(self: *TypeEnvironment) !void {
        try self.frames.append(TypeFrame.init(self.alloc));
        std.debug.print("Extend scope. Depth: {}\n", .{self.frames.item.len});
    }

    pub fn popFrame(self: *TypeEnvironment) void {
        if (self.frames.items.len > 0) {
            var frame = self.frames.pop();
            frame.deinit();
        } else {
            @panic("Attempted to pop frame from empty or global-only environment");
        }
    }

    pub fn addBinding(self: *TypeEnvironment, name: []const u8, type_name: TypeName, is_mut: bool) !void {
        const current_frame = self.currentFrame();
        const owned_name = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(owned_name); // Free if put fails

        const info = SymbolInfo{ .type_name = type_name, .is_mut = is_mut };

        if (current_scope.contains(owned_name)) {
            std.debug.print("Type Error: Redeclaration of '{s}' in the same scope.\n", .{owned_name});
            self.alloc.free(owned_name);
            return error.SymbolAlreadyDeclared; // Or a more specific type error
        }

        try current_frame.put(owned_name, info);
        std.debug.print("Declared '{s}' (type: {any}, mut: {any}) in current frame.\n", .{ owned_name, type_name, is_mut });
    }

    pub fn lookup(self: *const TypeEnvironment, name: []const u8) ?Type {
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
            @panic("Attempted to access current frame from empty or global-only environment");
        }
        return &self.frames.items[self.frames.items.len - 1];
    }
};
