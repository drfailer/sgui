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
WidgetValueProc :: proc(self: ^Widget) -> WidgetValue

Widget :: struct {
    x, y, w, h: f32,
    min_w, min_h: f32,
    z_index: u64,
    resizable_w, resizable_h: bool,
    disabled: bool,
    focused: bool, // TODO: we need a focused widget in the handle (will be used for text input)
    init: WidgetInitProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,
    value: WidgetValueProc,
    data: WidgetData,
}

WidgetData :: union {
    Button,
    Text,
    Box,
    DrawBox,
}

WidgetValue :: union { string, bool, int, f64 }

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
        if widget.resizable_w {
            widget.w = max(widget.min_w, w)
        }
        if widget.resizable_h {
            widget.h = max(widget.min_h, h)
        }
    }
}

widget_update :: proc(handle: ^SGUIHandle, widget: ^Widget) {
    root := Widget{
        x = handle.rel_rect.x,
        y = handle.rel_rect.y,
        w = handle.rel_rect.w,
        h = handle.rel_rect.h,
    }
    widget_align(widget, root.x, root.y, root.w, root.h)
    widget->update(handle, &root)
}

widget_draw :: proc(widget: ^Widget, handle: ^SGUIHandle) {
    if !handle.processing_ordered_draws && widget.z_index > 0 {
        sgui_add_ordered_draw(handle, widget)
    } else {
        widget->draw(handle)
    }
}

widget_is_hovered :: proc(widget: ^Widget, mx, my: f32) -> bool {
    return (widget.x <= mx && mx <= widget.x + widget.w) && (widget.y <= my && my <= widget.y + widget.h)
}

////////////////////////////////////////////////////////////////////////////////

// QUESTION:
// Should input widgets have a value function so that we can make forms that
// will be submited in one callback instead of multiple.

OnelineInput :: struct {
    label: string,
}

Slider :: struct {
    min: int,
    max: int,
    update: rawptr, // todo: callback
    // config...
}

RadioButton :: struct {
}

Menu :: struct { // top menu
}

Line :: struct { // separator line
}

Image :: struct {
    lable: string,
    path: string,
}

// text ////////////////////////////////////////////////////////////////////////

// TODO: text wrapping

TextStyle :: struct {
    font: su.FontPath,
    font_size: su.FontSize,
    color: Color,
    wrap_width: f32,
}

TextAttributes :: struct {
    style: TextStyle,
}

Text :: struct {
    text: su.Text,
    content: string,
    content_proc: proc(data: rawptr) -> (string, Color),
    content_proc_data: rawptr,
    attr: TextAttributes,
}

text_from_string :: proc(
    content: string,
    attr := TextAttributes{
        style = SGUI_OPTS.style.text
    }
) -> Widget {
    return Widget{
        init = text_init,
        update = text_update,
        draw = text_draw,
        data = Text{
            content = content,
            attr = attr,
        }
    }
}

text_from_proc :: proc(
    content_proc: proc(data: rawptr) -> (string, Color),
    content_proc_data: rawptr,
    attr := TextAttributes{
        style = SGUI_OPTS.style.text
    }
) -> Widget {
    return Widget{
        init = text_init,
        update = text_update,
        draw = text_draw,
        data = Text{
            content_proc = content_proc,
            content_proc_data = content_proc_data,
            attr = attr
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
    data.text = su.text_create(
        handle.text_engine,
        su.font_cache_get_font(&handle.font_cache, data.attr.style.font, data.attr.style.font_size),
        data.content)
    su.text_update_color(&data.text, sdl.Color{
        data.attr.style.color.r,
        data.attr.style.color.g,
        data.attr.style.color.b,
        data.attr.style.color.a
    })
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
        su.text_update_text(&data.text, content)
        su.text_update_color(&data.text, sdl.Color{color.r, color.g, color.b, color.a})
        if data.attr.style.wrap_width > 0 {
            su.text_update_wrap_width(&data.text, data.attr.style.wrap_width)
        }
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

ButtonClickedProc :: proc(clicked_data: rawptr)

ButtonColors :: struct {
    text: Color,
    border: Color,
    bg: Color,
}

ButtonStyle :: struct {
    label_font_path: su.FontPath,
    label_font_size: su.FontSize,
    padding: Padding,
    border_thickness: f32,
    corner_radius: f32,
    colors: [ButtonState]ButtonColors,
}

ButtonAttributes :: struct {
    style: ButtonStyle,
}

Button :: struct {
    label: string,
    text: su.Text,
    state: ButtonState,
    clicked: ButtonClickedProc,
    clicked_data: rawptr,
    attr: ButtonAttributes,
}

button :: proc(
    label: string,
    clicked: ButtonClickedProc,
    clicked_data: rawptr = nil,
    attr: ButtonAttributes = ButtonAttributes{
        style = SGUI_OPTS.style.button,
    },
) -> Widget {
    return Widget{
        resizable_w = true,
        resizable_h = true,
        init = button_init,
        update = button_update,
        draw = button_draw,
        data = Button{
            label = label,
            clicked = clicked,
            clicked_data = clicked_data,
            attr = attr,
        }
    }
}

button_init :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(Button)
    data.text = su.text_create(
        handle.text_engine,
        su.font_cache_get_font(&handle.font_cache, data.attr.style.label_font_path, data.attr.style.label_font_size),
        data.label)
    self.w, self.h = su.text_size(&data.text)
    self.w += data.attr.style.padding.left + data.attr.style.padding.right
    self.h += data.attr.style.padding.top + data.attr.style.padding.bottom
    self.min_w = self.w
    self.min_h = self.h

    handle->click_handler(self, proc(self: ^Widget, button: u8, down: bool, click_count: u8, x, y: f32, mods: bit_set[KeyMod]) -> bool {
        if button != sdl.BUTTON_LEFT || !widget_is_hovered(self, x, y) do return false
        data := &self.data.(Button)

        if down {
            data.state = .Clicked
        } else if data.state == .Clicked {
            data.state = .Idle
            data.clicked(data.clicked_data)
        }
        return true
    })
}

button_update :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(Button)
    if widget_is_hovered(self, handle.mouse_x, handle.mouse_y) {
        if data.state == .Idle {
            data.state = .Hovered
        }
    } else {
        data.state = .Idle
    }
}

button_draw :: proc(self: ^Widget, handle: ^SGUIHandle) {
    data := &self.data.(Button)
    text_color := data.attr.style.colors[data.state].text
    bg_color := data.attr.style.colors[data.state].bg
    border_color := data.attr.style.colors[data.state].border
    border_thickness := data.attr.style.border_thickness

    su.text_update_color(&data.text, sdl.Color{text_color.r, text_color.g, text_color.b, text_color.a})
    if data.attr.style.corner_radius > 0 {
        if border_thickness > 0 {
            draw_rounded_box(handle, self.x, self.y, self.w, self.h, data.attr.style.corner_radius, border_color)
        }
        draw_rounded_box(handle, self.x + border_thickness, self.y + border_thickness,
                         self.w - 2 * border_thickness, self.h - 2 * border_thickness,
                         data.attr.style.corner_radius, bg_color)
    } else {
        if border_thickness > 0 {
            handle->draw_rect(self.x, self.y, self.w, self.h, border_color)
        }
        handle->draw_rect(self.x + border_thickness, self.y + border_thickness,
                          self.w - 2 * border_thickness, self.h - 2 * border_thickness,
                          bg_color)
    }
    label_w, label_h := su.text_size(&data.text)
    label_x := self.x + (self.w - label_w) / 2.
    label_y := self.y + (self.h - label_h) / 2.
    su.text_draw(&data.text, label_x, label_y)
}

// boxes ///////////////////////////////////////////////////////////////////////

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
    z_index: u64,
    widgets: ..Widget,
) -> Widget {
    widget_list := make([dynamic]Widget)

    for widget in widgets {
        append(&widget_list, widget)
    }
    return Widget{
        z_index = z_index,
        resizable_h = true,
        resizable_w = true,
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

vbox :: proc(widgets: ..Widget, attr := BoxAttributes{}, z_index: u64 = 0) -> Widget {
    return box(.Vertical, attr, box_init, box_update, box_draw, z_index, ..widgets)
}

hbox :: proc(widgets: ..Widget, attr := BoxAttributes{}, z_index: u64 = 0) -> Widget {
    return box(.Horizontal, attr, box_init, box_update, box_draw, z_index, ..widgets)
}

// TODO: alignment should be done in the udpate function since we need to realign when the window is resized

box_align :: proc(self: ^Widget, x, y, w, h: f32) {
    data := &self.data.(Box)
    self.x = x
    self.y = y
    if .FitW not_in data.attr.props {
        self.w = w
        self.min_w = w
    }
    if .FitH not_in data.attr.props {
        self.h = h
        self.min_h = h
    }

    if data.layout == .Vertical {
        vbox_align(self, x, y, w, h)
    } else {
        hbox_align(self, x, y, w, h)
    }
}

vbox_align :: proc(self: ^Widget, parent_x, parent_y, parent_w, parent_h: f32) {
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

hbox_align :: proc(self: ^Widget, parent_x, parent_y, parent_w, parent_h: f32) {
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

box_update :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    data := &self.data.(Box)

    for &widget in data.widgets {
        if widget.update != nil {
            widget->update(handle, self)
        }
    }
}

box_draw :: proc(self: ^Widget, handle: ^SGUIHandle) {
    data := &self.data.(Box)

    if data.attr.style.background_color.a > 0 {
        handle->draw_rect(self.x, self.y, self.w, self.h, data.attr.style.background_color)
    }
    for &widget in data.widgets {
        if widget.draw != nil {
            widget_draw(&widget, handle)
        }
    }
    bt := data.attr.style.border_thickness
    bc := data.attr.style.border_color
    if .Top in data.attr.style.active_borders {
        handle->draw_rect(self.x, self.y, self.w, bt, bc)
    }
    if .Bottom in data.attr.style.active_borders {
        handle->draw_rect(self.x, self.y + self.h - bt, self.w, bt, bc)
    }
    if .Left in data.attr.style.active_borders {
        handle->draw_rect(self.x, self.y, bt, self.h, bc)
    }
    if .Right in data.attr.style.active_borders {
        handle->draw_rect(self.x + self.w - bt, self.y, bt, self.h, bc)
    }
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
        resizable_h = true,
        resizable_w = true,
        init = draw_box_init,
        update = draw_box_update,
        draw = draw_box_draw,
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
    handle->key_handler(self, proc(self: ^Widget, key: Keycode, type: KeyEventType, mods: bit_set[KeyMod]) -> bool {// {{{
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
    handle->scroll_handler(self, proc(self: ^Widget, x, y: i32, mods: bit_set[KeyMod]) -> bool {// {{{
        data := &self.data.(DrawBox)
        if .Control in mods {
            return zoombox_zoom_handler(&data.zoombox, x, y, mods)
        } else {
            return scrollbox_scrolled_handler(&data.scrollbox, -y, 0, 100, 100)
        }
        return true
    })// }}}
    handle->click_handler(self, proc(self: ^Widget, button: u8, down: bool, click_count: u8, x, y: f32, mods: bit_set[KeyMod]) -> bool {// {{{
        data := &self.data.(DrawBox)
        return scrollbox_clicked_handler(&data.scrollbox, button, down, click_count, x, y, mods)
    })// }}}
    handle->mouse_move_handler(self, proc(self: ^Widget, x, y, xd, yd: f32, mods: bit_set[KeyMod]) -> bool {// {{{
        data := &self.data.(DrawBox)
        return scrollbox_dragged_handler(&data.scrollbox, x, y, xd, yd, mods)
    })// }}}
}

draw_box_update :: proc(self: ^Widget, handle: ^SGUIHandle, parent: ^Widget) {
    if self.disabled do return
    data := &self.data.(DrawBox)
    if data.user_update != nil {
        data.content_size = data.user_update(handle, self, data.user_data)
    }
    scrollbox_update(&data.scrollbox, data.content_size.width, data.content_size.height)
}

draw_box_draw :: proc(self: ^Widget, handle: ^SGUIHandle) {
    if self.disabled do return
    data := &self.data.(DrawBox)
    old_rel_rect := handle.rel_rect
    handle.rel_rect = Rect{self.x, self.y, self.w, self.h}
    data.user_draw(handle, self, data.user_data)
    handle.rel_rect = old_rel_rect
    if .WithScrollbar in data.props {
        scrollbox_draw(&data.scrollbox, handle)
    }
}
