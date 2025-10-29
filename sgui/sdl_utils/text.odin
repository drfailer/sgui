package sdl_utils

import "core:fmt"
import "core:c"
import "core:strings"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"

Text :: struct {
    text_engine: ^sdl_ttf.TextEngine,
    font: ^sdl_ttf.Font,
    text: ^sdl_ttf.Text,
    value: cstring,
}

// ideas:
// - font cache to store fonts
// - text cache to store text and draw + create at the same time?

text_create :: proc(text_engine: ^sdl_ttf.TextEngine, font: ^sdl_ttf.Font, text: string) -> Text {
    ctext := strings.clone_to_cstring(text)
    return Text{text_engine, font, sdl_ttf.CreateText(text_engine, font, ctext, len(text)), ctext}
}

text_destroy :: proc(text: ^Text) {
    sdl_ttf.DestroyText(text.text)
    delete(text.value)
}

text_update_text :: proc(text: ^Text, value: string, color: sdl.Color) {
    delete(text.value)
    text.value = strings.clone_to_cstring(value)
    sdl_ttf.SetTextString(text.text, text.value, len(value))
    sdl_ttf.SetTextColor(text.text, color.r, color.g, color.b, color.a)
    sdl_ttf.UpdateText(text.text)
}

text_update_font :: proc(text: ^Text, font: ^sdl_ttf.Font) {
    sdl_ttf.SetTextFont(text.text, font)
    sdl_ttf.UpdateText(text.text)
}

text_draw :: proc(text: ^Text, x, y: f32) {
	if !sdl_ttf.DrawRendererText(text.text, x, y) {
        fmt.printfln("error: cannot draw updateable text (text = {}).", text)
    }
}

text_update_and_draw :: proc(text: ^Text, value: string, x, y: f32, color: sdl.Color) {
    text_update_text(text, value, color)
    text_draw(text, x, y)
}

text_size :: proc(text: ^Text) -> (f32, f32) {
    w, h: c.int
	if !sdl_ttf.GetTextSize(text.text, &w, &h) {
        fmt.println("error: cannot get text size.")
        return 0, 0
    }
    return cast(f32)w, cast(f32)h
}

////////////////////////////////////////////////////////////////////////////////

draw_text_unoptimized :: proc(renderer: ^sdl.Renderer, font: ^sdl_ttf.Font, text: string, color: sdl.Color) {
    ctext := strings.clone_to_cstring(text)
    defer delete(ctext)

	// text_surface := sdl_ttf.RenderText_Blended(font, ctext, len(text), color)
    text_surface := sdl_ttf.RenderText_Solid(font, ctext, len(text), color)
    defer sdl.DestroySurface(text_surface)

    text_texture := sdl.CreateTextureFromSurface(renderer, text_surface)
    defer sdl.DestroyTexture(text_texture)

    text_dest_rect: sdl.FRect
    sdl.GetTextureSize(text_texture, &text_dest_rect.w, &text_dest_rect.h)
    sdl.RenderTexture(renderer, text_texture, nil, &text_dest_rect)
}
