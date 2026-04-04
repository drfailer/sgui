package widgets

import ".."
import "../gla"
import sdl "vendor:sdl3"


ButtonOnClickProc :: proc(ui: ^sgui.Ui, on_click_data: rawptr)

ButtonColors :: struct {
    text: sgui.Color,
    border: sgui.Color,
    bg: sgui.Color,
}

ButtonAttributes :: struct {
    expand_w, expand_h: bool,
    label_font_path: gla.FontPath,
    label_font_size: gla.FontSize,
    padding: Padding,
    border_thickness: f32,
    corner_radius: f32,
    colors: [sgui.WidgetMouseState]ButtonColors,
}

IconData :: struct {
    file: string,
    srcrect: sgui.Rect,
}

Button :: struct {
    using widget: sgui.Widget,
    label: string,
    text: ^gla.Text,
    state: sgui.WidgetMouseState,
    on_click: ButtonOnClickProc,
    on_click_data: rawptr,
    attr: ButtonAttributes,
    icons_data: [sgui.WidgetMouseState]IconData,
    icons_image: [sgui.WidgetMouseState]^gla.Image,
    iw, ih: f32,
}

button :: proc(
    label: string,
    on_click: ButtonOnClickProc,
    on_click_data: rawptr = nil,
    attr := DEFAULT_ATTRS.button,
) -> ^sgui.Widget {
    button_w := new(Button)
    button_w^ = Button{
        init = button_init,
        update = button_update,
        draw = button_draw,
        label = label,
        on_click = on_click,
        on_click_data = on_click_data,
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
    icons_data: [sgui.WidgetMouseState]IconData,
    on_click: ButtonOnClickProc,
    w: f32 = 0,
    h: f32 = 0,
    on_click_data: rawptr = nil,
    attr := DEFAULT_ATTRS.button,
) -> ^sgui.Widget {
    button_w := cast(^Button)button(icons_data[.Idle].file, on_click, on_click_data, attr)
    button_w.icons_data = icons_data
    button_w.iw = w
    button_w.ih = h
    button_w.init = icon_button_init
    button_w.fini = icon_button_fini
    button_w.draw = icon_button_draw
    return button_w
}

icon_button_idle_state :: proc(
    icon: IconData,
    on_click: ButtonOnClickProc,
    w: f32 = 0,
    h: f32 = 0,
    on_click_data: rawptr = nil,
    attr := DEFAULT_ATTRS.button,
) -> ^sgui.Widget {
    icons_data := [sgui.WidgetMouseState]IconData{ .Idle = icon, .Hovered = icon, .Clicked = icon }
    return icon_button_all_states(icons_data, on_click, w, h, on_click_data, attr)
}

icon_button :: proc{
    icon_button_all_states,
    icon_button_idle_state,
}

button_mouse_handler :: proc(widget: ^sgui.Widget, event: sgui.MouseClickEvent, ui: ^sgui.Ui) -> bool {
    if event.button != sdl.BUTTON_LEFT || !sgui.widget_is_hovered(widget, event.x, event.y) do return false
    self := cast(^Button)widget

    if event.down {
        self.state = .Clicked
    } else if self.state == .Clicked {
        self.state = .Idle
        self.on_click(ui, self.on_click_data)
    }
    return true
}

button_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Button)widget
    self.text = sgui.create_text(ui, self.label, self.attr.label_font_path, self.attr.label_font_size)
    self.w, self.h = gla.text_size(self.text)
    self.w += self.attr.padding.left + self.attr.padding.right
    self.h += self.attr.padding.top + self.attr.padding.bottom
    self.min_w = self.w
    self.min_h = self.h
    sgui.add_event_handler(ui, self, button_mouse_handler)
}

icon_button_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Button)widget
    self.icons_image[.Idle] = sgui.create_image(ui, self.icons_data[.Idle].file, self.icons_data[.Idle].srcrect)
    self.icons_image[.Hovered] = sgui.create_image(ui, self.icons_data[.Hovered].file, self.icons_data[.Hovered].srcrect)
    self.icons_image[.Clicked] = sgui.create_image(ui, self.icons_data[.Clicked].file, self.icons_data[.Clicked].srcrect)
    assert(self.icons_image[.Clicked].w == self.icons_image[.Idle].w)
    assert(self.icons_image[.Clicked].h == self.icons_image[.Idle].h)
    assert(self.icons_image[.Hovered].w == self.icons_image[.Idle].w)
    assert(self.icons_image[.Hovered].h == self.icons_image[.Idle].h)
    w := self.icons_image[.Idle].w if self.iw == 0 else self.iw
    w += self.attr.padding.left + self.attr.padding.right
    self.w = w
    self.min_w = w
    h := self.icons_image[.Idle].h if self.ih == 0 else self.ih
    h += self.attr.padding.top + self.attr.padding.bottom
    self.h = h
    self.min_h = h
    sgui.add_event_handler(ui, self, button_mouse_handler)
}

icon_button_fini :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Button)widget
    gla.image_destroy(self.icons_image[.Idle])
    gla.image_destroy(self.icons_image[.Hovered])
    gla.image_destroy(self.icons_image[.Clicked])
}

button_update :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Button)widget
    if sgui.widget_is_hovered(self, ui.mouse_x, ui.mouse_y) {
        if self.state == .Idle {
            self.state = .Hovered
        }
    } else {
        self.state = .Idle
    }
}

button_draw_background :: proc(self: ^Button, ui: ^sgui.Ui) {
    bg_color := self.attr.colors[self.state].bg
    border_color := self.attr.colors[self.state].border
    border_thickness := self.attr.border_thickness

    if self.attr.corner_radius > 0 {
        if border_thickness > 0 {
            sgui.draw_rounded_box_with_border(ui, self.x, self.y, self.w, self.h,
                                              self.attr.corner_radius, border_thickness,
                                              border_color, bg_color)
        } else {
            sgui.draw_rounded_box(ui, self.x + border_thickness, self.y + border_thickness,
                                  self.w - 2 * border_thickness, self.h - 2 * border_thickness,
                                  self.attr.corner_radius, bg_color)
        }
    } else {
        if border_thickness > 0 {
            sgui.draw_rect(ui, self.x, self.y, self.w, self.h, border_color)
        }
        sgui.draw_rect(ui, self.x + border_thickness, self.y + border_thickness,
                       self.w - 2 * border_thickness, self.h - 2 * border_thickness,
                       bg_color)
    }
}

button_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Button)widget
    text_color := self.attr.colors[self.state].text

    gla.text_set_color(self.text, sgui.Color{text_color.r, text_color.g, text_color.b, text_color.a})
    gla.text_update(self.text)
    button_draw_background(self, ui)
    label_w, label_h := gla.text_size(self.text)
    label_x := self.x + (self.w - label_w) / 2.
    label_y := self.y + (self.h - label_h) / 2.
    sgui.draw_text(ui, self.text, label_x, label_y)
}

icon_button_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Button)widget
    button_draw_background(self, ui)
    icon_x := self.x + (self.w - self.iw) / 2.
    icon_y := self.y + (self.h - self.ih) / 2.
    sgui.draw_image(ui, self.icons_image[self.state], icon_x, icon_y, self.iw, self.ih)
}
