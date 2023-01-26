# BitMatcher's FPGA Implementation

src/

- macro.v: some macro constants.
- entry_cal_3clk.v: the calculation for new bucket (need 3 clocks). Input is the original bucket value and the command(query/insert), Output is the new bucket value and the command results
- merge_query.v: merge the inputs to the queue items if there is match. Control is based on AXI for input and output.
- rw_solve_1clk.v: the lock management. If there is a match for the input and any queue item, output the lock failure; otherwise, store the value in the queue.
- main_one.v: the main module. This module needs the RAM and FIFO IP, so you must generate the corresponding IPs by yourself in Vivado before synthesizing the module.

testbench/

- entry_test.v: for the entry_cal_3clk.
- merge_query_test.v: for the merge_query.
- rw_solve_test.v: for the rw_solve.
- main_one_test.v: for the main test.

src/FPGA_sim.py: simulate for the influence for the lock (rw_solve) and merge with datasets.
