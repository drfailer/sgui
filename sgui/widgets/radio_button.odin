package widgets

import ".."
import "../gla"
import sdl "vendor:sdl3"


RadioButtonOnClickProc :: proc(ui: ^sgui.Ui, checked: bool, on_click_data: rawptr)

RadioButtonAttributes :: struct {
    base_radius: f32,
    border_thickness: f32,
    dot_radius: f32,
    border_color: sgui.Color,
    background_color: sgui.Color,
    dot_color: sgui.Color,
    label: TextAttributes,
}

RadioButton :: struct {
    using widget: sgui.Widget,
    checked: bool,
    // used to center the label/button when the they don't have the same height
    label_offset, button_offset: f32,
    label: Text,
    on_click: RadioButtonOnClickProc,
    on_click_data: rawptr,
    attr: RadioButtonAttributes,
}

radio_button :: proc(
    label: string,
    attr := DEFAULT_ATTRS.radio_button,
    default_checked := false,
    on_click: RadioButtonOnClickProc = nil,
    on_click_data: rawptr = nil,
) -> ^sgui.Widget {
    radio_button_w := new(RadioButton)
    radio_button_w^ = RadioButton{
        init = radio_button_init,
        update = radio_button_update,
        draw = radio_button_draw,
        checked = default_checked,
        label = Text{
            content = label,
            attr = attr.label,
        },
        on_click = on_click,
        on_click_data = on_click_data,
        attr = attr,
    }
    return radio_button_w
}

radio_button_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^RadioButton)widget

    text_init(&self.label, ui, parent)

    d := 2 * self.attr.base_radius
    self.w = d + self.label.w
    self.h = max(d, self.label.h)
    self.min_w = self.w
    self.min_h = self.h
    if self.label.h > d {
        self.button_offset = (self.label.h - d) / 2
    } else {
        self.label_offset = (d - self.label.h) / 2
    }

    sgui.add_event_handler(ui, self, proc(widget: ^sgui.Widget, event: sgui.MouseClickEvent, ui: ^sgui.Ui) -> bool {
        self := cast(^RadioButton)widget
        button_size := 2 * self.attr.base_radius
        button_x := self.x
        button_y := self.y + self.button_offset
        if event.down && event.button == sdl.BUTTON_LEFT && sgui.mouse_on_region(event.x, event.y, button_x, button_y, button_size, button_size) {
            self.checked = !self.checked
            if self.on_click != nil {
                self.on_click(ui, self.checked, self.on_click_data)
            }
            return true
        }
        return false
    })
}

radio_button_update :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {}

radio_button_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^RadioButton)widget

    r := self.attr.base_radius
    bgr := self.attr.base_radius - self.attr.border_thickness
    dr := self.attr.dot_radius
    by := self.y + self.button_offset + r
    bx := self.x + r
    if self.attr.border_thickness > 0 {
        sgui.draw_circle(ui, bx, by, r, self.attr.border_color)
    }
    sgui.draw_circle(ui, bx, by, bgr, self.attr.background_color)
    if self.checked {
        sgui.draw_circle(ui, bx, by, dr, self.attr.dot_color)
    }
    // note: this is not complex enough to justify adding an align function for this button
    self.label.x = self.x + 2 * r
    self.label.y = self.y + self.label_offset
    text_draw(&self.label, ui)
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
