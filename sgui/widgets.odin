package sgui

/*
 * How widgets should work:
 * - widget_name(args) -> create a widget (set user handlers, and properites)
 * - widget_name_init(handle, x, y, h, w, args) -> initialization that requires the handle + init position and size (depends on widgets in the tree!)
 *
 * note: the way the size of the widget is computed may vary since some widgets
 * have a fixed size (buttons, ...)
 *
 * create the widget tree:
 * widget_init(handle, ...)
 *
 */

import "core:fmt"
import su "sdl_utils"
import sdl "vendor:sdl3"
import "core:log"

Pixel :: distinct [4]u8

// widget //////////////////////////////////////////////////////////////////////

WidgetInitProc :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget)
WidgetUpdateProc :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget)
WidgetDrawProc :: proc(self: ^Widget, handle: ^SGUIHandle)

Widget :: struct {
    x, y, w, h: f32,
    resizable: bool,
    enabled: bool,
    visible: bool,
    focused: bool, // TODO: we need a focused widget in the handle (will be used for text input)
    init: WidgetInitProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,
    data: WidgetData,
}

WidgetData :: union {
    Scrollbar,
    DrawBox,
    Text,
    Box,
}

widget_init :: proc(widget: ^Widget, handle: ^SGUIHandle) {
    w, h: i32
    assert(sdl.GetWindowSize(handle.window, &w, &h));
    root := Widget{
        x = 0,
        y = 0,
        w = cast(f32)w,
        h = cast(f32)h,
    }
    widget->init(handle, &root)
    widget_align(widget, root.x, root.y, root.w, root.h)
}

widget_align :: proc(widget: ^Widget, x, y, w, h: f32) {
    #partial switch _ in widget.data {
    case Box: box_align(widget, x, y, w, h)
    case:
        widget.x = x
        widget.y = y
        if widget.resizable {
            widget.w = w
            widget.h = h
        }
    }
}

widget_update :: proc(handle: ^SGUIHandle, widget: ^Widget) {
    w, h: i32
    assert(sdl.GetWindowSize(handle.window, &w, &h));
    root := Widget{
        x = 0,
        y = 0,
        w = cast(f32)w,
        h = cast(f32)h,
    }
    widget_align(widget, root.x, root.y, root.w, root.h)
    widget->update(handle, &root)
}

widget_draw :: proc(handle: ^SGUIHandle, widget: ^Widget) {
    widget->draw(handle)
}

widget_is_clicked :: proc(widget: ^Widget, mx, my: f32) -> bool {
    return (widget.x <= mx && mx <= widget.x + widget.w) && (widget.y <= my && my <= widget.y + widget.h)
}

////////////////////////////////////////////////////////////////////////////////

Vertical :: distinct [dynamic]Widget
Horizontal :: distinct [dynamic]Widget

TextInput :: struct {
    label: string,
}

Slider :: struct {
    min: int,
    max: int,
    update: rawptr, // todo: callback
    // config...
}

Image :: struct {
    lable: string,
    path: string,
}

Texture :: struct {
    pixels: [dynamic]Pixel,
}

// boxs /////////////////////////////////////////////////////////////////////

Padding :: struct { top: f32, bottom: f32, left: f32, right: f32 }

BorderSide :: enum { Top, Bottom, Left, Right }
ActiveBorders :: bit_set[BorderSide]

// TODO: we should enable having different kinds of dimentions unit (%, in, cm, px)
BoxDimensionsKind :: enum {
    Pixel,
}

BoxDimensions :: struct {
    kind: BoxDimensionsKind,
    w: f32,
    h: f32,
}

BoxStyle :: struct {
    background_color: Color,
    border_thickness: f32,
    active_borders: ActiveBorders,
    border_color: Color,
    padding: Padding,
    items_spacing: f32,
}

BoxLayout :: enum {
    Vertical,
    Horizontal,
}

BoxProperties :: bit_set[BoxProperty]
BoxProperty :: enum {
    AlignCenter,
    AlignLeft,
    AlignRight,
    AlignTop,
    AlignBottom,
    FitW,
    FitH,
}

BoxAttributes :: struct {
    style: BoxStyle,
    props: BoxProperties,
    dims: BoxDimensions,
}

// TODO: scrollbars
Box :: struct {
    layout: BoxLayout,
    attr: BoxAttributes,
    widgets: [dynamic]Widget,
    // TODO: add an optional ScrollBox that will contain the implementation of the scrollbars (The draw box must have it too)
    // TODO: The standard boxes should be scrollable, but only the the draw box should be zoomable
    // TODO: The the update function of the scrollbox will need to know the content size
    // TODO: separate the logic of the scrollbar into the scrollbox that will also handle mouse wheel (if the box is hovered)
}

// TODO: the box should also have scrollbars
box :: proc(
    layout: BoxLayout,
    attr: BoxAttributes,
    init: WidgetInitProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,
    widgets: ..Widget,
) -> Widget {
    widget_list := make([dynamic]Widget)

    for widget in widgets {
        append(&widget_list, widget)
    }
    return Widget{
        resizable = true,
        init = init,
        update = update,
        draw = draw,
        data = Box{
            layout = layout,
            attr = attr,
            widgets = widget_list,
        }
    }
}

vertical_box :: proc(widgets: ..Widget, attr := BoxAttributes{}) -> Widget {
    return box(.Vertical, attr, box_init, box_update, box_draw, ..widgets)
}

horizontal_box :: proc(widgets: ..Widget, attr := BoxAttributes{}) -> Widget {
    return box(.Horizontal, attr, box_init, box_update, box_draw, ..widgets)
}

// TODO: alignment should be done in the udpate function since we need to realign when the window is resized

box_align :: proc(self: ^Widget, x, y, w, h: f32) {
    data := &self.data.(Box)
    self.x = x
    self.y = y
    if .FitW not_in data.attr.props {
        self.w = w
    } // else error???
    if .FitH not_in data.attr.props {
        self.h = h
    }

    if data.layout == .Vertical {
        vertical_box_align(self, x, y, w, h)
    } else {
        horizontal_box_align(self, x, y, w, h)
    }
}

vertical_box_align :: proc(self: ^Widget, parent_x, parent_y, parent_w, parent_h: f32) {
    data := &self.data.(Box)

    widget_x := self.x
    widget_y := self.y
    widget_h := self.h

    for &widget in data.widgets {
        if .AlignCenter in data.attr.props {
            widget_x = self.x + (self.w - widget.w) / 2.
        }
        widget_align(&widget, widget_x, widget_y, self.w, widget_h)
        widget_y += widget.h
        widget_h -= widget.h
    }
}

horizontal_box_align :: proc(self: ^Widget, parent_x, parent_y, parent_w, parent_h: f32) {
    data := &self.data.(Box)

    widget_x := self.x
    widget_y := self.y
    widget_w := self.w

    for &widget in data.widgets {
        if .AlignCenter in data.attr.props {
            widget_y = self.y + (self.h - widget.h) / 2.
        }
        widget_align(&widget, widget_x, widget_y, widget_w, self.h)
        widget_x += widget.w
        widget_w -= widget.w
    }
}

box_init :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(Box)
    max_w := data.widgets[0].w
    max_h := data.widgets[0].h
    ttl_w, ttl_h: f32

    for &widget in data.widgets {
        widget->init(handle, self)
        max_w = max(max_w, widget.w)
        ttl_w += widget.w
        max_h = max(max_h, widget.h)
        ttl_h += widget.h
    }

    // TODO: this should be done in the update
    if data.layout == .Vertical {
        self.w = max_w if .FitW in data.attr.props else parent.w
        self.h = ttl_h if .FitH in data.attr.props else parent.h
    } else {
        self.w = ttl_w if .FitW in data.attr.props else parent.w
        self.h = max_h if .FitH in data.attr.props else parent.h
    }
}

// TODO: the update should take the parent widget
box_update :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(Box)

    // TODO: align
    // box_align(self, parent.x, parent.y, parent.w, parent.h)

    for &widget in data.widgets {
        if widget.update != nil {
            widget->update(handle, self)
        }
    }
}

box_draw :: proc(self: ^Widget, handle: ^SGUIHandle) {
    data := &self.data.(Box)

    handle->draw_rect(Rect{self.x, self.y, self.w, self.h}, data.attr.style.background_color)
    for &widget in data.widgets {
        if widget.draw != nil {
            widget->draw(handle)
        }
    }
}

// text ////////////////////////////////////////////////////////////////////////

Text :: struct {
    text: su.Text,
    content: string,
    color: Color,
    content_proc: proc(data: rawptr) -> (string, Color),
    content_proc_data: rawptr,
}

text_from_string :: proc(content: string, color: Color) -> Widget {
    return Widget{
        init = text_init,
        update = text_update,
        draw = text_draw,
        data = Text{
            content = content,
            color = color,
        }
    }
}

text_from_proc :: proc(
    content_proc: proc(data: rawptr) -> (string, Color),
    content_proc_data: rawptr
) -> Widget {
    return Widget{
        init = text_init,
        update = text_update,
        draw = text_draw,
        data = Text{
            content_proc = content_proc,
            content_proc_data = content_proc_data,
        }
    }
}

// TODO: create a printf like version
text :: proc {
    text_from_string,
    text_from_proc,
}

text_init :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(Text)
    data.text = su.text_create(handle.text_engine, handle.font, data.content)
    w, h := su.text_size(&data.text)
    self.w = w
    self.h = h

    if self.w > parent.w || self.h > parent.h {
        log.warn("text widget container too small")
    }
}

text_update :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(Text)
    if data.content_proc != nil {
        content, color := data.content_proc(data.content_proc_data)
        su.text_update_text(&data.text, content, sdl.Color{color.r, color.g, color.b, color.a})
        w, h := su.text_size(&data.text)
        self.w = w
        self.h = h
    }
}

text_draw :: proc(self: ^Widget, handle: ^SGUIHandle) {
    data := &self.data.(Text)
    su.text_draw(&data.text, self.x, self.y)
}

// button //////////////////////////////////////////////////////////////////////

ButtonState :: enum { Idle, Hovered, Clicked }

Button :: struct {
    label: string,
    state: ButtonState,
    clicked: rawptr, // todo: callback (click on release)
}

// draw box ////////////////////////////////////////////////////////////////////

DrawBoxProperties :: bit_set[DrawBoxProperty]
DrawBoxProperty :: enum {
    Zoomable,
    WithScrollbar,
}

ContentSize :: struct {
    width: f32,
    height: f32,
}

// TODO: the draw box should give a draw rect proc
DrawBox :: struct {
    zoom_lvl: f32,
    content_size: ContentSize,
    scrollbox: ScrollBox,
    props: DrawBoxProperties,
    user_init: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr),
    user_update: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr) -> ContentSize,
    user_draw: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr),
    user_data: rawptr,
}

draw_box :: proc(
    draw: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr),
    update: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr) -> ContentSize = nil,
    init: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr) = nil,
    data: rawptr = nil,
    props := DrawBoxProperties{},
) -> Widget {
    return Widget{
        resizable = true,
        init = draw_box_init,
        update = draw_box_update,
        draw = draw_box_draw,
        enabled = true,
        data = DrawBox{
            zoom_lvl = 1,
            props = props,
            scrollbox = scrollbox(),
            user_draw = draw,
            user_init = init,
            user_update = update,
            user_data = data,
        }
    }
}

draw_box_init :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(DrawBox)

    if data.user_init != nil {
        data.user_init(handle, self, data.user_data)
    }

    scrollbox_init(&data.scrollbox, handle, self)

    // TODO: factor this code v
    sgui_add_event_handler(handle, self, proc(self: ^Widget, key: Keycode, type: KeyEventType, mods: bit_set[KeyMod]) -> bool {// {{{
        if type != .Down do return false
        data := &self.data.(DrawBox)

        vcount, hcount: i32

        switch key {
        case sdl.K_H: hcount = -1
        case sdl.K_L: hcount = 1
        case sdl.K_K: vcount = -1
        case sdl.K_J: vcount = 1
        }
        return scrollbox_scrolled_handler(&data.scrollbox, vcount, hcount, 100, 100)
    })// }}}
    sgui_add_event_handler(handle, self, proc(self: ^Widget, x, y: i32, mods: bit_set[KeyMod]) -> bool {// {{{
        data := &self.data.(DrawBox)
        if .Control in mods {
            if y == -1 {
                data.zoom_lvl -= 0.2
            } else if y == 1 {
                data.zoom_lvl += 0.2
            } else {
                return false
            }
        } else {
            return scrollbox_scrolled_handler(&data.scrollbox, -y, 0, 100, 100)
        }
        return true
    })// }}}
    sgui_add_event_handler(handle, self, proc(self: ^Widget, button: u8, down: bool, click_count: u8, x, y: f32, mods: bit_set[KeyMod]) -> bool {// {{{
        data := &self.data.(DrawBox)
        return scrollbox_clicked_handler(&data.scrollbox, button, down, click_count, x, y, mods)
    })// }}}
    sgui_add_event_handler(handle, self, proc(self: ^Widget, x, y, xd, yd: f32, mods: bit_set[KeyMod]) -> bool {// {{{
        data := &self.data.(DrawBox)
        return scrollbox_dragged_handler(&data.scrollbox, x, y, xd, yd, mods)
    })// }}}
}

draw_box_update :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    if !self.enabled do return
    data := &self.data.(DrawBox)
    if data.user_update != nil {
        data.content_size = data.user_update(handle, self, data.user_data)
    }
    scrollbox_update(&data.scrollbox, data.content_size.width, data.content_size.height)
}

draw_box_draw :: proc(self: ^Widget, handle: ^SGUIHandle) {
    if !self.enabled do return
    data := &self.data.(DrawBox)
    data.user_draw(handle, self, data.user_data)
    if .WithScrollbar in data.props {
        scrollbox_draw(&data.scrollbox, handle)
    }
}

// scroll box //////////////////////////////////////////////////////////////////

ScrollBoxProperties :: bit_set[ScrollBoxProperty]
ScrollBoxProperty :: enum {
    ScrollbarInvisible,
    DisableHorizontalScroll,
    DisableVerticalScroll,
}

ScrollBoxData :: struct {
    enabled: bool,
    position: f32,
    target_position: f32,
    scrollbar: Scrollbar,
}

ScrollBox :: struct {
    parent: ^Widget,
    props: ScrollBoxProperties,
    vertical: ScrollBoxData,
    horizontal: ScrollBoxData,
}

scrollbox :: proc(props := ScrollBoxProperties{}) -> ScrollBox {
    return ScrollBox{
        props = props,
        vertical = ScrollBoxData{
            scrollbar = scrollbar(.Vertical),
        },
        horizontal = ScrollBoxData{
            scrollbar = scrollbar(.Horizontal),
        },
    }
}

scrollbox_scroll_data :: proc(data: ^ScrollBoxData, count: i32, step: f32) {
    if count == 0 || step == 0 || data.scrollbar.parent_size > data.scrollbar.content_size do return
    data.target_position += cast(f32)count * step
    data.target_position = clamp(data.target_position, 0, data.scrollbar.content_size - data.scrollbar.parent_size)
    fmt.printfln("scrolling: target_position = {}, count = {}", data.target_position, count)
}

scrollbox_scrolled_handler :: proc(scrollbox: ^ScrollBox, vcount, hcount: i32, vstep, hstep: f32) -> bool {
    if .DisableVerticalScroll not_in scrollbox.props && scrollbox.vertical.enabled {
        scrollbox_scroll_data(&scrollbox.vertical, vcount, vstep)
    }
    if .DisableHorizontalScroll not_in scrollbox.props && scrollbox.horizontal.enabled {
        scrollbox_scroll_data(&scrollbox.horizontal, hcount, hstep)
    }
    return true
}

scrollbox_clicked_handler :: proc(scrollbox: ^ScrollBox, button: u8, down: bool, click_count: u8, x, y: f32, mods: bit_set[KeyMod]) -> bool {
    if button == sdl.BUTTON_LEFT {
        if .DisableVerticalScroll not_in scrollbox.props && scrollbox.vertical.enabled {
            scrollbar_clicked_hander(&scrollbox.vertical.scrollbar, button, down, click_count, x, y, mods)
        }
        if .DisableHorizontalScroll not_in scrollbox.props && scrollbox.horizontal.enabled {
            scrollbar_clicked_hander(&scrollbox.horizontal.scrollbar, button, down, click_count, x, y, mods)
        }
    }
    return true
}

scrollbox_dragged_handler :: proc(scrollbox: ^ScrollBox, x, y, xd, yd: f32, mods: bit_set[KeyMod]) -> bool {
    if .DisableVerticalScroll not_in scrollbox.props && scrollbox.vertical.enabled {
        scrollbar_dragged_handler(&scrollbox.vertical.scrollbar, x, y, xd, yd, mods)
    }
    if .DisableHorizontalScroll not_in scrollbox.props && scrollbox.horizontal.enabled {
        scrollbar_dragged_handler(&scrollbox.horizontal.scrollbar, x, y, xd, yd, mods)
    }
    return true
}

scrollbox_init :: proc(scrollbox: ^ScrollBox, handle: ^SGUIHandle, parent: ^Widget) {
    scrollbox.parent = parent
    if .DisableHorizontalScroll not_in scrollbox.props {
        scrollbar_init(&scrollbox.horizontal.scrollbar, handle, parent)
    }
    if .DisableVerticalScroll not_in scrollbox.props {
        scrollbar_init(&scrollbox.vertical.scrollbar, handle, parent)
    }
}

scrollbox_data_udpate :: proc(data: ^ScrollBoxData) {
    if data.scrollbar.selected {
        data.position = data.scrollbar.bar_position
        data.target_position = data.position
    } else {
        if data.target_position > data.position {
            data.position += min(10, data.target_position - data.position)
        } else if data.target_position < data.position {
            data.position -= min(10, data.position - data.target_position)
        }
    }
}

// TODO: add content size in the scrollbox struct
scrollbox_update :: proc(scrollbox: ^ScrollBox, content_w, content_h: f32) {
    scrollbox_data_udpate(&scrollbox.vertical)
    scrollbox_data_udpate(&scrollbox.horizontal)

    // scrollbars
    scrollbox.vertical.enabled = content_h > scrollbox.parent.h
    scrollbox.horizontal.enabled = content_w > scrollbox.parent.w

    if scrollbox.vertical.enabled {
        scrollbar_update(&scrollbox.vertical.scrollbar,
                         scrollbox.parent.x + scrollbox.parent.w - SCROLLBAR_THICKNESS,
                         scrollbox.parent.y, scrollbox.vertical.position,
                         content_h, scrollbox.parent.h, scrollbox.parent)
    }

    if scrollbox.horizontal.enabled {
        size := scrollbox.parent.w if !scrollbox.vertical.enabled else scrollbox.parent.w - SCROLLBAR_THICKNESS
        scrollbar_update(&scrollbox.horizontal.scrollbar,
                         scrollbox.parent.x, scrollbox.parent.y + scrollbox.parent.h - SCROLLBAR_THICKNESS,
                         scrollbox.horizontal.position,
                         content_w, size, scrollbox.parent)
    }
}

scrollbox_draw :: proc(scrollbox: ^ScrollBox, handle: ^SGUIHandle) {
    if .DisableVerticalScroll not_in scrollbox.props && scrollbox.vertical.enabled {
        scrollbar_draw(&scrollbox.vertical.scrollbar, handle);
    }
    if .DisableHorizontalScroll not_in scrollbox.props && scrollbox.horizontal.enabled {
        scrollbar_draw(&scrollbox.horizontal.scrollbar, handle);
    }
}

// scrollbar ///////////////////////////////////////////////////////////////////

ScrollbarDirection :: enum {
    Vertical,
    Horizontal,
}

// TODO: add a position (top, bottom, left, right)??
Scrollbar :: struct {
    x, y, w, h: f32,
    selected: bool,
    bar_size: f32,
    bar_position: f32,
    content_size: f32,
    parent_size: f32,
    direction: ScrollbarDirection,
}

scrollbar :: proc(direction: ScrollbarDirection) -> Scrollbar {
    return Scrollbar{
        direction = direction,
    }
}

scrollbar_is_clicked :: proc(scrollbar: ^Scrollbar, mx, my: f32) -> bool {
    return (scrollbar.x <= mx && mx <= scrollbar.x + scrollbar.w) \
        && (scrollbar.y <= my && my <= scrollbar.y + scrollbar.h)
}

scrollbar_clicked_hander :: proc(bar: ^Scrollbar, button: u8, down: bool, click_count: u8, x, y: f32, mods: bit_set[KeyMod]) -> bool {
    if !down && bar.selected {
        bar.selected = false
    } else if scrollbar_is_clicked(bar, x, y) {
        bar.selected = true
    }
    return bar.selected
}

scrollbar_dragged_handler :: proc(bar: ^Scrollbar, x, y, xd, yd: f32, mods: bit_set[KeyMod]) -> bool {
    if !bar.selected do return false

    // TODO: invert
    scale_factor := bar.parent_size / bar.content_size

    if bar.direction == .Vertical {
        bar.bar_position += yd / scale_factor
    } else {
        bar.bar_position += xd / scale_factor
    }

    if bar.bar_position < 0 {
        bar.bar_position = 0
    } else if bar.bar_position > bar.content_size - bar.bar_size {
        bar.bar_position = bar.content_size - bar.bar_size
    }

    return true
}

scrollbar_init :: proc(self: ^Scrollbar, handle: ^SGUIHandle, parent: ^Widget) {}

scrollbar_update :: proc(bar: ^Scrollbar, x, y: f32, position: f32, content_size, parent_size: f32, parent: ^Widget) {
    if bar.direction == .Vertical {
        bar.x = parent.x + parent.w - SCROLLBAR_THICKNESS
        bar.y = parent.y
        bar.w = SCROLLBAR_THICKNESS
        bar.h = parent.h
        bar.parent_size = parent.h
    } else {
        bar.x = parent.x
        bar.y = parent.y + parent.h - SCROLLBAR_THICKNESS
        bar.w = parent.w
        bar.h = SCROLLBAR_THICKNESS
        bar.parent_size = parent.h
    }

    bar.x = x
    bar.y = y
    bar.bar_size = parent_size
    bar.bar_position = position
    bar.content_size = content_size
    bar.parent_size = parent_size
}

scrollbar_draw :: proc(bar: ^Scrollbar, handle: ^SGUIHandle) {
    scale_factor := bar.parent_size / bar.content_size
    rect := Rect{x = bar.x, y = bar.y}

    // fmt.printfln("draw scrollbar: x = {}, y = {}, w = {}, h = {}", bar.x, bar.y, bar.w, bar.h)

    if bar.direction == .Vertical {
        rect.w = SCROLLBAR_THICKNESS
        rect.h = bar.parent_size
    } else {
        rect.h = SCROLLBAR_THICKNESS
        rect.w = bar.parent_size
    }
    handle->draw_rect(rect, Color{50, 50, 50, 255})
    if bar.direction == .Vertical {
        rect.y = bar.y + bar.bar_position * scale_factor
        rect.h = bar.bar_size * scale_factor
    } else {
        rect.x = bar.x + bar.bar_position * scale_factor
        rect.w = bar.bar_size * scale_factor
    }
    // handle->draw_rect(rect, Color{100, 100, 100, 255})
    draw_rounded_box(handle, rect, 5, Color{100, 100, 100, 255})
}

// zoom box ////////////////////////////////////////////////////////////////////

ZoomBox :: struct {
    container: ^Widget,
    zoom_lvl: f32,
}
