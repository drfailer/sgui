package widgets

import ".."
import "../gla"
import sdl "vendor:sdl3"


SwitchButtonOnClickProc :: proc(ui: ^sgui.Ui, on: bool, on_click_data: rawptr)

// TODO: the switch is very simple for now, but on/off colors might be added at some point
// TODO: sgui doesn't have shadows yet.
SwitchButtonAttributes :: struct {
    thumb_size: f32,
    thumb_padding: f32,
    corner_radius: f32,
    background_color: sgui.Color,
    thumb_color: sgui.Color,
}

// TODO: this widget would benefit from beeing animated
SwitchButton :: struct {
    using widget: sgui.Widget,
    on: bool,
    on_click: SwitchButtonOnClickProc,
    on_click_data: rawptr,
    attr: SwitchButtonAttributes,
}

switch_button :: proc(
    attr := DEFAULT_ATTRS.switch_button,
    on := false,
    on_click: SwitchButtonOnClickProc = nil,
    on_click_data: rawptr = nil,
) -> ^sgui.Widget {
    switch_button_w := new(SwitchButton)
    switch_button_w^ = SwitchButton{
        init = switch_button_init,
        update = switch_button_update,
        draw = switch_button_draw,
        on = on,
        on_click = on_click,
        on_click_data = on_click_data,
        attr = attr,
    }
    return switch_button_w
}

switch_button_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^SwitchButton)widget
    self.w = 2 * self.attr.thumb_size + 2 * self.attr.thumb_padding
    self.h = self.attr.thumb_size + 2 * self.attr.thumb_padding
    self.min_w = self.w
    self.min_h = self.h
    sgui.add_event_handler(ui, self, proc(widget: ^sgui.Widget, event: sgui.MouseClickEvent, ui: ^sgui.Ui) -> bool {
        self := cast(^SwitchButton)widget
        if event.down && event.button == sdl.BUTTON_LEFT && sgui.mouse_on_region(event.x, event.y, self.x, self.y, self.w, self.h) {
            self.on = !self.on
            if self.on_click != nil {
                self.on_click(ui, self.on, self.on_click_data)
            }
            return true
        }
        return false
    })
}

switch_button_update :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {}

switch_button_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^SwitchButton)widget

    // draw background
    if self.attr.corner_radius > 0 {
        sgui.draw_rounded_box(ui, self.x, self.y, self.w, self.h, self.attr.corner_radius,
                              self.attr.background_color)
    } else {
        sgui.draw_rect(ui, self.x, self.y, self.w, self.h, self.attr.background_color)
    }

    // draw thumb
    thumb_x := self.x + self.attr.thumb_padding
    thumb_y := self.y + self.attr.thumb_padding
    if self.on {
        thumb_x += self.attr.thumb_size
    }
    if self.attr.corner_radius > 0 {
        sgui.draw_rounded_box(ui, thumb_x, thumb_y, self.attr.thumb_size, self.attr.thumb_size,
                              self.attr.corner_radius, self.attr.thumb_color)
    } else {
        sgui.draw_rect(ui, thumb_x, thumb_y, self.attr.thumb_size, self.attr.thumb_size,
                       self.attr.thumb_color)
    }
}

switch_button_get_value :: proc(widget: ^sgui.Widget) -> bool {
    self := cast(^SwitchButton)widget
    return self.on
}

switch_button_set_value :: proc(widget: ^sgui.Widget, value: bool) {
    self := cast(^SwitchButton)widget
    self.on = value
}

switch_button_value :: proc{
    switch_button_get_value,
    switch_button_set_value,
}
