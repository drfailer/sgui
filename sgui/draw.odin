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

draw_ring :: proc(handle: ^Handle, cx, cy, radius: f32, color: Color) {
    x := 0
    y := cast(int)-radius
    p := cast(int)-radius

    for x < -y {
        if p > 0 {
            // instead of drawing the outer point when diff < 0, we can draw it
            // here to have a more precise value at the cost of an extra sqrt
            // diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
            // if diff >= 0 {
            //     draw_circle_edge_pixel(handle, cx, cy, x, y, color, 1 - diff)
            // }
            y += 1
            p += 2 * (x + y) + 1
        } else {
            p += 2 * x + 1
        }

        xl1 := cx - cast(f32)x
        xr1 := cx + cast(f32)x
        xl2 := cx + cast(f32)y
        xr2 := cx - cast(f32)y
        w1 := xr1 - xl1 + 1
        w2 := xr2 - xl2 + 1

        diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
        if diff >= 0 {
            draw_circle_edge_pixel(handle, cx, cy, x, y, color, 1 - diff) // out
            draw_circle_edge_pixel(handle, cx, cy, x, y + 1, color, diff) // in
        } else {
            draw_circle_edge_pixel(handle, cx, cy, x, y, color, 1 + diff)  // in
            draw_circle_edge_pixel(handle, cx, cy, x, y - 1, color, -diff) // out
        }
        x += 1
    }
}

draw_circle_edge_pixel :: proc(handle: ^Handle, cx, cy: f32, x, y: int, color: Color, diff: f32) {
    color := color
    color.a = cast(u8)(cast(f32)color.a * diff)

    // top left
    draw_rect(handle, cx - cast(f32)x, cy + cast(f32)y, 1., 1., color)
    draw_rect(handle, cx + cast(f32)y, cy - cast(f32)x, 1., 1., color)

    // top right
    draw_rect(handle, cx + cast(f32)x, cy + cast(f32)y, 1., 1., color)
    draw_rect(handle, cx - cast(f32)y, cy - cast(f32)x, 1., 1., color)

    // bottom left
    draw_rect(handle, cx - cast(f32)x, cy - cast(f32)y, 1., 1., color)
    draw_rect(handle, cx + cast(f32)y, cy + cast(f32)x, 1., 1., color)

    // bottom right
    draw_rect(handle, cx + cast(f32)x, cy - cast(f32)y, 1., 1., color)
    draw_rect(handle, cx - cast(f32)y, cy + cast(f32)x, 1., 1., color)
}

draw_circle :: proc(handle: ^Handle, cx, cy, radius: f32, color: Color) {
    x := 0
    y := cast(int)-radius
    p := cast(int)-radius

    for x < -y {
        if p > 0 {
            // instead of drawing the outer point when diff < 0, we can draw it
            // here to have a more precise value at the cost of an extra sqrt
            // diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
            // if diff >= 0 {
            //     draw_circle_edge_pixel(handle, cx, cy, x, y, color, 1 - diff)
            // }
            y += 1
            p += 2 * (x + y) + 1
        } else {
            p += 2 * x + 1
        }

        xl1 := cx - cast(f32)x
        xr1 := cx + cast(f32)x
        xl2 := cx + cast(f32)y
        xr2 := cx - cast(f32)y
        w1 := xr1 - xl1 + 1
        w2 := xr2 - xl2 + 1

        diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
        if diff >= 0  {
            draw_circle_edge_pixel(handle, cx, cy, x, y, color, 1 - diff) // in

            // draw inside

            // top
            draw_rect(handle, xl1 + 1, cy + cast(f32)y, w1 - 2, 1., color)
            draw_rect(handle, xl2 + 1, cy - cast(f32)x, w2 - 2, 1., color)

            // bottom
            draw_rect(handle, xl1 + 1, cy - cast(f32)y, w1 - 2, 1., color)
            draw_rect(handle, xl2 + 1, cy + cast(f32)x, w2 - 2, 1., color)
        } else {
            draw_circle_edge_pixel(handle, cx, cy, x, y - 1, color, -diff) // out

            // draw inside

            // top
            draw_rect(handle, xl1, cy + cast(f32)y, w1, 1., color)
            draw_rect(handle, xl2, cy - cast(f32)x, w2, 1., color)

            // bottom
            draw_rect(handle, xl1, cy - cast(f32)y, w1, 1., color)
            draw_rect(handle, xl2, cy + cast(f32)x, w2, 1., color)
        }
        x += 1
    }
}

draw_rounded_box_corner_edge_pixel :: proc(handle: ^Handle, cx, cy: f32, x, y: int, w, h: f32, color: Color, diff: f32) {
    xl1 := cx - cast(f32)x - w
    xr1 := cx + cast(f32)x - 1
    xl2 := cx + cast(f32)y - w
    xr2 := cx - cast(f32)y - 1
    color := color
    color.a = cast(u8)(cast(f32)color.a * diff)

    // top left
    draw_rect(handle, xl1, cy + cast(f32)y, 1., 1., color)
    draw_rect(handle, xl2, cy - cast(f32)x, 1., 1., color)

    // top right
    draw_rect(handle, xr1, cy + cast(f32)y, 1., 1., color)
    draw_rect(handle, xr2, cy - cast(f32)x, 1., 1., color)

    // bottom left
    draw_rect(handle, xl1, cy - cast(f32)y + h, 1., 1., color)
    draw_rect(handle, xl2, cy + cast(f32)x + h, 1., 1., color)

    // bottom right
    draw_rect(handle, xr1, cy - cast(f32)y + h, 1., 1., color)
    draw_rect(handle, xr2, cy + cast(f32)x + h, 1., 1., color)
}

// TODO: update the draw rounded box

draw_rounded_box :: proc (handle: ^Handle, bx, by, bw, bh, radius: f32, color: Color) {
    if bw < radius || bh < radius {
        if bw < 1 || bh < 1 do return
        draw_rect(handle, bx, by, bw, bh, color)
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
            // Like circle, rounded corners anti-alizing can be improved at the
            // cost of an extra square root.
            // diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
            // if 0 < diff && diff < 1  {
            //     draw_rounded_box_corner_edge_pixel(handle, cx, cy, x, y, w, h, color, 1 - diff)
            // }
            y += 1
            p += 2 * (x + y) + 1
        } else {
            p += 2 * x + 1
        }

        xl1 := cx - cast(f32)x - w
        xr1 := cx + cast(f32)x - 1
        xl2 := cx + cast(f32)y - w
        xr2 := cx - cast(f32)y - 1
        w1 := xr1 - xl1 + 1
        w2 := xr2 - xl2 + 1

        diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
        if 0 < diff && diff < 1  {
            draw_rounded_box_corner_edge_pixel(handle, cx, cy, x, y, w, h, color, 1 - diff) // in

            // draw inside

            // top
            draw_rect(handle, xl1 + 1, cy + cast(f32)y, w1 - 2, 1., color)
            draw_rect(handle, xl2 + 1, cy - cast(f32)x, w2 - 2, 1., color)

            // bottom
            draw_rect(handle, xl1 + 1, cy - cast(f32)y + h, w1 - 2, 1., color)
            draw_rect(handle, xl2 + 1, cy + cast(f32)x + h, w2 - 2, 1., color)
        } else {
            draw_rounded_box_corner_edge_pixel(handle, cx, cy, x, y - 1, w, h, color, -diff) // out

            // draw inside

            // top
            draw_rect(handle, xl1, cy + cast(f32)y, w1, 1., color)
            draw_rect(handle, xl2, cy - cast(f32)x, w2, 1., color)

            // bottom
            draw_rect(handle, xl1, cy - cast(f32)y + h, w1, 1., color)
            draw_rect(handle, xl2, cy + cast(f32)x + h, w2, 1., color)
        }

        x += 1
    }
    draw_rect(handle, bx, by + radius, bw, h, color)
}

// TODO: we should be able to configure the ring/rounded frame border thickness!

draw_rounded_frame :: proc (handle: ^Handle, bx, by, bw, bh, radius: f32, color: Color) {
    if bw < radius || bh < radius {
        if bw < 1 || bh < 1 do return
        draw_rect(handle, bx, by, bw, 1, color)
        draw_rect(handle, bx, by + bh - 1, bw, 1, color)
        draw_rect(handle, bx, by, 1, bh, color)
        draw_rect(handle, bx + bw - 1, by, 1, bh, color)
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
            // Like circle, rounded corners anti-alizing can be improved at the
            // cost of an extra square root.
            // diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
            // if 0 < diff && diff < 1  {
            //     draw_rounded_box_corner_edge_pixel(handle, cx, cy, x, y, w, h, color, 1 - diff)
            // }
            y += 1
            p += 2 * (x + y) + 1
        } else {
            p += 2 * x + 1
        }

        xl1 := cx - cast(f32)x - w
        xr1 := cx + cast(f32)x - 1
        xl2 := cx + cast(f32)y - w
        xr2 := cx - cast(f32)y - 1
        w1 := xr1 - xl1 + 1
        w2 := xr2 - xl2 + 1

        diff := math.sqrt(cast(f32)(x * x + y * y)) - radius
        if diff >= 0  {
            draw_rounded_box_corner_edge_pixel(handle, cx, cy, x, y, w, h, color, 1 - diff) // out
            draw_rounded_box_corner_edge_pixel(handle, cx, cy, x, y + 1, w, h, color, diff) // in
        } else {
            draw_rounded_box_corner_edge_pixel(handle, cx, cy, x, y, w, h, color, 1 + diff)  // in
            draw_rounded_box_corner_edge_pixel(handle, cx, cy, x, y - 1, w, h, color, -diff) // out
        }
        x += 1
    }
    draw_rect(handle, bx + radius, by, bw - 2 * radius, 1, color)          // top
    draw_rect(handle, bx + radius, by + bh, bw - 2 * radius, 1, color)     // bottom
    draw_rect(handle, bx, by + radius, 1, bh - 2 * radius, color)          // left
    draw_rect(handle, bx + bw - 1, by + radius, 1, bh - 2 * radius, color) // right
}

draw_rounded_box_with_border :: proc (
    handle: ^Handle, bx, by, bw, bh, radius, border_thickness: f32, border_color: Color, color: Color) {
    draw_rounded_box(handle, bx, by, bw, bh, radius, color)
    draw_rounded_frame(handle, bx, by, bw, bh, radius, border_color)
}

// source: https://en.wikipedia.org/wiki/Xiaolin_Wu%27s_line_algorithm

fpart :: proc(x: f32) -> f32 {
    return x - math.floor(x)
}

rfpart :: proc(x: f32) -> f32 {
    return 1 - fpart(x)
}

draw_point_with_alpha :: proc(handle: ^Handle, x, y: f32, color: Color, intensity: f32) {
    color := color
    color.a = cast(u8)(cast(f32)color.a * intensity)
    draw_rect(handle, x, y, 1, 1, color)
}

swap :: proc(a, b: ^f32) {
    tmp := a^
    a^ = b^
    b^ = tmp
}

draw_line :: proc(handle: ^Handle, x0, y0, x1, y1: f32, color: Color) {
    steep := abs(y1 - y0) > abs(x1 - x0)
    x0, y0, x1, y1 := x0, y0, x1, y1

    if steep {
        swap(&x0, &y0)
        swap(&x1, &y1)
    }

    if x0 > x1 {
        swap(&x0, &x1)
        swap(&y0, &y1)
    }

    dx := x1 - x0
    dy := y1 - y0

    gradient := cast(f32)1.0
    if dx != 0 {
        gradient = dy / dx
    }

    // handle first endpoint
    xend := math.floor(x0)
    yend := y0 + gradient * (xend - x0)
    xgap := 1 - (x0 - xend)
    xpxl1 := xend
    ypxl1 := math.floor(yend)
    if steep {
        draw_point_with_alpha(handle, ypxl1, xpxl1, color, rfpart(yend) * xgap)
        draw_point_with_alpha(handle, ypxl1 + 1, xpxl1, color,  fpart(yend) * xgap)
    } else {
        draw_point_with_alpha(handle, xpxl1, ypxl1, color, rfpart(yend) * xgap)
        draw_point_with_alpha(handle, xpxl1, ypxl1 + 1, color, fpart(yend) * xgap)
    }
    intery := yend + gradient // first y-intersection for the main loop

    // handle second endpoint
    xend = math.ceil(x1)
    yend = y1 + gradient * (xend - x1)
    xgap = 1 - (xend - x1)
    xpxl2 := xend //this will be used in the main loop
    ypxl2 := math.floor(yend)
    if steep {
        draw_point_with_alpha(handle, ypxl2, xpxl2, color, rfpart(yend) * xgap)
        draw_point_with_alpha(handle, ypxl2+1, xpxl2, color, fpart(yend) * xgap)
    } else {
        draw_point_with_alpha(handle, xpxl2, ypxl2, color, rfpart(yend) * xgap)
        draw_point_with_alpha(handle, xpxl2, ypxl2+1, color, fpart(yend) * xgap)
    }

    // main loop
    if steep {
        for x in (xpxl1 + 1)..<xpxl2 {
            draw_point_with_alpha(handle, math.floor(intery), x, color, rfpart(intery))
            draw_point_with_alpha(handle, math.floor(intery) + 1, x, color,  fpart(intery))
            intery = intery + gradient
        }
    } else {
        for x in (xpxl1 + 1)..<xpxl2 {
            draw_point_with_alpha(handle, x, math.floor(intery), color, rfpart(intery))
            draw_point_with_alpha(handle, x, math.floor(intery) + 1, color, fpart(intery))
            intery = intery + gradient
        }
    }
}

draw_triangle :: proc(handle: ^Handle, x0, y0, x1, y1, x2, y2: f32, color: Color) {
    x0, y0, x1, y1, x2, y2 := x0, y0, x1, y1, x2, y2

    // sort the points
    if y0 > y1 {
        swap(&x0, &x1)
        swap(&y0, &y1)
    }
    if y1 > y2 {
        swap(&x1, &x2)
        swap(&y1, &y2)
    }
    if y0 > y1 {
        swap(&x0, &x1)
        swap(&y0, &y1)
    }

    dx02, dy02 := x0 - x2, y0 - y2
    dx01, dy01 := x0 - x1, y0 - y1
    dx12, dy12 := x1 - x2, y1 - y2
    a02 := dx02 / dy02
    a01 := dx01 / dy01
    a12 := dx12 / dy12

    // first half
    for iy := y0; iy <= y1; iy += 1. {
        xl := a02 * (iy - y0) + x0
        xr := a01 * (iy - y1) + x1
        if xl >= xr {
            swap(&xl, &xr)
        }
        draw_rect(handle, xl, iy, xr - xl, 1, color)
    }

    // second half
    for iy := y1; iy <= y2; iy += 1. {
        xl := a02 * (iy - y0) + x0
        xr := a12 * (iy - y2) + x2
        if xl >= xr {
            swap(&xl, &xr)
        }
        draw_rect(handle, xl, iy, xr - xl, 1, color)
    }
}
