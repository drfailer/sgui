package widgets

/*
 * This file contains the tools used by widgets such as scrollbars, magnifiers,
 * ...
 */

// TODO: the scrollbar should be a widget

import "core:fmt"
import "../gla"
import ".."
import "core:log"

// scrollbar ///////////////////////////////////////////////////////////////////

MIN_SCROLLBAR_THUMB_SIZE :: 10

/*
 * Logic for drawing and using a scrollbar in a particular direction.
 */

ScrollbarDirection :: enum {
    Vertical,
    Horizontal,
}

ScrollbarStyle :: struct {
    track_color: sgui.Color,
    track_padding: Padding,
    thumb_color: [sgui.WidgetMouseState]sgui.Color,
    button_color: [sgui.WidgetMouseState]sgui.Color,
}

Scrollbar :: struct {
    enabled: bool,
    hovered: bool,
    x, y: f32,
    direction: ScrollbarDirection,
    thumb_size: f32,
    track_size: f32,
    window_size: f32,
    content_size: f32,
    position: f32,
    thumb_position: f32,
    scale_factor: f32,
    thumb_scroll_step: f32,
    content_pixel_ratio: f32,
    scroll_step: f32,
    // states
    thumb_state: sgui.WidgetMouseState,
    button1_state: sgui.WidgetMouseState,
    button2_state: sgui.WidgetMouseState,
    style: ScrollbarStyle,
}

scrollbar_resize :: proc(self: ^Scrollbar, window_size, content_size: f32) {
    padding: f32

    self.enabled = content_size > window_size

    if !self.enabled do return

    // Adapt the scrollbar position to the zoom lvl. If this is not done, the
    // scrollbar moves when zooming and dezooming.
    if self.content_size != content_size {
        self.position *= content_size / self.content_size
    }

    self.window_size = window_size
    self.content_size = content_size

    if self.direction == .Vertical {
        padding = self.style.track_padding.top + self.style.track_padding.bottom
    } else {
        padding = self.style.track_padding.left + self.style.track_padding.right
    }

    self.track_size = window_size - 2 * SCROLLBAR_THICKNESS - padding
    self.scale_factor = self.track_size / content_size

    thumb_size := self.window_size * self.scale_factor
    if thumb_size >= MIN_SCROLLBAR_THUMB_SIZE {
        self.thumb_size = thumb_size
        self.thumb_scroll_step = 1
    } else {
        self.thumb_size = MIN_SCROLLBAR_THUMB_SIZE
        self.thumb_scroll_step = (self.track_size - thumb_size) / (self.track_size - MIN_SCROLLBAR_THUMB_SIZE)
    }
    self.content_pixel_ratio = self.thumb_scroll_step / self.scale_factor
    // make sure the current position fits in the new dimensions
    scrollbar_update_position(self, self.position)
}

scrollbars_align :: proc(self: ^Scrollbars, x, y: f32) {
    // TODO: configurable positions???
    self.vertical.x = x + self.window_w - SCROLLBAR_THICKNESS
    self.vertical.y = y
    self.horizontal.x = x
    self.horizontal.y = y + self.window_h - SCROLLBAR_THICKNESS
}

scrollbar_update_position :: proc(self: ^Scrollbar, position: f32) {
    self.position = clamp(position, 0, self.content_size - self.window_size)
    self.thumb_position = self.position / self.content_pixel_ratio
}

scrollbar_update :: proc(self: ^Scrollbar, ui: ^sgui.Ui) -> bool {
    updated := false
    // scroll while buttons are clicked
    if self.button1_state == .Clicked {
        scrollbar_scroll_handler(self, -1, 10)
        updated = true
    } else if self.button2_state == .Clicked {
        scrollbar_scroll_handler(self, 1, 10)
        updated = true
    }
    return updated
}

scrollbar_buttons_draw :: proc(self: ^Scrollbar, ui: ^sgui.Ui) {
    if self.direction == .Vertical {
        XOFFSET :: 0
        YOFFSET :: 2
        sgui.draw_triangle( // ^
            ui,
            self.x + XOFFSET,                       self.y + SCROLLBAR_THICKNESS - YOFFSET,
            self.x + SCROLLBAR_THICKNESS / 2,       self.y + YOFFSET,
            self.x + SCROLLBAR_THICKNESS - XOFFSET, self.y + SCROLLBAR_THICKNESS - YOFFSET,
            self.style.button_color[self.button1_state]
        )
        sgui.draw_triangle( // v
            ui,
            self.x + XOFFSET,                       self.y + self.window_size - SCROLLBAR_THICKNESS + YOFFSET,
            self.x + SCROLLBAR_THICKNESS / 2,       self.y + self.window_size - YOFFSET,
            self.x + SCROLLBAR_THICKNESS - XOFFSET, self.y + self.window_size - SCROLLBAR_THICKNESS + YOFFSET,
            self.style.button_color[self.button2_state]
        )
    } else {
        XOFFSET :: 2
        YOFFSET :: 0
        sgui.draw_triangle( // <
            ui,
            self.x + SCROLLBAR_THICKNESS - XOFFSET, self.y + YOFFSET,
            self.x + XOFFSET,                       self.y + SCROLLBAR_THICKNESS / 2,
            self.x + SCROLLBAR_THICKNESS - XOFFSET, self.y + SCROLLBAR_THICKNESS - YOFFSET,
            self.style.button_color[self.button1_state]
        )
        sgui.draw_triangle( // >
            ui,
            self.x + self.window_size - SCROLLBAR_THICKNESS + XOFFSET, self.y + YOFFSET,
            self.x + self.window_size - XOFFSET,                       self.y + SCROLLBAR_THICKNESS / 2,
            self.x + self.window_size - SCROLLBAR_THICKNESS + XOFFSET, self.y + SCROLLBAR_THICKNESS - YOFFSET,
            self.style.button_color[self.button2_state]
        )
    }
}

scrollbar_draw :: proc(self: ^Scrollbar, ui: ^sgui.Ui) {
    if !self.enabled do return

    // TODO: button background in style
    // TODO: border in style
    // TODO: thumb style (rounded/squared/border)
    if self.direction == .Vertical {
        thumb_thickness := SCROLLBAR_THICKNESS - (self.style.track_padding.left + self.style.track_padding.right)
        sgui.draw_rect(ui, self.x, self.y, SCROLLBAR_THICKNESS, self.window_size, self.style.track_color)
        sgui.draw_rounded_box(ui,
            self.x + self.style.track_padding.left,
            self.y + self.thumb_position + SCROLLBAR_THICKNESS,
            thumb_thickness,
            self.thumb_size,
            thumb_thickness / 2,
            self.style.thumb_color[self.thumb_state]
        )
    } else {
        thumb_thickness := SCROLLBAR_THICKNESS - (self.style.track_padding.top + self.style.track_padding.bottom)
        sgui.draw_rect(ui, self.x, self.y, self.window_size, SCROLLBAR_THICKNESS, self.style.track_color)
        sgui.draw_rounded_box(ui,
            self.x + self.thumb_position + SCROLLBAR_THICKNESS,
            self.y + self.style.track_padding.top,
            self.thumb_size,
            thumb_thickness,
            thumb_thickness / 2,
            self.style.thumb_color[self.thumb_state]
        )
    }

    scrollbar_buttons_draw(self, ui)
}

scrollbar_scroll_handler :: proc(self: ^Scrollbar, scroll_count: i32, scroll_step: f32) {
    scrollbar_update_position(self, self.position + cast(f32)scroll_count * scroll_step)
}

scrollbar_mouse_on_thumb :: proc(self: ^Scrollbar, mx, my: f32) -> (result: bool) {
    if self.direction == .Vertical {
        tx := self.x + self.style.track_padding.left
        ty := self.y + self.thumb_position + SCROLLBAR_THICKNESS

        result = (tx <= mx && mx <= tx + SCROLLBAR_THICKNESS) \
              && (ty <= my && my <= ty + self.thumb_size)
    } else {
        tx := self.x + self.thumb_position + SCROLLBAR_THICKNESS
        ty := self.y + self.style.track_padding.top

        result = (tx <= mx && mx <= tx + self.thumb_size) \
              && (ty <= my && my <= ty + SCROLLBAR_THICKNESS)
    }
    return result
}

scrollbar_mouse_on_track :: proc(self: ^Scrollbar, mx, my: f32) -> (result: bool) {
    if self.direction == .Vertical {
        result = (self.x <= mx && mx <= self.x + SCROLLBAR_THICKNESS) \
              && (self.y + SCROLLBAR_THICKNESS <= my && my <= self.y + self.track_size)
    } else {
        result = (self.x + SCROLLBAR_THICKNESS <= mx && mx <= self.x + self.track_size) \
              && (self.y <= my && my <= self.y + SCROLLBAR_THICKNESS)
    }
    return result
}

scrollbar_mouse_on_button1 :: proc(self: ^Scrollbar, mx, my: f32) -> (result: bool){
    result = (self.x <= mx && mx <= self.x + SCROLLBAR_THICKNESS) \
          && (self.y <= my && my <= self.y + SCROLLBAR_THICKNESS)
    return result
}

scrollbar_mouse_on_button2 :: proc(self: ^Scrollbar, mx, my: f32) -> (result: bool) {
    if self.direction == .Vertical {
        by := self.y + self.window_size - SCROLLBAR_THICKNESS
        result = (self.x <= mx && mx <= self.x + SCROLLBAR_THICKNESS) \
              && (by <= my && my <= by + SCROLLBAR_THICKNESS)
    } else {
        bx := self.x + self.window_size - SCROLLBAR_THICKNESS
        result = (bx <= mx && mx <= bx + SCROLLBAR_THICKNESS) \
              && (self.y <= my && my <= self.y + SCROLLBAR_THICKNESS)
    }
    return result
}

/* event handlers */

scrollbar_hover :: proc(self: ^Scrollbar, mx, my: f32) {
        self.thumb_state = .Idle
        self.button1_state = .Idle
        self.button2_state = .Idle
        self.hovered = false
        if scrollbar_mouse_on_thumb(self, mx, my) {
            self.thumb_state = .Hovered
            self.hovered = true
        } else if scrollbar_mouse_on_button1(self, mx, my) {
            self.button1_state = .Hovered
            self.hovered = true
        } else if scrollbar_mouse_on_button2(self, mx, my) {
            self.button2_state = .Hovered
            self.hovered = true
        }
}

scrollbar_click_handler :: proc(self: ^Scrollbar, event: sgui.MouseClickEvent) {
    if event.down {
        if self.thumb_state == .Hovered {
            self.thumb_state = .Clicked
        } else if self.button1_state == .Hovered {
            self.button1_state = .Clicked
        } else if self.button2_state == .Hovered {
            self.button2_state = .Clicked
        } else if scrollbar_mouse_on_track(self, event.x, event.y) {
            if self.direction == .Vertical {
                scrollbar_update_position(self, (cast(f32)event.y - self.y) * self.content_pixel_ratio - self.window_size / 2)
            } else {
                scrollbar_update_position(self, (cast(f32)event.x - self.x) * self.content_pixel_ratio - self.window_size / 2)
            }
        }
    } else {
        scrollbar_hover(self, event.x, event.y)
    }
}

scrollbar_mouse_motion_handler :: proc(self: ^Scrollbar, event: sgui.MouseMotionEvent) {
    if self.thumb_state == .Clicked {
        if self.direction == .Vertical {
            scrollbar_update_position(self, self.position + cast(f32)event.yd * self.content_pixel_ratio)
        } else {
            scrollbar_update_position(self, self.position + cast(f32)event.xd * self.content_pixel_ratio)
        }
    } else if self.button1_state != .Clicked && self.button2_state != .Clicked {
        scrollbar_hover(self, event.x, event.y)
    }
}

// scrollbars //////////////////////////////////////////////////////////////////

/*
 * Logic for drawing and using two scrollbars in two directions.
 */

ScrollbarsProperties :: bit_set[ScrollbarsProperty]
ScrollbarsProperty :: enum {
    V_Disabled,
    H_Disabled,
    V_ShowOnHover,
    H_ShowOnHover,
}

ScrollbarsAttributes :: struct {
    style: ScrollbarStyle,
    props: ScrollbarsProperties,
}

Scrollbars :: struct {
    window_w, window_h: f32,
    vertical: Scrollbar,
    horizontal: Scrollbar,
    attr: ScrollbarsAttributes,
}

scrollbars_create :: proc(attr := OPTS.scrollbars_attr) -> Scrollbars {
    return Scrollbars{
        vertical = Scrollbar{
            direction = .Vertical,
            style = attr.style,
        },
        horizontal = Scrollbar{
            direction = .Horizontal,
            style = attr.style,
        },
        attr = attr,
    }
}

scrollbars_resize :: proc(self: ^Scrollbars, window_w, window_h, content_w, content_h: f32) {
    window_w := window_w
    self.window_w = window_w
    self.window_h = window_h

    if .V_Disabled not_in self.attr.props {
        scrollbar_resize(&self.vertical, window_h, content_h)
        if self.vertical.enabled && .V_ShowOnHover not_in self.attr.props && window_w < content_w {
            window_w -= SCROLLBAR_THICKNESS
        }
    }
    if .H_Disabled not_in self.attr.props {
        scrollbar_resize(&self.horizontal, window_w, content_w)
    }
}

scrollbars_update :: proc(self: ^Scrollbars, ui: ^sgui.Ui) -> bool {
    updated := false

    if self.vertical.enabled && .V_Disabled not_in self.attr.props {
        updated |= scrollbar_update(&self.vertical, ui)
    }
    if self.horizontal.enabled && .H_Disabled not_in self.attr.props {
        updated |= scrollbar_update(&self.horizontal, ui)
    }
    return updated
}

scrollbars_draw :: proc(self: ^Scrollbars, ui: ^sgui.Ui) {
    if .V_Disabled not_in self.attr.props {
        if .V_ShowOnHover not_in self.attr.props || self.vertical.hovered {
            scrollbar_draw(&self.vertical, ui)
        }
    }
    if .H_Disabled not_in self.attr.props {
        if .H_ShowOnHover not_in self.attr.props || self.horizontal.hovered {
            scrollbar_draw(&self.horizontal, ui)
        }
    }
}

/* event handlers */

scrollbars_scroll_handler :: proc(self: ^Scrollbars, vcount, hcount: i32, vstep, hstep: f32) {
    if self.vertical.enabled && .V_Disabled not_in self.attr.props {
        scrollbar_scroll_handler(&self.vertical, vcount, vstep)
    }
    if self.horizontal.enabled && .H_Disabled not_in self.attr.props {
        scrollbar_scroll_handler(&self.horizontal, hcount, hstep)
    }
}

scrollbars_click_handler :: proc(self: ^Scrollbars, event: sgui.MouseClickEvent) {
    // TODO: do not test the second bar if the first is true
    if self.vertical.enabled && .V_Disabled not_in self.attr.props {
        scrollbar_click_handler(&self.vertical, event)
    }
    if self.horizontal.enabled && .H_Disabled not_in self.attr.props {
        scrollbar_click_handler(&self.horizontal, event)
    }
}

scrollbars_mouse_motion_handler :: proc(self: ^Scrollbars, event: sgui.MouseMotionEvent) {
    // TODO: do not test the second bar if the first is true
    if self.vertical.enabled && .V_Disabled not_in self.attr.props {
        scrollbar_mouse_motion_handler(&self.vertical, event)
    }
    if self.horizontal.enabled && .H_Disabled not_in self.attr.props {
        scrollbar_mouse_motion_handler(&self.horizontal, event)
    }
}

/*
 * Utility function that sets event handler for the scrollbars. This functions
 * expects that the given widget store the scrollbars in a field named
 * `scrollbars`.
 */
scrollbars_set_event_handlers :: proc(parent_widget: $T, ui: ^sgui.Ui) {
    sgui.add_event_handler(ui, parent_widget, proc(widget: ^sgui.Widget, event: sgui.MouseWheelEvent, ui: ^sgui.Ui) -> bool {
        if !sgui.widget_is_hovered(widget, ui.mouse_x, ui.mouse_y) do return false
        self := cast(T)widget

        if event.mods == {} {
            scrollbars_scroll_handler(&self.scrollbars, -event.y, -event.x, 100, 100)
            sgui.widget_align(self, self.x, self.y)
        }
        return true
    })
    sgui.add_event_handler(ui, parent_widget, proc(widget: ^sgui.Widget, event: sgui.MouseClickEvent, ui: ^sgui.Ui) -> bool {
        self := cast(T)widget
        scrollbars_click_handler(&self.scrollbars, event)
        return true
    })
    sgui.add_event_handler(ui, parent_widget, proc(widget: ^sgui.Widget, event: sgui.MouseMotionEvent, ui: ^sgui.Ui) -> bool {
        self := cast(T)widget
        scrollbars_mouse_motion_handler(&self.scrollbars, event)
        sgui.widget_align(self, self.x, self.y)
        return true
    })
}

// zoom box ////////////////////////////////////////////////////////////////////

// TODO: this should be called a mignifier and the draw function would draw the zoom buttons

ZoomBox :: struct {
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

zoombox_zoom_handler :: proc(zoombox: ^ZoomBox, x, y: i32, mods: bit_set[sgui.KeyMod]) -> bool {
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
