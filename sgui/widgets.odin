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
        if widget.w == 0 {
            widget.w = w
        }
        if widget.h == 0 {
            fmt.printfln("align height: {}", h)
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
    position_x: f32,
    position_y: f32,
    target_position_x: f32,
    target_position_y: f32,
    content_size: ContentSize,
    props: DrawBoxProperties,
    user_init: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr),
    user_update: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr) -> ContentSize,
    user_draw: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr),
    user_data: rawptr,
    vertical_scrollbar: ^Widget,
    horizontal_scrollbar: ^Widget,
}

draw_box :: proc(
    draw: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr),
    update: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr) -> ContentSize = nil,
    init: proc(handle: ^SGUIHandle, widget: ^Widget, user_data: rawptr) = nil,
    data: rawptr = nil,
    props := DrawBoxProperties{},
) -> Widget {
    vertical_scrollbar := new(Widget)
    vertical_scrollbar^ = scrollbar(.Vertical)
    horizontal_scrollbar := new(Widget)
    horizontal_scrollbar^ = scrollbar(.Horizontal)

    return Widget{
        init = draw_box_init,
        update = draw_box_update,
        draw = draw_box_draw,
        enabled = true,
        data = DrawBox{
            zoom_lvl = 1,
            props = props,
            user_draw = draw,
            user_init = init,
            user_update = update,
            user_data = data,
            vertical_scrollbar = vertical_scrollbar,
            horizontal_scrollbar = horizontal_scrollbar,
        }
    }
}

draw_box_init :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(DrawBox)

    if data.user_init != nil {
        data.user_init(handle, self, data.user_data)
    }

    data.vertical_scrollbar->init(handle, self)
    data.horizontal_scrollbar->init(handle, self)

    // TODO: factor this code v
    sgui_add_event_handler(handle, self, proc(self: ^Widget, key: Keycode, type: KeyEventType, mods: bit_set[KeyMod]) -> bool {// {{{
        if type != .Down do return false
        data := &self.data.(DrawBox)

        switch key {
        case sdl.K_H:
            if data.target_position_x > 0 {
                data.target_position_x -= min(100, data.target_position_x)
            }
        case sdl.K_L:
            increment := min(100, data.content_size.width - data.target_position_x - self.w)
            if increment > 0 && data.target_position_x + self.w + increment <= data.content_size.width {
                data.target_position_x += increment
            }
        case sdl.K_K:
            if data.target_position_y > 0 {
                data.target_position_y -= min(100, data.target_position_y)
            }
        case sdl.K_J:
            increment := min(100, data.content_size.height - data.target_position_y - self.h)
            if increment > 0 && data.target_position_y + self.h + increment <= data.content_size.height {
                data.target_position_y += increment
            }
        }
        return true
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
            if y == -1 {
                increment := min(100, data.content_size.height - data.target_position_y - self.h)
                if increment > 0 && data.target_position_y + self.h + increment <= data.content_size.height {
                    data.target_position_y += increment
                }
            } else if y == 1 {
                if data.target_position_y > 0 {
                    data.target_position_y -= min(100, data.target_position_y)
                }
            } else {
                return false
            }
        }
        return true
    })// }}}
}

draw_box_update :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    if !self.enabled do return
    data := &self.data.(DrawBox)

    if data.user_update != nil {
        data.content_size = data.user_update(handle, self, data.user_data)
    }

    // TODO: this is for testing but a solution non fps dependent would be better!
    if !data.vertical_scrollbar.data.(Scrollbar).selected {
        if data.target_position_y > data.position_y {
            data.position_y += min(10, data.target_position_y - data.position_y)
        } else if data.target_position_y < data.position_y {
            data.position_y -= min(10, data.position_y - data.target_position_y)
        }
    } else {
        data.position_y = data.vertical_scrollbar.data.(Scrollbar).bar_position
        data.target_position_y = data.position_y
    }
    if !data.horizontal_scrollbar.data.(Scrollbar).selected {
        if data.target_position_x > data.position_x {
            data.position_x += min(10, data.target_position_x - data.position_x)
        } else if data.target_position_x < data.position_x {
            data.position_x -= min(10, data.position_x - data.target_position_x)
        }
    } else {
        data.position_x = data.horizontal_scrollbar.data.(Scrollbar).bar_position
        data.target_position_x = data.position_x
    }

    // scrollbars
    data.vertical_scrollbar.enabled = data.content_size.height > self.h
    data.horizontal_scrollbar.enabled = data.content_size.width > self.w

    if data.vertical_scrollbar.enabled {
        scrollbar_update(data.vertical_scrollbar, self.x + self.w - SCROLLBAR_THICKNESS, self.y,
                         data.position_y, data.content_size.height, self.h, self)
    }

    if data.horizontal_scrollbar.enabled {
        size := self.w if !data.vertical_scrollbar.enabled else self.w - SCROLLBAR_THICKNESS
        scrollbar_update(data.horizontal_scrollbar, self.x, self.y + self.h - SCROLLBAR_THICKNESS,
                         data.position_x, data.content_size.width, size, self)
    }
}

draw_box_draw :: proc(self: ^Widget, handle: ^SGUIHandle) {
    if !self.enabled do return
    data := &self.data.(DrawBox)

    data.user_draw(handle, self, data.user_data)

    if .WithScrollbar not_in data.props {
        return
    }

    data.vertical_scrollbar->draw(handle)
    data.horizontal_scrollbar->draw(handle)
}

// scrollbar ///////////////////////////////////////////////////////////////////

ScrollbarDirection :: enum {
    Vertical,
    Horizontal,
}

// TODO: add a position (top, bottom, left, right)??
Scrollbar :: struct {
    selected: bool,
    bar_size: f32,
    bar_position: f32,
    content_size: f32,
    parent_size: f32,
    direction: ScrollbarDirection,
}

scrollbar :: proc(direction: ScrollbarDirection) -> Widget {
    return Widget{
        init = scrollbar_init,
        update = nil,
        draw = scrollbar_draw,
        data = Scrollbar{
            direction = direction,
        }
    }
}

scrollbar_init :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    sgui_add_event_handler(handle, self, proc(self: ^Widget, button: u8, down: bool, click_count: u8, x, y: f32, mods: bit_set[KeyMod]) -> bool {
        data := &self.data.(Scrollbar)
        if button == sdl.BUTTON_LEFT {
            if !down && data.selected {
                data.selected = false
            } else if widget_is_clicked(self, x, y) {
                data.selected = true
            }
        }
        return true
    })
    sgui_add_event_handler(handle, self, proc(self: ^Widget, x, y, xd, yd: f32, mods: bit_set[KeyMod]) -> bool {
        data := &self.data.(Scrollbar)
        scale_factor := data.parent_size / data.content_size

        if !data.selected do return false

        if data.direction == .Vertical {
            data.bar_position += yd / scale_factor
        } else {
            data.bar_position += xd / scale_factor
        }

        if data.bar_position < 0 {
            data.bar_position = 0
        } else if data.bar_position > data.content_size - data.bar_size {
            data.bar_position = data.content_size - data.bar_size
        }

        return true
    })
}

scrollbar_update :: proc(self: ^Widget, x, y: f32, position: f32, content_size, parent_size: f32, parent: ^Widget) {
    if !self.enabled do return
    data := &self.data.(Scrollbar)

    if data.direction == .Vertical {
        self.x = parent.x + parent.w - SCROLLBAR_THICKNESS
        self.y = parent.y
        self.w = SCROLLBAR_THICKNESS
        self.h = parent.h
        data.parent_size = parent.h
    } else {
        self.x = parent.x
        self.y = parent.y + parent.h - SCROLLBAR_THICKNESS
        self.w = parent.w
        self.h = SCROLLBAR_THICKNESS
        data.parent_size = parent.h
    }

    self.x = x
    self.y = y
    data.bar_size = parent_size
    data.bar_position = position
    data.content_size = content_size
    data.parent_size = parent_size
}

scrollbar_draw :: proc(self: ^Widget, handle: ^SGUIHandle) {
    if !self.enabled do return
    data := &self.data.(Scrollbar)
    scale_factor := data.parent_size / data.content_size
    rect := Rect{x = self.x, y = self.y}

    // fmt.printfln("draw scrollbar: x = {}, y = {}, w = {}, h = {}", self.x, self.y, self.w, self.h)

    if data.direction == .Vertical {
        rect.w = SCROLLBAR_THICKNESS
        rect.h = data.parent_size
    } else {
        rect.h = SCROLLBAR_THICKNESS
        rect.w = data.parent_size
    }
    handle->draw_rect(rect, Color{50, 50, 50, 255})
    if data.direction == .Vertical {
        rect.y = self.y + data.bar_position * scale_factor
        rect.h = data.bar_size * scale_factor
    } else {
        rect.x = self.x + data.bar_position * scale_factor
        rect.w = data.bar_size * scale_factor
    }
    // handle->draw_rect(rect, Color{100, 100, 100, 255})
    draw_rounded_box(handle, rect, 5, Color{100, 100, 100, 255})
}
