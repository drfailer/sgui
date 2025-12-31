package sdl_utils

import sdl "vendor:sdl3"
import sdl_img "vendor:sdl3/image"
import "core:log"
import "core:strings"

Texture :: sdl.Texture
Rect :: sdl.FRect

// texture cache ///////////////////////////////////////////////////////////////

TextureCache :: struct {
    textures: map[string]^Texture,
    renderer: ^sdl.Renderer,
}

texture_cache_create :: proc(renderer: ^sdl.Renderer) -> (cache: ^TextureCache) {
    cache = new(TextureCache)
    cache.textures = make(map[string]^Texture)
    cache.renderer = renderer
    return cache
}

texture_cache_destroy :: proc(cache: ^TextureCache) {
    for _, texture in cache.textures {
        sdl.DestroyTexture(texture)
    }
    delete(cache.textures)
    free(cache)
}

texture_cache_load_texture :: proc(cache: ^TextureCache, path: string) -> (texture: ^Texture) {
    if len(path) == 0 {
        log.error("texture_cache_load_texture called with empty path.")
    }
    if path in cache.textures {
        texture = cache.textures[path]
    } else {
        cpath := strings.clone_to_cstring(path, context.temp_allocator)
        texture = sdl_img.LoadTexture(cache.renderer, cpath)
        cache.textures[path] = texture
    }
    return texture
}

texture_cache_delete_texture :: proc(cache: ^TextureCache, path: string) {
    if path in cache.textures {
        sdl.DestroyTexture(cache.textures[path])
        delete_key(&cache.textures, path)
    }
}

// image ///////////////////////////////////////////////////////////////////////

Image :: struct {
    path: string,
    texture: ^Texture,
    srcrect: Rect,
    w, h: f32,
}

image_create :: proc(cache: ^TextureCache, path: string, srcrect: Rect = Rect{0, 0, 0, 0}) -> (image: ^Image) {
    image = new(Image)
    image.texture = texture_cache_load_texture(cache, path)
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
