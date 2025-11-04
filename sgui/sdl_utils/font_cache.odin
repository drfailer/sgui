package sdl_utils

import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"
import "core:strings"
import "core:log"
import "core:fmt"

Font :: ^sdl_ttf.Font
FontPath :: string
FontSize :: f32

FontCache :: struct {
    fonts: map[FontPath]map[FontSize]Font,
}

font_cache_create :: proc(allocator := context.allocator) -> FontCache {
    return FontCache{
        fonts = make(map[FontPath]map[FontSize]Font, allocator = allocator)
    }
}

font_cache_destroy :: proc(cache: ^FontCache) {
    for _, fonts in cache.fonts {
        for _, font in fonts {
            sdl_ttf.CloseFont(font)
        }
    }
}

font_cache_get_font :: proc(cache: ^FontCache, path: FontPath, size: FontSize) -> (font: Font) {
    if len(path) == 0 {
        log.error("font_cache_get_font called with empty path.")
    }
    if path in cache.fonts {
        if size in cache.fonts[path] {
            font = cache.fonts[path][size]
        } else {
            cpath := strings.clone_to_cstring(path)
            defer delete(cpath)
            font = sdl_ttf.OpenFont(cpath, size)
            map_insert(&cache.fonts[path], size, font)
        }
    } else {
        cpath := strings.clone_to_cstring(path)
        defer delete(cpath)
        font = sdl_ttf.OpenFont(cpath, size)
        cache.fonts[path] = make(map[FontSize]Font)
        map_insert(&cache.fonts[path], size, font)
    }
    if font == nil {
        log.error("font_cache_get_font returned nil font.")
    }
    return font
}
