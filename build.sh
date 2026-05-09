#!/bin/sh
set -e

unset SOURCE_DATE_EPOCH
mkdir -p out/obj
export LD_LIBRARY_PATH=/run/opengl-driver/lib:$LD_LIBRARY_PATH

srcs_cu=$(find src -name '*.cu' 2>/dev/null)
srcs_cc=$(find src -name '*.cc' 2>/dev/null)
export nvcc_flags="-I src -O2 -Wno-deprecated-gpu-targets -arch=sm_61"
nvcc_libs="-lz3"
output="out/sup"

# job count
cores=$(nproc)
jobs=$(( cores > 2 ? cores - 2 : 1 ))

# build in parallel
echo "$srcs_cu $srcs_cc" | tr ' ' '\n' | xargs -P $jobs -I {} sh -c '
	src="{}"
	obj="out/obj/$(basename "$src").o"
	echo $src
	nvcc $nvcc_flags -c "$src" -o "$obj"
'

objects=$(find out/obj -name '*.o')

# link
echo "linking $output"
nvcc $nvcc_flags $objects $nvcc_libs -o "$output"
