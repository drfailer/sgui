package widgets

import ".."
import "../gla"

OnelineInput :: struct {
    label: string,
}

Slider :: struct {
    min: int,
    max: int,
    update: rawptr, // todo: callback
    // config...
}

DropDownSelector :: struct {
}

Tabs :: struct {
}

Menu :: struct { // top menu
}

Line :: struct { // separator line
}

FloatingWindow :: struct { // draggable floating window (can also be done by creating a separated ui in a separated window)
}
