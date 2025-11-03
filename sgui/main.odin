package sgui

import "core:fmt"
import "core:time"
import "core:math"
import "core:strings"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"

// TODO: move this elsewhere and add #config
// TODO: most of this should also appear in the opts

FONT :: "/usr/share/fonts/TTF/FiraGO-Regular.ttf"
FONT_SIZE :: 18

WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600
// WINDOW_FLAGS :: sdl.WindowFlags{.RESIZABLE}
WINDOW_FLAGS :: sdl.WindowFlags{}
FPS :: 60

SCROLLBAR_THICKNESS :: 10

// using: PixelFormat.RGBA32
// Pixel :: [4]u8 // p.r, p.g, p.b, p.a
//
// CreateSurface        :: proc(width, height: c.int, format: PixelFormat) -> ^Surface ---
//
// GetWindowPixelFormat :: proc(window: ^Window) -> PixelFormat ---
// CreateSurfaceFrom    :: proc(width, height: c.int, format: PixelFormat, pixels: rawptr, pitch: c.int) -> ^Surface ---
//
// FillSurfaceRect      :: proc(dst: ^Surface, rect: Maybe(^Rect), color: Uint32) -> bool ---
// FillSurfaceRects     :: proc(dst: ^Surface, rects: [^]Rect, count: c.int, color: Uint32) -> bool ---
//
// CreateTexture :: proc(renderer: ^Renderer, format: PixelFormat, access: TextureAccess, w, h: c.int) -> ^Texture ---
// SetRenderTarget :: proc(renderer: ^Renderer, texture: Maybe(^Texture)) -> bool ---

MeasuredTime :: struct { begin, end: u32 }
DATA :: [?]MeasuredTime{
    MeasuredTime{0, 250},
    MeasuredTime{250, 600},
    MeasuredTime{600, 800},
    MeasuredTime{800, 1400},
}

DATA_BOX_HEIGHT :: 100
MS_TO_PIXEL :: 1

draw_data :: proc(handle: ^Handle, box: ^Widget, _: rawptr) {
    box_data := &box.data.(DrawBox)
    data_rect := Rect{
        x = -box_data.scrollbox.horizontal.position,
        y = (box.h - box_data.zoombox.lvl * DATA_BOX_HEIGHT) / 2. - box_data.scrollbox.vertical.position,
        w = box.w,
        h = box_data.zoombox.lvl * DATA_BOX_HEIGHT,
    }

    if data_rect.y < 0 {
        data_rect.h += data_rect.y
        data_rect.y = 0
    }

    // compute the scale depending on the zoom level
    ttl_time := DATA[len(DATA) - 1].end - DATA[0].begin
    scaling_factor := box_data.zoombox.lvl * MS_TO_PIXEL

    for data, idx in DATA {
        data_rect.w = scaling_factor * cast(f32)(data.end - data.begin)
        draw_rounded_box(handle, data_rect.x, data_rect.y,
            data_rect.w, data_rect.h, box_data.zoombox.lvl * 20, Color{255, 255 * cast(u8)(idx % 2), 255, 255})
        draw_rounded_box(handle, data_rect.x + 1, data_rect.y + 1,
            data_rect.w - 2, data_rect.h - 2, box_data.zoombox.lvl * 20, Color{100, 100 * cast(u8)(idx % 2), 100, 255})
        data_rect.x += data_rect.w

        if data_rect.x > box.w {
            break
        }
    }
}

update_data :: proc(handle: ^Handle, box: ^Widget, _: rawptr) -> ContentSize {
    ttl_time := DATA[len(DATA) - 1].end - DATA[0].begin
    box_data := &box.data.(DrawBox)
    return ContentSize{
        box_data.zoombox.lvl * MS_TO_PIXEL * cast(f32)ttl_time,
        box_data.zoombox.lvl * DATA_BOX_HEIGHT,
    }
}

main :: proc() {
    handle := create()

    handle->add_layer(
        vbox(
            vbox(
                hbox(
                    text("Top pannel"),
                    text("Top pannel"),
                    attr = BoxAttributes{
                        props = BoxProperties{.FitH, .FitW},
                        style = BoxStyle{
                            background_color = Color{0, 100, 0, 255},
                            items_spacing = 10,
                            padding = Padding{ 10, 10, 10, 10 },
                        },
                    }
                ),
                attr = BoxAttributes{
                    props = BoxProperties{.FitH, .AlignCenter},
                    style = BoxStyle{
                        background_color = Color{0, 0, 255, 255},
                        border_thickness = 2,
                        active_borders = ActiveBorders{.Bottom},
                        border_color = Color{0, 200, 200, 255},
                    },
                }
            ),
            hbox(
                hbox(
                    vbox(
                        text("Side Pannel",
                            attr = TextAttributes{
                                style = TextStyle{
                                    font = FONT,
                                    font_size = FONT_SIZE,
                                    color = Color{0, 0, 0, 255},
                                },
                            }),
                        button("hellope", proc(_: rawptr) { fmt.println("clicked!!!") }),
                        attr = BoxAttributes{
                            props = BoxProperties{.FitH, .FitW, .AlignCenter},
                            style = BoxStyle{
                                items_spacing = 10,
                            },
                        }
                    ),
                    attr = BoxAttributes{
                        props = BoxProperties{.FitW, .AlignCenter},
                        style = BoxStyle{
                            background_color = Color{255, 0, 0, 255},
                            padding = Padding{ 10, 10, 10, 10 },
                            border_thickness = 2,
                            active_borders = ActiveBorders{.Right},
                            border_color = Color{200, 200, 0, 255},
                        },
                    }
                ),
                draw_box(draw_data, update_data, props = DrawBoxProperties{.Zoomable, .WithScrollbar}),
            )
        )
    )
    init(&handle)
    run(&handle)
    terminate(&handle)
}
