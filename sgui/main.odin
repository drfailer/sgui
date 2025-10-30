package sgui

import "core:fmt"
import "core:time"
import "core:math"
import "core:strings"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"

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
draw_data :: proc(handle: ^SGUIHandle, box: ^Widget, _: rawptr) {
    box_data := &box.data.(DrawBox)
    data_rect := Rect{
        x = 0,
        y = (box.h - box_data.zoom_lvl * DATA_BOX_HEIGHT) / 2. - box_data.scrollbox.vertical.position,
        w = box.w,
        h = box_data.zoom_lvl * DATA_BOX_HEIGHT,
    }

    if data_rect.y < 0 {
        data_rect.h += data_rect.y
        data_rect.y = 0
    }

    // compute the scale depending on the zoom level
    ttl_time := DATA[len(DATA) - 1].end - DATA[0].begin
    scaling_factor := box.w / cast(f32)ttl_time

    data_rect.x -= box_data.scrollbox.horizontal.position
    for data, idx in DATA {
        data_rect.w = box_data.zoom_lvl * scaling_factor * cast(f32)(data.end - data.begin)
        if data_rect.x < 0 {
            data_rect.w += data_rect.x
            data_rect.x = 0
        }
        draw_rounded_box(handle, box.x + data_rect.x, box.y + data_rect.y, data_rect.w, data_rect.h, 10, Color{255, 255 * cast(u8)(idx % 2), 255, 255})
        data_rect.x += data_rect.w

        if data_rect.x > box.w {
            break
        }
    }

}

update_data :: proc(handle: ^SGUIHandle, box: ^Widget, _: rawptr) -> ContentSize {
    ttl_time := DATA[len(DATA) - 1].end - DATA[0].begin
    scaling_factor := box.w / cast(f32)ttl_time
    box_data := &box.data.(DrawBox)
    return ContentSize{
        box_data.zoom_lvl * scaling_factor * cast(f32)ttl_time,
        box_data.zoom_lvl * DATA_BOX_HEIGHT,
    }
}

main :: proc() {
    handle := sgui_create()

    handle.widget =
        vertical_box(
            vertical_box(
                horizontal_box(
                    text("Top pannel", Color{255, 255, 255, 255}),
                    text("Top pannel", Color{255, 255, 255, 255}),
                    attr = BoxAttributes{
                        props = BoxProperties{.FitH, .FitW},
                        style = BoxStyle{background_color = Color{0, 100, 0, 255}},
                    }
                ),
                attr = BoxAttributes{
                    props = BoxProperties{.FitH, .AlignCenter},
                    style = BoxStyle{background_color = Color{0, 0, 255, 255}},
                }
            ),
            horizontal_box(
                horizontal_box(
                    text("Side Pannel", Color{255, 255, 255, 255}),
                    attr = BoxAttributes{
                        props = BoxProperties{.FitW, .AlignCenter},
                        style = BoxStyle{background_color = Color{255, 0, 0, 255}},
                    }
                ),
                draw_box(draw_data, update_data, props = DrawBoxProperties{.Zoomable, .WithScrollbar}),
            )
        )
    sgui_init(&handle)
    sgui_run(&handle)
    sgui_terminate(&handle)
}
