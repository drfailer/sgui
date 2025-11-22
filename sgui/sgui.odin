package sgui

import "core:fmt"
import "core:log"
import "core:time"
import "core:math"
import "core:strings"
import "core:mem"
import "core:container/queue"
import "core:container/priority_queue"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"
import su "sdl_utils"

// handle //////////////////////////////////////////////////////////////////////

Handle :: struct {
    run: bool,

    /* fps variables */
    dt: f32,
    tick: time.Tick,

    /* allocators */
    widget_arena: mem.Dynamic_Arena,
    widget_allocator: mem.Allocator,

    /* sdl */
    window: ^sdl.Window,
    renderer: ^sdl.Renderer,
    text_engine: ^su.TextEngine,
    mouse_x, mouse_y: f32,
    window_w, window_h: f32,
    resize: bool,

    /* event handlers */
    event_handlers: EventHandlers,
    widget_event_queue: queue.Queue(WidgetEvent),

    focused_widget: ^Widget,
    tagged_widgets: map[u64]^Widget,

    /* layers */
    layers: [dynamic]^Widget,
    current_layer: int,
    rel_rect: Rect,

    /* draw ordering (when widget.z_index > 0, it is added to the queue) */
    ordered_draws: priority_queue.Priority_Queue(OrderedDraw),
    processing_ordered_draws: bool,
}

OrderedDraw :: struct {
    priority: u64,
    widget: ^Widget,
    draw_proc: proc(handle: ^Handle, draw_data: rawptr),
    draw_data: rawptr,
}

Rect :: sdl.FRect
Color :: distinct [4]u8

// create & destroy ////////////////////////////////////////////////////////////

create :: proc() -> (handle: ^Handle) { // TODO: allocator
    handle = new(Handle)

    /* base */
    handle^ = Handle{
        layers = make([dynamic]^Widget),
        tagged_widgets = make(map[u64]^Widget),
    }

    /* allocators */
    mem.dynamic_arena_init(&handle.widget_arena)
    handle.widget_allocator = mem.dynamic_arena_allocator(&handle.widget_arena)

    return handle
}

destroy :: proc(handle: ^Handle) {
    su.text_engine_destroy(handle.text_engine)
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
    delete(handle.tagged_widgets)
    mem.dynamic_arena_destroy(&handle.widget_arena)
    free(handle)
}

// init ////////////////////////////////////////////////////////////////////////

init :: proc(handle: ^Handle) {
    /* sdl */
    if !sdl.Init(sdl.InitFlags{.VIDEO, .EVENTS}) {
        fmt.printfln("error: {}", sdl.GetError())
        return
    }

    if !sdl.CreateWindowAndRenderer("Hello window", WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_FLAGS, &handle.window, &handle.renderer) {
        fmt.printfln("error: {}", sdl.GetError())
        return
    }

    sdl.SetRenderDrawBlendMode(handle.renderer, sdl.BLENDMODE_BLEND)

    if !sdl_ttf.Init() {
        fmt.printfln("error: couldn't init sdl_ttf.")
        return
    }

    handle.text_engine = su.text_engine_create(handle.renderer)

    w, h: i32
    assert(sdl.GetWindowSize(handle.window, &w, &h));
    handle.window_w = cast(f32)w
    handle.window_h = cast(f32)h

    /* widget event queue */
    queue.init(&handle.widget_event_queue)

    /* draw queue */
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

    /* layers */
    for layer in handle.layers {
        widget_init(layer, handle)
    }
    handle.run = true
}

// update //////////////////////////////////////////////////////////////////////

update :: proc(handle: ^Handle) {
    handle.rel_rect = Rect{0, 0, handle.window_w, handle.window_h}
    if handle.resize {
        handle.resize = false
        for layer in handle.layers {
            widget_resize(layer, handle)
        }
    }
    widget_update(handle, handle.layers[handle.current_layer])
}

// draw ////////////////////////////////////////////////////////////////////////

draw :: proc(handle: ^Handle) {
    clear_color := OPTS.clear_color
    sdl.SetRenderDrawColor(handle.renderer, clear_color.r, clear_color.g, clear_color.b, clear_color.a)
    sdl.RenderClear(handle.renderer)
    widget_draw(handle.layers[handle.current_layer], handle)
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

// terminate ///////////////////////////////////////////////////////////////////

terminate :: proc(handle: ^Handle) {
    widget_destroy(handle.layers[handle.current_layer], handle)
}

// run /////////////////////////////////////////////////////////////////////////

run :: proc(handle: ^Handle) {
    for handle.run {
        handle.dt = cast(f32)time.duration_seconds(time.tick_lap_time(&handle.tick))

        process_events(handle)
        update(handle)
        draw(handle)

        // present
        sdl.RenderPresent(handle.renderer)

        free_all(context.temp_allocator)

        // sleep to match the FPS
        time.sleep(1_000_000_000 / FPS - time.tick_since(handle.tick))
    }
    terminate(handle)
}

// events //////////////////////////////////////////////////////////////////////


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

Event :: sdl.Event
EventType :: sdl.EventType
Keycode :: sdl.Keycode

KeyMods :: bit_set[KeyMod]
KeyMod :: enum { Control, Alt, Shift }

KeyEvent :: struct {
    key: Keycode,
    down: bool,
    mods: KeyMods,
}
KeyEventHandlerProc :: proc(self: ^Widget, event: KeyEvent, handle: ^Handle) -> bool

MouseClickEvent :: struct {
    button: u8,
    down: bool,
    click_count: u8,
    x, y: f32,
    mods: KeyMods,
}
MouseClickEventHandlerProc :: proc(self: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool

MouseMotionEvent :: struct {
    x, y, xd, yd: f32,
    mods: KeyMods,
}
MouseMotionEventHandlerProc :: proc(self: ^Widget, event: MouseMotionEvent, handle: ^Handle) -> bool

MouseWheelEvent :: struct {
    x, y: i32,
    mods: KeyMods,
}
MouseWheelEventHandlerProc :: proc(self: ^Widget, event: MouseWheelEvent, handle: ^Handle) -> bool

WidgetEventTag :: u64
WidgetEvent :: struct {
    tag: WidgetEventTag,
    emitter: ^Widget,
    data: rawptr,
}
WidgetEventHandlerProc :: proc(self: ^Widget, event: WidgetEvent, handle: ^Handle) -> bool
WidgetEventHandler :: struct {
    widget: ^Widget,
    emitter: ^Widget,
    exec: WidgetEventHandlerProc,
    exec_data: rawptr
}

/* event api */

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

/* event processing */

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
                handler.exec(handler.widget, event, handle)
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
        case .WINDOW_RESIZED:
            w, h: i32
            assert(sdl.GetWindowSize(handle.window, &w, &h));
            handle.window_w = cast(f32)w
            handle.window_h = cast(f32)h
            for layer in handle.layers {
                widget_resize(layer, handle)
            }
        case .KEY_DOWN:
            if event.key.key == sdl.K_LCTRL || event.key.key == sdl.K_RCTRL {
                handle.event_handlers.mods |= { .Control }
            } else if event.key.key == sdl.K_LALT || event.key.key == sdl.K_RALT {
                handle.event_handlers.mods |= { .Alt }
            } else if event.key.key == sdl.K_LSHIFT || event.key.key == sdl.K_RSHIFT {
                handle.event_handlers.mods |= { .Shift }
            }
            key_event := KeyEvent{ event.key.key, true, handle.event_handlers.mods }
            for handler in handle.event_handlers.key {
                if handle.focused_widget != nil && handler.widget != handle.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, key_event, handle)
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
            key_event := KeyEvent{ event.key.key, false, handle.event_handlers.mods }
            for handler in handle.event_handlers.key {
                if handle.focused_widget != nil && handler.widget != handle.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, key_event, handle)
                }
            }
        case .MOUSE_WHEEL:
            wheel_event := MouseWheelEvent{
                event.wheel.integer_x,
                event.wheel.integer_y,
                handle.event_handlers.mods,
            }
            for handler in handle.event_handlers.mouse_wheel {
                if handle.focused_widget != nil && handler.widget != handle.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, wheel_event, handle)
                }
            }
        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
            mouse_click_event := MouseClickEvent{
                event.button.button,
                event.button.down,
                event.button.clicks,
                event.button.x, event.button.y,
                handle.event_handlers.mods,
            }
            for handler in handle.event_handlers.mouse_click {
                if handle.focused_widget != nil && handler.widget != handle.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, mouse_click_event, handle)
                }
            }
        case .MOUSE_MOTION:
            handle.mouse_x = event.motion.x
            handle.mouse_y = event.motion.y
            mouse_motion_event := MouseMotionEvent{
                event.motion.x, event.motion.y, event.motion.xrel, event.motion.yrel,
                handle.event_handlers.mods,
            }
            for handler in handle.event_handlers.mouse_motion {
                if handle.focused_widget != nil && handler.widget != handle.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, mouse_motion_event, handle)
                }
            }
        }
    }
}

// text utilities //////////////////////////////////////////////////////////////

create_text :: proc(handle: ^Handle, content: string, font: string, font_size: f32) -> ^su.Text {
    return su.text_engine_create_text(handle.text_engine, content, font, font_size)
}

draw_text :: proc(handle: ^Handle, text: ^su.Text, x, y: f32) {
    su.text_draw(text, x + handle.rel_rect.x, y + handle.rel_rect.y)
}

// draw utilities //////////////////////////////////////////////////////////////

draw_rect :: proc(handle: ^Handle, x, y, w, h: f32, color: Color) {
    sdl.SetRenderDrawColor(handle.renderer, color.r, color.g, color.b, color.a)
    sx := clamp(x, 0, handle.rel_rect.w)
    sy := clamp(y, 0, handle.rel_rect.h)
    sw := max(0, w - abs(sx - abs(x)))
    sh := max(0, h - abs(sy - abs(y)))
    sdl.RenderFillRect(handle.renderer, &Rect{sx + handle.rel_rect.x, sy + handle.rel_rect.y, sw, sh})
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

// mouse utilities /////////////////////////////////////////////////////////////

mouse_on_region_handle :: proc(handle: ^Handle, x, y, w, h: f32) -> bool {
    x := x + handle.rel_rect.x
    y := y + handle.rel_rect.y
    return x <= handle.mouse_x && handle.mouse_x <= (x + w) \
        && y <= handle.mouse_y && handle.mouse_y <= (y + h)
}

mouse_on_region_coordinates :: proc(mx, my, x, y, w, h: f32) -> bool {
    return x <= mx && mx <= (x + w) \
        && y <= my && my <= (y + h)
}

mouse_on_region :: proc{
    mouse_on_region_handle,
    mouse_on_region_coordinates,
}

// layers utilities ////////////////////////////////////////////////////////////

add_layer :: proc(handle: ^Handle, widget: ^Widget) {
    append(&handle.layers, widget)
}

switch_to_layer :: proc(handle: ^Handle, layer_idx: int) -> bool {
    if layer_idx > len(handle.layers) {
        return false
    }
    handle.current_layer = layer_idx
    return true
}

// widgets utilities ///////////////////////////////////////////////////////////

make_widget :: proc(handle: ^Handle, widget_proc: proc(handle: ^Handle) -> ^Widget) -> ^Widget {
    context.allocator = handle.widget_allocator
    return widget_proc(handle)
}

focus_widget :: proc(handle: ^Handle, widget: ^Widget) {
    handle.focused_widget = widget
}

unfocus_widget :: proc(handle: ^Handle, widget: ^Widget = nil) {
    handle.focused_widget = nil
}

// TODO: we need a more flexible widget cache that will allow referencing widgets with both tags and strings

tag_widget :: proc(handle: ^Handle, widget: ^Widget, tag: u64) {
    if tag in handle.tagged_widgets {
        log.warn("widget tag `{}` is replaced.", tag)
    }
    handle.tagged_widgets[tag] = widget
}

get_tagged_widget :: proc(handle: ^Handle, tag: u64) -> ^Widget{
    if tag not_in handle.tagged_widgets {
        log.error("widget `{}` does not exist.", tag)
        return nil
    }
    return handle.tagged_widgets[tag]
}
