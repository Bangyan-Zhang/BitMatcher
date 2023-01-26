`timescale 1ns/100ps
`include "merge_query.v"

module merge_query_test;

localparam ITEM_LENGTH = 48;
localparam ITEM_COUNTER_SIZE = 12;
localparam QUEUE_LEN = 30;

reg clk;
reg rst_n;
reg valid_in;
reg [ITEM_LENGTH-1:0] item_in;
reg [ITEM_COUNTER_SIZE-2:0] item_counter_in;
reg output_ready;

wire valid_out;
wire [ITEM_LENGTH-1:0] item_out;
wire [ITEM_COUNTER_SIZE-1:0] item_counter;
wire queue_full_signal;
wire queue_emtpy_signal;
wire [5:0] dbg_item_size;
reg [5:0] tmp_res;

merge_query #(.ITEM_LENGTH(ITEM_LENGTH), .ITEM_COUNTER_SIZE(ITEM_COUNTER_SIZE),  .QUEUE_LEN(QUEUE_LEN) ) 
    main
(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .item_in(item_in),
    .item_counter_in(item_counter_in),
    .output_ready(output_ready),

    .valid_out(valid_out),
    .item_out(item_out),
    .item_counter(item_counter),
    .queue_full_signal(queue_full_signal),
    .queue_emtpy_signal(queue_emtpy_signal),
    .dbg_item_size(dbg_item_size)
);

initial begin
  clk = 0;
  forever #2 clk = ~clk;
end

initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, merge_query_test);
end

integer k1;
integer seed = 100;
integer sum1, sum2;

initial begin
  rst_n = 0;
  valid_in = 0;
  item_in = 0;
  item_counter_in = 0;
  output_ready = 0;
  $display("*** Start the simulation ***");

  // TestCase: check the reset signal works
  #20;
  for (k1 = 0; k1 < 0; k1 = k1+1) begin
    #1;
    valid_in = 1;
    output_ready = 1;
    item_in = $random(seed);
    item_counter_in = $random(seed);
    if (valid_out || queue_full_signal || !queue_emtpy_signal ) begin
      $display("Error: valid_out = %d", valid_out);
      $finish;
    end
  end

  // Testcase
  rst_n = 1;
  valid_in = 0;
  output_ready = 0;

  // - input and check whether it is empty
  #4; valid_in = 1; item_in = 1; item_counter_in = 1;
  #4; valid_in = 0; item_in = 0;
  #4; if (queue_emtpy_signal || dbg_item_size != 1) begin
    $display("Error: the queue is empty."); $finish;
  end
  // input the same value and check the queue is 1
  #4; valid_in = 1; item_in = 1;
  #4; valid_in = 0; item_in = 0;
  if (queue_emtpy_signal || dbg_item_size != 1) begin
    $display("Error: the queue is not one item."); $finish;
  end
  // - input and the queue is 2
  #4; valid_in = 1; item_in = 2;
  #4;
  if (queue_emtpy_signal || dbg_item_size != 2) begin
    $display("Error: the queue is not two items."); $finish;
  end
  // - reset
  #4; rst_n = 0; valid_in = 0; // valid_in is set 0 to avoid inputing by mistake
  #4; rst_n = 1; valid_in = 0;
  if (!queue_emtpy_signal || dbg_item_size != 0 ) begin
    $display("Error: the queue is not empty"); $finish;
  end
  // - keep inputing various values until the queue is full
  for( k1=0; k1 < QUEUE_LEN; k1++) begin
    #4; valid_in = 1; item_in = k1+1;
    if ( dbg_item_size != k1 || queue_full_signal == 1 ) begin
        $display("The item size is not correct! %d is not %d", dbg_item_size, tmp_res); $finish;
    end
  end
  #4;
  output_ready = 1;   // read 
  valid_in = 0;       // stop the input
  if (queue_full_signal != 1) begin
      $display("The queue is not full"); $finish;
  end
  for( k1=0; k1 < QUEUE_LEN; k1++) begin
    #4;
    if ( (!valid_out) || (item_out + dbg_item_size != QUEUE_LEN) || (item_out != (k1+1)) ) begin
        $display("Vld: %d, Output %d (cnt: %d), left: %d ", valid_out, item_out, item_counter, dbg_item_size); $finish;
    end
  end
  for ( k1=0; k1 < QUEUE_LEN; k1++) begin
    #4;
    if (valid_out || !queue_emtpy_signal) begin
        $display("The queue is already empty, but there is output!"); $finish;
    end
  end
  // - input two values multiply and check the final results
  #4; rst_n = 0; valid_in = 0; output_ready = 0;
  #4; rst_n = 1; valid_in = 0; output_ready = 0;
  sum1 = 0; sum2 = 0;
  for (k1 = 0; k1 < 20; k1++) begin
    #4; valid_in = 1; item_in = (k1 % 2) + 1; item_counter_in = ($random(seed) & 15) + 1;
    if (item_in == 1) begin
        sum1 = sum1 + item_counter_in;
    end else begin sum2 = sum2 +  item_counter_in; end
  end
  #4; valid_in = 0;
  if (dbg_item_size != 2) begin
    $display("The item size is not 2"); $finish;
  end
  output_ready = 1;
  #4; // Wait for a while
  if (!valid_out || item_out != 1 || item_counter != sum1) begin
      $display("Error, %d: item_out: %d, item_counter: %d not %d", valid_out, item_out, item_counter, sum1); $finish;
  end
  #4;
  if (!valid_out || item_out != 2 || item_counter != sum2) begin
      $display("%d: item_out: %d, item_counter: %d", valid_out, item_out, item_counter);
  end
  #4; output_ready = 0;
  if (valid_out) $display("Error! There should not output!");
  #4;
  valid_in = 1; item_in = 1; item_counter_in = 2; output_ready = 1;
  // - input and output at the same time
  for (k1 = 1; k1 < 20; k1++) begin
    #4; valid_in = 1; item_in = k1 + 1; item_counter_in = k1 + 2;
    if (valid_out != 1 || item_out != k1 || item_counter != k1 + 1) begin
        $display("The input and output is not the same! %d:%d is not %d:%d", item_out, item_counter, k1, k1+1); $finish;
    end
  end

  $display("=== Finish the test cases successfully..");
  $finish;
end

initial begin
  #200_0000;
  $display("Stop the simulation...");
  $finish;
end

endmodule