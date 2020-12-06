# Newport 
Newport is a modular game engine built in odin for odin. It is designed to be easily extendable and easy to use.

## Setup
1. Clone the repo into a desired folder
`sh
$ git clone https://github.com/colbyhall/newport.git
`
2. Add the collection to your project build command
`sh
$ odin build example.odin -collection:newport=desired\
`
3. Import the collection into your project
```odin
package example

import "newport:core"

main :: proc() {
    core_init_details := core.default_init_details("example");
    core.init_scoped(core_init_details);
}
```