package sgui

import "core:fmt"
import "core:time"
import "core:math"
import "core:strings"
import "core:container/queue"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"
import su "sdl_utils"

SGUIOpts :: struct {
    // TODO
    // - text font
    // - button font
    // - theme (color, attributes, ...)
}

SGUI_DEFAULTS :: SGUIOpts{
    // TODO
    // - default font
    // - theme
}

SGUIHandle :: struct {
    run: bool,
    dt: f32,
    tick: time.Tick,
    window: ^sdl.Window,
    renderer: ^sdl.Renderer,
    font_cache: su.FontCache,
    text_engine: ^sdl_ttf.TextEngine,
    widget_event_queue: queue.Queue(WidgetEvent),
    event_handlers: EventHandlers,
    mouse_x, mouse_y: f32,
    // TODO: focused widget
    layers: [dynamic]Widget,
    current_layer: int,
    // TODO: priority queue of draw callbacks
    // TODO: theme -> color palette
    // procs
    draw_rect: proc(handle: ^SGUIHandle, rect: Rect, color: Color),
    add_layer: proc(handle: ^SGUIHandle, widget: Widget),
    switch_to_layer: proc(handle: ^SGUIHandle, layer_idx: int) -> bool,
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

WidgetEventTag :: u64
WidgetEvent :: struct {
    tag: WidgetEventTag,
    emitter: ^Widget,
    data: rawptr,
}
WidgetEventHandlerProc :: proc(dest: ^Widget, event: WidgetEvent, handle: ^SGUIHandle) -> bool

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
    widget_event: map[WidgetEventTag][dynamic]EventHandler(WidgetEventHandlerProc)
}

sgui_create :: proc() -> SGUIHandle { // TODO: allocator
    return SGUIHandle{
        draw_rect = sgui_draw_rect,
        add_layer = sgui_add_layer,
        switch_to_layer = sgui_switch_to_layer,
        layers = make([dynamic]Widget)
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
    queue.init(&handle.widget_event_queue)
    handle.run = true
    for &layer in handle.layers {
        widget_init(&layer, handle)
    }
}

sgui_terminate :: proc(handle: ^SGUIHandle) {
    sdl_ttf.DestroyRendererTextEngine(handle.text_engine)
    su.font_cache_destroy(&handle.font_cache)
    sdl_ttf.Quit()
    sdl.DestroyRenderer(handle.renderer)
    sdl.DestroyWindow(handle.window)
    sdl.Quit()
    // TODO: use an arena
    delete(handle.event_handlers.key)
    delete(handle.event_handlers.mouse_click)
    delete(handle.event_handlers.mouse_motion)
    delete(handle.event_handlers.mouse_wheel)
    for _, arr in handle.event_handlers.widget_event {
        delete(arr)
    }
    delete(handle.event_handlers.widget_event)
    queue.destroy(&handle.widget_event_queue)
    delete(handle.layers)
}

sgui_process_widget_events :: proc(handle: ^SGUIHandle) {
    // We reset the queue to avoid event to constantly append new event into it.
    // Here, if any handler emit a new event, it will be process during the
    // next iteration so that we never get stuck into an infit loop here.
    q := handle.widget_event_queue
    defer queue.destroy(&q)
    queue.init(&handle.widget_event_queue)

    for queue.len(q) > 0 {
        event := queue.dequeue(&q)
        for handler in handle.event_handlers.widget_event[event.tag] {
            handler.exec(handler.widget, event, handle)
        }
    }
}

sgui_process_events :: proc(handle: ^SGUIHandle) {
    sgui_process_widget_events(handle)

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
                if !handler.widget.disabled {
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
                if !handler.widget.disabled {
                    handler.exec(handler.widget, event.key.key, .Up, handle.event_handlers.mods)
                }
            }
        case .MOUSE_WHEEL:
            for handler in handle.event_handlers.mouse_wheel {
                if !handler.widget.disabled {
                    handler.exec(handler.widget, event.wheel.integer_x, event.wheel.integer_y,
                                 handle.event_handlers.mods)
                }
            }
        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
            for handler in handle.event_handlers.mouse_click {
                if !handler.widget.disabled {
                    handler.exec(handler.widget, event.button.button, event.button.down,
                                 event.button.clicks, event.button.x, event.button.y,
                                 handle.event_handlers.mods)
                }
            }
        case .MOUSE_MOTION:
            handle.mouse_x = event.motion.x
            handle.mouse_y = event.motion.y
            for handler in handle.event_handlers.mouse_motion {
                if !handler.widget.disabled {
                    handler.exec(handler.widget, event.motion.x, event.motion.y,
                                 event.motion.xrel, event.motion.yrel,
                                 handle.event_handlers.mods)
                }
            }
        }
    }
}

sgui_update :: proc(handle: ^SGUIHandle) {
    widget_update(handle, &handle.layers[handle.current_layer])
}

sgui_draw :: proc(handle: ^SGUIHandle) {
    // clear screen
    sdl.SetRenderDrawColor(handle.renderer, 0, 0, 0, 255)
    sdl.RenderClear(handle.renderer)
    widget_draw(handle, &handle.layers[handle.current_layer])

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

sgui_add_widget_event_handler :: proc(handle: ^SGUIHandle, widget: ^Widget, tag: WidgetEventTag, exec: WidgetEventHandlerProc) {
    if tag not_in handle.event_handlers.widget_event {
        handle.event_handlers.widget_event[tag] = make([dynamic]EventHandler(WidgetEventHandlerProc))
    }
    append(&handle.event_handlers.widget_event[tag], EventHandler(WidgetEventHandlerProc){exec, widget})
}

sgui_add_event_handler :: proc {
    sgui_add_key_event_handler,
    sgui_add_mouse_wheel_event_handler,
    sgui_add_mouse_click_event_handler,
    sgui_add_mouse_motion_event_handler,
    sgui_add_widget_event_handler,
}

sgui_emit :: proc(handle: ^SGUIHandle, tag: WidgetEventTag, emitter: ^Widget, data: rawptr = nil) {
    queue.enqueue(&handle.widget_event_queue, WidgetEvent{tag, emitter, data})
}

sgui_draw_rect :: proc(handle: ^SGUIHandle, rect: Rect, color: Color) {
    rect := rect
    sdl.SetRenderDrawColor(handle.renderer, color.r, color.g, color.b, color.a)
    sdl.RenderFillRect(handle.renderer, &rect)
}

sgui_add_layer :: proc(handle: ^SGUIHandle, widget: Widget) {
    append(&handle.layers, widget)
}

sgui_switch_to_layer :: proc(handle: ^SGUIHandle, layer_idx: int) -> bool {
    if layer_idx > len(handle.layers) {
        return false
    }
    handle.current_layer = layer_idx
    return true
}
