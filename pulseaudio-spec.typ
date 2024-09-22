
= PulseAudio Native Protocol

Notes on the format of the PulseAudio Native Protocol.

== Connection

Client connects to \$xdg_runtime_dir/pulse/native and sends the Auth command, including the clients protcol version and the contents of the \$HOME/.config/pulse/cookie file.

The server replies with a Reply command that contains a sequence number, and the negotiated protocol version.

== Packet

PulseAudio packets have a 20 byte header with the following layout:

- length: u32, specifies the size of the payload
- channel: u32, specifies the channel, std.math.maxInt(u32) has special meaning
- offset high: u32, TBD
- offset low: u32, TBD
- flags: u32, TBD

== TagStruct

TagStruct is the name of the undocumented POD format that PulseAudio uses for communication between the client and server.

=== Types

- u32
- arbitrary

== Commands

Command messages start with the following:

- Header
  - Channel is set to 0xFFFF_FFFF
- Payload
  - command id: u32
  - sequence: u32

Some commands lack any further payload, but most have more.

=== Error

Sent when something has gone wrong.

- error: u32, error code indicating what has gone wrong

=== Auth

- version: u32, the version of the pulseaudio protocol the client intends to use
- cookie: arbitrary, contents of \$HOME/.config/pulse/cookie

=== SetClientName

- properties: property list
