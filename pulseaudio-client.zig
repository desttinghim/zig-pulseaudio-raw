const std = @import("std");

pub fn main() !void {
    if (!std.net.has_unix_sockets) @compileError("Pulseaudio requires unix domain sockets");

    const allocator = std.heap.page_allocator;

    const pa_socket = socket: {
        const xdg_runtime_dir = try std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR");
        defer allocator.free(xdg_runtime_dir);

        const pa_path = try std.fs.path.join(allocator, &.{ xdg_runtime_dir, "pulse", "native" });
        defer allocator.free(pa_path);

        std.log.info("Connecting to {s}", .{pa_path});

        break :socket try std.net.connectUnixSocket(pa_path);
    };
    defer pa_socket.close();

    const pa_cookie = try get_pa_cookie(allocator);
    defer allocator.free(pa_cookie);

    std.log.info("PulseAudio cookie: {}", .{std.fmt.fmtSliceHexUpper(pa_cookie)});

    var buffer_write: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer_write);
    var writer = fbs.writer();

    var seq: u32 = 0;

    {
        std.log.info("Sending Auth...", .{});

        try writer.writeInt(u32, 0x0, .big); // length
        try writer.writeInt(u32, 0xff_ff_ff_ff, .big); // channel
        try writer.writeInt(u32, 0x0, .big); // offset high
        try writer.writeInt(u32, 0x0, .big); // offset low
        try writer.writeInt(u32, 0x0, .big); // flags
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32)); // type tag
        try writer.writeInt(u32, @intFromEnum(PulseAudio.Command.Auth), .big); // command
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32)); // type tag
        try writer.writeInt(u32, seq, .big); // seq
        seq += 1;
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32)); // type tag
        try writer.writeInt(u32, PulseAudio.version, .big); // version
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Arbitrary)); // type tag
        try writer.writeInt(u32, @intCast(pa_cookie.len), .big); // type tag
        _ = try writer.write(pa_cookie);

        const written = fbs.getWritten();
        try fbs.seekTo(0);

        try writer.writeInt(u32, @intCast(written.len - 20), .big);

        std.log.info("{}", .{std.fmt.fmtSliceHexUpper(written)});

        try pa_socket.writeAll(written);
    }

    {
        var buffer_read: [1024]u8 = undefined;

        const amount_read = try pa_socket.read(&buffer_read);

        std.log.info("PulseAudio Response: \n{}", .{std.fmt.fmtSliceHexUpper(buffer_read[0..amount_read])});

        var fbs_read = std.io.fixedBufferStream(buffer_read[0..amount_read]);

        const reader = fbs_read.reader();
        const length = try reader.readInt(u32, .big);
        const channel = try reader.readInt(u32, .big);
        const offset_hi = try reader.readInt(u32, .big);
        const offset_lo = try reader.readInt(u32, .big);
        const flags = try reader.readInt(u32, .big);

        std.log.info(
            \\
            \\length      {}
            \\channel     {x}
            \\offset (hi) {}
            \\offset (lo) {}
            \\flags       {}
            \\payload:
            \\{}
        , .{
            length,
            channel,
            offset_hi,
            offset_lo,
            flags,
            std.fmt.fmtSliceHexUpper(buffer_read[20..][0..length]),
        });

        std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        const cmd = try reader.readEnum(PulseAudio.Command, .big);
        std.debug.assert(cmd == .Reply);

        std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        const server_seq = try reader.readInt(u32, .big);

        std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        const authp: PulseAudio.AuthParams = @bitCast(try reader.readInt(u32, .big));

        std.log.info(
            \\
            \\cmd  {}
            \\seq  {}
            \\auth {}
        , .{
            cmd,
            server_seq,
            authp,
        });

        if (authp.version < PulseAudio.version) {
            return error.PulseAudioVersionMismatch;
        }
    }

    // Send another message
    fbs.reset();

    {
        std.log.info("Setting Name...", .{});

        try writer.writeInt(u32, 0x0, .big); // length
        try writer.writeInt(u32, 0xff_ff_ff_ff, .big); // channel
        try writer.writeInt(u32, 0x0, .big); // offset high
        try writer.writeInt(u32, 0x0, .big); // offset low
        try writer.writeInt(u32, 0x0, .big); // flags
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32)); // type tag
        try writer.writeInt(u32, @intFromEnum(PulseAudio.Command.SetClientName), .big); // command
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32)); // type tag
        try writer.writeInt(u32, seq, .big); // seq
        seq += 1;

        const app_biny = std.mem.span(std.os.argv[0]);
        const app_name = std.fs.path.basename(app_biny);
        const app_pid = try std.fmt.allocPrint(allocator, "{}", .{std.os.linux.getpid()});
        defer allocator.free(app_pid);
        // const username = try std.os.linux.getuid();

        try writer.writeByte(@intFromEnum(PulseAudio.Type.PropList));
        try write_pa_property(writer.any(), "application.name", app_name);
        try write_pa_property(writer.any(), "application.process.id", app_pid);
        try write_pa_property(writer.any(), "application.process.binary", app_biny);
        try write_pa_property(writer.any(), "application.language", "en_US.UTF-8");
        // try write_pa_property(writer.any(), "application.process.user", "en_US.UTF-8");
        try writer.writeByte(@intFromEnum(PulseAudio.Type.StringNull));

        const written = fbs.getWritten();
        try fbs.seekTo(0);
        try writer.writeInt(u32, @intCast(written.len - 20), .big);

        std.log.info("{}", .{std.fmt.fmtSliceHexUpper(written)});

        try pa_socket.writeAll(written);
    }

    {
        var buffer_read: [1024]u8 = undefined;

        const amount_read = try pa_socket.read(&buffer_read);

        std.log.info("PulseAudio Response: \n{}", .{std.fmt.fmtSliceHexUpper(buffer_read[0..amount_read])});

        var fbs_read = std.io.fixedBufferStream(buffer_read[0..amount_read]);

        const reader = fbs_read.reader();
        const length = try reader.readInt(u32, .big);
        const channel = try reader.readInt(u32, .big);
        const offset_hi = try reader.readInt(u32, .big);
        const offset_lo = try reader.readInt(u32, .big);
        const flags = try reader.readInt(u32, .big);

        std.log.info(
            \\
            \\length      {}
            \\channel     {x}
            \\offset (hi) {}
            \\offset (lo) {}
            \\flags       {}
            \\payload:
            \\{}
        , .{
            length,
            channel,
            offset_hi,
            offset_lo,
            flags,
            std.fmt.fmtSliceHexUpper(buffer_read[20..][0..length]),
        });

        // std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        // const cmd = try reader.readEnum(PulseAudio.Command, .big);
        // std.debug.assert(cmd == .Error);

        // std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        // const server_seq = try reader.readInt(u32, .big);

        // std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        // const err = try reader.readEnum(PulseAudio.Error, .big);

        // std.log.info(
        //     \\
        //     \\cmd  {}
        //     \\seq  {}
        //     \\err  {}
        // , .{
        //     cmd,
        //     server_seq,
        //     err,
        // });

        std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        const cmd = try reader.readEnum(PulseAudio.Command, .big);
        std.debug.assert(cmd == .Reply);

        std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        const server_seq = try reader.readInt(u32, .big);

        std.debug.assert(try reader.readEnum(PulseAudio.Type, .big) == .Uint32);
        const client_index = try reader.readInt(u32, .big);

        std.log.info(
            \\
            \\cmd          {}
            \\seq          {}
            \\client index {}
        , .{
            cmd,
            server_seq,
            client_index,
        });
    }

    {
        var buffer_read: [1024]u8 = undefined;

        const amount_read = try pa_socket.read(&buffer_read);
        _ = amount_read;
    }
}

pub fn write_pa_property(writer: std.io.AnyWriter, key: []const u8, value: []const u8) !void {
    // write out key string
    try writer.writeByte(@intFromEnum(PulseAudio.Type.String));
    try writer.writeAll(key);
    try writer.writeByte(0); // null terminator

    // write out length of value
    const length: u32 = @intCast(value.len + 1);
    try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32));
    try writer.writeInt(u32, length, .big);

    // write out value
    try writer.writeByte(@intFromEnum(PulseAudio.Type.Arbitrary));
    try writer.writeInt(u32, length, .big);
    try writer.writeAll(value);
    try writer.writeByte(0); // null terminator
}

/// Returns a slice containing the pulseaudio authentication cookie.
/// Must be freed with the same allocator passed to function.
/// User is responsible for freeing returned value.
pub fn get_pa_cookie(allocator: std.mem.Allocator) ![]const u8 {
    const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);

    const path_cookie = try std.fs.path.join(allocator, &.{ home_dir, ".config", "pulse", "cookie" });
    defer allocator.free(path_cookie);

    const fd_cookie = try std.fs.openFileAbsolute(path_cookie, .{ .mode = .read_only });
    defer fd_cookie.close();

    const bin_cookie = try fd_cookie.readToEndAlloc(allocator, 256);

    const pos = try fd_cookie.getPos();
    const end = try fd_cookie.getEndPos();

    std.debug.assert(pos == end);

    return bin_cookie;
}

const PulseAudio = struct {
    const version = 32;
    const version_mask = 0x0000_FFFF;
    const AuthParams = packed struct(u32) {
        /// Clients protocol version
        version: u16,
        _unused: u14,
        /// If the client supports memfd blocks
        supports_memfd: bool,
        /// If the client supports shared memory blocks
        supports_shm: bool,
    };
    const Error = enum(u32) {
        AccessDenied = 1,
        Command = 2,
        Invalid = 3,
        Exists = 4,
        NoEntity = 5,
        ConnectionRefused = 6,
        Protocol = 7,
        Timeout = 8,
        Authkey = 9,
        Internal = 10,
        ConnectionTerminated = 11,
        Killed = 12,
        InvalidServer = 13,
        ModInitFailed = 14,
        BadState = 15,
        NoData = 16,
        Version = 17,
        TooLarge = 18,
        NotSupported = 19,
        Unknown = 20,
        NoExtension = 21,
        Obsolete = 22,
        NotImplemented = 23,
        Forked = 24,
        Io = 25,
        Busy = 26,
        _,
    };
    const Type = enum(u8) {
        Invalid = 0,
        String = 't',
        StringNull = 'N',
        Uint32 = 'L',
        Uint8 = 'B',
        Uint64 = 'R',
        Sint64 = 'r',
        SampleSpec = 'a',
        Arbitrary = 'x',
        True = '1',
        False = '0',
        Time = 'T',
        Usec = 'U',
        ChannelMap = 'm',
        CVolume = 'v',
        PropList = 'P',
        Volume = 'V',
        FormatInfo = 'f',
        _,
    };
    const Command = enum(u32) {
        Error = 0,
        Timeout = 1,
        Reply = 2,

        CreatePlaybackStream = 3,
        DeletePlaybackStream = 4,
        CreateRecordStream = 5,
        DeleteRecordStream = 6,
        Exit = 7,
        Auth = 8,
        SetClientName = 9,
        _,
    };
};
