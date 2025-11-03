package sgui

import "core:math"
import sdl "vendor:sdl3"

import "core:fmt"

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
    x := math.sqrt(abs(r * r - y * y))
    return math.ceil(x) - x
}

draw_circle :: proc(handle: ^Handle, cx, cy, radius: f32, color: Color) {
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
        handle->draw_rect(cx + cast(f32)x, cy + cast(f32)y, 1., 1., color)
        handle->draw_rect(cx - cast(f32)y, cy - cast(f32)x, 1., 1., color)

        // top left
        handle->draw_rect(cx - cast(f32)x, cy + cast(f32)y, 1., 1., color)
        handle->draw_rect(cx + cast(f32)y, cy - cast(f32)x, 1., 1., color)

        // bottom right
        handle->draw_rect(cx + cast(f32)x, cy - cast(f32)y, 1., 1., color)
        handle->draw_rect(cx - cast(f32)y, cy + cast(f32)x, 1., 1., color)

        // bottom left
        handle->draw_rect(cx - cast(f32)x, cy - cast(f32)y, 1., 1., color)
        handle->draw_rect(cx + cast(f32)y, cy + cast(f32)x, 1., 1., color)
        x += 1
    }
}

draw_rounded_box_from_values :: proc (handle: ^Handle, bx, by, bw, bh, radius: f32, color: Color) {
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

    a := cast(f32)color.a

    for x < -y {
        if p > 0 {
            y += 1
            p += 2 * (x + y) + 1
        } else {
            p += 2 * x + 1
        }

        xl1 := cx - cast(f32)x - w
        xr1 := cx + cast(f32)x
        xl2 := cx + cast(f32)y - w
        xr2 := cx - cast(f32)y
        w1 := xr1 - xl1
        w2 := xr2 - xl2

        diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
        if 0 < diff && diff < 1  {
            {
                color := color
                color.a = cast(u8)(a * (1 - diff))

                // top left
                handle->draw_rect(xl1, cy + cast(f32)y, 1., 1., color)
                handle->draw_rect(xl2, cy - cast(f32)x, 1., 1., color)

                // top right
                handle->draw_rect(xr1 - 1, cy + cast(f32)y, 1., 1., color)
                handle->draw_rect(xr2 - 1, cy - cast(f32)x, 1., 1., color)

                // bottom left
                handle->draw_rect(xl1, cy - cast(f32)y + h, 1., 1., color)
                handle->draw_rect(xl2, cy + cast(f32)x + h, 1., 1., color)

                // bottom right
                handle->draw_rect(xr1 - 1, cy - cast(f32)y + h, 1., 1., color)
                handle->draw_rect(xr2 - 1, cy + cast(f32)x + h, 1., 1., color)
            }

            // draw inside

            // top
            handle->draw_rect(xl1 + 1, cy + cast(f32)y, w1 - 2, 1., color)
            handle->draw_rect(xl2 + 1, cy - cast(f32)x, w2 - 2, 1., color)

            // bottom
            handle->draw_rect(xl1 + 1, cy - cast(f32)y + h, w1 - 2, 1., color)
            handle->draw_rect(xl2 + 1, cy + cast(f32)x + h, w2 - 2, 1., color)
        } else {
            // top
            handle->draw_rect(xl1, cy + cast(f32)y, w1, 1., color)
            handle->draw_rect(xl2, cy - cast(f32)x, w2, 1., color)

            // bottom
            handle->draw_rect(xl1, cy - cast(f32)y + h, w1, 1., color)
            handle->draw_rect(xl2, cy + cast(f32)x + h, w2, 1., color)
        }

        x += 1
    }
    handle->draw_rect(bx, by + radius, bw, h, color)
}

draw_rounded_box_from_rect :: proc (handle: ^Handle, rect: Rect, radius: f32, color: Color) {
    draw_rounded_box_from_values(handle, rect.x, rect.y, rect.w, rect.h, radius, color)
}

draw_rounded_box :: proc {
    draw_rounded_box_from_values,
    draw_rounded_box_from_rect,
}
