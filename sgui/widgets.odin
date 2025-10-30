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

    widget_x := self.x + data.attr.style.padding.left
    widget_y := self.y + data.attr.style.padding.top
    widget_h := self.h - data.attr.style.padding.top - data.attr.style.padding.bottom

    for &widget in data.widgets {
        if .AlignCenter in data.attr.props {
            widget_x = self.x + data.attr.style.padding.left \
                     + (self.w - widget.w - data.attr.style.padding.left - data.attr.style.padding.right) / 2.
        }
        widget_align(&widget, widget_x, widget_y, self.w, widget_h)
        widget_y += widget.h + data.attr.style.items_spacing
        widget_h -= widget.h + data.attr.style.items_spacing
    }
}

horizontal_box_align :: proc(self: ^Widget, parent_x, parent_y, parent_w, parent_h: f32) {
    data := &self.data.(Box)

    widget_x := self.x + data.attr.style.padding.left
    widget_y := self.y + data.attr.style.padding.top
    widget_w := self.w - data.attr.style.padding.left - data.attr.style.padding.right

    for &widget in data.widgets {
        if .AlignCenter in data.attr.props {
            widget_y = self.y + data.attr.style.padding.top \
                     + (self.h - widget.h - data.attr.style.padding.top - data.attr.style.padding.bottom) / 2.
        }
        widget_align(&widget, widget_x, widget_y, widget_w, self.h)
        widget_x += widget.w + data.attr.style.items_spacing
        widget_w -= widget.w + data.attr.style.items_spacing
    }
}

box_init :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(Box)
    padding_w := data.attr.style.padding.left + data.attr.style.padding.right
    padding_h := data.attr.style.padding.top + data.attr.style.padding.bottom
    max_w := data.widgets[0].w
    max_h := data.widgets[0].h
    ttl_w := padding_w
    ttl_h := padding_h

    for &widget in data.widgets {
        widget->init(handle, self)
        max_w = max(max_w, widget.w)
        ttl_w += widget.w + data.attr.style.items_spacing
        max_h = max(max_h, widget.h)
        ttl_h += widget.h + data.attr.style.items_spacing
    }

    // TODO: this should be done in the update
    if data.layout == .Vertical {
        self.w = max_w + padding_w if .FitW in data.attr.props else parent.w
        self.h = ttl_h - data.attr.style.items_spacing if .FitH in data.attr.props else parent.h
    } else {
        self.w = ttl_w - data.attr.style.items_spacing if .FitW in data.attr.props else parent.w
        self.h = max_h + padding_h if .FitH in data.attr.props else parent.h
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
    content_size: ContentSize,
    zoombox: ZoomBox,
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
            props = props,
            zoombox = zoombox(1., 10., 0.2),
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
    zoombox_init(&data.zoombox, self)

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
            return zoombox_zoom_handler(&data.zoombox, x, y, mods)
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
