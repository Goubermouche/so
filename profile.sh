#!/bin/sh
./build.sh profile
sudo nsys profile --stats=true --trace=cuda,osrt -o profile ./out/sup ./test/1.s -r 10
nsys-ui profile.nsys-rep