`timescale 1ns/1ns
`include "rw_solve_1clk.v"
`define assert(signal) \
        if (!(signal)) begin \
            $display("ASSERTION FAILED in %m: signal"); \
            $finish; \
        end

module assert_mod(input clk, input test);
    always @(posedge clk)
    begin
        if (test !== 1)
        begin
            $display("ASSERTION FAILED in %m");
            $finish;
        end
    end
endmodule

module rw_solve_test;
parameter DATA1_LEN = 12, DATA2_LEN = 12, QUEUE_LEN = 64, LOC_WIDTH = 6;

reg clk;
reg rst_n;
// new input
reg valid_insert;
reg [DATA1_LEN-1:0] data1;
reg [DATA2_LEN-1:0] data2;
// delete
reg valid_delete;
reg [LOC_WIDTH-1:0] del_loc_in;
// output
wire valid_out;
wire [DATA1_LEN-1:0] data1_out;
wire [DATA2_LEN-1:0] data2_out;
wire insert_success;
wire [LOC_WIDTH-1:0] insert_loc;

reg [7:0] fp_val;
reg [3:0] bucket_type;

initial begin
  clk = 0;
  forever #1 clk = ~clk; 
end

rw_solve_1clk  #(.DATA1_LEN(DATA1_LEN), .DATA2_LEN(DATA2_LEN), .QUEUE_LEN(QUEUE_LEN), .LOC_WIDTH(LOC_WIDTH))
inst
(
    .clk(clk),
    .rst_n(rst_n),

    // new insert
    .valid_insert(valid_insert),
    .data1(data1),
    .data2(data2),

    // delete
    .valid_delete(valid_delete),
    .del_loc_in(del_loc_in),

    // output
    .valid_out(valid_out),
    .data1_out(data1_out),
    .data2_out(data2_out),
    .insert_success(insert_success),
    .insert_loc(insert_loc)
);


integer k1, k2, k3;
integer v1, v2, v3;
integer seed = 10;
integer start_loc, end_loc, len, mask;

initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, inst);
end

parameter check_time = 0;
initial begin
  rst_n = 0; valid_insert = 0; valid_delete = 0;
  $display("Start the simulation...");
  #3;
  // TestCase: check reset
  $display("TestCase: Check the reset signal...");
  for (k1 = 0; k1 < check_time; k1 = k1+1) begin
    `assert(valid_out == 0);
    valid_insert = $random(seed) & 1;
    #1;
  end
    // close rst and check the valid_insert
  rst_n = 1; valid_insert = 0;
  for (k1 = 0; k1 < check_time; k1 = k1+1) begin
    `assert(valid_out == 0);
    #1;
  end
  $display("TestCase: Check the reset signal...OK");

  // TestCase
  $display("TestCase: Check the insert success signal...");
  #4;
  // insert (1,2)
  valid_insert = 1; data1 = 1; data2 = 2;
  for (k1 = 0; k1 < check_time; k1 = k1+1) begin
    #2;
    $display("%d: valid: %d, data1: %d, data2: %d, insert s/f: %d, loc: %d", k1, valid_out, data1_out, data2_out, insert_success, insert_loc);
  end
  // checking inserting (1,x) / (x, 2), it should fail
  data1 = 1; data2 = 3;
  for (k1 = 0; k1 < check_time; k1 = k1+1) begin
    #2;
    $display("%d: valid: %d, data1: %d, data2: %d, insert s/f: %d, loc: %d", k1, valid_out, data1_out, data2_out, insert_success, insert_loc);
    data2 = $random(seed);
  end
  #2;
  // insert (3,4), (5,6), ...
  data1 = 3; data2 = 4;
  for (k1 = 0; k1 < 6; k1 = k1+1) begin
    #2;
    $display("%d: valid: %d, data1: %d, data2: %d, insert s/f: %d, loc: %d", k1, valid_out, data1_out, data2_out, insert_success, insert_loc);
    data1 = data1 + 2; data2 = data2 + 2;
  end
  for (k1 = 0; k1 < 6; k1 = k1+1) begin
    #2;
    $display("%d: valid: %d, data1: %d, data2: %d, insert s/f: %d, loc: %d", k1, valid_out, data1_out, data2_out, insert_success, insert_loc);
  end
  
  #4;
  $display("Success!");
  $finish(0);
end

initial begin
  #2000000;
  $display("Stop the simulation...");
  $finish(-1);
end

endmodule
