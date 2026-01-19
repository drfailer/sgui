package sgui

import gla "gla"
import "core:fmt"

/*
 * Global initialization and deinitialization functions common to all uis.
 */

init :: proc() {
    gla.init()
}

fini :: proc() {
    gla.fini()
}
