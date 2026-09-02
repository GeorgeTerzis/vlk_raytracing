#!/bin/sh
# Usage:
#   ./capture.sh        — RRA capture (default)
#   ./capture.sh --rgp  — RGP capture
#   ./capture.sh --rmv  — RMV capture

MODE="rra"
EXT="rra"

mkdir -p ./captures

if [ "$1" = "--rgp" ]; then
    MODE="rgp"
    EXT="rgp"

    echo "RGP mode..."

    MESA_VK_TRACE=rgp \
    MESA_VK_TRACE_FRAME=3 \
        ./zig-out/bin/emma ./scene_lite.zon

elif [ "$1" = "--rmv" ]; then
    MODE="rmv"
    EXT="rmv"

    echo "RMV mode..."

    MESA_VK_TRACE="rmv"\
    MESA_VK_TRACE_FRAME=3 \
        ./zig-out/bin/emma

else
    echo "Starting capture in RRA mode..."

    MESA_VK_TRACE=rra \
    MESA_VK_TRACE_FRAME=3 \
        ./zig-out/bin/emma
fi

mv /tmp/emma_*."$EXT" ./captures/ 2>/dev/null
echo "Capture saved to ./captures/"
