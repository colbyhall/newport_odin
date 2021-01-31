# Newport 
Newport is a modular game engine built in odin for odin. It is designed to be easily extendable and easy to use.

## Setup
1. Clone the repo into a desired folder
```sh
$ git clone https://github.com/colbyhall/newport.git
```
2. Run the setup script
```sh
$ setup.bat
```
3. Add the collection to your project build command
```sh
$ odin build example.odin -collection:newport=desired\
```
4. Import the collection into your project
```odin
package example

import "newport:core"
import "newport:engine"
import "newport:asset"
import "newport:job"

import "core:fmt"

main :: proc() {
    init_details := engine.default_init_details("test");
    engine.init_scoped(init_details);

    context = engine.default_context();

    asset.discover();

    job.init_scoped();

    core.show_window(engine.get().window, true);

    for engine.is_running() {
        job := job.create(proc(job: ^Job) {
            x := 0;
            for i in 0..1000000 {
                x += i;
            }

            fmt.println(x);
        });

        counter : job.Counter;
        for _ in 0..<64 {
            job.schedule(job, &counter);
        }

        engine.dispatch_input();

        job.wait(counter = &counter, stay_on_thread = true);
    }
}
```