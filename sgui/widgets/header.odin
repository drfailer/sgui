package widgets

import ".."
import "../gla"
import sdl "vendor:sdl3"

// TODO: this should be named header

COLLAPSABLE_SECTION_SYMBOL_PADDING :: 5
COLLAPSABLE_SECTION_SYMBOL_SIZE :: 9

HeaderStyle :: struct {
    // TODO
    content_padding: Padding,
    // symbol_size???
    // hover_color???
}

HeaderAttributes :: struct {
    // TODO
}

Header :: struct {
    using widget: sgui.Widget,
    label: ^Text,
    content: ^Box,
    opened: bool,
    state: sgui.WidgetMouseState,
    attr: HeaderAttributes,
    style: HeaderStyle,
}

header :: proc(
    label: string,
    content: ..^sgui.Widget,
    attr := HeaderAttributes{},
    style := HeaderStyle{},
) -> ^sgui.Widget {
    header_w := new(Header)
    header_w^ = Header{
        init = header_init,
        fini = header_fini,
        draw = header_draw,
        align = header_align,
        resize = header_resize,
        label = cast(^Text)text(label),
        content = cast(^Box)vbox(
            ..content,
            attr = {
                props = {.FitW, .FitH}
            },
        ),
        attr = attr,
        style = style,
    }
    return header_w
}

header_mouse_handler :: proc(widget: ^sgui.Widget, event: sgui.MouseClickEvent, ui: ^sgui.Ui) -> bool {
    if event.button != sdl.BUTTON_LEFT || !sgui.widget_is_hovered(widget, event.x, event.y) do return false
    self := cast(^Header)widget

    if event.down {
        self.state = .Clicked
    } else if self.state == .Clicked {
        self.state = .Idle
        self.opened = !self.opened
        ui.resize = true
    }
    return true
}

header_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Header)widget
    self.label->init(ui, parent)
    self.content->init(ui, parent)
    self.w = self.label.w + 2 * COLLAPSABLE_SECTION_SYMBOL_PADDING + COLLAPSABLE_SECTION_SYMBOL_SIZE
    self.h = self.label.h

    sgui.add_event_handler(ui, self, header_mouse_handler)
}

header_fini :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Header)widget
    self.content->fini(ui)
}

header_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Header)widget
    symbol_x := self.x + self.label.w + COLLAPSABLE_SECTION_SYMBOL_PADDING
    symbol_y := self.y + self.label.h / 2

    self.label->draw(ui) // TODO: draw triangle
    if self.opened {
        sgui.draw_triangle(
            ui,
            symbol_x, symbol_y - COLLAPSABLE_SECTION_SYMBOL_SIZE / 2,
            symbol_x + COLLAPSABLE_SECTION_SYMBOL_SIZE, symbol_y - COLLAPSABLE_SECTION_SYMBOL_SIZE / 2,
            symbol_x + COLLAPSABLE_SECTION_SYMBOL_SIZE / 2, symbol_y + COLLAPSABLE_SECTION_SYMBOL_SIZE / 2,
            self.label.attr.style.color)
        self.content->draw(ui)
    } else {
        sgui.draw_triangle(
            ui,
            symbol_x, symbol_y - COLLAPSABLE_SECTION_SYMBOL_SIZE / 2,
            symbol_x + COLLAPSABLE_SECTION_SYMBOL_SIZE, symbol_y,
            symbol_x, symbol_y + COLLAPSABLE_SECTION_SYMBOL_SIZE / 2,
            self.label.attr.style.color)
    }
}

header_align :: proc(widget: ^sgui.Widget, x, y: f32) {
    self := cast(^Header)widget
    self.x = x // TODO: spacing???
    self.y = y
    sgui.widget_align(self.label, x, y)
    if self.opened {
        sgui.widget_align(self.content, x, y + self.label.h)
    }
}

header_resize :: proc(widget: ^sgui.Widget, w, h: f32) {
    self := cast(^Header)widget

    header_w := self.label.w + 2 * COLLAPSABLE_SECTION_SYMBOL_PADDING + COLLAPSABLE_SECTION_SYMBOL_SIZE
    if self.opened {
        self.content->resize(w, h)
        self.w = max(header_w, self.content.w)
        self.h = self.label.h + self.content.h // TODO: spacing???
    } else {
        self.w = header_w
        self.h = self.label.h
    }
    self.min_w = self.w
    self.min_h = self.h
}
