package sdl_utils

import "core:fmt"
import "core:mem"
import "core:log"
import "core:c"
import "core:strings"
import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"

// text manager ////////////////////////////////////////////////////////////////

TextEngine :: struct {
    font_cache: FontCache,
    text_engine: ^sdl_ttf.TextEngine,
    texts: [dynamic]^Text,
}

text_engine_create :: proc(renderer: ^sdl.Renderer) -> (text_engine: ^TextEngine) {
    text_engine = new(TextEngine)
    text_engine.text_engine = sdl_ttf.CreateRendererTextEngine(renderer)
    text_engine.font_cache = font_cache_create()
    text_engine.texts = make([dynamic]^Text)
    return text_engine
}

text_engine_destroy :: proc(text_engine: ^TextEngine) {
    for text in text_engine.texts {
        text_destroy(text)
    }
    font_cache_destroy(&text_engine.font_cache)
    sdl_ttf.DestroyRendererTextEngine(text_engine.text_engine)
    delete(text_engine.texts)
    free(text_engine)
}

text_engine_create_text :: proc(
    text_engine: ^TextEngine,
    content: string,
    font_path: FontPath,
    font_size: FontSize,
) -> ^Text {
    font := font_cache_get_font(&text_engine.font_cache, font_path, font_size)
    text := text_create(text_engine.text_engine, font, content)
    append(&text_engine.texts, text)
    return text
}

// text ////////////////////////////////////////////////////////////////////////

Color :: sdl.Color

Text :: struct {
    text_engine: ^sdl_ttf.TextEngine,
    font: ^sdl_ttf.Font,
    text: ^sdl_ttf.Text,
}

@(private="file")
text_create :: proc(text_engine: ^sdl_ttf.TextEngine, font: ^sdl_ttf.Font, content: string) -> (text: ^Text) {
    ccontent := strings.clone_to_cstring(content, context.temp_allocator)
    text = new(Text)
    text.text_engine = text_engine
    text.font = font
    text.text = sdl_ttf.CreateText(text_engine, font, ccontent, len(content))
    return text
}

@(private="file")
text_destroy :: proc(text: ^Text) {
    sdl_ttf.DestroyText(text.text)
    free(text)
}

text_set_text :: proc(text: ^Text, value: string) {
    ctext := strings.clone_to_cstring(value, context.temp_allocator)
    sdl_ttf.SetTextString(text.text, ctext, len(value))
}

text_set_color :: proc(text: ^Text, color: sdl.Color) {
    sdl_ttf.SetTextColor(text.text, color.r, color.g, color.b, color.a)
}

text_set_font :: proc(text: ^Text, font: ^sdl_ttf.Font) {
    sdl_ttf.SetTextFont(text.text, font)
}

text_set_wrap_width :: proc(text: ^Text, wrap_width: f32) {
    sdl_ttf.SetTextWrapWidth(text.text, cast(c.int)wrap_width)
}

text_update :: proc(text: ^Text) {
    sdl_ttf.UpdateText(text.text)
}

text_draw :: proc(text: ^Text, x, y: f32) {
	if !sdl_ttf.DrawRendererText(text.text, x, y) {
        fmt.printfln("error: cannot draw updateable text (text = {}).", text)
    }
}

text_size :: proc(text: ^Text) -> (f32, f32) {
    w, h: c.int
	if !sdl_ttf.GetTextSize(text.text, &w, &h) {
        fmt.println("error: cannot get text size.")
        return 0, 0
    }
    return cast(f32)w, cast(f32)h
}

// font cache //////////////////////////////////////////////////////////////////

Font :: ^sdl_ttf.Font
FontPath :: string
FontSize :: f32

@(private="file")
FontCache :: struct {
    fonts: map[FontPath]map[FontSize]Font,
}

@(private="file")
font_cache_create :: proc() -> FontCache {
    return FontCache{
        fonts = make(map[FontPath]map[FontSize]Font)
    }
}

@(private="file")
font_cache_destroy :: proc(cache: ^FontCache) {
    for _, fonts in cache.fonts {
        for _, font in fonts {
            sdl_ttf.CloseFont(font)
        }
        delete(fonts)
    }
    delete(cache.fonts)
}

@(private="file")
font_cache_get_font :: proc(cache: ^FontCache, path: FontPath, size: FontSize) -> (font: Font) {
    if len(path) == 0 {
        log.error("font_cache_get_font called with empty path.")
    }
    if path in cache.fonts {
        if size in cache.fonts[path] {
            font = cache.fonts[path][size]
        } else {
            cpath := strings.clone_to_cstring(path, context.temp_allocator)
            font = sdl_ttf.OpenFont(cpath, size)
            map_insert(&cache.fonts[path], size, font)
        }
    } else {
        cpath := strings.clone_to_cstring(path, context.temp_allocator)
        font = sdl_ttf.OpenFont(cpath, size)
        cache.fonts[path] = make(map[FontSize]Font)
        map_insert(&cache.fonts[path], size, font)
    }
    if font == nil {
        log.error("font_cache_get_font returned nil font ", path, sdl.GetError())
    }
    return font
}

////////////////////////////////////////////////////////////////////////////////

draw_text_unoptimized :: proc(renderer: ^sdl.Renderer, font: ^sdl_ttf.Font, text: string, color: sdl.Color) {
    ctext := strings.clone_to_cstring(text, context.temp_allocator)

	// text_surface := sdl_ttf.RenderText_Blended(font, ctext, len(text), color)
    text_surface := sdl_ttf.RenderText_Solid(font, ctext, len(text), color)
    defer sdl.DestroySurface(text_surface)

    text_texture := sdl.CreateTextureFromSurface(renderer, text_surface)
    defer sdl.DestroyTexture(text_texture)

    text_dest_rect: sdl.FRect
    sdl.GetTextureSize(text_texture, &text_dest_rect.w, &text_dest_rect.h)
    sdl.RenderTexture(renderer, text_texture, nil, &text_dest_rect)
}
