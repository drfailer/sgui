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
import sdl_img "vendor:sdl3/image"
import "core:strings"
import "core:log"

Pixel :: distinct [4]u8

// widget //////////////////////////////////////////////////////////////////////

WidgetInitProc :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget)
WidgetDestroyProc :: proc(widget: ^Widget, handle: ^Handle)
WidgetUpdateProc :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget)
WidgetDrawProc :: proc(widget: ^Widget, handle: ^Handle)
WidgetResizeProc :: proc(widget: ^Widget, pw, ph: f32)
WidgetAlignProc :: proc(widget: ^Widget, px, py: f32)

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
    destroy: WidgetDestroyProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,
    resize: WidgetResizeProc,
    align: WidgetAlignProc,
}

widget_init :: proc(widget: ^Widget, handle: ^Handle) {
    if widget.init == nil do return
    root := Widget{
        x = 0,
        y = 0,
        w = cast(f32)handle.window_w,
        h = cast(f32)handle.window_h,
    }
    widget->init(handle, &root)
    widget_resize(widget, handle)
}

widget_destroy :: proc(widget: ^Widget, handle: ^Handle) {
    if widget.destroy == nil do return
    widget->destroy(handle)
}

widget_resize :: proc(widget: ^Widget, handle: ^Handle) {
    if widget.disabled do return
    if .FillW in widget.size_policy {
        widget.w = handle.window_w
    }
    if .FillH in widget.size_policy {
        widget.h = handle.window_h
    }
    if widget.resize != nil {
        widget->resize(handle.window_w, handle.window_h)
    }
    widget_align(widget, 0, 0)
}

widget_align :: proc(widget: ^Widget, x, y: f32) {
    widget.x = x
    widget.y = y
    if widget.align != nil {
        widget->align(x, y)
    }
}

widget_update :: proc(handle: ^Handle, widget: ^Widget) {
    if widget.update == nil do return
    root := Widget{
        x = handle.rel_rect.x,
        y = handle.rel_rect.y,
        w = handle.rel_rect.w,
        h = handle.rel_rect.h,
    }
    widget->update(handle, &root)
}

widget_draw :: proc(widget: ^Widget, handle: ^Handle) {
    // if widget.draw == nil do return // assume it is never the case
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

Tabs :: struct {
}

Menu :: struct { // top menu
}

Line :: struct { // separator line
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
    using widget: Widget,
    text: ^su.Text,
    content: string,
    content_proc: proc(data: rawptr) -> (string, Color),
    content_proc_data: rawptr,
    attr: TextAttributes,
}

text_from_string :: proc(content: string, attr := OPTS.text_attr) -> ^Widget {
    text_w := new(Text)
    text_w^ = Text{
        init = text_init,
        update = text_update,
        draw = text_draw,
        content = content,
        attr = attr,
    }
    return text_w
}

text_from_proc :: proc(
    content_proc: proc(data: rawptr) -> (string, Color),
    content_proc_data: rawptr,
    attr := OPTS.text_attr,
) -> ^Widget {
    text_w := new(Text)
    text_w^ = Text{
        init = text_init,
        update = text_update,
        draw = text_draw,
        content_proc = content_proc,
        content_proc_data = content_proc_data,
        attr = attr
    }
    return text_w
}

// TODO: create a printf like version
text :: proc {
    text_from_string,
    text_from_proc,
}

text_init :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^Text)widget
    self.text = create_text(handle, self.content, self.attr.style.font, self.attr.style.font_size)
    su.text_set_color(self.text, su.Color{
        self.attr.style.color.r,
        self.attr.style.color.g,
        self.attr.style.color.b,
        self.attr.style.color.a
    })
    su.text_update(self.text)
    w, h := su.text_size(self.text)
    self.w = w
    self.h = h
    self.min_w = w
    self.min_h = h
}

text_update :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^Text)widget
    if self.content_proc != nil {
        content, color := self.content_proc(self.content_proc_data)
        su.text_set_text(self.text, content)
        su.text_set_color(self.text, sdl.Color{color.r, color.g, color.b, color.a})
        if self.attr.style.wrap_width > 0 {
            su.text_set_wrap_width(self.text, self.attr.style.wrap_width)
        }
        su.text_update(self.text)
        w, h := su.text_size(self.text)
        if w > self.w || h > self.h {
            handle.resize = true
        }
        self.w = w
        self.h = h
        self.min_w = w
        self.min_h = h
    }
}

text_draw :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^Text)widget
    draw_text(handle, self.text, self.x, self.y)
}

// image ///////////////////////////////////////////////////////////////////////

// TODO: add a custom size for the texture
// can the size be relative to the original image size (ratio?)???
// also need some helper functions to handle textures in draw boxes (not so
// sure that this specific widget will be very useful for anything else that
// printing a logo)
Image :: struct {
    using widget: Widget,
    file: string,
    image: ^su.Image,
    srcrect: Rect,
    iw, ih: f32,
}

image :: proc(
    file: string,
    w: f32 = 0,
    h: f32 = 0,
    srcrect := Rect{0, 0, 0, 0},
) -> ^Widget {
    image_w := new(Image)
    image_w^ = Image{
        init = image_init,
        destroy = image_destroy,
        draw = image_draw,
        file = file,
        srcrect = srcrect,
        iw = w,
        ih = h,
    }
    return image_w
}

image_init :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^Image)widget
    self.image = create_image(handle, self.file, self.srcrect)
    w := self.image.w if self.iw == 0 else self.iw
    self.w = w
    self.min_w = w
    h := self.image.h if self.ih == 0 else self.ih
    self.h = h
    self.min_h = h
}

image_destroy :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^Image)widget
    su.image_destroy(self.image)
}

image_draw :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^Image)widget
    draw_image(handle, self.image, self.x, self.y, self.w, self.h)
}

// button //////////////////////////////////////////////////////////////////////

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

IconData :: struct {
    file: string,
    srcrect: Rect,
}

Button :: struct {
    using widget: Widget,
    label: string,
    text: ^su.Text,
    state: ButtonState,
    clicked: ButtonClickedProc,
    clicked_data: rawptr,
    attr: ButtonAttributes,
    icons_data: [ButtonState]IconData,
    icons_image: [ButtonState]^su.Image,
    iw, ih: f32,
}

button :: proc(
    label: string,
    clicked: ButtonClickedProc,
    clicked_data: rawptr = nil,
    attr := OPTS.button_attr,
) -> ^Widget {
    button_w := new(Button)
    button_w^ = Button{
        init = button_init,
        update = button_update,
        draw = button_draw,
        label = label,
        clicked = clicked,
        clicked_data = clicked_data,
        attr = attr,
    }
    if attr.expand_w {
        button_w.size_policy |= {.FillW}
    }
    if attr.expand_h {
        button_w.size_policy |= {.FillH}
    }
    return button_w
}

icon_button_all_states :: proc(
    icons_data: [ButtonState]IconData,
    clicked: ButtonClickedProc,
    w: f32 = 0,
    h: f32 = 0,
    clicked_data: rawptr = nil,
    attr := OPTS.button_attr,
) -> ^Widget {
    button_w := cast(^Button)button(icons_data[.Idle].file, clicked, clicked_data, attr)
    button_w.icons_data = icons_data
    button_w.iw = w
    button_w.ih = h
    button_w.init = icon_button_init
    button_w.destroy = icon_button_destroy
    button_w.draw = icon_button_draw
    return button_w
}

icon_button_idle_state :: proc(
    icon: IconData,
    clicked: ButtonClickedProc,
    w: f32 = 0,
    h: f32 = 0,
    clicked_data: rawptr = nil,
    attr := OPTS.button_attr,
) -> ^Widget {
    icons_data := [ButtonState]IconData{ .Idle = icon, .Hovered = icon, .Clicked = icon }
    return icon_button_all_states(icons_data, clicked, w, h, clicked_data, attr)
}

icon_button :: proc{
    icon_button_all_states,
    icon_button_idle_state,
}

button_mouse_handler :: proc(widget: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
    if event.button != sdl.BUTTON_LEFT || !widget_is_hovered(widget, event.x, event.y) do return false
    self := cast(^Button)widget

    if event.down {
        self.state = .Clicked
    } else if self.state == .Clicked {
        self.state = .Idle
        self.clicked(handle, self.clicked_data)
    }
    return true
}

button_init :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^Button)widget
    self.text = create_text(handle, self.label, self.attr.style.label_font_path, self.attr.style.label_font_size)
    self.w, self.h = su.text_size(self.text)
    self.w += self.attr.style.padding.left + self.attr.style.padding.right
    self.h += self.attr.style.padding.top + self.attr.style.padding.bottom
    self.min_w = self.w
    self.min_h = self.h
    add_event_handler(handle, self, button_mouse_handler)
}

icon_button_init :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^Button)widget
    self.icons_image[.Idle] = create_image(handle, self.icons_data[.Idle].file, self.icons_data[.Idle].srcrect)
    self.icons_image[.Hovered] = create_image(handle, self.icons_data[.Hovered].file, self.icons_data[.Hovered].srcrect)
    self.icons_image[.Clicked] = create_image(handle, self.icons_data[.Clicked].file, self.icons_data[.Clicked].srcrect)
    assert(self.icons_image[.Clicked].w == self.icons_image[.Idle].w)
    assert(self.icons_image[.Clicked].h == self.icons_image[.Idle].h)
    assert(self.icons_image[.Hovered].w == self.icons_image[.Idle].w)
    assert(self.icons_image[.Hovered].h == self.icons_image[.Idle].h)
    w := self.icons_image[.Idle].w if self.iw == 0 else self.iw
    w += self.attr.style.padding.left + self.attr.style.padding.right
    self.w = w
    self.min_w = w
    h := self.icons_image[.Idle].h if self.ih == 0 else self.ih
    h += self.attr.style.padding.top + self.attr.style.padding.bottom
    self.h = h
    self.min_h = h
    add_event_handler(handle, self, button_mouse_handler)
}

icon_button_destroy :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^Button)widget
    su.image_destroy(self.icons_image[.Idle])
    su.image_destroy(self.icons_image[.Hovered])
    su.image_destroy(self.icons_image[.Clicked])
}

button_update :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^Button)widget
    if widget_is_hovered(self, handle.mouse_x, handle.mouse_y) {
        if self.state == .Idle {
            self.state = .Hovered
        }
    } else {
        self.state = .Idle
    }
}

button_draw_background :: proc(self: ^Button, handle: ^Handle) {
    bg_color := self.attr.style.colors[self.state].bg
    border_color := self.attr.style.colors[self.state].border
    border_thickness := self.attr.style.border_thickness

    if self.attr.style.corner_radius > 0 {
        if border_thickness > 0 {
            draw_rounded_box_with_border(handle, self.x, self.y, self.w, self.h,
                                         self.attr.style.corner_radius, border_thickness,
                                         border_color, bg_color)
        } else {
            draw_rounded_box(handle, self.x + border_thickness, self.y + border_thickness,
                             self.w - 2 * border_thickness, self.h - 2 * border_thickness,
                             self.attr.style.corner_radius, bg_color)
        }
    } else {
        if border_thickness > 0 {
            draw_rect(handle, self.x, self.y, self.w, self.h, border_color)
        }
        draw_rect(handle, self.x + border_thickness, self.y + border_thickness,
                          self.w - 2 * border_thickness, self.h - 2 * border_thickness,
                          bg_color)
    }
}

button_draw :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^Button)widget
    text_color := self.attr.style.colors[self.state].text

    su.text_set_color(self.text, sdl.Color{text_color.r, text_color.g, text_color.b, text_color.a})
    su.text_update(self.text)
    button_draw_background(self, handle)
    label_w, label_h := su.text_size(self.text)
    label_x := self.x + (self.w - label_w) / 2.
    label_y := self.y + (self.h - label_h) / 2.
    draw_text(handle, self.text, label_x, label_y)
}

icon_button_draw :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^Button)widget
    button_draw_background(self, handle)
    icon_x := self.x + (self.w - self.iw) / 2.
    icon_y := self.y + (self.h - self.ih) / 2.
    draw_image(handle, self.icons_image[self.state], icon_x, icon_y, self.iw, self.ih)
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
    using widget: Widget,
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
    destroy: WidgetDestroyProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,
    z_index: u64,
    widgets: ..^Widget,
) -> ^Widget {
    box_w := new(Box)
    widget_list := make([dynamic]^Widget)

    for widget in widgets {
        if widget.alignment_policy == {} {
            widget.alignment_policy = AlignmentPolicy{.Top, .Left}
        }
        append(&widget_list, widget)
    }
    box_w^ = Box{
        z_index = z_index,
        min_w = attr.w,
        min_h = attr.h,
        init = init,
        destroy = destroy,
        update = update,
        draw = draw,
        resize = box_resize,
        align = box_align,
        layout = layout,
        widgets = widget_list,
        scrollbars = scrollbars(),
        attr = attr,
    }

    box_w.min_w = attr.min_w
    box_w.min_h = attr.min_h

    if .FixedW in attr.props {
        box_w.w = attr.w
        box_w.min_w = attr.w
    }

    if .FixedH in attr.props {
        box_w.h = attr.h
        box_w.min_h = attr.h
    }

    if .FixedW not_in attr.props && .FitW not_in attr.props {
        box_w.size_policy |= {.FillW}
    }
    if .FixedH not_in attr.props && .FitH not_in attr.props {
        box_w.size_policy |= {.FillH}
    }
    return box_w
}// }}}

vbox :: proc(widgets: ..^Widget, attr := BoxAttributes{}, z_index: u64 = 0) -> ^Widget {// {{{
    return box(.Vertical, attr, box_init, box_destroy, box_update, box_draw, z_index, ..widgets)
}// }}}

hbox :: proc(widgets: ..^Widget, attr := BoxAttributes{}, z_index: u64 = 0) -> ^Widget {// {{{
    return box(.Horizontal, attr, box_init, box_destroy, box_update, box_draw, z_index, ..widgets)
}// }}}

vbox_align :: proc(widget: ^Widget, x, y: f32) {// {{{
    self := cast(^Box)widget
    left_x := x + self.attr.style.padding.left
    right_x := x + self.content_w - self.attr.style.padding.right
    top_y := y + self.attr.style.padding.top
    bottom_y := y + self.content_h - self.attr.style.padding.bottom

    for child in self.widgets {
        if child.disabled do continue
        wx, wy: f32

        if .FitH in self.attr.props {
            wy = top_y
            top_y += child.h + self.attr.style.items_spacing
        } else {
            if .VCenter in child.alignment_policy {
                wy = y + self.attr.style.padding.top + (self.content_h - child.h) / 2.
            } else if .Bottom in child.alignment_policy {
                wy = bottom_y - child.h
                bottom_y -= child.h + self.attr.style.items_spacing
            } else {
                wy = top_y
                top_y += child.h + self.attr.style.items_spacing
            }
        }

        // since widgets are added in a column, there is no need to decrease the width
        if .FitW in self.attr.props {
            wx = left_x
        } else {
            if .HCenter in child.alignment_policy {
                wx = x + self.attr.style.padding.left + (self.content_w - child.w) / 2.
            } else if .Right in child.alignment_policy {
                wx = right_x - child.w
            } else {
                wx = left_x
            }
        }
        widget_align(child, wx, wy)
    }
}// }}}

hbox_align :: proc(widget: ^Widget, x, y: f32) {// {{{
    self := cast(^Box)widget
    left_x := x + self.attr.style.padding.left
    right_x := x + self.content_w - self.attr.style.padding.right
    top_y := y + self.attr.style.padding.top
    bottom_y := y + self.content_h - self.attr.style.padding.bottom

    for child in self.widgets {
        if child.disabled do continue
        wx, wy: f32

        // since widgets are added in a row, there is no need to decrease the height
        if .FitH in self.attr.props {
            wy = top_y
        } else {
            if .VCenter in child.alignment_policy {
                wy = y + self.attr.style.padding.top + (self.content_h - child.h) / 2.
            } else if .Bottom in child.alignment_policy {
                wy = bottom_y - child.h
            } else {
                wy = top_y
            }
        }

        if .FitW in self.attr.props {
            wx = left_x
            left_x += child.w + self.attr.style.items_spacing
        } else {
            if .HCenter in child.alignment_policy {
                wx = x + self.attr.style.padding.left + (self.content_w - child.w) / 2.
            } else if .Right in child.alignment_policy {
                wx = right_x - child.w
                right_x -= child.w + self.attr.style.items_spacing
            } else {
                wx = left_x
                left_x += child.w + self.attr.style.items_spacing
            }
        }
        widget_align(child, wx, wy)
    }
}// }}}

box_align :: proc(widget: ^Widget, x, y: f32) {// {{{
    self := cast(^Box)widget
    x, y := x, y
    if self.scrollbars.vertical.enabled {
        y -= self.scrollbars.vertical.position
    }
    if self.scrollbars.horizontal.enabled {
        x -= self.scrollbars.horizontal.position
    }
    if self.layout == .Vertical {
        vbox_align(self, x, y)
    } else {
        hbox_align(self, x, y)
    }
    scrollbars_align(&self.scrollbars, self.x, self.y)
}// }}}

box_add_widget :: proc(widget: ^Widget, child: ^Widget) {// {{{
    self := cast(^Box)widget
    if child.alignment_policy == {} {
        child.alignment_policy = AlignmentPolicy{.Top, .Left}
    }
    append(&self.widgets, child)
}// }}}

box_init :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {// {{{
    self := cast(^Box)widget

    for child in self.widgets {
        if child.init != nil {
            child->init(handle, self)
        }
    }
    add_event_handler(handle, self, proc(widget: ^Widget, event: MouseWheelEvent, handle: ^Handle) -> bool {
        if !widget_is_hovered(widget, handle.mouse_x, handle.mouse_y) do return false
        self := cast(^Box)widget

        if event.mods == {} {
            scrollbars_scroll(&self.scrollbars, -event.y, 0, 100, 100)
            box_align(self, self.x, self.y)
        }
        return true
    })
    add_event_handler(handle, self, proc(widget: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
        self := cast(^Box)widget
        scrollbars_click(&self.scrollbars, event)
        return true
    })
    add_event_handler(handle, self, proc(widget: ^Widget, event: MouseMotionEvent, handle: ^Handle) -> bool {
        self := cast(^Box)widget
        scrollbars_mouse_motion(&self.scrollbars, event)
        box_align(self, self.x, self.y)
        return true
    })
}// }}}

box_destroy :: proc(widget: ^Widget, handle: ^Handle) {// {{{
    self := cast(^Box)widget

    for child in self.widgets {
        widget_destroy(child, handle)
    }
}// }}}

box_find_content_w :: proc(widget: ^Widget, parent_w: f32) -> (w: f32, ttl_w: f32, max_w: f32) {// {{{
    self := cast(^Box)widget
    padding_w := self.attr.style.padding.left + self.attr.style.padding.right
    ttl_w = padding_w
    has_widget_on_right := false

    for widget in self.widgets {
        if widget.disabled || .FillW in widget.size_policy do continue
        if .Right in widget.alignment_policy {
            has_widget_on_right = true
        }
        ww := widget.min_w
        max_w = max(max_w, ww)
        ttl_w += ww + self.attr.style.items_spacing
    }
    ttl_w -= self.attr.style.items_spacing
    w = max_w + padding_w if self.layout == .Vertical else ttl_w

    if has_widget_on_right {
        return max(w, parent_w), ttl_w, max_w
    }
    return w, ttl_w, max_w
}// }}}

box_find_content_h :: proc(widget: ^Widget, parent_h: f32) -> (h: f32, ttl_h: f32, max_h: f32) {// {{{
    self := cast(^Box)widget
    padding_h := self.attr.style.padding.top + self.attr.style.padding.bottom
    ttl_h = padding_h
    has_widget_on_bottom := false

    for widget in self.widgets {
        if widget.disabled || .FillH in widget.size_policy do continue
        if .Bottom in widget.alignment_policy {
            has_widget_on_bottom = true
        }
        wh := widget.min_h
        max_h = max(max_h, wh)
        ttl_h += wh + self.attr.style.items_spacing
    }
    h = ttl_h - self.attr.style.items_spacing if self.layout == .Vertical else max_h + padding_h

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
    if widget.resize != nil {
        widget->resize(w, h)
    }
}// }}}

box_expand_widget :: proc(widget: ^Widget, w, h: f32) {// {{{
    if widget.disabled do return
    widget.w = w
    widget.h = h
    if widget.resize != nil {
        widget->resize(w, h)
    }
}// }}}

box_update_size :: proc(widget: ^Widget, w, h: f32) {// {{{
    self := cast(^Box)widget
    if .FixedW not_in self.attr.props {
        if .FitW in self.attr.props {
            self.w = self.content_w
            self.min_w = self.content_w
        } else {
            self.w = w
            self.content_w = max(self.content_w, self.w)
        }
        self.w = max(self.min_w, self.w)
    }
    if .FixedH not_in self.attr.props {
        if .FitH in self.attr.props {
            self.h = self.content_h
            self.min_h = self.content_h
        } else {
            self.h = h
            self.content_h = max(self.content_h, self.h)
        }
        self.h = max(self.min_h, self.h)
    }

    bt := self.attr.style.border_thickness
    if .Top in self.attr.style.active_borders {
        self.h += bt
        self.min_h += bt
    }
    if .Bottom in self.attr.style.active_borders {
        self.h += bt
        self.min_h += bt
    }
    if .Left in self.attr.style.active_borders {
        self.w += bt
        self.min_w += bt
    }
    if .Right in self.attr.style.active_borders {
        self.w += bt
        self.min_w += bt
    }
}// }}}

vbox_resize :: proc(widget: ^Widget, w, h: f32) {// {{{
    self := cast(^Box)widget
    ttl_w, max_w, ttl_h, max_h: f32
    nb_expandable_widgets := 0

    for child in self.widgets {
        if child.disabled do continue
        box_resize_widget(child, w, h)
        if .FillH in child.size_policy {
            nb_expandable_widgets += 1
        }
    }

    self.content_w, ttl_w, max_w = box_find_content_w(self, w)
    self.content_h, ttl_h, max_h = box_find_content_h(self, h)
    box_update_size(self, w, h)

    remaining_h := self.h - ttl_h - self.attr.style.items_spacing * cast(f32)nb_expandable_widgets
    for child in self.widgets {
        if child.disabled do continue
        if .FillW not_in child.size_policy && .FillH not_in child.size_policy do continue
        ww, wh := child.w, child.h
        if .FillW in child.size_policy {
            ww = self.w
        }
        if .FillH in child.size_policy {
            wh = remaining_h / cast(f32)nb_expandable_widgets
        }
        box_expand_widget(child, ww, wh)
    }
}// }}}

hbox_resize :: proc(widget: ^Widget, w, h: f32) {// {{{
    self := cast(^Box)widget
    ttl_w, max_w, ttl_h, max_h: f32
    nb_expandable_widgets := 0

    for child in self.widgets {
        if child.disabled do continue
        box_resize_widget(child, w, h)
        if .FillW in child.size_policy {
            nb_expandable_widgets += 1
        }
    }

    self.content_w, ttl_w, max_w = box_find_content_w(self, w)
    self.content_h, ttl_h, max_h = box_find_content_h(self, h)
    box_update_size(self, w, h)

    remaining_w := self.w - ttl_w - self.attr.style.items_spacing * cast(f32)nb_expandable_widgets
    for child in self.widgets {
        if child.disabled do continue
        if .FillW not_in child.size_policy && .FillH not_in child.size_policy do continue
        ww, wh := child.w, child.h
        if .FillW in child.size_policy {
            ww = remaining_w / cast(f32)nb_expandable_widgets
        }
        if .FillH in child.size_policy {
            wh = self.h
        }
        box_expand_widget(child, ww, wh)
    }
}// }}}

box_resize :: proc(widget: ^Widget, w, h: f32) {// {{{
    self := cast(^Box)widget

    if self.layout == .Vertical {
        vbox_resize(self, w, h)
    } else {
        hbox_resize(self, w, h)
    }

    self.scrollbars.vertical.enabled = self.content_h > self.h
    if !self.scrollbars.vertical.enabled {
        self.scrollbars.vertical.position = 0
    }
    self.scrollbars.horizontal.enabled = self.content_w > self.w
    if !self.scrollbars.horizontal.enabled {
        self.scrollbars.horizontal.position = 0
    }
    scrollbars_resize(&self.scrollbars, self.w, self.h, self.content_w, self.content_h)
}// }}}

box_update :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {// {{{
    self := cast(^Box)widget

    for child in self.widgets {
        if child.update != nil && !child.disabled {
            child->update(handle, self)
        }
    }
    scrollbars_update(&self.scrollbars, handle)
}// }}}

box_draw :: proc(widget: ^Widget, handle: ^Handle) {// {{{
    self := cast(^Box)widget

    if self.attr.style.background_color.a > 0 {
        draw_rect(handle, self.x, self.y, self.w, self.h, self.attr.style.background_color)
    }

    for child in self.widgets {
        widget_draw(child, handle)
    }
    scrollbars_draw(&self.scrollbars, handle)

    bt := self.attr.style.border_thickness
    bc := self.attr.style.border_color
    if .Top in self.attr.style.active_borders {
        draw_rect(handle, self.x, self.y, self.w, bt, bc)
    }
    if .Bottom in self.attr.style.active_borders {
        draw_rect(handle, self.x, self.y + self.h - bt, self.w, bt, bc)
    }
    if .Left in self.attr.style.active_borders {
        draw_rect(handle, self.x, self.y, bt, self.h, bc)
    }
    if .Right in self.attr.style.active_borders {
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
    using widget: Widget,
    checked: bool,
    label: string,
    label_text: ^su.Text,
    button_offset: f32,
    label_offset: f32,
    attr: RadioButtonAttributes,
}

radio_button :: proc(
    label: string,
    attr := OPTS.radio_button_attr,
    default_checked := false,
) -> ^Widget {
    radio_button_w := new(RadioButton)
    radio_button_w^ = RadioButton{
        init = radio_button_init,
        update = radio_button_update,
        draw = radio_button_draw,
        checked = default_checked,
        label = label,
        attr = attr,
    }
    return radio_button_w
}

radio_button_init :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^RadioButton)widget

    self.label_text = create_text(handle, self.label, self.attr.style.font, self.attr.style.font_size)
    label_color := su.Color{
        self.attr.style.label_color.r,
        self.attr.style.label_color.g,
        self.attr.style.label_color.b,
        self.attr.style.label_color.a,
    }
    su.text_set_color(self.label_text, label_color)
    su.text_update(self.label_text)
    label_w, label_h := su.text_size(self.label_text)

    d := 2 * self.attr.style.base_radius
    self.w = d + self.attr.style.label_padding + label_w
    self.h = max(d, label_h)
    self.min_w = self.w
    self.min_h = self.h
    if label_h > d {
        self.button_offset = (label_h - d) / 2
    } else {
        self.label_offset = (d - label_h) / 2
    }

    add_event_handler(handle, self, proc(widget: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
        self := cast(^RadioButton)widget
        button_size := 2 * self.attr.style.base_radius
        button_x := self.x
        button_y := self.y + self.button_offset
        if event.down && event.button == sdl.BUTTON_LEFT && mouse_on_region(event.x, event.y, button_x, button_y, button_size, button_size) {
            self.checked = !self.checked
            return true
        }
        return false
    })
}

radio_button_update :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {}

radio_button_draw :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^RadioButton)widget

    r := self.attr.style.base_radius
    bgr := self.attr.style.base_radius - self.attr.style.border_thickness
    dr := self.attr.style.dot_radius
    by := self.y + self.button_offset + r
    bx := self.x + r
    if self.attr.style.border_thickness > 0 {
        draw_circle(handle, bx, by, r, self.attr.style.border_color)
    }
    draw_circle(handle, bx, by, bgr, self.attr.style.background_color)
    if self.checked {
        draw_circle(handle, bx, by, dr, self.attr.style.dot_color)
    }

    text_xoffset := 2 * r + self.attr.style.label_padding
    text_yoffset := self.label_offset
    draw_text(handle, self.label_text, self.x + text_xoffset, self.y + text_yoffset)
}

radio_button_get_value :: proc(widget: ^Widget) -> bool {
    self := cast(^RadioButton)widget
    return self.checked
}

radio_button_set_value :: proc(widget: ^Widget, value: bool) {
    self := cast(^RadioButton)widget
    self.checked = value
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
    using widget: Widget,
    content_size: ContentSize,
    zoombox: ZoomBox,
    scrollbars: Scrollbars,
    user_init: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    user_destroy: proc(handle: ^Handle, user_data: rawptr),
    user_update: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) -> ContentSize,
    user_draw: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    user_data: rawptr,
    attr: DrawBoxAttributes,
}

draw_box :: proc(
    draw: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    update: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) -> ContentSize = nil,
    init: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) = nil,
    destroy: proc(handle: ^Handle, user_data: rawptr) = nil,
    data: rawptr = nil,
    attr := OPTS.draw_box_attr,
) -> ^Widget {
    draw_box_w := new(DrawBox)
    draw_box_w^ = DrawBox{
        size_policy = {.FillW, .FillH},
        init = draw_box_init,
        destroy = draw_box_destroy,
        update = draw_box_update,
        draw = draw_box_draw,
        zoombox = zoombox(attr.zoom_min, attr.zoom_max, attr.zoom_step),
        scrollbars = scrollbars(attr.scrollbars_attr),
        user_draw = draw,
        user_init = init,
        user_destroy = destroy,
        user_update = update,
        user_data = data,
        attr = attr,
    }
    return draw_box_w
}

draw_box_init :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^DrawBox)widget

    if self.user_init != nil {
        self.user_init(handle, self, self.user_data)
    }

    zoombox_init(&self.zoombox, self)

    add_event_handler(handle, self, proc(widget: ^Widget, event: MouseWheelEvent, handle: ^Handle) -> bool {
        if !widget_is_hovered(widget, handle.mouse_x, handle.mouse_y) do return false
        self := cast(^DrawBox)widget

        if .Control in event.mods && .Zoomable in self.attr.props {
            return zoombox_zoom_handler(&self.zoombox, event.x, event.y, event.mods)
        } else if .WithScrollbar in self.attr.props {
            scrollbars_scroll(&self.scrollbars, -event.y, 0, 100, 100)
        }
        return true
    })
    add_event_handler(handle, self, proc(widget: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
        self := cast(^DrawBox)widget
        if .WithScrollbar not_in self.attr.props do return false
        scrollbars_click(&self.scrollbars, event)
        return true
    })
    add_event_handler(handle, self, proc(widget: ^Widget, event: MouseMotionEvent, handle: ^Handle) -> bool {
        self := cast(^DrawBox)widget
        if .WithScrollbar not_in self.attr.props do return false
        scrollbars_mouse_motion(&self.scrollbars, event)
        return true
    })
}

draw_box_destroy :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^DrawBox)widget
    if self.user_destroy != nil {
        self.user_destroy(handle, self.user_data)
    }
}

draw_box_update :: proc(widget: ^Widget, handle: ^Handle, parent: ^Widget) {
    self := cast(^DrawBox)widget
    if self.user_update != nil {
        self.content_size = self.user_update(handle, self, self.user_data)
    }
    if .WithScrollbar in self.attr.props {
        scrollbars_resize(&self.scrollbars, self.w, self.h, self.content_size.width, self.content_size.height)
        scrollbars_align(&self.scrollbars, self.x, self.y)
        scrollbars_update(&self.scrollbars, handle)
    }
}

draw_box_draw :: proc(widget: ^Widget, handle: ^Handle) {
    self := cast(^DrawBox)widget
    old_rel_rect := handle.rel_rect
    handle.rel_rect = Rect{self.x, self.y, self.w, self.h}
    self.user_draw(handle, self, self.user_data)
    handle.rel_rect = old_rel_rect
    if .WithScrollbar in self.attr.props {
        scrollbars_draw(&self.scrollbars, handle)
    }
}
