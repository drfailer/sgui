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

WidgetInitProc :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget)
WidgetUpdateProc :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget)
WidgetDrawProc :: proc(self: ^Widget, handle: ^Handle)

AlignmentPolicy :: bit_set[AlignmentFlag]
AlignmentFlag :: enum {
    Left,
    Right,
    Top,
    Bottom,
    VCenter,
    HCenter,
}

SizePolicy :: bit_set[SizeFlag]
SizeFlag :: enum {
    FillW,
    FillH,
    // TODO: ratio / relative to a widget??
}

Widget :: struct {
    /* position and dimentions */
    x, y, w, h: f32,
    min_w, min_h: f32,
    z_index: u64,

    /* flags */
    disabled: bool,
    invisible: bool,
    focused: bool,

    /* policies */
    size_policy: SizePolicy,
    alignment_policy: AlignmentPolicy,

    /* procs */
    init: WidgetInitProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,

    /* data specific to the underlying widget */
    data: WidgetData,
    // TODO: custom widget (just hold a rawptr)
}

WidgetData :: union {
    Button,
    Text,
    Box,
    DrawBox,
    RadioButton,
    rawptr, // custom widget
}

widget_init :: proc(widget: ^Widget, handle: ^Handle) {
    root := Widget{
        x = 0,
        y = 0,
        w = cast(f32)handle.window_w,
        h = cast(f32)handle.window_h,
    }
    widget->init(handle, &root)
    widget_resize(widget, handle)
}

widget_resize :: proc(widget: ^Widget, handle: ^Handle) {
    if widget.disabled do return
    if .FillW in widget.size_policy {
        widget.w = handle.window_w
    }
    if .FillH in widget.size_policy {
        widget.h = handle.window_h
    }
    #partial switch _ in widget.data {
    case Box: box_resize(widget, handle.window_w, handle.window_h)
    }
    widget_align(widget, 0, 0)
}

widget_align :: proc(widget: ^Widget, x, y: f32) {
    widget.x = x
    widget.y = y
    #partial switch _ in widget.data {
    case Box: box_align(widget, x, y)
    }
}

widget_update :: proc(handle: ^Handle, widget: ^Widget) {
    root := Widget{
        x = handle.rel_rect.x,
        y = handle.rel_rect.y,
        w = handle.rel_rect.w,
        h = handle.rel_rect.h,
    }
    widget->update(handle, &root)
}

widget_draw :: proc(widget: ^Widget, handle: ^Handle) {
    if widget.draw == nil do return
    if !handle.processing_ordered_draws && widget.z_index > 0 {
        add_ordered_draw(handle, widget)
    } else if !widget.disabled && !widget.invisible {
        widget->draw(handle)
    }
}

widget_is_hovered :: proc(widget: ^Widget, mx, my: f32) -> bool {
    return mouse_on_region(mx, my, widget.x, widget.y, widget.w, widget.h)
}

widget_enable :: proc(widget: ^Widget, handle: ^Handle) {
    widget.disabled = false
    handle.resize = true
}

widget_disable :: proc(widget: ^Widget, handle: ^Handle) {
    widget.disabled = true
    handle.resize = true
}

widget_toggle :: proc(widget: ^Widget, handle: ^Handle) {
    widget.disabled = !widget.disabled
    handle.resize = true
}

////////////////////////////////////////////////////////////////////////////////

OnelineInput :: struct {
    label: string,
}

Slider :: struct {
    min: int,
    max: int,
    update: rawptr, // todo: callback
    // config...
}

DropDownSelector :: struct {
}

SwitchButton :: struct {
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

text_from_string :: proc(content: string, attr := OPTS.text_attr) -> (text: ^Widget) {
    text = new(Widget)
    text^ = Widget{
        init = text_init,
        update = text_update,
        draw = text_draw,
        data = Text{
            content = content,
            attr = attr,
        }
    }
    return text
}

text_from_proc :: proc(
    content_proc: proc(data: rawptr) -> (string, Color),
    content_proc_data: rawptr,
    attr := OPTS.text_attr,
) -> (text: ^Widget) {
    text = new(Widget)
    text^ = Widget{
        init = text_init,
        update = text_update,
        draw = text_draw,
        data = Text{
            content_proc = content_proc,
            content_proc_data = content_proc_data,
            attr = attr
        }
    }
    return text
}

// TODO: create a printf like version
text :: proc {
    text_from_string,
    text_from_proc,
}

text_init :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
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
    self.min_w = w
    self.min_h = h
}

text_update :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    data := &self.data.(Text)
    if data.content_proc != nil {
        content, color := data.content_proc(data.content_proc_data)
        su.text_update_text(&data.text, content)
        su.text_update_color(&data.text, sdl.Color{color.r, color.g, color.b, color.a})
        if data.attr.style.wrap_width > 0 {
            su.text_update_wrap_width(&data.text, data.attr.style.wrap_width)
        }
        w, h := su.text_size(&data.text)
        if w > self.w || h > self.h {
            handle.resize = true
        }
        self.w = w
        self.h = h
        self.min_w = w
        self.min_h = h
    }
}

text_draw :: proc(self: ^Widget, handle: ^Handle) {
    data := &self.data.(Text)
    draw_text(handle, &data.text, self.x, self.y)
}

// button //////////////////////////////////////////////////////////////////////

// TODO: icon button

ButtonState :: enum { Idle, Hovered, Clicked }

ButtonClickedProc :: proc(handle: ^Handle, clicked_data: rawptr)

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
    expand_w, expand_h: bool,
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
    attr := OPTS.button_attr,
) -> (button: ^Widget) {
    button = new(Widget)
    button^ = Widget{
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
    if attr.expand_w {
        button.size_policy |= {.FillW}
    }
    if attr.expand_h {
        button.size_policy |= {.FillH}
    }
    return button
}

button_init :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
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

    add_event_handler(handle, self, proc(self: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
        if event.button != sdl.BUTTON_LEFT || !widget_is_hovered(self, event.x, event.y) do return false
        data := &self.data.(Button)

        if event.down {
            data.state = .Clicked
        } else if data.state == .Clicked {
            data.state = .Idle
            data.clicked(handle, data.clicked_data)
        }
        return true
    })
}

button_update :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    data := &self.data.(Button)
    if widget_is_hovered(self, handle.mouse_x, handle.mouse_y) {
        if data.state == .Idle {
            data.state = .Hovered
        }
    } else {
        data.state = .Idle
    }
}

button_draw :: proc(self: ^Widget, handle: ^Handle) {
    data := &self.data.(Button)
    text_color := data.attr.style.colors[data.state].text
    bg_color := data.attr.style.colors[data.state].bg
    border_color := data.attr.style.colors[data.state].border
    border_thickness := data.attr.style.border_thickness

    su.text_update_color(&data.text, sdl.Color{text_color.r, text_color.g, text_color.b, text_color.a})
    if data.attr.style.corner_radius > 0 {
        if border_thickness > 0 {
            draw_rounded_box_with_border(handle, self.x, self.y, self.w, self.h,
                                         data.attr.style.corner_radius, border_thickness,
                                         border_color, bg_color)
        } else {
            draw_rounded_box(handle, self.x + border_thickness, self.y + border_thickness,
                             self.w - 2 * border_thickness, self.h - 2 * border_thickness,
                             data.attr.style.corner_radius, bg_color)
        }
    } else {
        if border_thickness > 0 {
            draw_rect(handle, self.x, self.y, self.w, self.h, border_color)
        }
        draw_rect(handle, self.x + border_thickness, self.y + border_thickness,
                          self.w - 2 * border_thickness, self.h - 2 * border_thickness,
                          bg_color)
    }
    label_w, label_h := su.text_size(&data.text)
    label_x := self.x + (self.w - label_w) / 2.
    label_y := self.y + (self.h - label_h) / 2.
    draw_text(handle, &data.text, label_x, label_y)
}

// boxes ///////////////////////////////////////////////////////////////////////

Padding :: struct { top: f32, bottom: f32, left: f32, right: f32 }

BorderSide :: enum { Top, Bottom, Left, Right }
ActiveBorders :: bit_set[BorderSide]

BoxStyle :: struct {
    background_color: Color,
    border_thickness: f32,
    active_borders: ActiveBorders,
    border_color: Color,
    padding: Padding,
    items_spacing: f32,
    // TODO: corner radius (only if all the borders are activated)
}

BoxLayout :: enum {
    Vertical,
    Horizontal,
}

BoxProperties :: bit_set[BoxProperty]
BoxProperty :: enum {
    FitW,
    FitH,
    FixedW,
    FixedH,
}

BoxAttributes :: struct {
    style: BoxStyle,
    props: BoxProperties,
    w, h: f32,
    min_w, min_h: f32,
}

Box :: struct {
    layout: BoxLayout,
    widgets: [dynamic]^Widget,
    scrollbars: Scrollbars,
    content_w, content_h: f32,
    attr: BoxAttributes,
}

box :: proc(// {{{
    layout: BoxLayout,
    attr: BoxAttributes,
    init: WidgetInitProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,
    z_index: u64,
    widgets: ..^Widget,
) -> (box: ^Widget) {
    box = new(Widget)
    widget_list := make([dynamic]^Widget)

    for widget in widgets {
        if widget.alignment_policy == {} {
            widget.alignment_policy = AlignmentPolicy{.Top, .Left}
        }
        append(&widget_list, widget)
    }
    box^ = Widget{
        z_index = z_index,
        min_w = attr.w,
        min_h = attr.h,
        init = init,
        update = update,
        draw = draw,
        data = Box{
            layout = layout,
            widgets = widget_list,
            scrollbars = scrollbars(),
            attr = attr,
        }
    }

    box.min_w = attr.min_w
    box.min_h = attr.min_h

    if .FixedW in attr.props {
        box.w = attr.w
        box.min_w = attr.w
    }

    if .FixedH in attr.props {
        box.h = attr.h
        box.min_h = attr.h
    }

    if .FixedW not_in attr.props && .FitW not_in attr.props {
        box.size_policy |= {.FillW}
    }
    if .FixedH not_in attr.props && .FitH not_in attr.props {
        box.size_policy |= {.FillH}
    }
    return box
}// }}}

vbox :: proc(widgets: ..^Widget, attr := BoxAttributes{}, z_index: u64 = 0) -> ^Widget {// {{{
    return box(.Vertical, attr, box_init, box_update, box_draw, z_index, ..widgets)
}// }}}

hbox :: proc(widgets: ..^Widget, attr := BoxAttributes{}, z_index: u64 = 0) -> ^Widget {// {{{
    return box(.Horizontal, attr, box_init, box_update, box_draw, z_index, ..widgets)
}// }}}

vbox_align :: proc(self: ^Widget, x, y: f32) {// {{{
    data := &self.data.(Box)
    left_x := x + data.attr.style.padding.left
    right_x := x + data.content_w - data.attr.style.padding.right
    top_y := y + data.attr.style.padding.top
    bottom_y := y + data.content_h - data.attr.style.padding.bottom

    for widget in data.widgets {
        if widget.disabled do continue
        wx, wy: f32

        if .FitH in data.attr.props {
            wy = top_y
            top_y += widget.h + data.attr.style.items_spacing
        } else {
            if .VCenter in widget.alignment_policy {
                wy = y + data.attr.style.padding.top + (data.content_h - widget.h) / 2.
            } else if .Bottom in widget.alignment_policy {
                wy = bottom_y - widget.h
                bottom_y -= widget.h + data.attr.style.items_spacing
            } else {
                wy = top_y
                top_y += widget.h + data.attr.style.items_spacing
            }
        }

        // since widgets are added in a column, there is no need to decrease the width
        if .FitW in data.attr.props {
            wx = left_x
        } else {
            if .HCenter in widget.alignment_policy {
                wx = x + data.attr.style.padding.left + (data.content_w - widget.w) / 2.
            } else if .Right in widget.alignment_policy {
                wx = right_x - widget.w
            } else {
                wx = left_x
            }
        }
        widget_align(widget, wx, wy)
    }
}// }}}

hbox_align :: proc(self: ^Widget, x, y: f32) {// {{{
    data := &self.data.(Box)
    left_x := x + data.attr.style.padding.left
    right_x := x + data.content_w - data.attr.style.padding.right
    top_y := y + data.attr.style.padding.top
    bottom_y := y + data.content_h - data.attr.style.padding.bottom

    for widget in data.widgets {
        if widget.disabled do continue
        wx, wy: f32

        // since widgets are added in a row, there is no need to decrease the height
        if .FitH in data.attr.props {
            wy = top_y
        } else {
            if .VCenter in widget.alignment_policy {
                wy = y + data.attr.style.padding.top + (data.content_h - widget.h) / 2.
            } else if .Bottom in widget.alignment_policy {
                wy = bottom_y - widget.h
            } else {
                wy = top_y
            }
        }

        if .FitW in data.attr.props {
            wx = left_x
            left_x += widget.w + data.attr.style.items_spacing
        } else {
            if .HCenter in widget.alignment_policy {
                wx = x + data.attr.style.padding.left + (data.content_w - widget.w) / 2.
            } else if .Right in widget.alignment_policy {
                wx = right_x - widget.w
                right_x -= widget.w + data.attr.style.items_spacing
            } else {
                wx = left_x
                left_x += widget.w + data.attr.style.items_spacing
            }
        }
        widget_align(widget, wx, wy)
    }
}// }}}

box_align :: proc(self: ^Widget, x, y: f32) {// {{{
    data := &self.data.(Box)
    if data.layout == .Vertical {
        vbox_align(self, x, y)
    } else {
        hbox_align(self, x, y)
    }
}// }}}

box_add_widget :: proc(box_widget: ^Widget, widget: ^Widget) {// {{{
    data := &box_widget.data.(Box)
    if widget.alignment_policy == {} {
        widget.alignment_policy = AlignmentPolicy{.Top, .Left}
    }
    append(&data.widgets, widget)
}// }}}

box_init :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {// {{{
    data := &self.data.(Box)

    for widget in data.widgets {
        widget->init(handle, self)
    }
    add_event_handler(handle, self, proc(self: ^Widget, event: MouseWheelEvent, handle: ^Handle) -> bool {
        if !widget_is_hovered(self, handle.mouse_x, handle.mouse_y) do return false
        data := &self.data.(Box)

        if event.mods == {} {
            scrollbars_scroll(&data.scrollbars, -event.y, 0, 100, 100)
            box_align(self, self.x - data.scrollbars.horizontal.position, self.y - data.scrollbars.vertical.position)
        }
        return true
    })
    add_event_handler(handle, self, proc(self: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
        data := &self.data.(Box)
        scrollbars_click(&data.scrollbars, event)
        return true
    })
    add_event_handler(handle, self, proc(self: ^Widget, event: MouseMotionEvent, handle: ^Handle) -> bool {
        data := &self.data.(Box)
        scrollbars_mouse_motion(&data.scrollbars, event)
        box_align(self, self.x - data.scrollbars.horizontal.position, self.y - data.scrollbars.vertical.position)
        return true
    })
}// }}}

box_find_content_w :: proc(self: ^Widget, parent_w: f32) -> (w: f32, ttl_w: f32, max_w: f32) {// {{{
    data := &self.data.(Box)
    padding_w := data.attr.style.padding.left + data.attr.style.padding.right
    ttl_w = padding_w
    has_widget_on_right := false

    for widget in data.widgets {
        if widget.disabled || .FillW in widget.size_policy do continue
        if .Right in widget.alignment_policy {
            has_widget_on_right = true
        }
        ww := widget.min_w
        max_w = max(max_w, ww)
        ttl_w += ww + data.attr.style.items_spacing
    }
    ttl_w -= data.attr.style.items_spacing
    w = max_w + padding_w if data.layout == .Vertical else ttl_w

    if has_widget_on_right {
        return max(w, parent_w), ttl_w, max_w
    }
    return w, ttl_w, max_w
}// }}}

box_find_content_h :: proc(self: ^Widget, parent_h: f32) -> (h: f32, ttl_h: f32, max_h: f32) {// {{{
    data := &self.data.(Box)
    padding_h := data.attr.style.padding.top + data.attr.style.padding.bottom
    ttl_h = padding_h
    has_widget_on_bottom := false

    for widget in data.widgets {
        if widget.disabled || .FillH in widget.size_policy do continue
        if .Bottom in widget.alignment_policy {
            has_widget_on_bottom = true
        }
        wh := widget.min_h
        max_h = max(max_h, wh)
        ttl_h += wh + data.attr.style.items_spacing
    }
    h = ttl_h - data.attr.style.items_spacing if data.layout == .Vertical else max_h + padding_h

    if has_widget_on_bottom {
        return max(h, parent_h), ttl_h, max_h
    }
    return h, ttl_h, max_h
}// }}}

box_resize_widget :: proc(widget: ^Widget, w, h: f32) {// {{{
    if widget.disabled do return
    if .FillW not_in widget.size_policy {
        widget.w = min(widget.min_w, w)
    }
    if .FillH not_in widget.size_policy {
        widget.h = min(widget.min_h, h)
    }
    #partial switch _ in widget.data {
    case Box: box_resize(widget, w, h)
    }
}// }}}

box_expand_widget :: proc(widget: ^Widget, w, h: f32) {// {{{
    if widget.disabled do return
    widget.w = w
    widget.h = h
    #partial switch _ in widget.data {
    case Box: box_resize(widget, w, h)
    }
}// }}}

box_update_size :: proc(self: ^Widget, w, h: f32) {// {{{
    data := &self.data.(Box)
    if .FixedW not_in data.attr.props {
        if .FitW in data.attr.props {
            self.w = data.content_w
            self.min_w = data.content_w
        } else {
            self.w = w
            data.content_w = max(data.content_w, self.w)
        }
        self.w = max(self.min_w, self.w)
    }
    if .FixedH not_in data.attr.props {
        if .FitH in data.attr.props {
            self.h = data.content_h
            self.min_h = data.content_h
        } else {
            self.h = h
            data.content_h = max(data.content_h, self.h)
        }
        self.h = max(self.min_h, self.h)
    }

    bt := data.attr.style.border_thickness
    if .Top in data.attr.style.active_borders {
        self.h += bt
        self.min_h += bt
    }
    if .Bottom in data.attr.style.active_borders {
        self.h += bt
        self.min_h += bt
    }
    if .Left in data.attr.style.active_borders {
        self.w += bt
        self.min_w += bt
    }
    if .Right in data.attr.style.active_borders {
        self.w += bt
        self.min_w += bt
    }
}// }}}

vbox_resize :: proc(self: ^Widget, w, h: f32) {// {{{
    data := &self.data.(Box)
    ttl_w, max_w, ttl_h, max_h: f32
    nb_expandable_widgets := 0

    for widget in data.widgets {
        if widget.disabled do continue
        box_resize_widget(widget, w, h)
        if .FillH in widget.size_policy {
            nb_expandable_widgets += 1
        }
    }

    data.content_w, ttl_w, max_w = box_find_content_w(self, w)
    data.content_h, ttl_h, max_h = box_find_content_h(self, h)
    box_update_size(self, w, h)

    remaining_h := self.h - ttl_h - data.attr.style.items_spacing * cast(f32)nb_expandable_widgets
    for widget in data.widgets {
        if widget.disabled do continue
        if .FillW not_in widget.size_policy && .FillH not_in widget.size_policy do continue
        ww, wh := widget.w, widget.h
        if .FillW in widget.size_policy {
            ww = self.w
        }
        if .FillH in widget.size_policy {
            wh = remaining_h / cast(f32)nb_expandable_widgets
        }
        box_expand_widget(widget, ww, wh)
    }
}// }}}

hbox_resize :: proc(self: ^Widget, w, h: f32) {// {{{
    data := &self.data.(Box)
    ttl_w, max_w, ttl_h, max_h: f32
    nb_expandable_widgets := 0

    for widget in data.widgets {
        if widget.disabled do continue
        box_resize_widget(widget, w, h)
        if .FillW in widget.size_policy {
            nb_expandable_widgets += 1
        }
    }

    data.content_w, ttl_w, max_w = box_find_content_w(self, w)
    data.content_h, ttl_h, max_h = box_find_content_h(self, h)
    box_update_size(self, w, h)

    remaining_w := self.w - ttl_w - data.attr.style.items_spacing * cast(f32)nb_expandable_widgets
    for widget in data.widgets {
        if widget.disabled do continue
        if .FillW not_in widget.size_policy && .FillH not_in widget.size_policy do continue
        ww, wh := widget.w, widget.h
        if .FillW in widget.size_policy {
            ww = remaining_w / cast(f32)nb_expandable_widgets
        }
        if .FillH in widget.size_policy {
            wh = self.h
        }
        box_expand_widget(widget, ww, wh)
    }
}// }}}

box_resize :: proc(self: ^Widget, w, h: f32) {// {{{
    data := &self.data.(Box)

    if data.layout == .Vertical {
        vbox_resize(self, w, h)
    } else {
        hbox_resize(self, w, h)
    }

    data.scrollbars.vertical.enabled = data.content_h > self.h
    if !data.scrollbars.vertical.enabled {
        data.scrollbars.vertical.position = 0
        data.scrollbars.vertical.target_position = 0
    }
    data.scrollbars.horizontal.enabled = data.content_w > self.w
    if !data.scrollbars.horizontal.enabled {
        data.scrollbars.horizontal.position = 0
        data.scrollbars.horizontal.target_position = 0
    }
    scrollbars_resize(&data.scrollbars, self.w, self.h, data.content_w, data.content_h)
    scrollbars_align(&data.scrollbars, self.x, self.y)
}// }}}

box_update :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {// {{{
    data := &self.data.(Box)

    for widget in data.widgets {
        if widget.update != nil && !widget.disabled {
            widget->update(handle, self)
        }
    }
    scrollbars_update(&data.scrollbars, handle)
}// }}}

box_draw :: proc(self: ^Widget, handle: ^Handle) {// {{{
    data := &self.data.(Box)

    if data.attr.style.background_color.a > 0 {
        draw_rect(handle, self.x, self.y, self.w, self.h, data.attr.style.background_color)
    }

    for widget in data.widgets {
        widget_draw(widget, handle)
    }
    scrollbars_draw(&data.scrollbars, handle)

    bt := data.attr.style.border_thickness
    bc := data.attr.style.border_color
    if .Top in data.attr.style.active_borders {
        draw_rect(handle, self.x, self.y, self.w, bt, bc)
    }
    if .Bottom in data.attr.style.active_borders {
        draw_rect(handle, self.x, self.y + self.h - bt, self.w, bt, bc)
    }
    if .Left in data.attr.style.active_borders {
        draw_rect(handle, self.x, self.y, bt, self.h, bc)
    }
    if .Right in data.attr.style.active_borders {
        draw_rect(handle, self.x + self.w - bt, self.y, bt, self.h, bc)
    }
}// }}}

// align functions //

align_widgets :: proc(widget: ^Widget, alignment_policy: = AlignmentPolicy{.Top, .Left}) -> (result: ^Widget) {
    widget.alignment_policy = alignment_policy
    return widget
}

center :: proc(widget: ^Widget) -> ^Widget {
    return align_widgets(widget, alignment_policy = AlignmentPolicy{.HCenter, .VCenter})
}

// radio button ////////////////////////////////////////////////////////////////

RadioButtonStyle :: struct {
    base_radius: f32,
    border_thickness: f32,
    dot_radius: f32,
    border_color: Color,
    background_color: Color,
    dot_color: Color,
    label_padding: f32,
    label_color: Color,
    font: string,
    font_size: su.FontSize,
}

RadioButtonAttributes :: struct {
    style: RadioButtonStyle,
}

RadioButton :: struct {
    checked: bool,
    label: string,
    label_text: su.Text,
    button_offset: f32,
    label_offset: f32,
    attr: RadioButtonAttributes,
}

radio_button :: proc(
    label: string,
    attr := OPTS.radio_button_attr,
    default_checked := false,
) -> (radio_button: ^Widget) {
    radio_button = new(Widget)
    radio_button^ = Widget{
        init = radio_button_init,
        update = radio_button_update,
        draw = radio_button_draw,
        data = RadioButton {
            checked = default_checked,
            label = label,
            attr = attr,
        }
    }
    return radio_button
}

radio_button_init :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    data := &self.data.(RadioButton)

    data.label_text = su.text_create(
        handle.text_engine,
        su.font_cache_get_font(&handle.font_cache, data.attr.style.font, data.attr.style.font_size),
        data.label)
    label_color := su.Color{
        data.attr.style.label_color.r,
        data.attr.style.label_color.g,
        data.attr.style.label_color.b,
        data.attr.style.label_color.a,
    }
    su.text_update_color(&data.label_text, label_color)
    label_w, label_h := su.text_size(&data.label_text)

    d := 2 * data.attr.style.base_radius
    self.w = d + data.attr.style.label_padding + label_w
    self.h = max(d, label_h)
    self.min_w = self.w
    self.min_h = self.h
    if label_h > d {
        data.button_offset = (label_h - d) / 2
    } else {
        data.label_offset = (d - label_h) / 2
    }

    add_event_handler(handle, self, proc(self: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
        data := &self.data.(RadioButton)
        button_size := 2 * data.attr.style.base_radius
        button_x := self.x
        button_y := self.y + data.button_offset
        if event.down && event.button == sdl.BUTTON_LEFT && mouse_on_region(event.x, event.y, button_x, button_y, button_size, button_size) {
            data.checked = !data.checked
            return true
        }
        return false
    })
}

radio_button_update :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {}

radio_button_draw :: proc(self: ^Widget, handle: ^Handle) {
    data := &self.data.(RadioButton)

    r := data.attr.style.base_radius
    bgr := data.attr.style.base_radius - data.attr.style.border_thickness
    dr := data.attr.style.dot_radius
    by := self.y + data.button_offset + r
    bx := self.x + r
    if data.attr.style.border_thickness > 0 {
        draw_circle(handle, bx, by, r, data.attr.style.border_color)
    }
    draw_circle(handle, bx, by, bgr, data.attr.style.background_color)
    if data.checked {
        draw_circle(handle, bx, by, dr, data.attr.style.dot_color)
    }

    text_xoffset := 2 * r + data.attr.style.label_padding
    text_yoffset := data.label_offset
    draw_text(handle, &data.label_text, self.x + text_xoffset, self.y + text_yoffset)
}

radio_button_get_value :: proc(self: ^Widget) -> bool {
    data := &self.data.(RadioButton)
    return data.checked
}

radio_button_set_value :: proc(self: ^Widget, value: bool) {
    data := &self.data.(RadioButton)
    data.checked = value
}

radio_button_value :: proc{
    radio_button_get_value,
    radio_button_set_value,
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

DrawBoxAttributes :: struct {
    props: DrawBoxProperties,
    zoom_min, zoom_max, zoom_step: f32,
    scrollbars_attr: ScrollbarsAttributes,
}

DrawBox :: struct {
    content_size: ContentSize,
    zoombox: ZoomBox,
    scrollbars: Scrollbars,
    user_init: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    user_update: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) -> ContentSize,
    user_draw: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    user_data: rawptr,
    attr: DrawBoxAttributes,
}

draw_box :: proc(
    draw: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    update: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) -> ContentSize = nil,
    init: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) = nil,
    data: rawptr = nil,
    attr := OPTS.draw_box_attr,
) -> (draw_box: ^Widget) {
    draw_box = new(Widget)
    draw_box^ = Widget{
        size_policy = {.FillW, .FillH},
        init = draw_box_init,
        update = draw_box_update,
        draw = draw_box_draw,
        data = DrawBox{
            zoombox = zoombox(attr.zoom_min, attr.zoom_max, attr.zoom_step),
            scrollbars = scrollbars(attr.scrollbars_attr),
            user_draw = draw,
            user_init = init,
            user_update = update,
            user_data = data,
            attr = attr,
        }
    }
    return draw_box
}

draw_box_init :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    data := &self.data.(DrawBox)

    if data.user_init != nil {
        data.user_init(handle, self, data.user_data)
    }

    zoombox_init(&data.zoombox, self)

    add_event_handler(handle, self, proc(self: ^Widget, event: KeyEvent, handle: ^Handle) -> bool {
        if !event.down do return false
        data := &self.data.(DrawBox)

        vcount, hcount: i32

        switch event.key {
        case sdl.K_H: hcount = -1
        case sdl.K_L: hcount = 1
        case sdl.K_K: vcount = -1
        case sdl.K_J: vcount = 1
        }
        scrollbars_scroll(&data.scrollbars, vcount, hcount, 100, 100)
        return true
    })
    add_event_handler(handle, self, proc(self: ^Widget, event: MouseWheelEvent, handle: ^Handle) -> bool {
        if !widget_is_hovered(self, handle.mouse_x, handle.mouse_y) do return false
        data := &self.data.(DrawBox)

        if .Control in event.mods && .Zoomable in data.attr.props {
            return zoombox_zoom_handler(&data.zoombox, event.x, event.y, event.mods)
        } else if .WithScrollbar in data.attr.props {
            scrollbars_scroll(&data.scrollbars, -event.y, 0, 100, 100)
        }
        return true
    })
    add_event_handler(handle, self, proc(self: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
        data := &self.data.(DrawBox)
        if .WithScrollbar not_in data.attr.props do return false
        scrollbars_click(&data.scrollbars, event)
        return true
    })
    add_event_handler(handle, self, proc(self: ^Widget, event: MouseMotionEvent, handle: ^Handle) -> bool {
        data := &self.data.(DrawBox)
        if .WithScrollbar not_in data.attr.props do return false
        scrollbars_mouse_motion(&data.scrollbars, event)
        return true
    })
}

draw_box_update :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    data := &self.data.(DrawBox)
    if data.user_update != nil {
        data.content_size = data.user_update(handle, self, data.user_data)
    }
    if .WithScrollbar in data.attr.props {
        scrollbars_resize(&data.scrollbars, self.w, self.h, data.content_size.width, data.content_size.height)
        scrollbars_align(&data.scrollbars, self.x, self.y)
        scrollbars_update(&data.scrollbars, handle)
    }
}

draw_box_draw :: proc(self: ^Widget, handle: ^Handle) {
    data := &self.data.(DrawBox)
    old_rel_rect := handle.rel_rect
    handle.rel_rect = Rect{self.x, self.y, self.w, self.h}
    data.user_draw(handle, self, data.user_data)
    handle.rel_rect = old_rel_rect
    if .WithScrollbar in data.attr.props {
        scrollbars_draw(&data.scrollbars, handle)
    }
}
