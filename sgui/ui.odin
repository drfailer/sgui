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
import gla "gla"

// TODO: rework the sdl backend, we need a more generic api!!!

// ui //////////////////////////////////////////////////////////////////////

Ui :: struct {
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
    text_engine: ^gla.TextEngine,
    texture_engine: ^gla.TextureEngine,
    mouse_x, mouse_y: f32,
    window_w, window_h: f32,
    resize: bool,

    /* event handlers */
    event_handlers: EventUirs,
    widget_event_queue: queue.Queue(WidgetEvent),

    focused_widget: ^Widget,
    hovered_widget: ^Widget, // TODO

    /* widget storage */
    widget_storage: WidgetStorage,
    store: proc(ui: ^Ui, key: WidgetKey, widget: ^Widget),
    widget: proc(ui: ^Ui, key: WidgetKey) -> ^Widget,

    /* layers */
    layers: [dynamic]^Widget,
    current_layer: int,
    rel_rect: Rect,

    /* draw ordering (when widget.z_index > 0, it is added to the queue) */
    ordered_draws: priority_queue.Priority_Queue(OrderedDraw),
    processing_ordered_draws: bool,
}

WidgetTag :: u64

WidgetStorage :: struct {
    tagged_widgets: map[WidgetTag]^Widget,
    named_widgets: map[string]^Widget,
}

OrderedDraw :: struct {
    priority: u64,
    widget: ^Widget,
    draw_proc: proc(ui: ^Ui, draw_data: rawptr),
    draw_data: rawptr,
}

Rect :: sdl.FRect
Color :: gla.Color

// create & destroy ////////////////////////////////////////////////////////////

create :: proc() -> (ui: ^Ui) { // TODO: allocator
    ui = new(Ui)

    /* base */
    ui^ = Ui{
        layers = make([dynamic]^Widget),
        widget_storage = WidgetStorage{
            tagged_widgets = make(map[WidgetTag]^Widget),
            named_widgets = make(map[string]^Widget),
        },
        store = store_widget,
        widget = get_widget,
    }

    /* allocators */
    mem.dynamic_arena_init(&ui.widget_arena)
    ui.widget_allocator = mem.dynamic_arena_allocator(&ui.widget_arena)

    return ui
}

destroy :: proc(ui: ^Ui) {
    gla.text_engine_destroy(ui.text_engine)
    gla.texture_engine_destroy(ui.texture_engine)
    sdl.DestroyRenderer(ui.renderer)
    sdl.DestroyWindow(ui.window)
    // TODO: use an arena
    delete(ui.event_handlers.key)
    delete(ui.event_handlers.mouse_click)
    delete(ui.event_handlers.mouse_motion)
    delete(ui.event_handlers.mouse_wheel)
    for _, arr in ui.event_handlers.widget_event {
        delete(arr)
    }
    delete(ui.event_handlers.widget_event)
    queue.destroy(&ui.widget_event_queue)
    priority_queue.destroy(&ui.ordered_draws)
    delete(ui.layers)
    delete(ui.widget_storage.tagged_widgets)
    delete(ui.widget_storage.named_widgets)
    mem.dynamic_arena_destroy(&ui.widget_arena)
    free(ui)
}

// init ////////////////////////////////////////////////////////////////////////

start :: proc(ui: ^Ui) {
    if !sdl.CreateWindowAndRenderer("Hello window", WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_FLAGS, &ui.window, &ui.renderer) {
        fmt.printfln("error: {}", sdl.GetError())
        return
    }

    sdl.SetRenderDrawBlendMode(ui.renderer, sdl.BLENDMODE_BLEND)

    ui.text_engine = gla.text_engine_create(ui.renderer)
    ui.texture_engine = gla.texture_engine_create(ui.renderer)

    w, h: i32
    assert(sdl.GetWindowSize(ui.window, &w, &h));
    ui.window_w = cast(f32)w
    ui.window_h = cast(f32)h

    /* widget event queue */
    queue.init(&ui.widget_event_queue)

    /* draw queue */
    priority_queue.init(
        &ui.ordered_draws,
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
    for layer in ui.layers {
        widget_init(layer, ui)
    }
    ui.run = true
}

// update //////////////////////////////////////////////////////////////////////

update :: proc(ui: ^Ui) {
    ui.rel_rect = Rect{0, 0, ui.window_w, ui.window_h}
    if ui.resize {
        ui.resize = false
        for layer in ui.layers {
            widget_resize(layer, ui)
        }
    }
    widget_update(ui, ui.layers[ui.current_layer])
}

// draw ////////////////////////////////////////////////////////////////////////

draw :: proc(ui: ^Ui) {
    clear_color := OPTS.clear_color
    sdl.SetRenderDrawColor(ui.renderer, clear_color.r, clear_color.g, clear_color.b, clear_color.a)
    sdl.RenderClear(ui.renderer)
    widget_draw(ui.layers[ui.current_layer], ui)
    ui.processing_ordered_draws = true
    for priority_queue.len(ui.ordered_draws) > 0 {
        od := priority_queue.pop(&ui.ordered_draws)
        if od.draw_proc == nil {
            od.widget->draw(ui)
        } else {
            od.draw_proc(ui, od.draw_data)
        }
    }
    ui.processing_ordered_draws = false
}

// terminate ///////////////////////////////////////////////////////////////////

terminate :: proc(ui: ^Ui) {
    widget_destroy(ui.layers[ui.current_layer], ui)
}

// run /////////////////////////////////////////////////////////////////////////

run :: proc(ui: ^Ui) {
    start(ui)

    for ui.run {
        ui.dt = cast(f32)time.duration_seconds(time.tick_lap_time(&ui.tick))

        process_events(ui)
        update(ui)
        draw(ui)

        // present
        sdl.RenderPresent(ui.renderer)

        free_all(context.temp_allocator)

        // sleep to match the FPS
        time.sleep(1_000_000_000 / FPS - time.tick_since(ui.tick))
    }
    terminate(ui)
}

// events //////////////////////////////////////////////////////////////////////

EventUir :: struct($P: typeid) {
    exec: P,
    widget: ^Widget,
}

EventUirs :: struct {
    mods: bit_set[KeyMod],
    key: [dynamic]EventUir(KeyEventUirProc),
    mouse_click: [dynamic]EventUir(MouseClickEventUirProc), // TODO: use a more efficent data stucture?
    mouse_motion: [dynamic]EventUir(MouseMotionEventUirProc), // TODO: use a more efficent data stucture?
    mouse_wheel: [dynamic]EventUir(MouseWheelEventUirProc),
    widget_event: map[WidgetEventTag][dynamic]WidgetEventUir
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
KeyEventUirProc :: proc(self: ^Widget, event: KeyEvent, ui: ^Ui) -> bool

MouseClickEvent :: struct {
    button: u8,
    down: bool,
    click_count: u8,
    x, y: f32,
    mods: KeyMods,
}
MouseClickEventUirProc :: proc(self: ^Widget, event: MouseClickEvent, ui: ^Ui) -> bool

MouseMotionEvent :: struct {
    x, y, xd, yd: f32,
    mods: KeyMods,
}
MouseMotionEventUirProc :: proc(self: ^Widget, event: MouseMotionEvent, ui: ^Ui) -> bool

MouseWheelEvent :: struct {
    x, y: i32,
    mods: KeyMods,
}
MouseWheelEventUirProc :: proc(self: ^Widget, event: MouseWheelEvent, ui: ^Ui) -> bool

WidgetEventTag :: u64
WidgetEvent :: struct {
    tag: WidgetEventTag,
    emitter: ^Widget,
    data: rawptr,
}
WidgetEventUirProc :: proc(self: ^Widget, event: WidgetEvent, ui: ^Ui) -> bool
WidgetEventUir :: struct {
    widget: ^Widget,
    emitter: ^Widget,
    exec: WidgetEventUirProc,
    exec_data: rawptr
}

/* event api */

add_key_event_handler :: proc(ui: ^Ui, widget: ^Widget, exec: KeyEventUirProc) {
    append(&ui.event_handlers.key, EventUir(KeyEventUirProc){exec, widget})
}

add_mouse_wheel_event_handler :: proc(ui: ^Ui, widget: ^Widget, exec: MouseWheelEventUirProc) {
    append(&ui.event_handlers.mouse_wheel, EventUir(MouseWheelEventUirProc){exec, widget})
}

add_mouse_click_event_handler :: proc(ui: ^Ui, widget: ^Widget, exec: MouseClickEventUirProc) {
    append(&ui.event_handlers.mouse_click, EventUir(MouseClickEventUirProc){exec, widget})
}

add_mouse_motion_event_handler :: proc(ui: ^Ui, widget: ^Widget, exec: MouseMotionEventUirProc) {
    append(&ui.event_handlers.mouse_motion, EventUir(MouseMotionEventUirProc){exec, widget})
}

add_widget_event_handler :: proc(
    ui: ^Ui,
    widget: ^Widget,
    emitter: ^Widget,
    tag: WidgetEventTag,
    exec: WidgetEventUirProc,
    exec_data: rawptr = nil
) {
    if tag not_in ui.event_handlers.widget_event {
        ui.event_handlers.widget_event[tag] = make([dynamic]WidgetEventUir)
    }
    append(&ui.event_handlers.widget_event[tag], WidgetEventUir{
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

emit :: proc(ui: ^Ui, tag: WidgetEventTag, emitter: ^Widget, data: rawptr = nil) {
    queue.enqueue(&ui.widget_event_queue, WidgetEvent{tag, emitter, data})
}

/* event processing */

process_widget_events :: proc(ui: ^Ui) {
    // We reset the queue to avoid event to constantly append new event into it.
    // Here, if any handler emit a new event, it will be process during the
    // next iteration so that we never get stuck into an infit loop here.
    q := ui.widget_event_queue
    defer queue.destroy(&q)
    queue.init(&ui.widget_event_queue)

    for queue.len(q) > 0 {
        event := queue.dequeue(&q)
        for handler in ui.event_handlers.widget_event[event.tag] {
            if handler.emitter == nil || handler.emitter == event.emitter {
                handler.exec(handler.widget, event, ui)
            }
        }
    }
}

process_events :: proc(ui: ^Ui) {
    process_widget_events(ui)

    event: sdl.Event
    for sdl.PollEvent(&event) {
        #partial switch event.type {
        case .WINDOW_CLOSE_REQUESTED: fallthrough
        case .QUIT:
            ui.run = false
        case .WINDOW_RESIZED:
            w, h: i32
            assert(sdl.GetWindowSize(ui.window, &w, &h));
            ui.window_w = cast(f32)w
            ui.window_h = cast(f32)h
            for layer in ui.layers {
                widget_resize(layer, ui)
            }
        case .KEY_DOWN:
            if event.key.key == sdl.K_LCTRL || event.key.key == sdl.K_RCTRL {
                ui.event_handlers.mods |= { .Control }
            } else if event.key.key == sdl.K_LALT || event.key.key == sdl.K_RALT {
                ui.event_handlers.mods |= { .Alt }
            } else if event.key.key == sdl.K_LSHIFT || event.key.key == sdl.K_RSHIFT {
                ui.event_handlers.mods |= { .Shift }
            }
            key_event := KeyEvent{ event.key.key, true, ui.event_handlers.mods }
            for handler in ui.event_handlers.key {
                if ui.focused_widget != nil && handler.widget != ui.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, key_event, ui)
                }
            }
        case .KEY_UP:
            if event.key.key == sdl.K_LCTRL || event.key.key == sdl.K_RCTRL {
                ui.event_handlers.mods ~= { .Control }
            } else if event.key.key == sdl.K_LALT || event.key.key == sdl.K_RALT {
                ui.event_handlers.mods ~= { .Alt }
            } else if event.key.key == sdl.K_LSHIFT || event.key.key == sdl.K_RSHIFT {
                ui.event_handlers.mods ~= { .Shift }
            }
            key_event := KeyEvent{ event.key.key, false, ui.event_handlers.mods }
            for handler in ui.event_handlers.key {
                if ui.focused_widget != nil && handler.widget != ui.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, key_event, ui)
                }
            }
        case .MOUSE_WHEEL:
            wheel_event := MouseWheelEvent{
                event.wheel.integer_x,
                event.wheel.integer_y,
                ui.event_handlers.mods,
            }
            for handler in ui.event_handlers.mouse_wheel {
                if ui.focused_widget != nil && handler.widget != ui.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, wheel_event, ui)
                }
            }
        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
            mouse_click_event := MouseClickEvent{
                event.button.button,
                event.button.down,
                event.button.clicks,
                event.button.x, event.button.y,
                ui.event_handlers.mods,
            }
            for handler in ui.event_handlers.mouse_click {
                if ui.focused_widget != nil && handler.widget != ui.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, mouse_click_event, ui)
                }
            }
        case .MOUSE_MOTION:
            ui.mouse_x = event.motion.x
            ui.mouse_y = event.motion.y
            mouse_motion_event := MouseMotionEvent{
                event.motion.x, event.motion.y, event.motion.xrel, event.motion.yrel,
                ui.event_handlers.mods,
            }
            for handler in ui.event_handlers.mouse_motion {
                if ui.focused_widget != nil && handler.widget != ui.focused_widget do continue
                if !handler.widget.disabled {
                    handler.exec(handler.widget, mouse_motion_event, ui)
                }
            }
        }
    }
}

// text utilities //////////////////////////////////////////////////////////////

create_text :: proc(ui: ^Ui, content: string, font: string, font_size: f32, color := Color{0, 0, 0, 0}) -> ^gla.Text {
    text := gla.text_engine_create_text(ui.text_engine, content, font, font_size)
    gla.text_set_color(text, color)
    gla.text_update(text)
    return text
}

draw_text :: proc(ui: ^Ui, text: ^gla.Text, x, y: f32) {
    gla.text_draw(text, x + ui.rel_rect.x, y + ui.rel_rect.y)
}

// image utilities /////////////////////////////////////////////////////////////

create_image :: proc(ui: ^Ui, path: string, srcrect: Rect = Rect{0, 0, 0, 0}) -> ^gla.Image {
    return gla.image_create(ui.texture_engine, path, srcrect)
}

draw_image :: proc(ui: ^Ui, image: ^gla.Image, x, y, w, h: f32) {
    gla.image_draw(ui.renderer, image, ui.rel_rect.x + x, ui.rel_rect.y + y, w, h)
}

// ordered draw ////////////////////////////////////////////////////////////////

add_widget_ordered_draw :: proc(ui: ^Ui, widget: ^Widget) {
    priority_queue.push(&ui.ordered_draws, OrderedDraw{
        priority = widget.z_index,
        widget = widget,
    })
}

add_proc_ordered_draw :: proc(
    ui: ^Ui,
    priority: u64,
    draw_proc: proc(handel: ^Ui, draw_data: rawptr),
    draw_data: rawptr = nil
) {
    priority_queue.push(&ui.ordered_draws, OrderedDraw{
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

mouse_on_region_ui :: proc(ui: ^Ui, x, y, w, h: f32) -> bool {
    x := x + ui.rel_rect.x
    y := y + ui.rel_rect.y
    return x <= ui.mouse_x && ui.mouse_x <= (x + w) \
        && y <= ui.mouse_y && ui.mouse_y <= (y + h)
}

mouse_on_region_coordinates :: proc(mx, my, x, y, w, h: f32) -> bool {
    return x <= mx && mx <= (x + w) \
        && y <= my && my <= (y + h)
}

mouse_on_region :: proc{
    mouse_on_region_ui,
    mouse_on_region_coordinates,
}

// layers utilities ////////////////////////////////////////////////////////////

add_layer :: proc(ui: ^Ui, widget: ^Widget) {
    append(&ui.layers, widget)
}

switch_to_layer :: proc(ui: ^Ui, layer_idx: int) -> bool {
    if layer_idx > len(ui.layers) {
        return false
    }
    ui.current_layer = layer_idx
    return true
}

// widgets utilities ///////////////////////////////////////////////////////////

make_widget :: proc(ui: ^Ui, widget_proc: proc(ui: ^Ui) -> ^Widget) -> ^Widget {
    context.allocator = ui.widget_allocator
    return widget_proc(ui)
}

focus_widget :: proc(ui: ^Ui, widget: ^Widget) {
    ui.focused_widget = widget
}

unfocus_widget :: proc(ui: ^Ui, widget: ^Widget = nil) {
    ui.focused_widget = nil
}

store_named_widget :: proc(ui: ^Ui, name: string, widget: ^Widget) {
    if name in ui.widget_storage.named_widgets {
        log.warn("widget nmad `{}` is replaced.", name)
    }
    ui.widget_storage.named_widgets[name] = widget
}

get_named_widget :: proc(ui: ^Ui, name: string) -> ^Widget{
    if name not_in ui.widget_storage.named_widgets {
        log.error("widget named `{}` does not exist.", name)
        return nil
    }
    return ui.widget_storage.named_widgets[name]
}

store_tagged_widget :: proc(ui: ^Ui, tag: WidgetTag, widget: ^Widget) {
    if tag in ui.widget_storage.tagged_widgets {
        log.warn("widget tagged `{}` is replaced.", tag)
    }
    ui.widget_storage.tagged_widgets[tag] = widget
}

get_tagged_widget :: proc(ui: ^Ui, tag: WidgetTag) -> ^Widget{
    if tag not_in ui.widget_storage.tagged_widgets {
        log.error("widget tagged `{}` does not exist.", tag)
        return nil
    }
    return ui.widget_storage.tagged_widgets[tag]
}

WidgetKey :: union {
    WidgetTag,
    string,
}

store_widget :: proc(ui: ^Ui, key: WidgetKey, widget: ^Widget) {
    switch _ in key {
    case WidgetTag: store_tagged_widget(ui, key.(WidgetTag), widget)
    case string: store_named_widget(ui, key.(string), widget)
    }
}

get_widget :: proc(ui: ^Ui, key: WidgetKey) -> ^Widget {
    switch _ in key {
    case WidgetTag: return get_tagged_widget(ui, key.(WidgetTag))
    case string: return get_named_widget(ui, key.(string))
    }
    return nil
}
