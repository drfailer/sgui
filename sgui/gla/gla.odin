package gla

import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"
import "core:fmt"

init :: proc() {
    if !sdl.Init(sdl.InitFlags{.VIDEO, .EVENTS}) {
        fmt.printfln("error: {}", sdl.GetError())
        return
    }

    if !sdl_ttf.Init() {
        fmt.printfln("error: couldn't init sdl_ttf.")
        return
    }
}

fini :: proc() {
    sdl_ttf.Quit()
    sdl.Quit()
}
