package sgui

import "core:log"

Form :: struct {
    widgets: map[string]^Widget,
}

form_add_widget :: proc(form: ^Form, name: string, widget: ^Widget) -> bool {
    if name in form.widgets {
        log.error("a widget named `{}` is already registered in this form.", name)
        return false
    }

    if widget.value == nil {
        log.error("the widget `{}` does not have value.", name)
        return false
    }
    form.widgets[name] = widget
    return true
}

form_value :: proc(form: ^Form, name: string) -> WidgetValue {
    return form.widgets[name]->value()
}
