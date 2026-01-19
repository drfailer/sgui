package sgui

import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"

// config //////////////////////////////////////////////////////////////////////

FPS :: #config(FPS, 60)

WINDOW_WIDTH :: #config(WINDOW_WIDTH, 800)
WINDOW_HEIGHT :: #config(WINDOW_HEIGHT, 600)

// TODO
WINDOW_FLAGS :: sdl.WindowFlags{.RESIZABLE}
// WINDOW_FLAGS :: sdl.WindowFlags{}

// defaults ////////////////////////////////////////////////////////////////////

Opts :: struct {
    clear_color: Color,
}

OPTS := Opts{
    clear_color = Color{0, 0, 0, 255},
}
