package sgui

/*
 * Attachable widgets are data structures that should be attached to a parent
 * widget, therefore, they cannot be drawn on their own. The parent widget is
 * responsible to link the envent handlers.
 */

import "core:fmt"
import su "sdl_utils"
import sdl "vendor:sdl3"
import "core:log"

// scroll box //////////////////////////////////////////////////////////////////

ScrollBoxProperties :: bit_set[ScrollBoxProperty]
ScrollBoxProperty :: enum {
    ScrollbarInvisible,
    DisableHorizontalScroll,
    DisableVerticalScroll,
    // TODO: visible on hover
}

ScrollboxStyle :: struct {
    scrollbar_style: ScrollbarStyle,
}

ScrollboxAttributes :: struct {
    props: ScrollBoxProperties,
    style: ScrollboxStyle,
}

ScrollBoxData :: struct {
    enabled: bool,
    position: f32,
    target_position: f32,
    scrollbar: Scrollbar,
}

ScrollBox :: struct {
    parent: ^Widget,
    vertical: ScrollBoxData,
    horizontal: ScrollBoxData,
    attr: ScrollboxAttributes,
}

scrollbox :: proc(attr := OPTS.scrollbox_attr) -> ScrollBox {
    return ScrollBox{
        vertical = ScrollBoxData{
            scrollbar = scrollbar(ScrollbarAttributes{
                direction = .Vertical,
                style = attr.style.scrollbar_style,
            }),
        },
        horizontal = ScrollBoxData{
            scrollbar = scrollbar(ScrollbarAttributes{
                direction = .Horizontal,
                style = attr.style.scrollbar_style,
            }),
        },
        attr = attr,
    }
}

scrollbox_scroll_data :: proc(data: ^ScrollBoxData, count: i32, step: f32) {
    if count == 0 || step == 0 || data.scrollbar.parent_size > data.scrollbar.content_size do return
    data.target_position += cast(f32)count * step
    data.target_position = clamp(data.target_position, 0, data.scrollbar.content_size - data.scrollbar.parent_size)
}

scrollbox_scrolled_handler :: proc(scrollbox: ^ScrollBox, vcount, hcount: i32, vstep, hstep: f32) -> (scrolled: bool) {
    if .DisableVerticalScroll not_in scrollbox.attr.props && scrollbox.vertical.enabled {
        scrollbox_scroll_data(&scrollbox.vertical, vcount, vstep)
        scrolled = true
    }
    if .DisableHorizontalScroll not_in scrollbox.attr.props && scrollbox.horizontal.enabled {
        scrollbox_scroll_data(&scrollbox.horizontal, hcount, hstep)
        scrolled = true
    }
    return scrolled
}

scrollbox_clicked_handler :: proc(scrollbox: ^ScrollBox, event: MouseClickEvent) -> (clicked: bool) {
    if event.button == sdl.BUTTON_LEFT {
        if .DisableVerticalScroll not_in scrollbox.attr.props && scrollbox.vertical.enabled {
            clicked = scrollbar_clicked_hander(&scrollbox.vertical.scrollbar, event)
        }
        if .DisableHorizontalScroll not_in scrollbox.attr.props && scrollbox.horizontal.enabled {
            clicked |= scrollbar_clicked_hander(&scrollbox.horizontal.scrollbar, event)
        }
    }
    return clicked
}

scrollbox_dragged_handler :: proc(scrollbox: ^ScrollBox, event: MouseMotionEvent) -> (scrolled: bool) {
    if .DisableVerticalScroll not_in scrollbox.attr.props && scrollbox.vertical.enabled {
        scrolled = scrollbar_dragged_handler(&scrollbox.vertical.scrollbar, event)
    }
    if .DisableHorizontalScroll not_in scrollbox.attr.props && scrollbox.horizontal.enabled {
        scrolled |= scrollbar_dragged_handler(&scrollbox.horizontal.scrollbar, event)
    }
    return scrolled
}

scrollbox_init :: proc(scrollbox: ^ScrollBox, handle: ^Handle, parent: ^Widget) {
    scrollbox.parent = parent
    if .DisableHorizontalScroll not_in scrollbox.attr.props {
        scrollbar_init(&scrollbox.horizontal.scrollbar, handle, parent)
    }
    if .DisableVerticalScroll not_in scrollbox.attr.props {
        scrollbar_init(&scrollbox.vertical.scrollbar, handle, parent)
    }
}

scrollbox_data_udpate :: proc(data: ^ScrollBoxData) {
    if data.scrollbar.state == .Selected {
        data.position = data.scrollbar.bar_position
        data.target_position = data.position
    } else {
        if data.target_position > data.position {
            data.position += min(10, data.target_position - data.position)
        } else if data.target_position < data.position {
            data.position -= min(10, data.position - data.target_position)
        }
    }
}

scrollbox_update :: proc(scrollbox: ^ScrollBox, content_w, content_h: f32) {
    scrollbox_data_udpate(&scrollbox.vertical)
    scrollbox_data_udpate(&scrollbox.horizontal)

    // scrollbars
    scrollbox.vertical.enabled = content_h > scrollbox.parent.h
    scrollbox.horizontal.enabled = content_w > scrollbox.parent.w

    if scrollbox.vertical.enabled {
        scrollbar_update(&scrollbox.vertical.scrollbar, scrollbox.vertical.position,
                         content_h, scrollbox.parent.h, scrollbox.parent)
    }

    if scrollbox.horizontal.enabled {
        size := scrollbox.parent.w if !scrollbox.vertical.enabled else scrollbox.parent.w - SCROLLBAR_THICKNESS
        scrollbar_update(&scrollbox.horizontal.scrollbar, scrollbox.horizontal.position,
                         content_w, size, scrollbox.parent)
    }
}

scrollbox_draw :: proc(scrollbox: ^ScrollBox, handle: ^Handle) {
    if .DisableVerticalScroll not_in scrollbox.attr.props && scrollbox.vertical.enabled {
        scrollbar_draw(&scrollbox.vertical.scrollbar, handle);
    }
    if .DisableHorizontalScroll not_in scrollbox.attr.props && scrollbox.horizontal.enabled {
        scrollbar_draw(&scrollbox.horizontal.scrollbar, handle);
    }
}

// scrollbar ///////////////////////////////////////////////////////////////////

ScrollbarDirection :: enum {
    Vertical,
    Horizontal,
}

ScrollbarState :: enum { Idle, Selected, Hovered }

ScrollbarStyle :: struct {
    background_color: Color,
    color: [ScrollbarState]Color,
}

ScrollbarAttributes :: struct {
    style: ScrollbarStyle,
    direction: ScrollbarDirection,
}

// TODO: add a position (top, bottom, left, right)??
Scrollbar :: struct {
    x, y, w, h: f32,
    state: ScrollbarState,
    bar_size: f32,
    bar_position: f32,
    content_size: f32,
    parent_size: f32,
    // TODO: add precomputed scalled values
    attr: ScrollbarAttributes,
}

scrollbar :: proc(attr: ScrollbarAttributes) -> Scrollbar {
    return Scrollbar{
        attr = attr,
    }
}

mouse_on_scrollbar_bar :: proc(scrollbar: ^Scrollbar, mx, my: f32) -> (result: bool) {
    scale_factor := scrollbar.parent_size / scrollbar.content_size
    pos := scrollbar.bar_position * scale_factor
    size := scrollbar.bar_size * scale_factor
    if scrollbar.attr.direction == .Vertical {
        result = (scrollbar.x <= mx && mx <= scrollbar.x + scrollbar.w) \
              && (scrollbar.y + pos <= my && my <= scrollbar.y + size)
    } else {
        result = (scrollbar.x + pos <= mx && mx <= scrollbar.x + size) \
              && (scrollbar.y <= my && my <= scrollbar.y + scrollbar.h)
    }
    return result
}

scrollbar_clicked_hander :: proc(bar: ^Scrollbar, event: MouseClickEvent) -> bool {
    if !event.down && bar.state == .Selected {
        bar.state = .Hovered if mouse_on_scrollbar_bar(bar, event.x, event.y) else .Idle
    } else if bar.state == .Hovered {
        bar.state = .Selected
    }
    return bar.state == .Selected
}

scrollbar_dragged_handler :: proc(bar: ^Scrollbar, event: MouseMotionEvent) -> bool {
    if bar.state == .Idle {
        if mouse_on_scrollbar_bar(bar, event.x, event.y) {
            bar.state = .Hovered
        }
    } else if bar.state == .Selected {
        scale_factor := bar.parent_size / bar.content_size

        if bar.attr.direction == .Vertical {
            bar.bar_position += event.yd / scale_factor
        } else {
            bar.bar_position += event.xd / scale_factor
        }

        if bar.bar_position < 0 {
            bar.bar_position = 0
        } else if bar.bar_position > bar.content_size - bar.bar_size {
            bar.bar_position = bar.content_size - bar.bar_size
        }
    } else {
        bar.state = .Hovered if mouse_on_scrollbar_bar(bar, event.x, event.y) else .Idle
    }
    return true
}

scrollbar_init :: proc(self: ^Scrollbar, handle: ^Handle, parent: ^Widget) {}

scrollbar_update :: proc(bar: ^Scrollbar, position: f32, content_size, parent_size: f32, parent: ^Widget) {
    if bar.attr.direction == .Vertical {
        bar.x = parent.x + parent.w - SCROLLBAR_THICKNESS
        bar.y = parent.y
        bar.w = SCROLLBAR_THICKNESS
        bar.h = parent.h
        bar.parent_size = parent.h
    } else {
        bar.x = parent.x
        bar.y = parent.y + parent.h - SCROLLBAR_THICKNESS
        bar.w = parent.w
        bar.h = SCROLLBAR_THICKNESS
        bar.parent_size = parent.h
    }

    bar.bar_size = parent_size
    bar.bar_position = position
    bar.content_size = content_size
    bar.parent_size = parent_size
}

scrollbar_draw :: proc(bar: ^Scrollbar, handle: ^Handle) {
    scale_factor := bar.parent_size / bar.content_size
    x, y, w, h := bar.x, bar.y, bar.w, bar.h

    if bar.attr.direction == .Vertical {
        w = SCROLLBAR_THICKNESS
        h = bar.parent_size
    } else {
        h = SCROLLBAR_THICKNESS
        w = bar.parent_size
    }
    draw_rect(handle, x, y, w, h, bar.attr.style.background_color)
    if bar.attr.direction == .Vertical {
        y = bar.y + bar.bar_position * scale_factor
        h = bar.bar_size * scale_factor
    } else {
        x = bar.x + bar.bar_position * scale_factor
        w = bar.bar_size * scale_factor
    }
    draw_rounded_box(handle, x, y, w, h, 5, bar.attr.style.color[bar.state])
}

// zoom box ////////////////////////////////////////////////////////////////////

ZoomBox :: struct {
    parent: ^Widget,
    lvl: f32,
    min, max, inc: f32,
}

zoombox :: proc(min, max, inc: f32, lvl: f32 = 1.) -> ZoomBox {
    return ZoomBox{
        lvl = lvl,
        min = min,
        max = max,
        inc = inc,
    }
}

zoombox_init :: proc(zoombox: ^ZoomBox, parent: ^Widget) {
    zoombox.parent = parent
}

zoombox_zoom_handler :: proc(zoombox: ^ZoomBox, x, y: i32, mods: bit_set[KeyMod]) -> bool {
    if .Control not_in mods {
        return false
    }
    if y == -1 {
        zoombox.lvl -= zoombox.inc
    } else if y == 1 {
        zoombox.lvl += zoombox.inc
    } else {
        return false
    }
    zoombox.lvl = clamp(zoombox.lvl, zoombox.min, zoombox.max)
    return true
}
