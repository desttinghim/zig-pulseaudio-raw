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

    var list = [_]tagstruct.Prop{
        .{ Property.MediaRole.to_string(), "game" },
        .{ Property.ApplicationName.to_string(), app_name },
        .{ Property.ApplicationProcessId.to_string(), app_id },
        .{ Property.ApplicationProcessBinary.to_string(), app_path },
        .{ Property.ApplicationLanguage.to_string(), "en_US.UTF8" },
    };
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
    error_code: ?ErrorCode = null,
    buf_write: [1024]u8 = .{0} ** 1024,
    buf_read: [1024]u8 = .{0} ** 1024,
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

        var write_index: usize = 0;

        try putHeader(&write_index, &pa.buf_write, .{});
        try putCommand(&write_index, &pa.buf_write, Command.Tag.Auth, pa.get_next_seq());
        try tagstruct.putU32(&write_index, &pa.buf_write, version);
        try tagstruct.putArbitrary(&write_index, &pa.buf_write, cookie);
        write_finish(&pa.buf_write, write_index);

        std.log.debug("{}", .{std.fmt.fmtSliceHexUpper(pa.buf_write[0..write_index])});

        try pa.socket.?.writeAll(pa.buf_write[0..write_index]);

        const count = try pa.socket.?.read(&pa.buf_read);

        const read_from = pa.buf_read[0..count];

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

    pub fn set_client_name(pa: *PulseAudio, list: tagstruct.PropList) !void {
        var write_index: usize = 0;

        try putHeader(&write_index, &pa.buf_write, .{});
        try putCommand(&write_index, &pa.buf_write, Command.Tag.SetClientName, pa.get_next_seq());
        try tagstruct.putPropList(&write_index, &pa.buf_write, list);
        write_finish(&pa.buf_write, write_index);

        std.log.debug("{}", .{std.fmt.fmtSliceHexUpper(pa.buf_write[0..write_index])});

        try pa.socket.?.writeAll(pa.buf_write[0..write_index]);

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
            pa.error_code = try std.meta.intToEnum(ErrorCode, try tagstruct.getU32(&index, read_from));
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

    const Header = struct {
        length: u32 = 0,
        channel: u32 = 0xFFFF_FFFF,
        offset_hi: u32 = 0,
        offset_lo: u32 = 0,
        flags: u32 = 0,
    };

    const Packet = struct {
        header: Header,
        seq: u32,
        command: Command,
    };

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

    pub fn putHeader(index: *usize, buffer: []u8, header: Header) !void {
        if (index.* + 20 > buffer.len) return error.OutOfSpace;
        const write_to = buffer[index.*..];

        // Most likely, the header length is not final and will need to be adjusted
        std.mem.writeInt(u32, write_to[0..][0..4], header.length, .big);
        std.mem.writeInt(u32, write_to[4..][0..4], header.channel, .big);
        std.mem.writeInt(u32, write_to[8..][0..4], header.offset_hi, .big);
        std.mem.writeInt(u32, write_to[12..][0..4], header.offset_lo, .big);
        std.mem.writeInt(u32, write_to[16..][0..4], header.flags, .big);

        index.* += 20;
    }

    pub fn putCommand(index: *usize, buffer: []u8, command: Command.Tag, seq: u32) !void {
        if (index.* + 10 > buffer.len) return error.OutOfSpace;

        try tagstruct.putU32(index, buffer, @intFromEnum(command));
        try tagstruct.putU32(index, buffer, seq);
    }

    pub fn write_finish(buffer: []u8, final_length: usize) void {
        std.mem.writeInt(u32, buffer[0..4], @intCast(final_length - 20), .big);
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

    const ErrorCode = enum(u32) {
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
        Error: ErrorCode,
        Timeout,
        Reply,

        CreatePlaybackStream,
        DeletePlaybackStream,
        CreateRecordStream,
        DeleteRecordStream,
        Exit,
        Auth: AuthParams,
        SetClientName: PropertyList,

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
