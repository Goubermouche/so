#!/bin/sh

set -e

mkdir -p out

srcs_cu=$(find src -name '*.cu' 2>/dev/null)
srcs_cc=$(find src -name '*.cc' 2>/dev/null)

nvcc_flags="-I src -O0 -Wno-deprecated-gpu-targets"
output="out/so"

if command -v bear >/dev/null 2>&1; then
	bear -- nvcc $nvcc_flags -o $output $srcs_cu $srcs_cc
else
	nvcc $nvcc_flags -o $output $srcs_cu $srcs_cc
fi

echo "built: $output"
