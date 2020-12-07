# Newport 
Newport is a modular game engine built in odin for odin. It is designed to be easily extendable and easy to use.

## Features
* Modular setup for easy extension. Also allows for select parts to be used alone.
* GL Rendering
* Asset Manager

## Setup
1. Clone the repo into a desired folder
```sh
$ git clone https://github.com/colbyhall/newport.git
```
2. Add the collection to your project build command
```sh
$ odin build example.odin -collection:newport=desired\
```
3. Import the collection into your project
```odin
package example

import "newport:engine"

main :: proc() {
    init_details := engine.default_init_details("test");
    engine.init_scoped(init_details);   
}
```