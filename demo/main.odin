package demo

import "core:fmt"
import "core:time"
import "core:math"
import "core:strings"
import "core:mem"
import "core:log"
import "../sgui"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"

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

draw_data :: proc(ui: ^sgui.Ui, box_widget: ^sgui.Widget, _: rawptr) {
    box := cast(^sgui.DrawBox)box_widget
    data_rect := sgui.Rect{
        x = -box.scrollbars.horizontal.position,
        y = (box.h - box.zoombox.lvl * DATA_BOX_HEIGHT) / 2. - box.scrollbars.vertical.position,
        w = box.w,
        h = box.zoombox.lvl * DATA_BOX_HEIGHT,
    }

    if data_rect.y < 0 {
        data_rect.h += data_rect.y
        data_rect.y = 0
    }

    sgui.draw_line(ui, 0, 0, 200, 100, sgui.Color{255, 255, 255, 255})
    sgui.draw_line(ui, 0, 0, 200, 300, sgui.Color{255, 255, 255, 255})
    sgui.draw_line(ui, 0, 0, 100, 300, sgui.Color{255, 255, 255, 255})

    // compute the scale depending on the zoom level
    ttl_time := DATA[len(DATA) - 1].end - DATA[0].begin
    scaling_factor := box.zoombox.lvl * MS_TO_PIXEL

    for data, idx in DATA {
        data_rect.w = scaling_factor * cast(f32)(data.end - data.begin)
        sgui.draw_rounded_box(ui, data_rect.x, data_rect.y,
            data_rect.w, data_rect.h, box.zoombox.lvl * 20, sgui.Color{255, 255 * cast(u8)(idx % 2), 255, 255})
        sgui.draw_rounded_box(ui, data_rect.x + 1, data_rect.y + 1,
            data_rect.w - 2, data_rect.h - 2, box.zoombox.lvl * 20, sgui.Color{100, 100 * cast(u8)(idx % 2), 100, 255})
        data_rect.x += data_rect.w

        if data_rect.x > box.w {
            break
        }
    }

    sgui.draw_rounded_frame(ui, 400, 400, 100, 100, 20, sgui.Color{255, 255, 255, 255})
}

update_data :: proc(ui: ^sgui.Ui, box_widget: ^sgui.Widget, _: rawptr) -> sgui.ContentSize {
    ttl_time := DATA[len(DATA) - 1].end - DATA[0].begin
    box := cast(^sgui.DrawBox)box_widget
    return sgui.ContentSize{
        box.zoombox.lvl * MS_TO_PIXEL * cast(f32)ttl_time,
        box.zoombox.lvl * DATA_BOX_HEIGHT,
    }
}

side_pannel_widget :: proc() -> (widget: ^sgui.Widget) {
    using sgui
    widget = hbox(
        vbox(
            text("Side Pannel"),
            button("hellope", proc(ui: ^sgui.Ui, _: rawptr) { fmt.println("clicked!!!") }),
            button("clickme", proc(ui: ^sgui.Ui, _: rawptr) { fmt.println("clicked!!!") }),
            button("clickme", proc(ui: ^sgui.Ui, _: rawptr) { fmt.println("clicked!!!") }),
            button("clickme", proc(ui: ^sgui.Ui, _: rawptr) { fmt.println("clicked!!!") }),
            radio_button("radio button"),
            attr = {
                props = {.FitH, .FitW},
                style = {
                    items_spacing = 10,
                },
            }
        ),
        attr = {
            props = {.FitW},
            style = {
                background_color = {255, 0, 0, 255},
                padding = {10, 10, 10, 20},
                border_thickness = 2,
                active_borders = {.Right},
                border_color = {200, 200, 0, 255},
            },
        }
    )
    return widget
}

main_layer :: proc(ui: ^sgui.Ui) -> ^sgui.Widget {
    using sgui
    menu_btn := icon_button(IconData{file = "img/menu-icon.png"},
        clicked = proc(ui: ^Ui, _: rawptr) {
            widget_toggle(ui->widget("side_pannel"), ui)
        },
        w = 20,
        h = 20,
        attr = {
            style = {
                padding = {4, 4, 4, 4},
                corner_radius = 5,
                colors = OPTS.button_attr.style.colors,
            },
        }
    )
    title := hbox(
        text("Demo App"),
        attr = {
            props = {.FitH, .FitW},
            style = {
                background_color = {0, 100, 0, 255},
            },
        }
    )
    header := hbox(
        left(menu_btn),
        center(title),
        attr = {
            props = {.FitH},
            style = {
                background_color = {0, 0, 255, 255},
                border_thickness = 2,
                active_borders = {.Bottom},
                border_color = {0, 200, 200, 255},
                padding = { 10, 10, 10, 10 },
            },
        },
        z_index = 1, // draw after to allow scrolling in the menu pannel
    )
    side_pannel := side_pannel_widget()
    ui->store("side_pannel", side_pannel)
    content := hbox(
        side_pannel,
        // the draw box is at the end: since it is resizable, all the other parts needs to be align first
        draw_box(draw_data, update_data, attr = {
            props = {.Zoomable, .WithScrollbar},
            zoom_min = 1.,
            zoom_max = 10.,
            zoom_step = 0.2,
            scrollbars_attr = OPTS.scrollbars_attr,
        }),
        attr = BoxAttributes{
            props = {},
            style = {
                background_color = {10, 10, 10, 255},
            },
        }
    )
    footer := align_widgets(
        vbox(
            center(text("footer")),
            attr = {
                props = {.FitH},
                style = {
                    background_color = {0, 100, 100, 255},
                    items_spacing = 10,
                    padding = { 4, 4, 4, 4 },
                },
            }
        ),
        {.Bottom, .HCenter}
    )
    return vbox(
        header,
        content,
        footer,
    )
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)

    sgui.init()
    {
        ui := sgui.create()
        defer sgui.destroy(ui)

        sgui.add_layer(ui, sgui.make_widget(ui, main_layer))
        sgui.run(ui)
    }
    sgui.fini()
}
