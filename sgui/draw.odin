package sgui

import "core:math"

// TODO

@(private="file")
multiply_color :: proc(color: Color, a: f32) -> Color {
    return Color{
        cast(u8)(cast(f32)color.r * a),
        cast(u8)(cast(f32)color.g * a),
        cast(u8)(cast(f32)color.b * a),
        color.a,
    }
}

distance_ceil :: proc(r, y: f32) -> f32 {
    x := math.sqrt(r * r - y * y)
    return math.ceil(x) - x
}

draw_circle :: proc (handle: ^SGUIHandle, cx, cy, radius: f32, color: Color) {
    x := 0
    y := cast(int)-radius
    p := cast(int)-radius

    for x < -y {
        if p > 0 {
            y += 1
            p += 2 * (x + y) + 1
        } else {
            p += 2 * x + 1
        }
        // top right
        handle->draw_rect(Rect{cx + cast(f32)x, cy + cast(f32)y, 1., 1.}, color)
        handle->draw_rect(Rect{cx - cast(f32)y, cy - cast(f32)x, 1., 1.}, color)

        // top left
        handle->draw_rect(Rect{cx - cast(f32)x, cy + cast(f32)y, 1., 1.}, color)
        handle->draw_rect(Rect{cx + cast(f32)y, cy - cast(f32)x, 1., 1.}, color)

        // bottom right
        handle->draw_rect(Rect{cx + cast(f32)x, cy - cast(f32)y, 1., 1.}, color)
        handle->draw_rect(Rect{cx - cast(f32)y, cy + cast(f32)x, 1., 1.}, color)

        // bottom left
        handle->draw_rect(Rect{cx - cast(f32)x, cy - cast(f32)y, 1., 1.}, color)
        handle->draw_rect(Rect{cx + cast(f32)y, cy + cast(f32)x, 1., 1.}, color)
        x += 1
    }
}

draw_rounded_box_from_values :: proc (handle: ^SGUIHandle, bx, by, bw, bh, radius: f32, color: Color) {
    if bw < radius || bh < radius {
        return
    }

    cx := bx + bw - radius
    cy := by + radius
    x := 0
    y := cast(int)-radius
    p := cast(int)-radius
    w := bw - 2 * radius
    h := bh - 2 * radius

    for x < -y {
        if p > 0 {
            y += 1
            p += 2 * (x + y) + 1
        } else {
            p += 2 * x + 1
        }

        // top
        tx1 := cx - cast(f32)x
        tw1 := cx + cast(f32)x - tx1
        tx2 := cx + cast(f32)y
        tw2 := cx - cast(f32)y - tx2
        handle->draw_rect(Rect{tx1 - w, cy + cast(f32)y, tw1 + w, 1.}, color)
        handle->draw_rect(Rect{tx2 - w, cy - cast(f32)x, tw2 + w, 1.}, color)

        // bottom
        bx1 := cx - cast(f32)x
        bw1 := cx + cast(f32)x - bx1
        bx2 := cx + cast(f32)y
        bw2 := cx - cast(f32)y - bx2
        handle->draw_rect(Rect{bx1 - w, cy - cast(f32)y + h, bw1 + w, 1.}, color)
        handle->draw_rect(Rect{bx2 - w, cy + cast(f32)x + h, bw2 + w, 1.}, color)

        x += 1
    }
    handle->draw_rect(Rect{bx, by + radius, bw, h}, color)
}

draw_rounded_box_from_rect :: proc (handle: ^SGUIHandle, rect: Rect, radius: f32, color: Color) {
    draw_rounded_box_from_values(handle, rect.x, rect.y, rect.w, rect.h, radius, color)
}

draw_rounded_box :: proc {
    draw_rounded_box_from_values,
    draw_rounded_box_from_rect,
}
