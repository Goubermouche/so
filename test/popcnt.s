# skip
srli x5, x1, 1
andi x5, x5, 0x55
sub  x6, x1, x5
srli x5, x6, 2
andi x5, x5, 0x33
andi x6, x6, 0x33
add  x6, x5, x6
andi x7, x6, 0xFF
