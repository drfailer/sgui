package sgui

import "core:fmt"
import "core:time"
import "core:math"
import "core:strings"
import "core:container/queue"
import "core:container/priority_queue"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"
import su "sdl_utils"

Opts :: struct {
    clear_color: Color,
    text_attr: TextAttributes,
    button_attr: ButtonAttributes,
}

// TODO: add a #config for some variables
// TODO: we should have different attributes depending on the type of text (Header, ...)

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
}

Handle :: struct {
    run: bool,

    /* fps variables */
    dt: f32,
    tick: time.Tick,

    /* sdl */
    window: ^sdl.Window,
    renderer: ^sdl.Renderer,
    font_cache: su.FontCache,
    text_engine: ^sdl_ttf.TextEngine,
    mouse_x, mouse_y: f32,

    /* event handlers */
    event_handlers: EventHandlers,
    widget_event_queue: queue.Queue(WidgetEvent),

    // TODO: focused widget

    /* layers */
    layers: [dynamic]Widget,
    current_layer: int,

    /* draw ordering (when widget.z_index > 0, it is added to the queue) */
    ordered_draws: priority_queue.Priority_Queue(OrderedDraw),
    processing_ordered_draws: bool,

    /* procs */

    // TODO: make_widget() // allocate a widget using internal allocator

    /** layers **/
    add_layer: proc(handle: ^Handle, widget: Widget),
    switch_to_layer: proc(handle: ^Handle, layer_idx: int) -> bool,

    /** events handlers **/
    key_handler: proc(handle: ^Handle, widget: ^Widget, exec: KeyEventHandlerProc),
    scroll_handler: proc(handle: ^Handle, widget: ^Widget, exec: MouseWheelEventHandlerProc),
    click_handler: proc(handle: ^Handle, widget: ^Widget, exec: MouseClickEventHandlerProc),
    mouse_move_handler: proc(handle: ^Handle, widget: ^Widget, exec: MouseMotionEventHandlerProc),
    widget_event_handler: proc(handle: ^Handle, widget: ^Widget, emitter: ^Widget, tag: WidgetEventTag, exec: WidgetEventHandlerProc, exec_data: rawptr),

    /** draw **/
    draw_rect: proc(handle: ^Handle, x, y, w, h: f32, color: Color),
    draw_text: proc(handle: ^Handle, text: ^su.Text, x, y: f32),
    rel_rect: Rect,
}

OrderedDraw :: struct {
    priority: u64,
    widget: ^Widget,
    draw_proc: proc(handle: ^Handle, draw_data: rawptr),
    draw_data: rawptr,
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
WidgetEventHandlerProc :: proc(dest: ^Widget, data: rawptr, event: WidgetEvent, handle: ^Handle) -> bool
WidgetEventHandler :: struct {
    widget: ^Widget,
    emitter: ^Widget,
    exec: WidgetEventHandlerProc,
    exec_data: rawptr
}

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
    widget_event: map[WidgetEventTag][dynamic]WidgetEventHandler
}

create :: proc() -> Handle { // TODO: allocator
    return Handle{
        layers = make([dynamic]Widget),
        draw_rect = draw_rect,
        draw_text = draw_text,
        add_layer = add_layer,
        switch_to_layer = switch_to_layer,
        key_handler = add_key_event_handler,
        scroll_handler = add_mouse_wheel_event_handler,
        click_handler = add_mouse_click_event_handler,
        mouse_move_handler = add_mouse_motion_event_handler,
        widget_event_handler = add_widget_event_handler,
    }
}

init :: proc(handle: ^Handle) {
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

    sdl.SetRenderDrawBlendMode(handle.renderer, sdl.BLENDMODE_BLEND)

    handle.font_cache = su.font_cache_create()
    queue.init(&handle.widget_event_queue)
    priority_queue.init(
        &handle.ordered_draws,
        less = proc(a, b: OrderedDraw) -> bool {
            // it is a widget priority, not a draw priority, which means that
            // widgets with higher priority should be drawn last
            return a.priority > b.priority
        },
        swap = proc(q: []OrderedDraw, i, j: int) {
            tmp := q[i]
            q[i] = q[j]
            q[j] = tmp
        }
    )
    handle.run = true
    for &layer in handle.layers {
        widget_init(&layer, handle)
    }
}

terminate :: proc(handle: ^Handle) {
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
    priority_queue.destroy(&handle.ordered_draws)
    delete(handle.layers)
}

process_widget_events :: proc(handle: ^Handle) {
    // We reset the queue to avoid event to constantly append new event into it.
    // Here, if any handler emit a new event, it will be process during the
    // next iteration so that we never get stuck into an infit loop here.
    q := handle.widget_event_queue
    defer queue.destroy(&q)
    queue.init(&handle.widget_event_queue)

    for queue.len(q) > 0 {
        event := queue.dequeue(&q)
        for handler in handle.event_handlers.widget_event[event.tag] {
            if handler.emitter == nil || handler.emitter == event.emitter {
                handler.exec(handler.widget, handler.exec_data, event, handle)
            }
        }
    }
}

process_events :: proc(handle: ^Handle) {
    process_widget_events(handle)

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

update :: proc(handle: ^Handle) {
    w, h: i32
    assert(sdl.GetWindowSize(handle.window, &w, &h));
    handle.rel_rect = Rect{0, 0, cast(f32)w, cast(f32)h}
    widget_update(handle, &handle.layers[handle.current_layer])
}

draw :: proc(handle: ^Handle) {
    clear_color := OPTS.clear_color
    sdl.SetRenderDrawColor(handle.renderer, clear_color.r, clear_color.g, clear_color.b, clear_color.a)
    sdl.RenderClear(handle.renderer)
    widget_draw(&handle.layers[handle.current_layer], handle)
    handle.processing_ordered_draws = true
    for priority_queue.len(handle.ordered_draws) > 0 {
        od := priority_queue.pop(&handle.ordered_draws)
        if od.draw_proc == nil {
            od.widget->draw(handle)
        } else {
            od.draw_proc(handle, od.draw_data)
        }
    }
    handle.processing_ordered_draws = false
}

run :: proc(handle: ^Handle) {
    for handle.run {
        handle.dt = cast(f32)time.duration_seconds(time.tick_lap_time(&handle.tick))

        process_events(handle)
        update(handle)
        draw(handle)

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

add_key_event_handler :: proc(handle: ^Handle, widget: ^Widget, exec: KeyEventHandlerProc) {
    append(&handle.event_handlers.key, EventHandler(KeyEventHandlerProc){exec, widget})
}

add_mouse_wheel_event_handler :: proc(handle: ^Handle, widget: ^Widget, exec: MouseWheelEventHandlerProc) {
    append(&handle.event_handlers.mouse_wheel, EventHandler(MouseWheelEventHandlerProc){exec, widget})
}

add_mouse_click_event_handler :: proc(handle: ^Handle, widget: ^Widget, exec: MouseClickEventHandlerProc) {
    append(&handle.event_handlers.mouse_click, EventHandler(MouseClickEventHandlerProc){exec, widget})
}

add_mouse_motion_event_handler :: proc(handle: ^Handle, widget: ^Widget, exec: MouseMotionEventHandlerProc) {
    append(&handle.event_handlers.mouse_motion, EventHandler(MouseMotionEventHandlerProc){exec, widget})
}

add_widget_event_handler :: proc(
    handle: ^Handle,
    widget: ^Widget,
    emitter: ^Widget,
    tag: WidgetEventTag,
    exec: WidgetEventHandlerProc,
    exec_data: rawptr = nil
) {
    if tag not_in handle.event_handlers.widget_event {
        handle.event_handlers.widget_event[tag] = make([dynamic]WidgetEventHandler)
    }
    append(&handle.event_handlers.widget_event[tag], WidgetEventHandler{
        widget = widget,
        emitter = emitter,
        exec = exec,
        exec_data = exec_data,
    })
}

add_event_handler :: proc {
    add_key_event_handler,
    add_mouse_wheel_event_handler,
    add_mouse_click_event_handler,
    add_mouse_motion_event_handler,
    add_widget_event_handler,
}

emit :: proc(handle: ^Handle, tag: WidgetEventTag, emitter: ^Widget, data: rawptr = nil) {
    queue.enqueue(&handle.widget_event_queue, WidgetEvent{tag, emitter, data})
}

draw_rect :: proc(handle: ^Handle, x, y, w, h: f32, color: Color) {
    sdl.SetRenderDrawColor(handle.renderer, color.r, color.g, color.b, color.a)
    sx := clamp(x, 0, handle.rel_rect.w)
    sy := clamp(y, 0, handle.rel_rect.h)
    sw := max(0, w - abs(sx - abs(x)))
    sh := max(0, h - abs(sy - abs(y)))
    sdl.RenderFillRect(handle.renderer, &Rect{sx + handle.rel_rect.x, sy + handle.rel_rect.y, sw, sh})
}

draw_text :: proc(handle: ^Handle, text: ^su.Text, x, y: f32) {
    su.text_draw(text, x + handle.rel_rect.x, y + handle.rel_rect.y)
}

mouse_on_region :: proc(handle: ^Handle, x, y, w, h: f32) -> bool {
    x := x + handle.rel_rect.x
    y := y + handle.rel_rect.y
    return x <= handle.mouse_x && handle.mouse_x <= (x + w) \
        && y <= handle.mouse_y && handle.mouse_y <= (y + h)
}

add_layer :: proc(handle: ^Handle, widget: Widget) {
    append(&handle.layers, widget)
}

switch_to_layer :: proc(handle: ^Handle, layer_idx: int) -> bool {
    if layer_idx > len(handle.layers) {
        return false
    }
    handle.current_layer = layer_idx
    return true
}

add_widget_ordered_draw :: proc(handle: ^Handle, widget: ^Widget) {
    priority_queue.push(&handle.ordered_draws, OrderedDraw{
        priority = widget.z_index,
        widget = widget,
    })
}

add_proc_ordered_draw :: proc(
    handle: ^Handle,
    priority: u64,
    draw_proc: proc(handel: ^Handle, draw_data: rawptr),
    draw_data: rawptr = nil
) {
    priority_queue.push(&handle.ordered_draws, OrderedDraw{
        priority = priority,
        draw_proc = draw_proc,
        draw_data = draw_data,
    })
}

add_ordered_draw :: proc{
    add_widget_ordered_draw,
    add_proc_ordered_draw,
}
