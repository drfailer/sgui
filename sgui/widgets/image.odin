package widgets

import ".."
import "../gla"

Image :: struct {
    using widget: sgui.Widget,
    file: string,
    image: ^gla.Image,
    srcrect: sgui.Rect,
    iw, ih: f32,
}

image :: proc(
    file: string,
    w: f32 = 0,
    h: f32 = 0,
    srcrect := sgui.Rect{0, 0, 0, 0},
) -> ^sgui.Widget {
    image_w := new(Image)
    image_w^ = Image{
        init = image_init,
        destroy = image_destroy,
        draw = image_draw,
        file = file,
        srcrect = srcrect,
        iw = w,
        ih = h,
    }
    return image_w
}

image_init :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui, parent: ^sgui.Widget) {
    self := cast(^Image)widget
    self.image = sgui.create_image(ui, self.file, self.srcrect)
    w := self.image.w if self.iw == 0 else self.iw
    self.w = w
    self.min_w = w
    h := self.image.h if self.ih == 0 else self.ih
    self.h = h
    self.min_h = h
}

image_destroy :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Image)widget
    gla.image_destroy(self.image)
}

image_draw :: proc(widget: ^sgui.Widget, ui: ^sgui.Ui) {
    self := cast(^Image)widget
    sgui.draw_image(ui, self.image, self.x, self.y, self.w, self.h)
}
