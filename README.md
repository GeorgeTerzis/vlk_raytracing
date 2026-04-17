## Install
```bash
git clone --recurse-submodules https://github.com/GeorgeTerzis/vlk_raytracing.git
```
if you already cloned
```bash
git submodule update --init --recursive
```
and then
```bash
zig build
```
or 
```bash
zig build -Doptimize=ReleaseFast
```
to run the program
```bash
./zig-out/bin/emma
```

because obj file reading can take a while

## Platform Support
Currently, this project only targets Linux, as that is the environment it has been developed and tested on.
Windows/macOS support is not guaranteed and may require changes to Vulkan/SDL3 setup.

libs used:
- tinyexr
- VMA
- zig-obj
- vulkan-zig
- zig-sdl3
