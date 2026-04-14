#!/bin/sh
# slangc -O3 src/shaders/raytracing_recursive/main.slang -o src/shaders/raytracing_recursive/shader.spv &
slangc -O3 src/shaders/hw_raytracing/main.slang -o src/shaders/hw_raytracing/shader.spv &
wait

# slangc -O3 src/shaders/pathtracing/path.slang -o src/shaders/pathtracing/shader.spv
# glslc src/shaders/pathtracing/shader.comp -o src/shaders/pathtracing/shader.spv
