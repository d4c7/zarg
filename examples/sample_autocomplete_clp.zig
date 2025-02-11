const zarg = @import("zarg");
const builtin = @import("builtin");
const option = zarg.option;
const options = zarg.options;
const flag = zarg.flag;
const help = zarg.help;
const positional = zarg.positional;
const positionals = zarg.positionals;

pub const ColorEnum = enum {
    red,
    green,
    gray,
    blue,
    yellow,
    orange,
};
const parsers = zarg.Parsers.List ++ [_]zarg.Parsers.Parser{ //
    zarg.Parsers.enumParser("COLOR", ColorEnum, null),
};

pub const clp = zarg.CommandLineParser.init(.{
    .parsers = &parsers,
    .params = &([_]zarg.Param{
        positional(.{
            .name = "string",
            .parser = "FILE",
            .help = "Any string.",
        }),
        help(.{ //
            .long = "help",
            .short = "h",
            .help = "Shows this help.",
        }),
        option(.{ //
            .long = "option1",
            .short = "o",
            .parser = "STR",
            .default = "1",
            .help = "Any option 1.",
        }),
        option(.{ //
            .long = "option1-a",
            .short = "x",
            .parser = "STR",
            .default = "1",
            .help = "Any option x.",
        }),
        flag(.{ //
            .long = "option1-b",
            .short = "y",
            .help = "Any option y.",
        }),
        option(.{ //
            .long = "option2",
            .short = "q",
            .parser = "DIR",
            .default = "1",
            .help = "Any option 2.",
        }),
        flag(.{ //
            .long = "option_flag",
            .help = "Any option Flag.",
        }),
        option(.{ //
            .long = "color",
            .short = "C",
            .parser = "COLOR",
            .default = "red",
            .help = "A color",
        }),
    }),
});
