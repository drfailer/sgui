package widgets

import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"
import ".."

// config //////////////////////////////////////////////////////////////////////

FONT :: #config(FONT, "/usr/share/fonts/TTF/FiraGO-Regular.ttf")
FONT_SIZE :: #config(FONT_SIZE, 18)

SCROLLBAR_THICKNESS :: #config(SCROLLBAR_THICKNESS, 12)

// defaults ////////////////////////////////////////////////////////////////////

Opts :: struct {
    text_attr: TextAttributes,
    button_attr: ButtonAttributes,
    radio_button_attr: RadioButtonAttributes,
    draw_box_attr: DrawBoxAttributes,
    scrollbars_attr: ScrollbarsAttributes,
}

OPTS := Opts{
    text_attr = TextAttributes{
        style = TextStyle{
            font = FONT,
            font_size = FONT_SIZE,
            color = sgui.Color{0, 0, 0, 255},
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
            colors = [sgui.WidgetMouseState]ButtonColors{
                .Idle = ButtonColors{
                    text = sgui.Color{0, 0, 0, 255},
                    border = sgui.Color{0, 0, 0, 255},
                    bg = sgui.Color{255, 255, 255, 255},
                },
                .Hovered = ButtonColors{
                    text = sgui.Color{0, 0, 0, 255},
                    border = sgui.Color{0, 0, 0, 255},
                    bg = sgui.Color{100, 100, 100, 255},
                },
                .Clicked = ButtonColors{
                    text = sgui.Color{255, 255, 255, 255},
                    border = sgui.Color{255, 255, 255, 255},
                    bg = sgui.Color{0, 0, 0, 255},
                },
            },
        },
    },
    radio_button_attr = RadioButtonAttributes{
        style = RadioButtonStyle{
            base_radius = 6,
            border_thickness = 1,
            dot_radius = 2,
            border_color = sgui.Color{0, 0, 0, 255},
            background_color = sgui.Color{255, 255, 255, 255},
            dot_color = sgui.Color{0, 0, 0, 255},
            label_padding = 10,
            label_color = sgui.Color{0, 0, 0, 255},
            font = FONT,
            font_size = FONT_SIZE,
        }
    },
    draw_box_attr = DrawBoxAttributes{
        props = DrawBoxProperties{.Zoomable, .WithScrollbar},
        zoom_min = 1, zoom_max = 100, zoom_step = 1,
    },
    scrollbars_attr = ScrollbarsAttributes{
        props = ScrollbarsProperties{},
        style = ScrollbarStyle{
            track_color = sgui.Color{50, 50, 50, 255},
            track_padding = Padding{0, 0, 0, 0},
            thumb_color = [sgui.WidgetMouseState]sgui.Color{
                .Idle = sgui.Color{100, 100, 100, 255},
                .Hovered = sgui.Color{120, 120, 110, 255},
                .Clicked = sgui.Color{110, 110, 110, 255},
            },
            button_color = [sgui.WidgetMouseState]sgui.Color{
                .Idle = sgui.Color{100, 100, 100, 255},
                .Hovered = sgui.Color{120, 120, 110, 255},
                .Clicked = sgui.Color{110, 110, 110, 255},
            },
        }
    },
}
