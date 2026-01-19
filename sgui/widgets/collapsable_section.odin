package widgets

import ".."
import "../gla"
import sdl "vendor:sdl3"


CollapsableSectionStyle :: struct {
    // TODO
    content_padding: Padding,
    // symbol_size???
    // hover_color???
}

CollapsableSectionAttributes :: struct {
    style: CollapsableSectionStyle,
}

CollapsableSection :: struct {
    using widget: sgui.Widget,
    label: ^Text,
    content: ^Box,
    opened: bool,
    state: sgui.WidgetMouseState,
}

collapsable_section :: proc(
    label: string,
    content: ..^sgui.Widget,
    attr := CollapsableSectionAttributes{},
) -> ^sgui.Widget {
    collapsable_section_w := new(CollapsableSection)
    collapsable_section_w^ = CollapsableSection{
        init = collapsable_section_init,
        destroy = collapsable_section_destroy,
        draw = collapsable_section_draw,
        align = collapsable_section_align,
        resize = collapsable_section_resize,
        label = cast(^Text)text(label),
        content = cast(^Box)vbox(
            ..content,
            attr = {
                props = {.FitW, .FitH}
            },
        ),
    }
    return collapsable_section_w
}

collapsable_section_mouse_handler :: proc(widget: ^sgui.Widget, event: sgui.MouseClickEvent, ui: ^sgui.Ui) -> bool {
    if event.button != sdl.BUTTON_LEFT || !sgui.widget_is_hovered(widget, event.x, event.y) do return false
    self := cast(^CollapsableSection)widget

    if event.down {
        self.state = .Clicked
    } else if self.state == .Clicked {
        self.state = .Idle
        self.opened = !self.opened
        ui.resize = true
    }
    return true
}

collapsable_section_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^CollapsableSection)widget
    self.label->init(ui, parent)
    self.content->init(ui, parent)
    self.w = self.label.w
    self.h = self.label.h

    sgui.add_event_handler(ui, self, collapsable_section_mouse_handler)
}

collapsable_section_destroy :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^CollapsableSection)widget
    self.content->destroy(ui)
}

COLLAPSABLE_SECTION_SYMBOL_PADDING :: 5
COLLAPSABLE_SECTION_SYMBOL_SIZE :: 8
collapsable_section_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^CollapsableSection)widget
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

collapsable_section_align :: proc(widget: ^sgui.Widget, x, y: f32) {
    self := cast(^CollapsableSection)widget
    self.x = x // TODO: spacing???
    self.y = y
    sgui.widget_align(self.label, x, y)
    if self.opened {
        sgui.widget_align(self.content, x, y + self.label.h)
    }
}

collapsable_section_resize :: proc(widget: ^sgui.Widget, w, h: f32) {
    self := cast(^CollapsableSection)widget

    // TODO: add open symbol size
    if self.opened {
        self.content->resize(w, h)
        self.w = max(self.label.w, self.content.w)
        self.h = self.label.h + self.content.h // TODO: spacing???
    } else {
        self.w = self.label.w
        self.h = self.label.h
    }
    self.min_w = self.w
    self.min_h = self.h
}
