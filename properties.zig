/// Tags copied from rust pulseaudio library: https://docs.rs/pulseaudio/latest/src/pulseaudio/protocol/serde/props.rs.html
pub const Property = enum {
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

    pub fn to_string(prop: Property) [:0]const u8 {
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
