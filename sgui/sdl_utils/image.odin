package sdl_utils

import sdl "vendor:sdl3"
import sdl_img "vendor:sdl3/image"
import "core:log"
import "core:strings"

Texture :: sdl.Texture
Rect :: sdl.FRect

// texture engine ///////////////////////////////////////////////////////////////

TextureEngine :: struct {
    cache: map[string]^Texture,
    renderer: ^sdl.Renderer,
}

texture_engine_create :: proc(renderer: ^sdl.Renderer) -> (engine: ^TextureEngine) {
    engine = new(TextureEngine)
    engine.cache = make(map[string]^Texture)
    engine.renderer = renderer
    return engine
}

texture_engine_destroy :: proc(engine: ^TextureEngine) {
    for _, texture in engine.cache {
        sdl.DestroyTexture(texture)
    }
    delete(engine.cache)
    free(engine)
}

texture_engine_load_texture :: proc(engine: ^TextureEngine, path: string) -> (texture: ^Texture) {
    if len(path) == 0 {
        log.error("texture_engine_load_texture called with empty path.")
    }
    if path in engine.cache {
        texture = engine.cache[path]
    } else {
        cpath := strings.clone_to_cstring(path, context.temp_allocator)
        texture = sdl_img.LoadTexture(engine.renderer, cpath)
        engine.cache[path] = texture
    }
    return texture
}

texture_engine_delete_texture :: proc(engine: ^TextureEngine, path: string) {
    if path in engine.cache {
        sdl.DestroyTexture(engine.cache[path])
        delete_key(&engine.cache, path)
    }
}

// image ///////////////////////////////////////////////////////////////////////

Image :: struct {
    path: string,
    texture: ^Texture,
    srcrect: Rect,
    w, h: f32,
}

image_create :: proc(engine: ^TextureEngine, path: string, srcrect: Rect = Rect{0, 0, 0, 0}) -> (image: ^Image) {
    image = new(Image)
    image.texture = texture_engine_load_texture(engine, path)
    sdl.GetTextureSize(image.texture, &image.w, &image.h)
    image.path = path
    image.srcrect = srcrect

    if srcrect.w == 0 {
        image.srcrect.w = image.w
    }
    if srcrect.h == 0 {
        image.srcrect.h = image.h
    }
    return image
}

image_destroy :: proc(image: ^Image) {
    free(image)
}

image_draw :: proc(renderer: ^sdl.Renderer, image: ^Image, x, y, w, h: f32) {
    dstrect := Rect{x, y, w, h}
	if !sdl.RenderTexture(renderer, image.texture, &image.srcrect, &dstrect) {
        log.warn("impossible to draw texture", sdl.GetError(), image.texture)
    }
}
