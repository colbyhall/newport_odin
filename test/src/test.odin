package test

import "newport:core"

main :: proc() {
    core_init_details := core.default_init_details("test");
    core.init_scoped(core_init_details);
}