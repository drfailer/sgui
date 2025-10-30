package sgui

import "core:fmt"
import "core:time"
import "core:math"
import "core:strings"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"
import su "sdl_utils"

SGUIHandle :: struct {
    run: bool,
    dt: f32,
    tick: time.Tick,
    window: ^sdl.Window,
    renderer: ^sdl.Renderer,
    font_cache: su.FontCache,
    text_engine: ^sdl_ttf.TextEngine,
    event_handlers: EventHandlers,
    mouse_x, mouse_y: f32,
    // TODO: focused widget
    widget: Widget, // TODO: we should have a list of widgets here in case there are multple independent menus
    // TODO: theme -> color palette
    // procs
    draw_rect: proc(handle: ^SGUIHandle, rect: Rect, color: Color),
}

Rect :: sdl.FRect

Event :: sdl.Event
EventType :: sdl.EventType
Keycode :: sdl.Keycode

KeyEventType :: enum { Up, Down }
KeyMod :: enum { Control, Alt, Shift }

KeyEventHandlerProc :: proc(self: ^Widget, key: Keycode, type: KeyEventType, mods: bit_set[KeyMod]) -> bool
MouseClickEventHandlerProc :: proc(self: ^Widget, button: u8, down: bool, click_count: u8, x, y: f32, mods: bit_set[KeyMod]) -> bool
MouseMotionEventHandlerProc :: proc(self: ^Widget, x, y, xd, yd: f32, mods: bit_set[KeyMod]) -> bool
MouseWheelEventHandlerProc :: proc(self: ^Widget, x, y: i32, mods: bit_set[KeyMod]) -> bool

// TODO: implement a Qt like signal system so that widgets can communicate
// - Signal
// - Signal Handler
// - Listener list
// - signal queue (all signal sent durint the step)
WidgetEvent :: struct {
    emitter: ^Widget,
    data: rawptr, // TODO
}
WidgetEventHandlerProc :: proc(dest: ^Widget, event: WidgetEvent) -> bool

Color :: distinct [4]u8

EventHandler :: struct($P: typeid) {
    exec: P,
    widget: ^Widget,
}

EventHandlers :: struct {
    mods: bit_set[KeyMod],
    key: [dynamic]EventHandler(KeyEventHandlerProc),
    mouse_click: [dynamic]EventHandler(MouseClickEventHandlerProc), // TODO: use a more efficent data stucture?
    mouse_motion: [dynamic]EventHandler(MouseMotionEventHandlerProc), // TODO: use a more efficent data stucture?
    mouse_wheel: [dynamic]EventHandler(MouseWheelEventHandlerProc),
}

sgui_create :: proc() -> SGUIHandle {
    return SGUIHandle{
        draw_rect = sgui_draw_rect,
    }
}

sgui_init :: proc(handle: ^SGUIHandle) {
    if !sdl.Init(sdl.InitFlags{.VIDEO, .EVENTS}) {
        fmt.printfln("error: {}", sdl.GetError())
        return
    }

    if !sdl.CreateWindowAndRenderer("Hello window", WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_FLAGS, &handle.window, &handle.renderer) {
        fmt.printfln("error: {}", sdl.GetError())
        return
    }

    if !sdl_ttf.Init() {
        fmt.printfln("error: couldn't init sdl_ttf.")
        return
    }

    handle.text_engine = sdl_ttf.CreateRendererTextEngine(handle.renderer)
    if handle.text_engine == nil {
        fmt.printfln("error: couldn't create text engine.")
        return
    }

    handle.font_cache = su.font_cache_create()
    handle.run = true
    widget_init(&handle.widget, handle)
}

sgui_terminate :: proc(handle: ^SGUIHandle) {
    sdl_ttf.DestroyRendererTextEngine(handle.text_engine)
    su.font_cache_destroy(&handle.font_cache)
    sdl_ttf.Quit()
    sdl.DestroyRenderer(handle.renderer)
    sdl.DestroyWindow(handle.window)
    sdl.Quit()
}

// TODO: since we are not dealing with a game here, it might be nice to redraw
// only when an event has been triggered. -> this function should return a bool
// and the handlers will return true when a redraw is required.
sgui_process_events :: proc(handle: ^SGUIHandle) {
    event: sdl.Event
    for sdl.PollEvent(&event) {
        #partial switch event.type {
        case .QUIT:
            handle.run = false
        case .KEY_DOWN:
            if event.key.key == sdl.K_LCTRL || event.key.key == sdl.K_RCTRL {
                handle.event_handlers.mods |= { .Control }
            } else if event.key.key == sdl.K_LALT || event.key.key == sdl.K_RALT {
                handle.event_handlers.mods |= { .Alt }
            } else if event.key.key == sdl.K_LSHIFT || event.key.key == sdl.K_RSHIFT {
                handle.event_handlers.mods |= { .Shift }
            }
            for handler in handle.event_handlers.key {
                if handler.widget.enabled {
                    handler.exec(handler.widget, event.key.key, .Down, handle.event_handlers.mods)
                }
            }
        case .KEY_UP:
            if event.key.key == sdl.K_LCTRL || event.key.key == sdl.K_RCTRL {
                handle.event_handlers.mods ~= { .Control }
            } else if event.key.key == sdl.K_LALT || event.key.key == sdl.K_RALT {
                handle.event_handlers.mods ~= { .Alt }
            } else if event.key.key == sdl.K_LSHIFT || event.key.key == sdl.K_RSHIFT {
                handle.event_handlers.mods ~= { .Shift }
            }
            for handler in handle.event_handlers.key {
                if handler.widget.enabled {
                    handler.exec(handler.widget, event.key.key, .Up, handle.event_handlers.mods)
                }
            }
        case .MOUSE_WHEEL:
            for handler in handle.event_handlers.mouse_wheel {
                if handler.widget.enabled {
                    handler.exec(handler.widget, event.wheel.integer_x, event.wheel.integer_y,
                                 handle.event_handlers.mods)
                }
            }
        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
            for handler in handle.event_handlers.mouse_click {
                if handler.widget.enabled {
                    handler.exec(handler.widget, event.button.button, event.button.down,
                                 event.button.clicks, event.button.x, event.button.y,
                                 handle.event_handlers.mods)
                }
            }
        case .MOUSE_MOTION:
            handle.mouse_x = event.motion.x
            handle.mouse_y = event.motion.y
            for handler in handle.event_handlers.mouse_motion {
                if handler.widget.enabled {
                    handler.exec(handler.widget, event.motion.x, event.motion.y,
                                 event.motion.xrel, event.motion.yrel,
                                 handle.event_handlers.mods)
                }
            }
        }
    }
}

sgui_update :: proc(handle: ^SGUIHandle) {
    widget_update(handle, &handle.widget)
}

sgui_draw :: proc(handle: ^SGUIHandle) {
    // clear screen
    sdl.SetRenderDrawColor(handle.renderer, 0, 0, 0, 255)
    sdl.RenderClear(handle.renderer)
    widget_draw(handle, &handle.widget)

    // draw_circle(handle, 100, 100, 50, Color{255, 255, 255, 255})
    // draw_rounded_box(handle, 100, 200, 100, 40, 10, Color{255, 255, 255, 255})
}

sgui_run :: proc(handle: ^SGUIHandle) {
    for handle.run {
        handle.dt = cast(f32)time.duration_seconds(time.tick_lap_time(&handle.tick))

        sgui_process_events(handle)
        sgui_update(handle)
        sgui_draw(handle)

        // draw fps text
        // TODO: optimize this v
        // fps_text := su.text_create(handle.text_engine, handle.font, "? FPS")
        // defer su.text_destroy(&fps_text)
        // fps_text_string := fmt.aprintf("%.1f FPS", 1./handle.dt, allocator = context.temp_allocator)
        // su.text_update_and_draw(&fps_text, fps_text_string, 0, 0, sdl.Color{0, 255, 0, 255})

        // present
        sdl.RenderPresent(handle.renderer)

        free_all(context.temp_allocator)

        // sleep to match the FPS
        time.sleep(1_000_000_000 / FPS - time.tick_since(handle.tick))
    }
}

sgui_add_key_event_handler :: proc(handle: ^SGUIHandle, widget: ^Widget, exec: KeyEventHandlerProc) {
    append(&handle.event_handlers.key, EventHandler(KeyEventHandlerProc){exec, widget})
}

sgui_add_mouse_wheel_event_handler :: proc(handle: ^SGUIHandle, widget: ^Widget, exec: MouseWheelEventHandlerProc) {
    append(&handle.event_handlers.mouse_wheel, EventHandler(MouseWheelEventHandlerProc){exec, widget})
}

sgui_add_mouse_click_event_handler :: proc(handle: ^SGUIHandle, widget: ^Widget, exec: MouseClickEventHandlerProc) {
    append(&handle.event_handlers.mouse_click, EventHandler(MouseClickEventHandlerProc){exec, widget})
}

sgui_add_mouse_motion_event_handler :: proc(handle: ^SGUIHandle, widget: ^Widget, exec: MouseMotionEventHandlerProc) {
    append(&handle.event_handlers.mouse_motion, EventHandler(MouseMotionEventHandlerProc){exec, widget})
}

sgui_add_event_handler :: proc {
    sgui_add_key_event_handler,
    sgui_add_mouse_wheel_event_handler,
    sgui_add_mouse_click_event_handler,
    sgui_add_mouse_motion_event_handler,
}

sgui_draw_rect :: proc(handle: ^SGUIHandle, rect: Rect, color: Color) {
    rect := rect
    sdl.SetRenderDrawColor(handle.renderer, color.r, color.g, color.b, color.a)
    sdl.RenderFillRect(handle.renderer, &rect)
}
