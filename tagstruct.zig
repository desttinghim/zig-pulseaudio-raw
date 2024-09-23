const max_tag_size = (64 * 1024);

// Public Declarations --------------------------------------------------------

pub const Error = error{
    OutOfSpace,
    InvalidEnumTag,
    TypeMismatch,
};

// --- Put Functions ----------------------------------------------------------

pub fn putString(index: *usize, buffer: []u8, str_opt: ?[]const u8) Error!void {
    if (buffer.len -| index.* < 1) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    if (str_opt) |str| {
        const need_to_add_null = str[str.len - 1] != 0;
        const length = if (need_to_add_null) str.len + 2 else str.len + 1;
        if (write_to.len < length) return error.OutOfSpace;
        write_to[0] = @intFromEnum(Tag.String);
        @memcpy(write_to[1..][0..str.len], str);
        write_to[1 + str.len] = 0;
        // if (length > str.len) write_to[length] = 0;
        index.* += length;
    } else {
        write_to[0] = @intFromEnum(Tag.StringNull);
        index.* += 1;
    }
}

test putString {
    var buffer = [_]u8{0} ** 128;
    var index: usize = 0;
    try putString(&index, &buffer, "application.name");
    const expected = [_]u8{@intFromEnum(Tag.String)} ++ "application.name\x00";
    try std.testing.expectEqualSlices(u8, expected, buffer[0..index]);
}

pub fn putU32(index: *usize, buffer: []u8, value: u32) Error!void {
    if (buffer.len -| index.* < 5) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Uint32);
    std.mem.writeInt(u32, write_to[1..5], value, .big);
    index.* += 5;
}

test putU32 {
    var buffer = [_]u8{0} ** 16;
    var index: usize = 0;
    try putU32(&index, &buffer, 0xDEADBEEF);
    const expected = [_]u8{ @intFromEnum(Tag.Uint32), 0xDE, 0xAD, 0xBE, 0xEF };
    try std.testing.expectEqualSlices(u8, &expected, buffer[0..index]);
}

pub fn putU8(index: *usize, buffer: []u8, value: u8) Error!void {
    if (buffer.len -| index.* < 2) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Uint8);
    write_to[1] = value;
    index.* += 2;
}

test putU8 {
    var buffer = [_]u8{0} ** 16;
    var index: usize = 0;
    try putU8(&index, &buffer, 69);
    const expected = [_]u8{ @intFromEnum(Tag.Uint8), 69 };
    try std.testing.expectEqualSlices(u8, &expected, buffer[0..index]);
}

pub fn putSampleSpec(index: *usize, buffer: []u8, sample_spec: SampleSpec) Error!void {
    if (buffer.len -| index.* < 7) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.SampleSpec);
    write_to[1] = @intFromEnum(sample_spec.format);
    write_to[2] = sample_spec.channels;
    std.mem.writeInt(u32, write_to[3..7], sample_spec.sample_rate, .big);
    index.* += 7;
}

test putSampleSpec {
    var buffer = [_]u8{0} ** 16;
    var index: usize = 0;
    try putSampleSpec(&index, &buffer, SampleSpec{
        .format = SampleSpec.Format.Uint8,
        .channels = 2,
        .sample_rate = 0xDEADBEEF,
    });
    const expected = [_]u8{
        @intFromEnum(Tag.SampleSpec),
        @intFromEnum(SampleSpec.Format.Uint8),
        2,
        0xDE,
        0xAD,
        0xBE,
        0xEF,
    };
    try std.testing.expectEqualSlices(u8, &expected, buffer[0..index]);
}

pub fn putArbitrary(index: *usize, buffer: []u8, bytes: []const u8) !void {
    if (buffer.len -| index.* < 5 + bytes.len) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Arbitrary);
    std.mem.writeInt(u32, write_to[1..5], @intCast(bytes.len), .big);
    @memcpy(write_to[5..][0..bytes.len], bytes);
    index.* += 5 + bytes.len;
}

pub fn putBoolean(index: *usize, buffer: []u8, value: bool) !void {
    if (buffer.len -| index.* < 1) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(if (value) Tag.True else Tag.False);
    index.* += 1;
}

pub fn putTimeval(index: *usize, buffer: []u8, timeval: TimeVal) !void {
    if (buffer.len -| index.* < 9) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Time);
    std.mem.writeInt(u32, write_to[1..5], timeval.sec, .big);
    std.mem.writeInt(u32, write_to[5..9], timeval.usec, .big);
    index.* += 9;
}

test putTimeval {
    var buffer = [_]u8{0} ** 16;
    var index: usize = 0;
    try putTimeval(&index, &buffer, .{ .sec = 0xDEADBEEF, .usec = 0xCAFEBABE });
    const expected = [_]u8{ @intFromEnum(Tag.Time), 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE };
    try std.testing.expectEqualSlices(u8, &expected, buffer[0..index]);
}

pub fn putUsec(index: *usize, buffer: []u8, usec: Usec) !void {
    if (buffer.len -| index.* < 1 + @sizeOf(u64)) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Usec);
    std.mem.writeInt(u64, write_to[1..9], usec, .big);
    index.* += 9;
}

pub fn putU64(index: *usize, buffer: []u8, uint64: u64) !void {
    if (buffer.len -| index.* < 1 + @sizeOf(u64)) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Uint64);
    std.mem.writeInt(u64, write_to[1..9], uint64, .big);
    index.* += 9;
}

pub fn putS64(index: *usize, buffer: []u8, sint64: i64) !void {
    if (buffer.len -| index.* < 1 + @sizeOf(i64)) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Sint64);
    std.mem.writeInt(i64, write_to[1..9], sint64, .big);
    index.* += 9;
}

pub fn putChannelMap(index: *usize, buffer: []u8, map: ChannelMap) Error!void {
    if (buffer.len -| index.* < 2 + map.channels) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.ChannelMap);
    write_to[1] = map.channels;
    for (0..@intCast(map.channels)) |i| {
        write_to[2 + i] = map.map[i];
    }
    index.* += 2 + map.channels;
}

pub fn putCVolume(index: *usize, buffer: []u8, c_volume: CVolume) Error!void {
    if (buffer.len -| index.* < 2 + c_volume.channels) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.CVolume);
    write_to[1] = c_volume.channels;
    for (0..@intCast(c_volume.channels)) |i| {
        write_to[2 + i] = c_volume.volumes[i];
    }
    index.* += 2 + c_volume.channels;
}

pub fn putVolume(index: *usize, buffer: []u8, volume: Volume) !void {
    if (buffer.len -| index.* < 5) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Volume);
    std.mem.writeInt(u32, write_to[1..5], @intFromEnum(volume), .big);
    index.* += 5;
}

pub fn putPropList(index: *usize, buffer: []u8, prop_list: PropList) !void {
    var total_length: usize = 1; // Tag
    for (prop_list) |item| {
        // TODO: decide whether to allow or disallow nulls
        total_length += 1 + item[0].len + 1; // Tag + Length + Null
        total_length += 1 + @sizeOf(u32); // Tag + U32
        total_length += 1 + @sizeOf(u32) + item[1].len; // Tag + U32 + Length
    }
    total_length += 1; // StringNull Tag
    if (buffer.len -| index.* < total_length) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.PropList);
    index.* += 1;
    for (prop_list) |item| {
        try putString(index, buffer, item[0]);
        try putU32(index, buffer, @intCast(item[1].len));
        try putArbitrary(index, buffer, item[1]);
    }
    try putString(index, buffer, null);
}

pub fn putFormatInfo(index: *usize, buffer: []u8, info: FormatInfo) !void {
    var total_length: usize = 1 + 1; // Tag + Encoding
    for (info.props) |item| {
        // TODO: decide whether to allow or disallow nulls
        total_length += 1 + item[0].len + 1; // Tag + Length + Null
        total_length += 1 + @sizeOf(u32); // Tag + U32
        total_length += 1 + @sizeOf(u32) + item[1].len; // Tag + U32 + Length
    }
    total_length += 1;

    if (buffer.len -| index.* < total_length) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.FormatInfo);
    write_to[1] = @intFromEnum(info.encoding);
    index.* += 2;
    try putPropList(index, buffer, info.props);
}

test putFormatInfo {
    var buffer = [_]u8{0} ** 256;
    var index: usize = 0;
    const f_info = FormatInfo{
        .encoding = FormatEncoding.Any,
        .props = &.{
            .{ Property.FormatSampleFormat.to_string(), "float" },
            .{ Property.FormatRate.to_string(), "44100" },
            .{ Property.FormatChannels.to_string(), "2" },
            .{ Property.FormatChannelMap.to_string(), "stereo" },
        },
    };
    try putFormatInfo(&index, &buffer, f_info);
    const expected = [_]u8{
        @intFromEnum(Tag.FormatInfo),
        @intFromEnum(FormatEncoding.Any),
        @intFromEnum(Tag.PropList),
        @intFromEnum(Tag.String),
    } ++ comptime Property.FormatSampleFormat.to_string() ++ .{
        0, // null terminator
        @intFromEnum(Tag.Uint32), 0, 0, 0, 5, // Length
        @intFromEnum(Tag.Arbitrary), 0, 0, 0, 5, // Length again
    } ++ "float" ++ .{
        @intFromEnum(Tag.String),
    } ++ Property.FormatRate.to_string() ++ .{
        0, // null terminator
        @intFromEnum(Tag.Uint32), 0, 0, 0, 5, // Length
        @intFromEnum(Tag.Arbitrary), 0, 0, 0, 5, // Length again
    } ++ "44100" ++ .{
        @intFromEnum(Tag.String),
    } ++ Property.FormatChannels.to_string() ++ .{
        0, // null terminator
        @intFromEnum(Tag.Uint32), 0, 0, 0, 1, // Length
        @intFromEnum(Tag.Arbitrary), 0, 0, 0, 1, // Length again
    } ++ "2" ++ .{
        @intFromEnum(Tag.String),
    } ++ Property.FormatChannelMap.to_string() ++ .{
        0, // null terminator
        @intFromEnum(Tag.Uint32), 0, 0, 0, 6, // Length
        @intFromEnum(Tag.Arbitrary), 0, 0, 0, 6, // Length again
    } ++ "stereo" ++ .{
        @intFromEnum(Tag.StringNull),
    };
    try std.testing.expectEqualSlices(u8, expected[0..], buffer[0..index]);
}

// --- Get Functions ----------------------------------------------------------

pub const Value = union(Value.Tag) {
    String: [:0]const u8,
    Arbitrary: []const u8,
    Uint32: u32,
    Uint8: u8,

    pub const Tag = enum {
        String,
        Arbitrary,
        Uint32,
        Uint8,
    };
};

pub fn getNextValue(index: *usize, buffer: []const u8) Error!?Value {
    if (index.* >= buffer.len - 1) return null;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    switch (tag) {
        .Invalid => return null,
        .Uint32 => return .{ .Uint32 = try getU32(index, buffer) },
        .Uint8 => return .{ .Uint8 = try getU8(index, buffer) },
        .String => {
            const str = std.mem.span(@as([*:0]const u8, @ptrCast(read_from[1..].ptr)));
            index.* += 1 + str.len + 1; // +1 for tag, +1 for null
            return .{ .String = str };
        },
        .Arbitrary => {
            const length = std.mem.readInt(u32, read_from[1..5], .big);
            index.* += 1 + length; // +1 for tag
            return .{ .Arbitrary = read_from[5 .. 5 + length] };
        },

        .StringNull,
        .Uint64,
        .Sint64,
        .SampleSpec,
        .True,
        .False,
        .Time,
        .Usec,
        .ChannelMap,
        .CVolume,
        .PropList,
        .Volume,
        .FormatInfo,
        => {
            @panic("Unimplemented");
        },
    }

    return null;
}

test getNextValue {
    var buffer = [_]u8{0} ** 128;
    var write_index: usize = 0;

    try putString(&write_index, &buffer, "spaghetti");
    try putU32(&write_index, &buffer, 0xCAFEBABE);
    try putU32(&write_index, &buffer, 0xDEADBEEF);

    try std.testing.expectEqualSlices(u8, &[_]u8{@intFromEnum(Tag.String)} ++ "spaghetti" ++ [_]u8{0}, buffer[0..11]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ @intFromEnum(Tag.Uint32), 0xCA, 0xFE, 0xBA, 0xBE }, buffer[11..16]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ @intFromEnum(Tag.Uint32), 0xDE, 0xAD, 0xBE, 0xEF }, buffer[16..21]);

    var read_index: usize = 0;

    const string = try getNextValue(&read_index, &buffer) orelse return error.UnexpectedEnd;
    try std.testing.expectEqual(Value.Tag.String, @as(Value.Tag, string));
    try std.testing.expectEqualSlices(u8, "spaghetti", string.String);

    const int = try getNextValue(&read_index, &buffer) orelse return error.UnexpectedEnd;
    try std.testing.expectEqual(Value{ .Uint32 = 0xCAFEBABE }, int);

    const int2 = try getNextValue(&read_index, &buffer) orelse return error.UnexpectedEnd;
    try std.testing.expectEqual(Value{ .Uint32 = 0xDEADBEEF }, int2);
}

pub fn getU32(index: *usize, buffer: []const u8) Error!u32 {
    if (index.* > buffer.len - 5) return error.OutOfSpace;
    const read_from = buffer[index.* .. index.* + 5];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .Uint32) return error.TypeMismatch;

    index.* += 5; // Only advance index if no error occurs

    return std.mem.readInt(u32, read_from[1..5], .big);
}

pub fn getU8(index: *usize, buffer: []const u8) Error!u8 {
    if (index.* > buffer.len - 2) return error.OutOfSpace;
    const read_from = buffer[index.*..][0..2];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .Uint8) return error.TypeMismatch;

    index.* += 2; // Only advance index if no error occurs

    return read_from[1];
}

// pub fn getString(index: *usize, buffer: []const u8) Error!?[]const u8 {
//     if (buffer.len -| index.* < 1) return error.OutOfSpace;
//     const write_to = buffer[index.*..];
//     if (str_opt) |str| {
//         const need_to_add_null = str[str.len - 1] != 0;
//         const length = if (need_to_add_null) str.len + 2 else str.len + 1;
//         if (write_to.len < length) return error.OutOfSpace;
//         write_to[0] = @intFromEnum(Tag.String);
//         @memcpy(write_to[1..][0..str.len], str);
//         if (length > str.len) write_to[length] = 0;
//         index.* += length;
//     } else {
//         write_to[0] = @intFromEnum(Tag.StringNull);
//         index.* += 1;
//     }
// }

// --- Data Structures --------------------------------------------------------
pub const TimeVal = struct {
    sec: u32,
    usec: u32,
};
pub const Usec = u64;
pub const SampleSpec = struct {
    format: Format,
    channels: u8,
    sample_rate: u32,

    pub const Format = enum(u8) {
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

        const Sint16Ne = if (builtin.cpu.arch.endian() == .little) Format.Sint16Le else Format.Sint16Be;
        const Sint16Re = if (builtin.cpu.arch.endian() == .little) Format.Sint16Be else Format.Sint16Le;
        const Sint32Ne = if (builtin.cpu.arch.endian() == .little) Format.Sint32Le else Format.Sint32Be;
        const Sint32Re = if (builtin.cpu.arch.endian() == .little) Format.Sint32Be else Format.Sint32Le;
        const Sint24Ne = if (builtin.cpu.arch.endian() == .little) Format.Sint24Le else Format.Sint24Be;
        const Sint24Re = if (builtin.cpu.arch.endian() == .little) Format.Sint24Be else Format.Sint24Le;
        const Sint24in32Ne = if (builtin.cpu.arch.endian() == .little) Format.Sint24in32Le else Format.Sint24in32Be;
        const Sint24in32Re = if (builtin.cpu.arch.endian() == .little) Format.Sint24in32Be else Format.Sint24in32Le;
        const Float32Ne = if (builtin.cpu.arch.endian() == .little) Format.Float32Le else Format.Float32Be;
        const Float32Re = if (builtin.cpu.arch.endian() == .little) Format.Float32Be else Format.Float32Le;

        pub const string_map = std.StaticStringMap(Format).initComptime(
            .{ "s16le", .Sint16Le },
            .{ "s16be", .Sint16Be },
            .{ "s16ne", Sint16Ne },
            .{ "s16", Sint16Ne },
            .{ "16", Sint16Ne },
            .{ "s16re", Sint16Re },
            .{ "u8", .Uint8 },
            .{ "8", .Uint8 },
            .{ "float32", Float32Ne },
            .{ "float32ne", Float32Ne },
            .{ "float", Float32Ne },
            .{ "float32re", .Float32Re },
            .{ "float32le", .Float32Le },
            .{ "float32be", .Float32Be },
            .{ "ulaw", .Ulaw },
            .{ "mulaw", .Ulaw },
            .{ "alaw", .Alaw },
            .{ "s32le", .Sint32Le },
            .{ "s32be", .Sint32Be },
            .{ "s32re", Sint32Re },
            .{ "s32ne", Sint32Ne },
            .{ "s32", Sint32Ne },
            .{ "32", Sint32Ne },
            .{ "s24le", .Sint24Le },
            .{ "s24be", .Sint24Be },
            .{ "s24re", Sint24Re },
            .{ "s24ne", Sint24Ne },
            .{ "s24", Sint24Ne },
            .{ "24", Sint24Ne },
            .{ "s24-32le", .Sint24in32Le },
            .{ "s24-32be", .Sint24in32Be },
            .{ "s24-32re", Sint24in32Re },
            .{ "s24-32ne", Sint24in32Ne },
            .{ "s24-32", Sint24in32Ne },
        );
    };
};
const MAX_CHANNELS = 32;
const ChannelMap = struct {
    channels: u8,
    map: [MAX_CHANNELS]Position,
    const Position = enum {};

    pub fn fromString(str: []const u8) ChannelMap {
        _ = str;
        // TODO!
        return undefined;
    }
};
const Volume = enum(u32) { _ };
const CVolume = struct {
    channels: u8,
    volumes: [MAX_CHANNELS]Volume,
};
const Prop = struct { []const u8, []const u8 };
const PropList = []const Prop;
const FormatEncoding = enum {
    Any,
    PCM,
    AC3_IEC61937,
    EAC3_IEC61937,
    MPEG_IEC61937,
    DTS_IEC61937,
    MPEG2_AAC_IEC61937,
    TRUEHD_IEC61937,
    DTSHD_IEC61937,
};
const FormatInfo = struct {
    encoding: FormatEncoding,
    props: PropList,
};

// --- Private Functions ------------------------------------------------------

/// Tags used to build values
pub const Tag = enum(u8) {
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

const ParseError = error{
    TypeMismatch,
    StringNull,
} || std.io.AnyReader.Error;

// pub fn readString(reader: std.io.AnyReader, buf: []u8) ParseError![]u8 {
//     switch (try reader.readEnum(Type, .big)) {
//         .String => {},
//         .StringNull => {
//             return error.StringNull;
//         },
//         else => return error.TypeMismatch,
//     }
//     return reader.readUntilDelimiter(buf, 0);
// }

// /// A list associating string keys with arbitrary values,
// /// usually strings.
// pub const PropertyList = struct {
//     pub const Property = struct {
//         key: []const u8,
//         value: []const u8,
//     };

//     pub fn readProperty(reader: std.io.AnyReader, key_buf: []u8, value_buf: []u8) !?Property {
//         const key = readString(reader, key_buf) catch |e| switch (e) {
//             error.StringNull => return null,
//             else => return e,
//         };
//         const value = try readString(reader, value_buf);
//         return .{
//             .key = key,
//             .value = value,
//         };
//     }
// };

const std = @import("std");
const builtin = @import("builtin");
const Property = @import("properties.zig").Property;
