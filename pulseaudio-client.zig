// NOTE: Imports are at the bottom of the file

pub fn main() !void {
    if (!std.net.has_unix_sockets) @compileError("Pulseaudio requires unix domain sockets");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var pa = PulseAudio{};

    try pa.connect(allocator);
    defer pa.close();

    var buf_id: [32]u8 = .{0} ** 32;

    const app_path = std.mem.span(std.os.argv[0]);
    const app_name = std.fs.path.basename(app_path);
    const app_id = try std.fmt.bufPrint(&buf_id, "{}", .{std.os.linux.getpid()});

    var list = PulseAudio.PropertyList.init(.{
        .MediaRole = "game",
        .ApplicationName = app_name,
        .ApplicationProcessId = app_id,
        .ApplicationProcessBinary = app_path,
        .ApplicationLanguage = "en_US.UTF8",
    });
    pa.set_client_name(&list) catch |e| {
        std.log.info("Error Code: {?}", .{pa.error_code});
        return e;
    };

    std.log.info("Client Index: {}", .{pa.client_index});

    while (true) {}
}

// fn state_callback(pa: *PulseAudio, userdata: *anyopaque) void {
//     _ = userdata;
//     const state = pa.get_context_state();
//     switch (state) {
//         .Unconnected,
//         .Connecting,
//         .Authorizing,
//         .SettingName,
//         => {},
//         .Failed,
//         .Terminated,
//         => {},
//         .Ready,
//         => {},
//     }
// }

const PulseAudio = struct {
    seq: u32 = 0,
    client_index: u32 = 0,
    error_code: ?Error = null,
    buf_write: [1024]u8 = .{0} ** 1024,
    buf_read: [1024]u8 = .{0} ** 1024,
    fbs_write: std.io.FixedBufferStream([]u8) = undefined,
    fbs_read: std.io.FixedBufferStream([]u8) = undefined,
    socket: ?std.net.Stream = null,

    const Context = struct {
        const State = enum {
            Unconnected,
            Connecting,
            Authorizing,
            SettingName,
            Failed,
            Terminated,
            Ready,
        };
    };

    pub fn connect(pa: *PulseAudio, allocator: std.mem.Allocator) !void {
        pa.socket = socket: {
            const xdg_runtime_dir = try std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR");
            defer allocator.free(xdg_runtime_dir);

            const pa_path = try std.fs.path.join(allocator, &.{ xdg_runtime_dir, "pulse", "native" });
            defer allocator.free(pa_path);

            break :socket try std.net.connectUnixSocket(pa_path);
        };

        const cookie = try get_pa_cookie(allocator);
        defer allocator.free(cookie);

        pa.fbs_write = std.io.fixedBufferStream(&pa.buf_write);

        const writer = pa.fbs_write.writer();

        try pa.write_pa_header(writer.any(), Command.Tag.Auth);
        try write_pa_u32(writer.any(), version);
        try write_pa_arbitrary(writer.any(), cookie);

        const msg = try pa.write_finish();

        try pa.socket.?.writeAll(msg);

        const count = try pa.socket.?.read(&pa.buf_read);

        const read_from = pa.buf_read[0..count];

        std.log.debug("{}", .{std.fmt.fmtSliceHexUpper(read_from)});

        var index: usize = 0;
        const header = try read_pa_header(&index, read_from);
        std.debug.assert(header.channel == std.math.maxInt(u32));

        const command = try readCommand(&index, read_from);
        if (command != .Reply) return error.UnexpectedCommand;

        const seq_int = try tagstruct.getNextValue(&index, read_from) orelse return error.EndOfStream;
        std.debug.assert(seq_int.Uint32 == 0);

        const version_srv_var = try tagstruct.getNextValue(&index, read_from) orelse return error.EndOfStream;
        if (version_srv_var != .Uint32) return error.UnexpectedValue;

        const version_srv = version_srv_var.Uint32;
        if (version_srv & version_mask < version) {
            std.log.debug("server version: {}", .{version_srv});
            return error.OutdatedServer;
        }
    }

    pub fn close(pa: *PulseAudio) void {
        if (pa.socket) |sock| {
            sock.close();
        }
    }

    const PropertyList = std.EnumMap(Property, []const u8);

    pub fn set_client_name(pa: *PulseAudio, list: *PropertyList) !void {
        pa.fbs_write.reset();

        const writer = pa.fbs_write.writer().any();

        try pa.write_pa_header(writer, Command.Tag.SetClientName);

        try writer.writeByte(@intFromEnum(Type.PropList));

        var iter = list.iterator();

        while (iter.next()) |item| {
            try write_pa_property(writer, item.key.to_string(), item.value.*);
        }

        try writer.writeByte(@intFromEnum(PulseAudio.Type.StringNull));

        const msg = try pa.write_finish();

        try pa.socket.?.writeAll(msg);

        // Response
        const count = try pa.socket.?.read(&pa.buf_read);

        const read_from = pa.buf_read[0..count];

        var index: usize = 0;
        const header = try read_pa_header(&index, read_from);
        std.debug.assert(header.channel == std.math.maxInt(u32));
        const command = try readCommand(&index, read_from);
        const seq_int = try tagstruct.getU32(&index, read_from);
        _ = seq_int;

        if (command != .Reply) {
            std.debug.assert(command == .Error);
            pa.error_code = try std.meta.intToEnum(Error, try tagstruct.getU32(&index, read_from));
            return error.UnexpectedCommand;
        }

        pa.client_index = try tagstruct.getU32(&index, read_from);
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

    const Header = struct {
        length: u32,
        channel: u32,
        offset_hi: u32,
        offset_lo: u32,
        flags: u32,
    };

    const Packet = struct {
        header: Header,
        seq: u32,
        command: Command,
    };

    pub fn read_packet(reader: std.io.AnyReader) !Packet {
        const header = try read_pa_header(reader);
        if (try reader.readEnum(Type, .big) != Type.Uint32) return error.MissingTag;
        const command_tag = try reader.readEnum(Command.Tag, .big);
        if (try reader.readEnum(Type, .big) != Type.Uint32) return error.MissingTag;
        const seq = try reader.readInt(u32, .big);

        const command = try Command.read(reader, command_tag);

        return .{
            .header = header,
            .seq = seq,
            .command = command,
        };
    }

    pub fn read_pa_header(index: *usize, buffer: []const u8) !Header {
        if (index.* > buffer.len -| 20) return error.EndOfStream;
        const read_from = buffer[index.*..];
        const length = std.mem.readInt(u32, read_from[0..4], .big);
        const channel = std.mem.readInt(u32, read_from[4..8], .big);
        const offset_hi = std.mem.readInt(u32, read_from[8..12], .big);
        const offset_lo = std.mem.readInt(u32, read_from[12..16], .big);
        const flags = std.mem.readInt(u32, read_from[16..20], .big);

        index.* += 20;

        return .{
            .length = length,
            .channel = channel,
            .offset_hi = offset_hi,
            .offset_lo = offset_lo,
            .flags = flags,
        };
    }

    pub fn readCommand(index: *usize, buffer: []const u8) !Command.Tag {
        const tag_int = try tagstruct.getU32(index, buffer);
        const tag = try std.meta.intToEnum(Command.Tag, tag_int);
        return tag;
    }

    pub fn write_pa_header(pa: *PulseAudio, writer: std.io.AnyWriter, command: Command.Tag) !void {
        try writer.writeInt(u32, 0x0, .big); // length - this will be fixed up later
        try writer.writeInt(u32, 0xff_ff_ff_ff, .big); // channel
        try writer.writeInt(u32, 0x0, .big); // offset high
        try writer.writeInt(u32, 0x0, .big); // offset low
        try writer.writeInt(u32, 0x0, .big); // flags
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32)); // type tag
        try writer.writeInt(u32, @intFromEnum(command), .big); // command
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32)); // type tag
        try writer.writeInt(u32, pa.get_next_seq(), .big); // seq
    }

    pub fn write_finish(pa: *PulseAudio) ![]const u8 {
        const written = pa.fbs_write.getWritten();
        try pa.fbs_write.seekTo(0);
        const writer = pa.fbs_write.writer();
        try writer.writeInt(u32, @intCast(written.len - 20), .big);
        return written;
    }

    pub fn write_pa_u32(writer: std.io.AnyWriter, int: u32) !void {
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Uint32)); // type tag
        try writer.writeInt(u32, int, .big); // seq
    }

    pub fn read_pa_u32(reader: std.io.AnyReader) !u32 {
        if (try reader.readEnum(PulseAudio.Type, .big) != .Uint32) return error.UintTagNotFound;
        const int = try reader.readInt(u32, .big); // seq
        return int;
    }

    pub fn write_pa_arbitrary(writer: std.io.AnyWriter, blob: []const u8) !void {
        try writer.writeByte(@intFromEnum(PulseAudio.Type.Arbitrary)); // type tag
        try writer.writeInt(u32, @intCast(blob.len), .big); // seq
        try writer.writeAll(blob);
    }

    pub fn get_next_seq(pa: *PulseAudio) u32 {
        const seq = pa.seq;
        pa.seq += 1;
        return seq;
    }

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

    const SampleSpec = struct {
        format: Format,
        channels: u8,
        sample_rate: u32,

        const Format = enum(u8) {
            Invalid = std.math.maxInt(u8),
            Uint8 = 0,
            Alaw = 1,
            Ulaw = 2,
            Sint16Le = 3,
            Sint16Be = 4,
            Float32Le = 5,
            Float32Be = 6,
            Sint32Le = 7,
            Sint32Be = 8,
            Sint24Le = 9,
            Sint24Be = 10,
            Sint24in32Le = 11,
            Sint24in32Be = 12,
        };
    };
    const MAX_CHANNELS = 32;
    const ChannelMap = struct {
        channels: u8,
        map: [MAX_CHANNELS]Position,
        const Position = enum {};
    };
    const Volume = enum(u32) { _ };
    const ChannelVolume = struct {
        channels: u8,
        volumes: [MAX_CHANNELS]Volume,
    };
    const FormatEncoding = enum {};
    const FormatInfo = struct {
        encoding: FormatEncoding,
        props: PropertyList,
    };
    const StreamFlags = packed struct(u16) {
        _unused: u32,
    };
    const BufferAttr = struct {
        max_length: u32,
        target_length: u32,
        pre_buffering: u32,
        minimum_request_length: u32,
        fragment_size: u32,
    };

    const PlaybackStreamParams = struct {
        sample_spec: SampleSpec,
        channel_map: ChannelMap,
        sink_index: ?u32,
        sink_name: ?[]const u8 = null,
        buffer_attr: BufferAttr,
        sync_id: u32,
        cvolume: ?ChannelVolume,
        props: PropertyList,
        formats: []const FormatInfo,
        flags: StreamFlags,
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

    /// A message from server to client
    const Reply = struct {
        // TODO
    };

    /// A message from server to client
    const Event = struct {
        // TODO
    };

    /// A message from client to server
    const Command = union(Tag) {
        Error: Error,
        Timeout,
        Reply,

        CreatePlaybackStream,
        DeletePlaybackStream,
        CreateRecordStream,
        DeleteRecordStream,
        Exit,
        Auth: AuthParams,
        SetClientName: PropertyList,

        pub fn read(reader: std.io.AnyReader, tag: Tag) !Command {
            switch (tag) {
                .Error => {
                    const err: Error = @enumFromInt(try read_pa_u32(reader));
                    return .{ .Error = err };
                },
                .Reply => {
                    // Do nothing, the format is determined by what command is being responded to
                    return .Reply;
                },
                .Auth => {
                    const val: AuthParams = @bitCast(try read_pa_u32(reader));
                    return .{ .Auth = val };
                },
                else => return error.Unimplemented,
            }
        }

        const Tag = enum(u32) {
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
        };
    };
};

const std = @import("std");
const Property = @import("properties.zig").Property;
const tagstruct = @import("tagstruct.zig");
