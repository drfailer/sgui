package widgets

import ".."
import "../gla"


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
    using widget: sgui.Widget,
    content_size: ContentSize,
    zoombox: ZoomBox,
    scrollbars: Scrollbars,
    user_init: proc(ui: ^sgui.Ui, widget: ^sgui.Widget, user_data: rawptr),
    user_destroy: proc(ui: ^sgui.Ui, user_data: rawptr),
    user_update: proc(ui: ^sgui.Ui, widget: ^sgui.Widget, user_data: rawptr) -> ContentSize,
    user_draw: proc(ui: ^sgui.Ui, widget: ^sgui.Widget, user_data: rawptr),
    user_data: rawptr,
    attr: DrawBoxAttributes,
}

draw_box :: proc(
    draw: proc(ui: ^sgui.Ui, widget: ^sgui.Widget, user_data: rawptr),
    update: proc(ui: ^sgui.Ui, widget: ^sgui.Widget, user_data: rawptr) -> ContentSize = nil,
    init: proc(ui: ^sgui.Ui, widget: ^sgui.Widget, user_data: rawptr) = nil,
    destroy: proc(ui: ^sgui.Ui, user_data: rawptr) = nil,
    data: rawptr = nil,
    attr := OPTS.draw_box_attr,
) -> ^sgui.Widget {
    draw_box_w := new(DrawBox)
    draw_box_w^ = DrawBox{
        size_policy = {.FillW, .FillH},
        init = draw_box_init,
        destroy = draw_box_destroy,
        update = draw_box_update,
        draw = draw_box_draw,
        zoombox = zoombox(attr.zoom_min, attr.zoom_max, attr.zoom_step),
        scrollbars = scrollbars_create(attr.scrollbars_attr),
        user_draw = draw,
        user_init = init,
        user_destroy = destroy,
        user_update = update,
        user_data = data,
        attr = attr,
    }
    return draw_box_w
}

draw_box_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^DrawBox)widget

    if self.user_init != nil {
        self.user_init(ui, self, self.user_data)
    }

    if .Zoomable in self.attr.props {
        sgui.add_event_handler(ui, self, proc(widget: ^sgui.Widget, event: sgui.MouseWheelEvent, ui: ^sgui.Ui) -> bool {
            if !sgui.widget_is_hovered(widget, ui.mouse_x, ui.mouse_y) do return false
            self := cast(^DrawBox)widget
            if .Control in event.mods {
                return zoombox_zoom_handler(&self.zoombox, event.x, event.y, event.mods)
            }
            return false
        })
    }
    if .WithScrollbar in self.attr.props {
        scrollbars_set_event_handlers(self, ui)
    }
}

draw_box_destroy :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^DrawBox)widget
    if self.user_destroy != nil {
        self.user_destroy(ui, self.user_data)
    }
}

draw_box_update :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^DrawBox)widget
    if self.user_update != nil {
        self.content_size = self.user_update(ui, self, self.user_data)
    }
    if .WithScrollbar in self.attr.props {
        scrollbars_resize(&self.scrollbars, self.w, self.h, self.content_size.width, self.content_size.height)
        scrollbars_align(&self.scrollbars, self.x, self.y)
        scrollbars_update(&self.scrollbars, ui)
    }
}

draw_box_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^DrawBox)widget
    old_rel_rect := ui.rel_rect
    ui.rel_rect = sgui.Rect{self.x, self.y, self.w, self.h}
    self.user_draw(ui, self, self.user_data)
    ui.rel_rect = old_rel_rect
    if .WithScrollbar in self.attr.props {
        scrollbars_draw(&self.scrollbars, ui)
    }
}
