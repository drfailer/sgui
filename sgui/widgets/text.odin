package widgets

import ".."
import "../gla"


// TODO: dynamic wrapping

TextAttributes :: struct {
    font: gla.FontPath,
    font_size: gla.FontSize,
    color: sgui.Color,
    wrap_width: f32,
    padding: Padding,
}

Text :: struct {
    using widget: sgui.Widget,
    text: ^gla.Text,
    content: string,
    content_proc: proc(data: rawptr) -> (string, sgui.Color),
    content_proc_data: rawptr,
    attr: TextAttributes,
}

text_from_string :: proc(content: string, attr := DEFAULT_ATTRS.text) -> ^sgui.Widget {
    text_w := new(Text)
    text_w^ = Text{
        init = text_init,
        draw = text_draw,
        content = content,
        attr = attr,
    }
    return text_w
}

text_from_proc :: proc(
    content_proc: proc(data: rawptr) -> (string, sgui.Color),
    content_proc_data: rawptr,
    attr := DEFAULT_ATTRS.text,
) -> ^sgui.Widget {
    text_w := new(Text)
    text_w^ = Text{
        init = text_init,
        update = text_update,
        draw = text_draw,
        content_proc = content_proc,
        content_proc_data = content_proc_data,
        attr = attr,
    }
    return text_w
}

// TODO: create a printf like version
text :: proc {
    text_from_string,
    text_from_proc,
}

text_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Text)widget
    self.text = sgui.create_text(ui,
                            self.content,
                            self.attr.font,
                            self.attr.font_size,
                            self.attr.color)
    w, h := gla.text_size(self.text)
    self.w = w + self.attr.padding.left + self.attr.padding.right
    self.h = h + self.attr.padding.bottom + self.attr.padding.top
    self.min_w = self.w
    self.min_h = self.h
}

text_update :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Text)widget
    assert(self.content_proc != nil)
    content, color := self.content_proc(self.content_proc_data)
    gla.text_set_text(self.text, content)
    gla.text_set_color(self.text, color)
    if self.attr.wrap_width > 0 {
        gla.text_set_wrap_width(self.text, self.attr.wrap_width)
    }
    gla.text_update(self.text)
    w, h := gla.text_size(self.text)
    if w > self.w || h > self.h {
        ui.resize = true
    }
    self.w = w + self.attr.padding.left + self.attr.padding.right
    self.h = h + self.attr.padding.bottom + self.attr.padding.top
    self.min_w = self.w
    self.min_h = self.h
}

text_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Text)widget
    sgui.draw_text(ui, self.text, self.x + self.attr.padding.left, self.y + self.attr.padding.top)
}
