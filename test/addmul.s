# > -e rv32i,rv32m
# addi x6, x0, 10
# add  x5, x1, x2
# mul  x9, x5, x6
add  x5, x1, x2
add  x6, x5, x5
add  x6, x6, x6
add  x6, x6, x5
add  x6, x6, x6
addi x7, x6, 0
add  x8, x7, x0
addi x9, x8, 0
