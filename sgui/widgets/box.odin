package widgets

import ".."
import "../gla"
import sdl "vendor:sdl3"


Padding :: struct { top: f32, bottom: f32, left: f32, right: f32 }

BorderSide :: enum { Top, Bottom, Left, Right }
ActiveBorders :: bit_set[BorderSide]

BoxStyle :: struct {
    background_color: sgui.Color,
    border_thickness: f32,
    active_borders: ActiveBorders,
    border_color: sgui.Color,
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
    using widget: sgui.Widget,
    layout: BoxLayout,
    widgets: [dynamic]^sgui.Widget,
    scrollbars: Scrollbars,
    content_w, content_h: f32,
    attr: BoxAttributes,
}

// constructors ////////////////////////////////////////////////////////////////

box :: proc(
    layout: BoxLayout,
    attr: BoxAttributes,
    init: sgui.WidgetInitProc,
    destroy: sgui.WidgetDestroyProc,
    update: sgui.WidgetUpdateProc,
    draw: sgui.WidgetDrawProc,
    z_index: u64,
    widgets: ..^sgui.Widget,
) -> ^sgui.Widget {
    box_w := new(Box)
    widget_list := make([dynamic]^sgui.Widget)

    for widget in widgets {
        if widget.alignment_policy == {} {
            widget.alignment_policy = sgui.AlignmentPolicy{.Top, .Left}
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
        scrollbars = scrollbars_create(),
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
}

vbox :: proc(widgets: ..^sgui.Widget, attr := BoxAttributes{}, z_index: u64 = 0) -> ^sgui.Widget {
    return box(.Vertical, attr, box_init, box_destroy, box_update, box_draw, z_index, ..widgets)
}

hbox :: proc(widgets: ..^sgui.Widget, attr := BoxAttributes{}, z_index: u64 = 0) -> ^sgui.Widget {
    return box(.Horizontal, attr, box_init, box_destroy, box_update, box_draw, z_index, ..widgets)
}

// init ////////////////////////////////////////////////////////////////////////

box_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Box)widget

    for child in self.widgets {
        if child.init != nil {
            child->init(ui, self)
        }
    }
    scrollbars_set_event_handlers(self, ui)
}

// destroy /////////////////////////////////////////////////////////////////////

box_destroy :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Box)widget

    for child in self.widgets {
        sgui.widget_destroy(child, ui)
    }
}

// update //////////////////////////////////////////////////////////////////////

box_update :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Box)widget

    if scrollbars_update(&self.scrollbars, ui) {
        box_align(self, self.x, self.y)
    }
    for child in self.widgets {
        if child.update != nil && !child.disabled {
            child->update(ui, self)
        }
    }
}

// draw ////////////////////////////////////////////////////////////////////////

box_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Box)widget

    if self.attr.style.background_color.a > 0 {
        sgui.draw_rect(ui, self.x, self.y, self.w, self.h, self.attr.style.background_color)
    }

    for child in self.widgets {
        sgui.widget_draw(child, ui)
    }
    scrollbars_draw(&self.scrollbars, ui)

    bt := self.attr.style.border_thickness
    bc := self.attr.style.border_color
    if .Top in self.attr.style.active_borders {
        sgui.draw_rect(ui, self.x, self.y, self.w, bt, bc)
    }
    if .Bottom in self.attr.style.active_borders {
        sgui.draw_rect(ui, self.x, self.y + self.h - bt, self.w, bt, bc)
    }
    if .Left in self.attr.style.active_borders {
        sgui.draw_rect(ui, self.x, self.y, bt, self.h, bc)
    }
    if .Right in self.attr.style.active_borders {
        sgui.draw_rect(ui, self.x + self.w - bt, self.y, bt, self.h, bc)
    }
}

// align ///////////////////////////////////////////////////////////////////////

box_align :: proc(widget: ^sgui.Widget, x, y: f32) {
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
}

vbox_align :: proc(widget: ^sgui.Widget, x, y: f32) {
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
        sgui.widget_align(child, wx, wy)
    }
}

hbox_align :: proc(widget: ^sgui.Widget, x, y: f32) {
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
        sgui.widget_align(child, wx, wy)
    }
}

// resize //////////////////////////////////////////////////////////////////////

box_resize :: proc(widget: ^sgui.Widget, w, h: f32) {
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
}

vbox_resize :: proc(widget: ^sgui.Widget, w, h: f32) {
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
}

hbox_resize :: proc(widget: ^sgui.Widget, w, h: f32) {
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
}

box_find_content_w :: proc(widget: ^sgui.Widget, parent_w: f32) -> (w: f32, ttl_w: f32, max_w: f32) {
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
}

box_find_content_h :: proc(widget: ^sgui.Widget, parent_h: f32) -> (h: f32, ttl_h: f32, max_h: f32) {
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
}

box_resize_widget :: proc(widget: ^sgui.Widget, w, h: f32) {
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
}

box_expand_widget :: proc(widget: ^sgui.Widget, w, h: f32) {
    if widget.disabled do return
    widget.w = w
    widget.h = h
    if widget.resize != nil {
        widget->resize(w, h)
    }
}

box_update_size :: proc(widget: ^sgui.Widget, w, h: f32) {
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
}

// extra functions /////////////////////////////////////////////////////////////

box_add_widget :: proc(widget: ^sgui.Widget, child: ^sgui.Widget) {
    self := cast(^Box)widget
    if child.alignment_policy == {} {
        child.alignment_policy = sgui.AlignmentPolicy{.Top, .Left}
    }
    append(&self.widgets, child)
}
