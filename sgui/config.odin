package sgui
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"

// config //////////////////////////////////////////////////////////////////////

FPS :: #config(FPS, 60)

FONT :: #config(FONT, "/usr/share/fonts/TTF/FiraGO-Regular.ttf")
FONT_SIZE :: #config(FONT_SIZE, 18)

WINDOW_WIDTH :: #config(WINDOW_WIDTH, 800)
WINDOW_HEIGHT :: #config(WINDOW_HEIGHT, 600)

// TODO
WINDOW_FLAGS :: sdl.WindowFlags{.RESIZABLE}
// WINDOW_FLAGS :: sdl.WindowFlags{}

SCROLLBAR_THICKNESS :: #config(SCROLLBAR_THICKNESS, 10)

// defaults ////////////////////////////////////////////////////////////////////

Opts :: struct {
    clear_color: Color,
    text_attr: TextAttributes,
    button_attr: ButtonAttributes,
    radio_button_attr: RadioButtonAttributes,
    scrollbox_attr: ScrollboxAttributes,
}

OPTS := Opts{
    clear_color = Color{0, 0, 0, 255},
    text_attr = TextAttributes{
        style = TextStyle{
            font = FONT,
            font_size = FONT_SIZE,
            color = Color{255, 255, 255, 255},
            wrap_width = 0,
        },
    },
    button_attr = ButtonAttributes{
        style = ButtonStyle{
            label_font_path = FONT,
            label_font_size = FONT_SIZE,
            padding = {2, 2, 2, 2},
            border_thickness = 1,
            corner_radius = 0,
            colors = [ButtonState]ButtonColors{
                .Idle = ButtonColors{
                    text = Color{0, 0, 0, 255},
                    border = Color{0, 0, 0, 255},
                    bg = Color{255, 255, 255, 255},
                },
                .Hovered = ButtonColors{
                    text = Color{0, 0, 0, 255},
                    border = Color{0, 0, 0, 255},
                    bg = Color{100, 100, 100, 255},
                },
                .Clicked = ButtonColors{
                    text = Color{255, 255, 255, 255},
                    border = Color{255, 255, 255, 255},
                    bg = Color{0, 0, 0, 255},
                },
            },
        },
    },
    radio_button_attr = RadioButtonAttributes{
        style = RadioButtonStyle{
            base_radius = 6,
            border_thickness = 1,
            dot_radius = 2,
            border_color = Color{0, 0, 0, 255},
            background_color = Color{255, 255, 255, 255},
            dot_color = Color{0, 0, 0, 255},
            label_padding = 10,
            label_color = Color{0, 0, 0, 255},
            font = FONT,
            font_size = FONT_SIZE,
        }
    },
    scrollbox_attr = ScrollboxAttributes{
        style = ScrollboxStyle{
            scrollbar_style = ScrollbarStyle{
                background_color = Color{50, 50, 50, 255},
                color = [ScrollbarState]Color{
                    .Idle = Color{100, 100, 100, 255},
                    .Hovered = Color{120, 120, 110, 255},
                    .Selected = Color{110, 110, 110, 255},
                },
            },
        },
    },
}
