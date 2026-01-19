package widgets

import ".."
import "../gla"
import sdl "vendor:sdl3"


RadioButtonStyle :: struct {
    base_radius: f32,
    border_thickness: f32,
    dot_radius: f32,
    border_color: sgui.Color,
    background_color: sgui.Color,
    dot_color: sgui.Color,
    label_padding: f32,
    label_color: sgui.Color,
    font: string,
    font_size: gla.FontSize,
}

RadioButtonAttributes :: struct {
    style: RadioButtonStyle,
}

RadioButton :: struct {
    using widget: sgui.Widget,
    checked: bool,
    label: string,
    label_text: ^gla.Text,
    button_offset: f32,
    label_offset: f32,
    attr: RadioButtonAttributes,
}

radio_button :: proc(
    label: string,
    attr := OPTS.radio_button_attr,
    default_checked := false,
) -> ^sgui.Widget {
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

radio_button_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^RadioButton)widget

    self.label_text = sgui.create_text(ui,
                                  self.label,
                                  self.attr.style.font,
                                  self.attr.style.font_size,
                                  self.attr.style.label_color)
    label_w, label_h := gla.text_size(self.label_text)

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

    sgui.add_event_handler(ui, self, proc(widget: ^sgui.Widget, event: sgui.MouseClickEvent, ui: ^sgui.Ui) -> bool {
        self := cast(^RadioButton)widget
        button_size := 2 * self.attr.style.base_radius
        button_x := self.x
        button_y := self.y + self.button_offset
        if event.down && event.button == sdl.BUTTON_LEFT && sgui.mouse_on_region(event.x, event.y, button_x, button_y, button_size, button_size) {
            self.checked = !self.checked
            return true
        }
        return false
    })
}

radio_button_update :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {}

radio_button_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^RadioButton)widget

    r := self.attr.style.base_radius
    bgr := self.attr.style.base_radius - self.attr.style.border_thickness
    dr := self.attr.style.dot_radius
    by := self.y + self.button_offset + r
    bx := self.x + r
    if self.attr.style.border_thickness > 0 {
        sgui.draw_circle(ui, bx, by, r, self.attr.style.border_color)
    }
    sgui.draw_circle(ui, bx, by, bgr, self.attr.style.background_color)
    if self.checked {
        sgui.draw_circle(ui, bx, by, dr, self.attr.style.dot_color)
    }

    text_xoffset := 2 * r + self.attr.style.label_padding
    text_yoffset := self.label_offset
    sgui.draw_text(ui, self.label_text, self.x + text_xoffset, self.y + text_yoffset)
}

radio_button_get_value :: proc(widget: ^sgui.Widget) -> bool {
    self := cast(^RadioButton)widget
    return self.checked
}

radio_button_set_value :: proc(widget: ^sgui.Widget, value: bool) {
    self := cast(^RadioButton)widget
    self.checked = value
}

radio_button_value :: proc{
    radio_button_get_value,
    radio_button_set_value,
}
