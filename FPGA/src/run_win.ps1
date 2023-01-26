iverilog.exe .\testbench\rw_solve_test.v
vvp.exe -n a.out -lxt2
# gtkwave.exe .\wave.vcd