
const std = @import("std");

const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const File = std.fs.File;
const ArrayList = std.ArrayList;
const Parsed = std.json.Parsed;



const Status = struct {
    tags_dir: Dir = undefined,
    tags_stack: ArrayList(*Parsed(Tag)),
    directories: usize = 0,
    files: usize = 0,
    dereferences: usize = 0,
    current_tag_type: []const u8 = undefined,
    current_tag_name: []const u8 = undefined
};



const Tag = struct {
    replace: bool = false,
    values: []Id
};



const Id = struct {
    required: bool = false,
    id: []u8
};



pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const dp_root = try std.fs.selfExeDirPathAlloc(allocator);
    std.mem.replaceScalar(u8, dp_root, '\\', '/');

    const tags_dir_path = blk: {
        const parts = [2][]const u8{
            dp_root,
            "/data/taglib/tags"
        };
        break :blk try std.mem.concat(allocator, u8, &parts);
    };
    allocator.free(dp_root);

    var tags_dir = try std.fs.openDirAbsolute(tags_dir_path, .{ .iterate = true });
    allocator.free(tags_dir_path);

    var status = Status{
        .tags_dir = tags_dir,
        .tags_stack = ArrayList(*Parsed(Tag)).init(allocator)
    };

    var dir_iter = tags_dir.iterate();

    while (try dir_iter.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                var inner_dir = try tags_dir.openDir(entry.name, .{ .iterate = true });
                defer inner_dir.close();

                status.current_tag_type = entry.name;
                try iterateDir(allocator, inner_dir, &status);
            },
            else => continue
        }
    }
    tags_dir.close();

    const ioOut = std.io.getStdOut();
    const msg = try std.fmt.allocPrint(
        allocator,
        "\x1b[32mSuccessfuly dereferenced {d} tags in {d} files inside {d} directories\x1b[0m\n",
        .{ status.dereferences, status.files, status.directories }
    );
    try ioOut.writeAll(msg);
    allocator.free(msg);

    status.tags_stack.deinit();
    _ = gpa.deinit();

    std.time.sleep(std.time.ns_per_hour * 1);
}



fn logErr(allocator: Allocator, status: *Status, err: anyerror) !void {
    const ioErr = std.io.getStdErr();
    const msg = try std.fmt.allocPrint(
        allocator,
        "\x1b[31mFailed to dereference tag in file '{s}' of the '{s}' tag types with error: '{any}'\x1b[0m\n",
        .{ status.current_tag_name, status.current_tag_type, err }
    );
    try ioErr.writeAll(msg);
    allocator.free(msg);

    std.process.exit(1);
}



fn iterateDir(allocator: Allocator, dir: Dir, status: *Status) !void {
    status.directories += 1;
    var dir_iter = dir.iterate();

    while (try dir_iter.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                var inner_dir = try dir.openDir(entry.name, .{ .iterate = true });
                defer inner_dir.close();
                try iterateDir(allocator, inner_dir, status);
            },
            .file => {
                var tag = try std.fs.Dir.openFile(dir, entry.name, .{ .mode = .read_write });
                defer tag.close();

                status.current_tag_name = entry.name;
                const is_null = processTag(allocator, tag, status, false) catch |err| {
                    try logErr(allocator, status, err);
                    std.process.exit(1);
                };
                if (is_null != null) return error.UnexpectedReturnValue;
                
            },
            else => continue
        }
    }
}



fn processTag(allocator: Allocator, tag: File, status: *Status, is_reference: bool) !?ArrayList(Id) {
    if (!is_reference) status.files += 1;
    const dereference_count = status.dereferences;

    // if (status.files == 2) return error.JustStop; //DEBUG
    // std.debug.print("\ncurrent file: {s}\n", .{status.current_tag_name}); //DEBUG

    const content = try tag.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);
    var content_json = try std.json.parseFromSlice(Tag, allocator, content, .{});
    try status.tags_stack.append(&content_json);

    var idList = ArrayList(Id).init(allocator);
    //TODO deinit

    for (content_json.value.values) |entry| {
        // std.debug.print("entry: {s}\n", .{entry.id}); //DEBUG

        if (std.mem.startsWith(u8, entry.id, "#taglib")) {
            status.dereferences += 1;

            var tag_ref = try openTagReference(allocator, status, entry.id);
            defer tag_ref.close();

            const ref_ids = (try processTag(allocator, tag_ref, status, true)).?;
            defer ref_ids.deinit();
            
            // prevent duplicate entries
            outer: for (ref_ids.items) |ref_id| {
                for (idList.items) |id| {
                    if (std.mem.eql(u8, ref_id.id, id.id)) continue :outer;
                }
                else try idList.append(ref_id);
            }
        }
        else try idList.append(entry);
    }

    // std.debug.print("\n dereference: {d} - {d}\n", .{status.dereferences, dereference_count}); //DEBUG

    if (status.dereferences != dereference_count) {
        content_json.value.values = idList.items;
        
        try tag.seekTo(0);
        try std.json.stringify(content_json.value, .{.whitespace = .indent_tab}, tag.writer());
        try tag.setEndPos(try tag.getPos());
    }

    if (is_reference) {
        return idList;
    }
    else {
        while (status.tags_stack.popOrNull()) |json| {
            json.deinit();
        }
        idList.deinit();
        return null;
    }
}



fn openTagReference(allocator: Allocator, status: *Status, id: []const u8) !File {
    const path = blk: {
        const parts = [4][]const u8{
            status.current_tag_type,
            "/",
            id[8..],
            ".json"
        };
        break :blk try std.mem.concat(allocator, u8, &parts);
    };
    defer allocator.free(path);
    
    return try status.tags_dir.openFile(path, .{ .mode = .read_write });
}