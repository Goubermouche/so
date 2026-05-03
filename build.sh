#!/bin/sh
set -e
mkdir -p out
export LD_LIBRARY_PATH=/run/opengl-driver/lib:$LD_LIBRARY_PATH
srcs_cu=$(find src -name '*.cu' 2>/dev/null)
srcs_cc=$(find src -name '*.cc' 2>/dev/null)
nvcc_flags="-I src -O2 -Wno-deprecated-gpu-targets -arch=sm_61"
nvcc_libs="-lz3"
output="out/so"
if command -v bear >/dev/null 2>&1; then
	bear -- nvcc $nvcc_flags -o $output $srcs_cu $srcs_cc $nvcc_libs
else
	nvcc $nvcc_flags -o $output $srcs_cu $srcs_cc $nvcc_libs
fi
echo "built: $output"
