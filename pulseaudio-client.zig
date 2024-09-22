const std = @import("std");

pub fn main() !void {
    if (!std.net.has_unix_sockets) @compileError("Pulseaudio requires unix domain sockets");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    _ = allocator;

    var pa = PulseAudio{};

    try pa.connect();
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

fn state_callback(pa: *PulseAudio, userdata: *anyopaque) void {
    _ = userdata;
    const state = pa.get_context_state();
    switch (state) {
        .Unconnected,
        .Connecting,
        .Authorizing,
        .SettingName,
        => {},
        .Failed,
        .Terminated,
        => {},
        .Ready,
        => {},
    }
}

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

    pub fn connect(pa: *PulseAudio) !void {
        var buf_fba: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf_fba);
        const allocator = fba.allocator();

        pa.socket = socket: {
            const xdg_runtime_dir = try std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR");
            defer allocator.free(xdg_runtime_dir);

            const pa_path = try std.fs.path.join(allocator, &.{ xdg_runtime_dir, "pulse", "native" });
            defer allocator.free(pa_path);

            break :socket try std.net.connectUnixSocket(pa_path);
        };

        const cookie = try get_pa_cookie(allocator);

        pa.fbs_write = std.io.fixedBufferStream(&pa.buf_write);

        const writer = pa.fbs_write.writer();

        try pa.write_pa_header(writer.any(), Command.Tag.Auth);
        try write_pa_u32(writer.any(), version);
        try write_pa_arbitrary(writer.any(), cookie);

        const msg = try pa.write_finish();

        try pa.socket.?.writeAll(msg);

        const count = try pa.socket.?.read(&pa.buf_read);

        pa.fbs_read = std.io.fixedBufferStream(pa.buf_read[0..count]);
        const reader = pa.fbs_read.reader();

        const packet = try read_packet(reader.any());
        if (packet.command != .Reply) return error.UnexpectedCommand;
        std.debug.assert(try reader.readEnum(Type, .big) == .Uint32);
        const version_srv = try reader.readInt(u32, .big);
        if (version_srv & version_mask < version) {
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

        pa.fbs_read = std.io.fixedBufferStream(pa.buf_read[0..count]);
        const reader = pa.fbs_read.reader();

        const packet = try read_packet(reader.any());
        std.debug.assert(packet.header.channel == std.math.maxInt(u32));
        if (packet.command != .Reply) {
            std.debug.assert(packet.command == .Error);
            pa.error_code = packet.command.Error;
            return error.UnexpectedCommand;
        }
        std.debug.assert(try reader.readEnum(Type, .big) == .Uint32);
        pa.client_index = try reader.readInt(u32, .big);
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

    pub fn read_pa_header(reader: std.io.AnyReader) !Header {
        const length = try reader.readInt(u32, .big);
        const channel = try reader.readInt(u32, .big);
        const offset_hi = try reader.readInt(u32, .big);
        const offset_lo = try reader.readInt(u32, .big);
        const flags = try reader.readInt(u32, .big);

        return .{
            .length = length,
            .channel = channel,
            .offset_hi = offset_hi,
            .offset_lo = offset_lo,
            .flags = flags,
        };
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
            _,
        };
    };
    /// Tags copied from rust pulseaudio library: https://docs.rs/pulseaudio/latest/src/pulseaudio/protocol/serde/props.rs.html
    const Property = enum {
        /// For streams: localized media name, formatted as UTF-8. E.g. "Guns'N'Roses: Civil War".
        MediaName,

        /// For streams: localized media title if applicable, formatted as UTF-8. E.g. "Civil War"
        MediaTitle,

        /// For streams: localized media artist if applicable, formatted as UTF-8. E.g. "Guns'N'Roses"
        MediaArtist,

        /// For streams: localized media copyright string if applicable, formatted as UTF-8. E.g. "Evil Record Corp."
        MediaCopyright,

        /// For streams: localized media generator software string if applicable, formatted as UTF-8. E.g. "Foocrop AudioFrobnicator"
        MediaSoftware,

        /// For streams: media language if applicable, in standard POSIX format. E.g. "de_DE"
        MediaLanguage,

        /// For streams: source filename if applicable, in URI format or local path. E.g. "/home/lennart/music/foobar.ogg"
        MediaFilename,

        /// For streams: icon for the media. A binary blob containing PNG image data
        MediaIcon,

        /// For streams: an XDG icon name for the media. E.g. "audio-x-mp3"
        MediaIconName,

        /// For streams: logic role of this media. One of the strings "video", "music", "game", "event", "phone", "animation", "production", "a11y", "test"
        MediaRole,

        /// For streams: the name of a filter that is desired, e.g.\ "echo-cancel" or "equalizer-sink". PulseAudio may choose to not apply the filter if it does not make sense (for example, applying echo-cancellation on a Bluetooth headset probably does not make sense. \since 1.0
        FilterWant,

        /// For streams: the name of a filter that is desired, e.g.\ "echo-cancel" or "equalizer-sink". Differs from PA_PROP_FILTER_WANT in that it forces PulseAudio to apply the filter, regardless of whether PulseAudio thinks it makes sense to do so or not. If this is set, PA_PROP_FILTER_WANT is ignored. In other words, you almost certainly do not want to use this. \since 1.0
        FilterApply,

        /// For streams: the name of a filter that should specifically suppressed (i.e.\ overrides PA_PROP_FILTER_WANT). Useful for the times that PA_PROP_FILTER_WANT is automatically added (e.g. echo-cancellation for phone streams when $VOIP_APP does its own, internal AEC) \since 1.0
        FilterSuppress,

        /// For event sound streams: XDG event sound name. e.g.\ "message-new-email" (Event sound streams are those with media.role set to "event")
        EventId,

        /// For event sound streams: localized human readable one-line description of the event, formatted as UTF-8. E.g. "Email from lennart@example.com received."
        EventDescription,

        /// For event sound streams: absolute horizontal mouse position on the screen if the event sound was triggered by a mouse click, integer formatted as text string. E.g. "865"
        EventMouseX,

        /// For event sound streams: absolute vertical mouse position on the screen if the event sound was triggered by a mouse click, integer formatted as text string. E.g. "432"
        EventMouseY,

        /// For event sound streams: relative horizontal mouse position on the screen if the event sound was triggered by a mouse click, float formatted as text string, ranging from 0.0 (left side of the screen) to 1.0 (right side of the screen). E.g. "0.65"
        EventMouseHPos,

        /// For event sound streams: relative vertical mouse position on the screen if the event sound was triggered by a mouse click, float formatted as text string, ranging from 0.0 (top of the screen) to 1.0 (bottom of the screen). E.g. "0.43"
        EventMouseVPos,

        /// For event sound streams: mouse button that triggered the event if applicable, integer formatted as string with 0=left, 1=middle, 2=right. E.g. "0"
        EventMouseButton,

        /// For streams that belong to a window on the screen: localized window title. E.g. "Totem Music Player"
        WindowName,

        /// For streams that belong to a window on the screen: a textual id for identifying a window logically. E.g. "org.gnome.Totem.MainWindow"
        WindowId,

        /// For streams that belong to a window on the screen: window icon. A binary blob containing PNG image data
        WindowIcon,

        /// For streams that belong to a window on the screen: an XDG icon name for the window. E.g. "totem"
        WindowIconName,

        /// For streams that belong to a window on the screen: absolute horizontal window position on the screen, integer formatted as text string. E.g. "865". \since 0.9.17
        WindowX,

        /// For streams that belong to a window on the screen: absolute vertical window position on the screen, integer formatted as text string. E.g. "343". \since 0.9.17
        WindowY,

        /// For streams that belong to a window on the screen: window width on the screen, integer formatted as text string. e.g. "365". \since 0.9.17
        WindowWidth,

        /// For streams that belong to a window on the screen: window height on the screen, integer formatted as text string. E.g. "643". \since 0.9.17
        WindowHeight,

        /// For streams that belong to a window on the screen: relative position of the window center on the screen, float formatted as text string, ranging from 0.0 (left side of the screen) to 1.0 (right side of the screen). E.g. "0.65". \since 0.9.17
        WindowHPos,

        /// For streams that belong to a window on the screen: relative position of the window center on the screen, float formatted as text string, ranging from 0.0 (top of the screen) to 1.0 (bottom of the screen). E.g. "0.43". \since 0.9.17
        WindowVPos,

        /// For streams that belong to a window on the screen: if the windowing system supports multiple desktops, a comma separated list of indexes of the desktops this window is visible on. If this property is an empty string, it is visible on all desktops (i.e. 'sticky'). The first desktop is 0. E.g. "0,2,3" \since 0.9.18
        WindowDesktop,

        /// For streams that belong to an X11 window on the screen: the X11 display string. E.g. ":0.0"
        WindowX11Display,

        /// For streams that belong to an X11 window on the screen: the X11 screen the window is on, an integer formatted as string. E.g. "0"
        WindowX11Screen,

        /// For streams that belong to an X11 window on the screen: the X11 monitor the window is on, an integer formatted as string. E.g. "0"
        WindowX11Monitor,

        /// For streams that belong to an X11 window on the screen: the window XID, an integer formatted as string. E.g. "25632"
        WindowX11Xid,

        /// For clients/streams: localized human readable application name. E.g. "Totem Music Player"
        ApplicationName,

        /// For clients/streams: a textual id for identifying an application logically. E.g. "org.gnome.Totem"
        ApplicationId,

        /// For clients/streams: a version string, e.g.\ "0.6.88"
        ApplicationVersion,

        /// For clients/streams: application icon. A binary blob containing PNG image data
        ApplicationIcon,

        /// For clients/streams: an XDG icon name for the application. E.g. "totem"
        ApplicationIconName,

        /// For clients/streams: application language if applicable, in standard POSIX format. E.g. "de_DE"
        ApplicationLanguage,

        /// For clients/streams on UNIX: application process PID, an integer formatted as string. E.g. "4711"
        ApplicationProcessId,

        /// For clients/streams: application process name. E.g. "totem"
        ApplicationProcessBinary,

        /// For clients/streams: application user name. E.g. "jonas"
        ApplicationProcessUser,

        /// For clients/streams: host name the application runs on. E.g. "omega"
        ApplicationProcessHost,

        /// For clients/streams: the D-Bus host id the application runs on. E.g. "543679e7b01393ed3e3e650047d78f6e"
        ApplicationProcessMachineId,

        /// For clients/streams: an id for the login session the application runs in. On Unix the value of $XDG_SESSION_ID. E.g. "5"
        ApplicationProcessSessionId,

        /// For devices: device string in the underlying audio layer's format. E.g. "surround51:0"
        DeviceString,

        /// For devices: API this device is access with. E.g. "alsa"
        DeviceApi,

        /// For devices: localized human readable device one-line description. E.g. "Foobar Industries USB Headset 2000+ Ultra"
        DeviceDescription,

        /// For devices: bus path to the device in the OS' format. E.g. "/sys/bus/pci/devices/0000:00:1f.2"
        DeviceBusPath,

        /// For devices: serial number if applicable. E.g. "4711-0815-1234"
        DeviceSerial,

        /// For devices: vendor ID if applicable. E.g. 1274
        DeviceVendorId,

        /// For devices: vendor name if applicable. E.g. "Foocorp Heavy Industries"
        DeviceVendorName,

        /// For devices: product ID if applicable. E.g. 4565
        DeviceProductId,

        /// For devices: product name if applicable. E.g. "SuperSpeakers 2000 Pro"
        DeviceProductName,

        /// For devices: device class. One of "sound", "modem", "monitor", "filter"
        DeviceClass,

        /// For devices: form factor if applicable. One of "internal", "speaker", "handset", "tv", "webcam", "microphone", "headset", "headphone", "hands-free", "car", "hifi", "computer", "portable"
        DeviceFormFactor,

        /// For devices: bus of the device if applicable. One of "isa", "pci", "usb", "firewire", "bluetooth"
        DeviceBus,

        /// For devices: icon for the device. A binary blob containing PNG image data
        DeviceIcon,

        /// For devices: an XDG icon name for the device. E.g. "sound-card-speakers-usb"
        DeviceIconName,

        /// For devices: access mode of the device if applicable. One of "mmap", "mmap_rewrite", "serial"
        DeviceAccessMode,

        /// For filter devices: master device id if applicable.
        DeviceMasterDevice,

        /// For devices: buffer size in bytes, integer formatted as string.
        DeviceBufferingBufferSize,

        /// For devices: fragment size in bytes, integer formatted as string.
        DeviceBufferingFragmentSize,

        /// For devices: profile identifier for the profile this devices is in. E.g. "analog-stereo", "analog-surround-40", "iec958-stereo", ...
        DeviceProfileName,

        /// For devices: intended use. A space separated list of roles (see PA_PROP_MEDIA_ROLE) this device is particularly well suited for, due to latency, quality or form factor. \since 0.9.16
        DeviceIntendedRoles,

        /// For devices: human readable one-line description of the profile this device is in. E.g. "Analog Stereo", ...
        DeviceProfileDescription,

        /// For modules: the author's name, formatted as UTF-8 string. E.g. "Lennart Poettering"
        ModuleAuthor,

        /// For modules: a human readable one-line description of the module's purpose formatted as UTF-8. E.g. "Frobnicate sounds with a flux compensator"
        ModuleDescription,

        /// For modules: a human readable usage description of the module's arguments formatted as UTF-8.
        ModuleUsage,

        /// For modules: a version string for the module. E.g. "0.9.15"
        ModuleVersion,

        /// For PCM formats: the sample format used as returned by pa_sample_format_to_string() \since 1.0
        FormatSampleFormat,

        /// For all formats: the sample rate (unsigned integer) \since 1.0
        FormatRate,

        /// For all formats: the number of channels (unsigned integer) \since 1.0
        FormatChannels,

        /// For PCM formats: the channel map of the stream as returned by pa_channel_map_snprint() \since 1.0
        FormatChannelMap,

        pub fn to_string(prop: Property) []const u8 {
            return switch (prop) {
                .MediaName => "media.name",
                .MediaTitle => "media.title",
                .MediaArtist => "media.artist",
                .MediaCopyright => "media.copyright",
                .MediaSoftware => "media.software",
                .MediaLanguage => "media.language",
                .MediaFilename => "media.filename",
                .MediaIconName => "media.icon_name",
                .MediaIcon => "media.icon",
                .MediaRole => "media.role",
                .FilterWant => "filter.want",
                .FilterApply => "filter.apply",
                .FilterSuppress => "filter.suppress",
                .EventId => "event.id",
                .EventDescription => "event.description",
                .EventMouseX => "event.mouse.x",
                .EventMouseY => "event.mouse.y",
                .EventMouseHPos => "event.mouse.hpos",
                .EventMouseVPos => "event.mouse.vpos",
                .EventMouseButton => "event.mouse.button",
                .WindowName => "window.name",
                .WindowId => "window.id",
                .WindowIconName => "window.icon_name",
                .WindowIcon => "window.icon",
                .WindowX => "window.x",
                .WindowY => "window.y",
                .WindowWidth => "window.width",
                .WindowHeight => "window.height",
                .WindowHPos => "window.hpos",
                .WindowVPos => "window.vpos",
                .WindowDesktop => "window.desktop",
                .WindowX11Display => "window.x11.display",
                .WindowX11Screen => "window.x11.screen",
                .WindowX11Monitor => "window.x11.monitor",
                .WindowX11Xid => "window.x11.xid",
                .ApplicationName => "application.name",
                .ApplicationId => "application.id",
                .ApplicationVersion => "application.version",
                .ApplicationIcon => "application.icon",
                .ApplicationIconName => "application.icon.name",
                .ApplicationLanguage => "application.language",
                .ApplicationProcessId => "application.process.id",
                .ApplicationProcessBinary => "application.process.binary",
                .ApplicationProcessUser => "application.process.user",
                .ApplicationProcessHost => "application.process.host",
                .ApplicationProcessMachineId => "application.process.machine_id",
                .ApplicationProcessSessionId => "application.process.session_id",
                .DeviceString => "device.string",
                .DeviceApi => "device.api",
                .DeviceDescription => "device.description",
                .DeviceBusPath => "device.bus_path",
                .DeviceSerial => "device.serial",
                .DeviceVendorId => "device.vendor.id",
                .DeviceVendorName => "device.vendor.name",
                .DeviceProductId => "device.product.id",
                .DeviceProductName => "device.product.name",
                .DeviceClass => "device.class",
                .DeviceFormFactor => "device.form_factor",
                .DeviceBus => "device.bus",
                .DeviceIconName => "device.icon_name",
                .DeviceIcon => "device.icon",
                .DeviceAccessMode => "device.access_mode",
                .DeviceMasterDevice => "device.master_device",
                .DeviceBufferingBufferSize => "device.buffering.buffer_size",
                .DeviceBufferingFragmentSize => "device.buffering.fragment_size",
                .DeviceProfileName => "device.profile.name",
                .DeviceIntendedRoles => "device.intended_roles",
                .DeviceProfileDescription => "device.profile.description",
                .ModuleAuthor => "module.author",
                .ModuleDescription => "module.description",
                .ModuleUsage => "module.usage",
                .ModuleVersion => "module.version",
                .FormatSampleFormat => "format.sample_format",
                .FormatRate => "format.rate",
                .FormatChannels => "format.channels",
                .FormatChannelMap => "format.channel_map",
            };
        }
    };
};
