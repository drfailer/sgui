package sgui

import sdl "vendor:sdl3"
import sdl_ttf "vendor:sdl3/ttf"
import su "sdl_utils"
import "core:fmt"

/*
 * Global initialization and deinitialization functions common to all uis.
 */

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
