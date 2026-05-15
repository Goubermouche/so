#!/bin/sh
set -e

# clear artifacts
rm -f ./out/sup
rm -f ./out/obj -rf

unset SOURCE_DATE_EPOCH
mkdir -p out/obj
export LD_LIBRARY_PATH=/run/opengl-driver/lib:$LD_LIBRARY_PATH

srcs_c=$(find src -name '*.c' 2>/dev/null)
srcs_cu=$(find src -name '*.cu' 2>/dev/null)
srcs_cc=$(find src -name '*.cc' 2>/dev/null)
export nvcc_flags="-I src -O2 -Wno-deprecated-gpu-targets -arch=sm_61"
nvcc_libs="-lz3"
output="out/sup"
cores=$(nproc)
jobs=$(( cores > 2 ? cores - 2 : 1 ))

build() {
	echo "$srcs_c $srcs_cu $srcs_cc" | tr ' ' '\n' | xargs -P "$jobs" -I {} sh -c '
		src="{}"
		obj="out/obj/$(basename "$src").o"
		echo $src
		nvcc $nvcc_flags -c "$src" -o "$obj"
	'
	objects=$(find out/obj -name '*.o')
	echo "linking $output"
	nvcc $nvcc_flags $objects $nvcc_libs -o "$output"
}

export srcs_c srcs_cu srcs_cc output nvcc_libs jobs
if [ "$1" = "_build" ]; then
	build
else
	bear -- "$0" _build
fi