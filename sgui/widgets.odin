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
    RadioButton,
}

WidgetValue :: union { string, bool, int, f64 }

widget_init :: proc(widget: ^Widget, handle: ^Handle) {
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
        if !widget.disabled {
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
}

widget_update :: proc(handle: ^Handle, widget: ^Widget) {
    root := Widget{
        x = handle.rel_rect.x,
        y = handle.rel_rect.y,
        w = handle.rel_rect.w,
        h = handle.rel_rect.h,
    }
    widget_align(widget, root.x, root.y, root.w, root.h)
    widget->update(handle, &root)
}

widget_draw :: proc(widget: ^Widget, handle: ^Handle) {
    if !handle.processing_ordered_draws && widget.z_index > 0 {
        add_ordered_draw(handle, widget)
    } else if !widget.disabled {
        widget->draw(handle)
    }
}

widget_is_hovered :: proc(widget: ^Widget, mx, my: f32) -> bool {
    return mouse_on_region(mx, my, widget.x, widget.y, widget.w, widget.h)
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

    if self.w > parent.w || self.h > parent.h {
        log.warn("text widget container too small")
    }
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
        self.w = w
        self.h = h
    }
}

text_draw :: proc(self: ^Widget, handle: ^Handle) {
    data := &self.data.(Text)
    su.text_draw(&data.text, self.x, self.y)
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

    handle->click_handler(self, proc(self: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
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

Alignment :: bit_set[AlignmentFlag]
AlignmentFlag :: enum {
    Left,
    Right,
    Top,
    Bottom,
    VCenter,
    HCenter,
}

BoxProperties :: bit_set[BoxProperty]
BoxProperty :: enum {
    FitW,
    FitH,
    FixedW,
    FixedH,
    MinW,
    MinH,
}

BoxAttributes :: struct {
    style: BoxStyle,
    props: BoxProperties,
    w, h: f32,
}

AlignedWidget :: struct {
    alignment: Alignment,
    widget: ^Widget,
}

// TODO: scrollbars
Box :: struct {
    layout: BoxLayout,
    attr: BoxAttributes,
    widgets: [dynamic]AlignedWidget,
    // TODO: add an optional ScrollBox that will contain the implementation of the scrollbars (The draw box must have it too)
    // TODO: The standard boxes should be scrollable, but only the the draw box should be zoomable
    // TODO: The the update function of the scrollbox will need to know the content size
    // TODO: separate the logic of the scrollbar into the scrollbox that will also handle mouse wheel (if the box is hovered)
}

BoxInput :: union {
    ^Widget,
    AlignedWidget,
}

// TODO: the box should also have scrollbars
box :: proc(
    layout: BoxLayout,
    attr: BoxAttributes,
    init: WidgetInitProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,
    z_index: u64,
    widgets: ..BoxInput,
) -> (box: ^Widget) {
    box = new(Widget)
    widget_list := make([dynamic]AlignedWidget)

    for widget in widgets {
        switch v in widget {
        case AlignedWidget: append(&widget_list, v)
        case ^Widget: append(&widget_list, AlignedWidget{widget = v, alignment = Alignment{.Top, .Left}})
        }
    }
    box^ = Widget{
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

    if .FixedW in attr.props {
        box.w = attr.w
    } else if .MinW in attr.props {
        box.min_w = attr.w
    }

    if .FixedH in attr.props {
        box.h = attr.h
    } else if .MinH in attr.props {
        box.min_h = attr.h
    }
    return box
}

vbox :: proc(widgets: ..BoxInput, attr := BoxAttributes{}, z_index: u64 = 0) -> ^Widget {
    return box(.Vertical, attr, box_init, box_update, box_draw, z_index, ..widgets)
}

hbox :: proc(widgets: ..BoxInput, attr := BoxAttributes{}, z_index: u64 = 0) -> ^Widget {
    return box(.Horizontal, attr, box_init, box_update, box_draw, z_index, ..widgets)
}

box_ensure_alignment_conditions :: proc(widget: ^Widget, remaining_w, remaining_h: f32) -> bool {
    if widget.w > remaining_w {
        if widget.resizable_w {
            widget.w = remaining_w
        } else {
            log.warn("disabling widget due to lack of width.")
            widget.disabled = true
            return false
        }
    }

    if widget.h > remaining_h {
        if widget.resizable_h {
            widget.h = remaining_h
        } else {
            log.warn("disabling widget due to lack of height.")
            widget.disabled = true
            return false
        }
    }
    return true
}

// TODO: the alignment logic is not great

vbox_align :: proc(self: ^Widget, parent_x, parent_y, parent_w, parent_h: f32) {
    data := &self.data.(Box)

    left_x := self.x + data.attr.style.padding.left
    right_x := self.x + self.w - data.attr.style.padding.right

    top_y := self.y + data.attr.style.padding.top
    bottom_y := self.y + self.h + data.attr.style.padding.bottom

    remaining_w := self.w - data.attr.style.padding.left - data.attr.style.padding.right
    remaining_h := self.h - data.attr.style.padding.top - data.attr.style.padding.bottom

    for aw in data.widgets {
        if aw.widget.disabled do continue
        if !box_ensure_alignment_conditions(aw.widget, remaining_w, remaining_h) do continue

        wx, wy, ww, wh := left_x, top_y, remaining_w, aw.widget.h
        if aw.widget.resizable_h && aw.widget.min_h == -1 {
            wh = remaining_h
            remaining_h = 0
        }

        if .FitH in data.attr.props {
            wy = top_y
            top_y += aw.widget.h + data.attr.style.items_spacing
            remaining_h -= aw.widget.h + data.attr.style.items_spacing
        } else {
            if .VCenter in aw.alignment {
                wy = self.y + data.attr.style.padding.top \
                   + (remaining_h - aw.widget.h - data.attr.style.padding.top - data.attr.style.padding.bottom) / 2.
            } else if .Bottom in aw.alignment {
                wy = bottom_y - aw.widget.h
                bottom_y -= aw.widget.h + data.attr.style.items_spacing
                remaining_h -= aw.widget.h + data.attr.style.items_spacing
            } else {
                wy = top_y
                top_y += aw.widget.h + data.attr.style.items_spacing
                remaining_h -= aw.widget.h + data.attr.style.items_spacing
            }
        }

        // since widgets are added in a column, there is no need to decrease the width
        if .FitW in data.attr.props {
            wx = left_x
        } else {
            if .HCenter in aw.alignment {
                wx = self.x + data.attr.style.padding.left \
                   + (remaining_w - aw.widget.w - data.attr.style.padding.left - data.attr.style.padding.right) / 2.
            } else if .Right in aw.alignment {
                wx = right_x - aw.widget.w
            } else {
                wx = left_x
            }
        }

        widget_align(aw.widget, wx, wy, ww, wh)
    }

    // TODO: update self
}

hbox_align :: proc(self: ^Widget, parent_x, parent_y, parent_w, parent_h: f32) {
    data := &self.data.(Box)

    left_x := self.x + data.attr.style.padding.left
    right_x := self.x + self.w - data.attr.style.padding.right

    top_y := self.y + data.attr.style.padding.top
    bottom_y := self.y + self.h + data.attr.style.padding.bottom

    remaining_w := self.w - data.attr.style.padding.left - data.attr.style.padding.right
    remaining_h := self.h - data.attr.style.padding.top - data.attr.style.padding.bottom

    for aw in data.widgets {
        if aw.widget.disabled do continue
        if !box_ensure_alignment_conditions(aw.widget, remaining_w, remaining_h) do continue

        wx, wy, ww, wh := left_x, top_y, aw.widget.w, remaining_h
        if aw.widget.resizable_w && aw.widget.min_w == -1 {
            ww = remaining_w
            remaining_w = 0
        }

        // since widgets are added in a row, there is no need to decrease the height
        if .FitH in data.attr.props {
            wy = top_y
        } else {
            if .VCenter in aw.alignment {
                wy = self.y + data.attr.style.padding.top \
                   + (remaining_h - aw.widget.h - data.attr.style.padding.top - data.attr.style.padding.bottom) / 2.
            } else if .Bottom in aw.alignment {
                wy = bottom_y - aw.widget.h
            } else {
                wy = top_y
            }
        }

        if .FitW in data.attr.props {
            wx = left_x
            left_x += aw.widget.w + data.attr.style.items_spacing
            remaining_w -= aw.widget.w + data.attr.style.items_spacing
        } else {
            if .HCenter in aw.alignment {
                wx = self.x + data.attr.style.padding.left \
                   + (remaining_w - aw.widget.w - data.attr.style.padding.left - data.attr.style.padding.right) / 2.
            } else if .Right in aw.alignment {
                wx = right_x - aw.widget.w
                right_x -= aw.widget.w + data.attr.style.items_spacing
                remaining_w -= aw.widget.w + data.attr.style.items_spacing
            } else {
                wx = left_x
                left_x += aw.widget.w + data.attr.style.items_spacing
                remaining_w -= aw.widget.w + data.attr.style.items_spacing
            }
        }

        widget_align(aw.widget, wx, wy, ww, wh)
    }

    // TODO: update self
}

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

box_add_widget :: proc(box_widget: ^Widget, input: BoxInput) {
    data := &box_widget.data.(Box)
    switch v in input {
    case AlignedWidget: append(&data.widgets, v)
    case ^Widget: append(&data.widgets, AlignedWidget{widget = v, alignment = Alignment{.Top, .Left}})
    }
}

box_init :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    data := &self.data.(Box)
    padding_w := data.attr.style.padding.left + data.attr.style.padding.right
    padding_h := data.attr.style.padding.top + data.attr.style.padding.bottom
    max_w := data.widgets[0].widget.w
    max_h := data.widgets[0].widget.h
    ttl_w := padding_w
    ttl_h := padding_h

    if .FixedW not_in data.attr.props {
        if .MinW in data.attr.props && parent.w < self.min_w {
            log.error("minimum width of box does not fit in the parent container.")
        }
        self.w = parent.w
    }
    if .FixedH not_in data.attr.props {
        if .MinH in data.attr.props && parent.h < self.min_h {
            log.error("minimum height of box does not fit in the parent container.")
        }
        self.h = parent.h
    }

    for aw in data.widgets {
        aw.widget->init(handle, self)
        max_w = max(max_w, aw.widget.w)
        ttl_w += aw.widget.w + data.attr.style.items_spacing
        max_h = max(max_h, aw.widget.h)
        ttl_h += aw.widget.h + data.attr.style.items_spacing
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

box_update :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    data := &self.data.(Box)

    for aw in data.widgets {
        if aw.widget.update != nil {
            aw.widget->update(handle, self)
        }
    }
}

box_draw :: proc(self: ^Widget, handle: ^Handle) {
    data := &self.data.(Box)

    if data.attr.style.background_color.a > 0 {
        handle->draw_rect(self.x, self.y, self.w, self.h, data.attr.style.background_color)
    }
    for aw in data.widgets {
        if aw.widget.draw != nil {
            widget_draw(aw.widget, handle)
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

// align functions //

align_widgets :: proc(widget: ^Widget, alignment: Alignment = {.Top, .Left}) -> (result: AlignedWidget) {
    return AlignedWidget{widget = widget, alignment = alignment}
}

center :: proc(widget: ^Widget) -> AlignedWidget {
    return align_widgets(widget, alignment = Alignment{.HCenter, .VCenter})
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
    attr: RadioButtonAttributes,
    checked: bool,
    label: string,
    label_text: su.Text,
    button_offset: f32,
    label_offset: f32,
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
        value = radio_button_value,
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
    if label_h > d {
        data.button_offset = (label_h - d) / 2
    } else {
        data.label_offset = (d - label_h) / 2
    }

    handle->click_handler(self, proc(self: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {
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
    if self.disabled do return
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
    handle->draw_text(&data.label_text, self.x + text_xoffset, self.y + text_yoffset)
}

radio_button_value :: proc(self: ^Widget) -> WidgetValue {
    data := &self.data.(RadioButton)
    return data.checked
}

// draw box ////////////////////////////////////////////////////////////////////

DrawBoxProperties :: bit_set[DrawBoxProperty]
DrawBoxProperty :: enum {
    Zoomable,
    WithScrollbar,
}

// TODO: draw box attribute -> allow changing zoombox attr

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
    user_init: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    user_update: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) -> ContentSize,
    user_draw: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    user_data: rawptr,
}

draw_box :: proc(
    draw: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr),
    update: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) -> ContentSize = nil,
    init: proc(handle: ^Handle, widget: ^Widget, user_data: rawptr) = nil,
    data: rawptr = nil,
    props := DrawBoxProperties{},
) -> (draw_box: ^Widget) {
    draw_box = new(Widget)
    draw_box^ = Widget{
        resizable_h = true,
        resizable_w = true,
        min_w = -1,
        min_h = -1,
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
    return draw_box
}

draw_box_init :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    data := &self.data.(DrawBox)

    if data.user_init != nil {
        data.user_init(handle, self, data.user_data)
    }

    scrollbox_init(&data.scrollbox, handle, self)
    zoombox_init(&data.zoombox, self)

    // TODO: factor this code v
    handle->key_handler(self, proc(self: ^Widget, event: KeyEvent, handle: ^Handle) -> bool {// {{{
        if !event.down do return false
        data := &self.data.(DrawBox)

        vcount, hcount: i32

        switch event.key {
        case sdl.K_H: hcount = -1
        case sdl.K_L: hcount = 1
        case sdl.K_K: vcount = -1
        case sdl.K_J: vcount = 1
        }
        return scrollbox_scrolled_handler(&data.scrollbox, vcount, hcount, 100, 100)
    })// }}}
    handle->scroll_handler(self, proc(self: ^Widget, event: MouseWheelEvent, handle: ^Handle) -> bool {// {{{
        data := &self.data.(DrawBox)
        if .Control in event.mods {
            return zoombox_zoom_handler(&data.zoombox, event.x, event.y, event.mods)
        } else {
            return scrollbox_scrolled_handler(&data.scrollbox, -event.y, 0, 100, 100)
        }
        return true
    })// }}}
    handle->click_handler(self, proc(self: ^Widget, event: MouseClickEvent, handle: ^Handle) -> bool {// {{{
        data := &self.data.(DrawBox)
        return scrollbox_clicked_handler(&data.scrollbox, event)
    })// }}}
    handle->mouse_move_handler(self, proc(self: ^Widget, event: MouseMotionEvent, handle: ^Handle) -> bool {// {{{
        data := &self.data.(DrawBox)
        return scrollbox_dragged_handler(&data.scrollbox, event)
    })// }}}
}

draw_box_update :: proc(self: ^Widget, handle: ^Handle, parent: ^Widget) {
    if self.disabled do return
    data := &self.data.(DrawBox)
    if data.user_update != nil {
        data.content_size = data.user_update(handle, self, data.user_data)
    }
    scrollbox_update(&data.scrollbox, data.content_size.width, data.content_size.height)
}

draw_box_draw :: proc(self: ^Widget, handle: ^Handle) {
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
