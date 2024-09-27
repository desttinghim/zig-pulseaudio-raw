//! # Tagstruct
//!
//! Tagstruct is the name of the Plain Old Data (P.O.D.) format used by
//! PulseAudio to communicate between the client and the server. The encoding
//! uses byte-sized tags to indicate the type of the following data, with the
//! size of the data depending on the type. All numerical types are big-endian
//! or network-order, since PulseAudio was designed to allow clients to connect
//! over the network.
//!
//! This file contains functions for building tagstruct payloads (put* prefix),
//! functions for parsing tagstruct payloads (get* prefix), and supporting type
//! definitions (structs and enums for the various types).

// Public Declarations --------------------------------------------------------

// --- Put Functions ----------------------------------------------------------
// ## Design Notes
//
// The put functions are designed to work with minimal supporting infrastructure
// and to work without an allocator. Users may build payloads in a stack-
// allocated or heap-allocated buffer, but they are responsible for the lifetime
// of the buffer.

pub fn putString(index: *usize, buffer: []u8, str_opt: ?[:0]const u8) Error!void {
    if (buffer.len -| index.* < 1) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    if (str_opt) |str| {
        const length = str.len + 1;
        if (write_to.len < length) return error.OutOfSpace;
        write_to[0] = @intFromEnum(Tag.String);
        @memcpy(write_to[1..][0..str.len], str);
        write_to[1..][str.len] = 0;
        index.* += 1 + str.len + 1; // Tag + Null-terminated String
    } else {
        write_to[0] = @intFromEnum(Tag.StringNull);
        index.* += 1;
    }
}

test putString {
    var buffer = [_]u8{0xAA} ** 128;
    var index: usize = 0;

    try putString(&index, &buffer, "application.name");
    try putString(&index, &buffer, null);

    const expected = [_]u8{@intFromEnum(Tag.String)} ++ "application.name\x00" ++ .{@intFromEnum(Tag.StringNull)};

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
    var buffer = [_]u8{0xAA} ** 16;
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
    var buffer = [_]u8{0xAA} ** 16;
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
    var buffer = [_]u8{0xAA} ** 16;
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

pub fn putArbitraryWithNull(index: *usize, buffer: []u8, bytes: []const u8) !void {
    if (buffer.len -| index.* < 5 + bytes.len + 1) return error.OutOfSpace;
    const length = bytes.len + 1;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.Arbitrary);
    std.mem.writeInt(u32, write_to[1..5], @intCast(length), .big);
    @memcpy(write_to[5..][0..bytes.len], bytes);
    write_to[5..][bytes.len] = 0;
    index.* += 5 + length;
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
        write_to[2 + i] = @intFromEnum(map.map[i]);
    }
    index.* += 2 + map.channels;
}

pub fn putCVolume(index: *usize, buffer: []u8, c_volume: CVolume) Error!void {
    if (buffer.len -| index.* < 2 + c_volume.channels * 4) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.CVolume);
    write_to[1] = c_volume.channels;
    for (0..@intCast(c_volume.channels), c_volume.volumes[0..c_volume.channels]) |i, volume| {
        std.mem.writeInt(u32, write_to[2..][i * 4 ..][0..4], @intFromEnum(volume), .big);
    }
    index.* += 2 + c_volume.channels * 4;
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
        total_length += 1 + @sizeOf(u32) + item[1].len + 1; // Tag + U32 + Length + Null
    }
    total_length += 1; // StringNull Tag
    if (buffer.len -| index.* < total_length) return error.OutOfSpace;
    const write_to = buffer[index.*..];
    write_to[0] = @intFromEnum(Tag.PropList);
    index.* += 1;
    for (prop_list) |item| {
        try putString(index, buffer, item[0]);
        try putU32(index, buffer, @intCast(item[1].len + 1));
        try putArbitraryWithNull(index, buffer, item[1]);
    }
    try putString(index, buffer, null);
}

test putPropList {
    var buffer = [_]u8{0xAA} ** 128;
    var index: usize = 0;

    var list = [_]Prop{
        .{ Property.MediaRole.to_string(), "game" },
        .{ Property.ApplicationName.to_string(), "tagstruct" },
        .{ Property.ApplicationLanguage.to_string(), "en_US.UTF8" },
    };

    try putPropList(&index, &buffer, &list);

    const expected =
        "P" ++
        "tmedia.role\x00L\x00\x00\x00\x05x\x00\x00\x00\x05game\x00" ++
        "tapplication.name\x00L\x00\x00\x00\x0ax\x00\x00\x00\x0atagstruct\x00" ++
        "tapplication.language\x00L\x00\x00\x00\x0bx\x00\x00\x00\x0ben_US.UTF8\x00" ++
        "N";
    try std.testing.expectEqualSlices(u8, expected, buffer[0..index]);
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

    const expected =
        "f\x00P" ++
        "tformat.sample_format\x00L\x00\x00\x00\x06x\x00\x00\x00\x06float\x00" ++
        "tformat.rate\x00L\x00\x00\x00\x06x\x00\x00\x00\x0644100\x00" ++
        "tformat.channels\x00L\x00\x00\x00\x02x\x00\x00\x00\x022\x00" ++
        "tformat.channel_map\x00L\x00\x00\x00\x07x\x00\x00\x00\x07stereo\x00" ++
        "N";

    try std.testing.expectEqualSlices(u8, expected[0..], buffer[0..index]);
}

// --- Get Functions ----------------------------------------------------------
// ## Design notes
//
// The get functions have been designed to have a minimum amount of external
// state. The lifetime of the data is equal to the lifetime of the underlying
// message buffer. It should be possible to do all parsing without an allocator,
// but for variable length data (like property lists!), helper functions may be
// created to automatically create an ArrayList.

pub const Value = union(Value.Tag) {
    String: [:0]const u8,
    Arbitrary: []const u8,
    Uint32: u32,
    Uint8: u8,
    SampleSpec: SampleSpec,

    pub const Tag = enum {
        String,
        Arbitrary,
        Uint32,
        Uint8,
        SampleSpec,
    };
};

pub fn getNextValue(index: *usize, buffer: []const u8) Error!?Value {
    if (index.* >= buffer.len - 1) return null;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    switch (tag) {
        .Invalid => return error.InvalidEnumTag,
        .Uint32 => return .{ .Uint32 = try getU32(index, buffer) },
        .Uint8 => return .{ .Uint8 = try getU8(index, buffer) },
        .String => return .{ .String = try getString(index, buffer) orelse "" },
        .Arbitrary => return .{ .Arbitrary = try getArbitrary(index, buffer) },
        .SampleSpec => return .{ .SampleSpec = try getSampleSpec(index, buffer) },

        .StringNull,
        .Uint64,
        .Sint64,
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
    var buffer = [_]u8{0xAA} ** 256;
    var write_index: usize = 0;

    try putString(&write_index, &buffer, "spaghetti");
    try putU32(&write_index, &buffer, 0xCAFEBABE);
    try putU32(&write_index, &buffer, 0xDEADBEEF);
    try putArbitrary(&write_index, &buffer, &.{ 69, 42, 0xAB, 0xCD });
    try putSampleSpec(&write_index, &buffer, .{
        .format = SampleSpec.Format.Alaw,
        .channels = 2,
        .sample_rate = 44100,
    });

    try std.testing.expectEqualSlices(u8, &[_]u8{@intFromEnum(Tag.String)} ++ "spaghetti\x00", buffer[0..11]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ @intFromEnum(Tag.Uint32), 0xCA, 0xFE, 0xBA, 0xBE }, buffer[11..16]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ @intFromEnum(Tag.Uint32), 0xDE, 0xAD, 0xBE, 0xEF }, buffer[16..21]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ @intFromEnum(Tag.Arbitrary), 0, 0, 0, 4, 69, 42, 0xAB, 0xCD }, buffer[21..30]);

    var read_index: usize = 0;

    const string = try getNextValue(&read_index, &buffer) orelse return error.UnexpectedEnd;
    try std.testing.expectEqual(Value.Tag.String, @as(Value.Tag, string));
    try std.testing.expectEqualSlices(u8, "spaghetti", string.String);

    const int = try getNextValue(&read_index, &buffer) orelse return error.UnexpectedEnd;
    try std.testing.expectEqual(Value{ .Uint32 = 0xCAFEBABE }, int);

    const int2 = try getNextValue(&read_index, &buffer) orelse return error.UnexpectedEnd;
    try std.testing.expectEqual(Value{ .Uint32 = 0xDEADBEEF }, int2);

    const arbitrary = try getNextValue(&read_index, &buffer) orelse return error.UnexpectedEnd;
    try std.testing.expectEqual(Value.Tag.Arbitrary, @as(Value.Tag, arbitrary));

    const sample_spec = try getNextValue(&read_index, &buffer) orelse return error.UnexpectedEnd;
    try std.testing.expectEqual(Value{ .SampleSpec = .{
        .format = SampleSpec.Format.Alaw,
        .channels = 2,
        .sample_rate = 44100,
    } }, sample_spec);
}

pub fn getString(index: *usize, buffer: []const u8) Error!?[:0]const u8 {
    if (buffer.len -| index.* < 1) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag == .StringNull) return null;
    if (tag != .String) return error.TypeMismatch;

    const str = std.mem.span(@as([*:0]const u8, @ptrCast(read_from[1..].ptr)));
    index.* += 1 + str.len + 1; // +1 for tag, +1 for null
    return str;
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

pub fn getArbitrary(index: *usize, buffer: []const u8) Error![]const u8 {
    if (buffer.len -| index.* < 5) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .Arbitrary) return error.TypeMismatch;
    const length = std.mem.readInt(u32, read_from[1..5], .big);

    index.* += 1 + 4 + length; // +1 for tag, +4 for length

    return read_from[5..][0..length];
}

pub fn getSampleSpec(index: *usize, buffer: []const u8) Error!SampleSpec {
    if (buffer.len -| index.* < 7) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .SampleSpec) return error.TypeMismatch;

    const format = try std.meta.intToEnum(SampleSpec.Format, read_from[1]);
    const channels = read_from[2];
    const sample_rate = std.mem.readInt(u32, read_from[3..7], .big);

    index.* += 7; // +1 for tag, +4 for length

    return .{
        .format = format,
        .channels = channels,
        .sample_rate = sample_rate,
    };
}

pub fn getBool(index: *usize, buffer: []const u8) Error!bool {
    if (index.* > buffer.len - 1) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .True and tag != .False) return error.TypeMismatch;
    const value = tag == .True;

    index.* += 1; // Only advance index if no error occurs

    return value;
}

pub fn getTimeVal(index: *usize, buffer: []const u8) Error!TimeVal {
    if (index.* > buffer.len - 9) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .Time) return error.TypeMismatch;
    const sec = std.mem.readInt(u32, read_from[1..5], .big);
    const usec = std.mem.readInt(u32, read_from[5..9], .big);

    index.* += 9; // Only advance index if no error occurs

    return .{ .sec = sec, .usec = usec };
}

pub fn getUsec(index: *usize, buffer: []const u8) Error!Usec {
    if (index.* > buffer.len - 9) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .Usec) return error.TypeMismatch;
    const sec = std.mem.readInt(u64, read_from[1..9], .big);

    index.* += 9; // Only advance index if no error occurs

    return sec;
}

pub fn getU64(index: *usize, buffer: []const u8) Error!u64 {
    if (index.* > buffer.len - 9) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .Uint64) return error.TypeMismatch;
    const int = std.mem.readInt(u64, read_from[1..9], .big);

    index.* += 9; // Only advance index if no error occurs

    return int;
}

pub fn getS64(index: *usize, buffer: []const u8) Error!i64 {
    if (index.* > buffer.len - 9) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .Uint64) return error.TypeMismatch;
    const int = std.mem.readInt(i64, read_from[1..9], .big);

    index.* += 9; // Only advance index if no error occurs

    return int;
}

pub fn getChannelMap(index: *usize, buffer: []const u8) Error!ChannelMap {
    // NOTE: This type has a variable size, this first check is the
    // bare minimum size for it to be a valid value
    if (index.* > buffer.len - 2) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .ChannelMap) return error.TypeMismatch;
    const count = read_from[1];

    if (index.* > buffer.len - 2 - count) return error.OutOfSpace;

    var channel_map = ChannelMap{ .channels = count };

    for (0..count, read_from[2..][0..count]) |i, position| {
        channel_map.map[i] = @enumFromInt(position);
    }

    index.* += 2 + channel_map.channels * 4; // Only advance index if no error occurs

    return channel_map;
}

test getChannelMap {
    var buffer = [_]u8{0xAA} ** 256;
    var write_index: usize = 0;

    var channel_map_original = ChannelMap{
        .channels = 2,
    };
    channel_map_original.map[0] = .FrontLeft;
    channel_map_original.map[1] = .FrontRight;

    try putChannelMap(&write_index, &buffer, channel_map_original);

    var read_index: usize = 0;

    const channel_map = try getChannelMap(&read_index, &buffer);
    try std.testing.expectEqual(channel_map_original, channel_map);
}

pub fn getCVolume(index: *usize, buffer: []const u8) Error!CVolume {
    // NOTE: This type has a variable size, this first check is the
    // bare minimum size for it to be a valid value
    if (index.* > buffer.len - 2) return error.OutOfSpace;
    const read_from = buffer[index.*..];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .CVolume) return error.TypeMismatch;
    const count = read_from[1];

    if (index.* > buffer.len - 2 - (count * 4)) return error.OutOfSpace;

    var cvolume = CVolume{ .channels = count };

    for (0..count) |i| {
        cvolume.volumes[i] = @enumFromInt(std.mem.readInt(u32, read_from[2..][i * 4 ..][0..4], .big));
    }

    index.* += 2 + cvolume.channels * 4; // Only advance index if no error occurs

    return cvolume;
}

test getCVolume {
    var buffer = [_]u8{0xAA} ** 256;
    var write_index: usize = 0;

    var cvolume_original = CVolume{
        .channels = 2,
    };
    cvolume_original.volumes[0] = .Normal;
    cvolume_original.volumes[1] = Volume.from_dB(1.0);

    try putCVolume(&write_index, &buffer, cvolume_original);

    var read_index: usize = 0;

    const cvolume = try getCVolume(&read_index, &buffer);
    try std.testing.expectEqual(cvolume_original, cvolume);
}

pub fn getVolume(index: *usize, buffer: []const u8) Error!Volume {
    const size = 5;
    if (index.* > buffer.len - size) return error.OutOfSpace;
    const read_from = buffer[index.*..][0..size];

    const tag = try std.meta.intToEnum(Tag, read_from[0]);
    if (tag != .Volume) return error.TypeMismatch;
    const int = std.mem.readInt(u32, read_from[1..size], .big);

    index.* += size; // Only advance index if no error occurs

    return @enumFromInt(int);
}

test getVolume {
    var buffer = [_]u8{0xAA} ** 256;
    var write_index: usize = 0;

    try putVolume(&write_index, &buffer, Volume.Normal);
    try putVolume(&write_index, &buffer, Volume.Muted);
    try putVolume(&write_index, &buffer, Volume.Max);

    var read_index: usize = 0;

    const volume1 = try getVolume(&read_index, &buffer);
    try std.testing.expectEqual(Volume.Normal, volume1);

    const volume2 = try getVolume(&read_index, &buffer);
    try std.testing.expectEqual(Volume.Muted, volume2);

    const volume3 = try getVolume(&read_index, &buffer);
    try std.testing.expectEqual(Volume.Max, volume3);
}

pub fn getPropList(index: *usize, buffer: []const u8) Error!PropList {
    // TODO
    _ = index;
    _ = buffer;
}

pub fn getFormatInfo(index: *usize, buffer: []const u8) Error!FormatInfo {
    // TODO
    _ = index;
    _ = buffer;
}

// --- Data Types -------------------------------------------------------------
// ## Design Notes
//
// The data structures in this file are primarily to support the basic parsing
// functions. The intent is not necessarily to make it easy to manipulate the
// types, so if the types are tedious to use that is unfortunate, but expected.
// Higher level abstractions should be kept somewhere else.

pub const Error = error{
    OutOfSpace,
    InvalidEnumTag,
    TypeMismatch,
};

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
pub const MAX_CHANNELS = 32;
pub const ChannelMap = struct {
    channels: u8,
    map: [MAX_CHANNELS]Position = [_]Position{.Mono} ** MAX_CHANNELS,
    pub const Position = enum(u8) {
        Mono = 0,

        FrontLeft,
        FrontRight,
        FrontCenter,

        RearCenter,
        RearLeft,
        RearRight,

        Subwoofer,

        FrontLeftOfCenter,
        FrontRightOfCenter,

        SideLeft,
        SideRight,

        Aux1,
        Aux2,
        Aux3,
        Aux4,
        Aux5,
        Aux6,
        Aux7,
        Aux8,
        Aux9,
        Aux10,
        Aux11,
        Aux12,
        Aux13,
        Aux14,
        Aux15,
        Aux16,
        Aux17,
        Aux18,
        Aux19,
        Aux20,
        Aux21,
        Aux22,
        Aux23,
        Aux24,
        Aux25,
        Aux26,
        Aux27,
        Aux28,
        Aux29,
        Aux30,
        Aux31,

        TopCenter,

        TopFrontLeft,
        TopFrontRight,
        TopFrontCenter,

        TopRearLeft,
        TopRearRight,
        TopRearCenter,

        const LFE = Position.Subwoofer;
    };

    pub fn fromString(str: []const u8) ChannelMap {
        _ = str;
        @panic("unimplemented");
    }
};
pub const Volume = enum(u32) {
    /// Minimal valid volume (0%, -inf dB)
    Muted = 0,
    /// Normal volume (100%, 0 dB)
    Normal = normal,
    /// Maximum valid volume we can store
    Max = std.math.maxInt(u32) / 2,
    /// Recommended maximum value to show in user facing UIs.
    MaxUI = max_ui: {
        const linear = dB_to_linear(11.0);
        break :max_ui @intFromFloat(@round(std.math.cbrt(linear) * normal));
    },
    /// Special 'invalid' volume
    Invalid = std.math.maxInt(u32),
    _,

    const decibel_min_infinity = 0;
    const normal = 0x10_000;

    pub fn linear_to_dB(v: f64) f64 {
        return 20.0 * std.math.log10(v);
    }

    pub fn dB_to_linear(v: f64) f64 {
        return std.math.pow(f64, 10.0, v / 20.0);
    }

    pub fn from_linear(v: f64) Volume {
        if (v <= 0.0) return .Muted;
        // pulseaudio/volume.c mentions that cubic mapping is used here.
        return clamp(@enumFromInt(@as(u64, @intFromFloat(@round(std.math.cbrt(v) * normal)))));
    }

    pub fn from_dB(dB: f64) Volume {
        if (std.math.isInf(dB) or std.math.isNegativeInf(dB))
            return .Muted;

        return from_linear(dB_to_linear(dB));
    }

    pub fn clamp(volume: Volume) Volume {
        const vol = @intFromEnum(volume);
        const muted = @intFromEnum(Volume.Muted);
        const max = @intFromEnum(Volume.Max);
        return @enumFromInt(@max(muted, @min(vol, max)));
    }
};
pub const CVolume = struct {
    channels: u8,
    volumes: [MAX_CHANNELS]Volume = [_]Volume{@enumFromInt(0)} ** MAX_CHANNELS,

    pub fn eq(lhs: CVolume, rhs: CVolume) bool {
        if (lhs.channels != rhs.channels) return false;
        for (lhs.volumes[0..lhs.channels], rhs.volumes[0..rhs.channels]) |lv, rv| {
            if (lv != rv) return false;
        }
        return true;
    }
};
pub const Prop = struct { [:0]const u8, [:0]const u8 };
pub const PropList = []const Prop;
pub const FormatEncoding = enum {
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
pub const FormatInfo = struct {
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

// --- Includes and Constants -------------------------------------------------
const max_tag_size = (64 * 1024);

const std = @import("std");
const builtin = @import("builtin");
const Property = @import("properties.zig").Property;
