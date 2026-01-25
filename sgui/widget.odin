package sgui

/*
 * How widgets should work:
 * - w(args, attr): create the widget.
 * - w_init(w, ui, parent): initialize the widget and allocates underlying data structures.
 * - w_destroy(w, ui): called when the widget is destroyed.
 * - w_update(w, ui): updated the widget before drawing a new frame.
 * - w_draw(w, ui): draw the widget.
 * - w_resize(w, pw, ph) && w_align(w, px, py): resize and align components inside the widget (used by layout widgets).
 */

// TODO: we need a better way to locate hovered widgets to avoid scrolling issues
// TODO: we should be able to specify the allocator to widget constructors

import "core:fmt"
import gla "gla"
import sdl "vendor:sdl3"
import sdl_img "vendor:sdl3/image"
import "core:strings"
import "core:log"

// widget //////////////////////////////////////////////////////////////////////

WidgetInitProc :: proc(widget: ^Widget, ui: ^Ui, parent: ^Widget)
WidgetDestroyProc :: proc(widget: ^Widget, ui: ^Ui)
WidgetUpdateProc :: proc(widget: ^Widget, ui: ^Ui, parent: ^Widget)
WidgetDrawProc :: proc(widget: ^Widget, ui: ^Ui)
WidgetResizeProc :: proc(widget: ^Widget, pw, ph: f32)
WidgetAlignProc :: proc(widget: ^Widget, px, py: f32)

AlignmentPolicy :: bit_set[AlignmentFlag]
AlignmentFlag :: enum {
    Left,
    Right,
    Top,
    Bottom,
    VCenter,
    HCenter,
}

SizePolicy :: bit_set[SizeFlag]
SizeFlag :: enum {
    FillW,
    FillH,
    // TODO: ratio / relative to a widget??
}

Widget :: struct {
    /* position and dimentions */
    x, y, w, h: f32,
    min_w, min_h: f32,
    z_index: u64,

    /* flags */
    disabled: bool,
    invisible: bool,
    focused: bool,

    /* childs widgets if any */
    children: [dynamic]^Widget,

    /* policies */
    size_policy: SizePolicy,
    alignment_policy: AlignmentPolicy,

    /* procs */
    init: WidgetInitProc,
    destroy: WidgetDestroyProc,
    update: WidgetUpdateProc,
    draw: WidgetDrawProc,
    resize: WidgetResizeProc,
    align: WidgetAlignProc,
}

WidgetMouseState :: enum {
    Idle,
    Hovered,
    Clicked,
}

widget_init :: proc(widget: ^Widget, ui: ^Ui) {
    if widget.init == nil do return
    root := Widget{
        x = 0,
        y = 0,
        w = cast(f32)ui.window_w,
        h = cast(f32)ui.window_h,
    }
    widget->init(ui, &root)
    widget_resize(widget, ui)
}

widget_destroy :: proc(widget: ^Widget, ui: ^Ui) {
    if widget.destroy == nil do return
    widget->destroy(ui)
}

widget_resize :: proc(widget: ^Widget, ui: ^Ui) {
    if widget.disabled do return
    if .FillW in widget.size_policy {
        widget.w = ui.window_w
    }
    if .FillH in widget.size_policy {
        widget.h = ui.window_h
    }
    if widget.resize != nil {
        widget->resize(ui.window_w, ui.window_h)
    }
    widget_align(widget, 0, 0)
}

widget_align :: proc(widget: ^Widget, x, y: f32) {
    widget.x = x
    widget.y = y
    if widget.align != nil {
        widget->align(x, y)
    }
}

widget_update :: proc(ui: ^Ui, widget: ^Widget) {
    if widget.update == nil do return
    root := Widget{
        x = ui.rel_rect.x,
        y = ui.rel_rect.y,
        w = ui.rel_rect.w,
        h = ui.rel_rect.h,
    }
    widget->update(ui, &root)
}

widget_draw :: proc(widget: ^Widget, ui: ^Ui) {
    // if widget.draw == nil do return // assume it is never the case
    if !ui.processing_ordered_draws && widget.z_index > 0 {
        add_ordered_draw(ui, widget)
    } else if !widget.disabled && !widget.invisible {
        widget->draw(ui)
    }
}

// TODO: need a way to know which widget is actually hovered
widget_is_hovered :: proc(widget: ^Widget, mx, my: f32) -> bool {
    return mouse_on_region(mx, my, widget.x, widget.y, widget.w, widget.h)
}

widget_enable :: proc(widget: ^Widget, ui: ^Ui) {
    widget.disabled = false
    ui.resize = true
}

widget_disable :: proc(widget: ^Widget, ui: ^Ui) {
    widget.disabled = true
    ui.resize = true
}

widget_toggle :: proc(widget: ^Widget, ui: ^Ui) {
    widget.disabled = !widget.disabled
    ui.resize = true
}

// align functions //

align_widgets :: proc(widget: ^Widget, alignment_policy: = AlignmentPolicy{.Top, .Left}) -> (result: ^Widget) {
    widget.alignment_policy = alignment_policy
    return widget
}

center :: proc(widget: ^Widget) -> ^Widget {
    return align_widgets(widget, alignment_policy = AlignmentPolicy{.HCenter, .VCenter})
}

left :: proc(widget: ^Widget) -> ^Widget {
    return align_widgets(widget, alignment_policy = AlignmentPolicy{.Left})
}

right :: proc(widget: ^Widget) -> ^Widget {
    return align_widgets(widget, alignment_policy = AlignmentPolicy{.Right})
}
