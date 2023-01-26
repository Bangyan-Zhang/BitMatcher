`timescale 1ns/1ns
`include "entry_cal.v"
`define assert(signal) \
        if (!(signal)) begin \
            $display("ASSERTION FAILED in %m: signal"); \
            $finish; \
        end

module entry_test;
parameter BUCKET_LEN = 64, CMD_LEN = 48, TABLE2 = 0;

reg clk;
reg rst_n;
reg valid_in;
reg [BUCKET_LEN-1:0] entry_in;
reg [CMD_LEN-1:0] cmd_in;
reg first_table_en_in;
reg last_table_has_empty_in;

wire valid_out;
wire ready;

// Output for reinsert operation
wire reinsert_write_ram_en;
wire [BUCKET_LEN-1:0] reinsert_entry_out;
wire reinsert_success_out;
wire reinsert_table_has_emtpy;

// Output for insert operation
wire insert_write_ram_en;
wire [BUCKET_LEN-1:0] insert_entry_out;
wire [CMD_LEN-1:0] insert_cmd_out;
wire insert_success_out;
wire insert_table_has_empty;

// Output for query operation
wire [26:0] query_counter_out;
wire query_success_out;
wire query_match_out;
wire [CMD_LEN-1:0] query_cmd_out;

reg [7:0] fp_val;
reg [3:0] bucket_type;

reg [BUCKET_LEN-1:0] delta_entry;
reg [BUCKET_LEN-1:0] delta_mask;
integer tmp_val;

initial begin
  clk = 0;
  forever #1 clk = ~clk; // clk
end

ENTRY_CAL_64bit entry_cal_module (
  .clk(clk),
  .rst_n(rst_n),
  .valid_in(valid_in),
  .entry_in(entry_in),
  .cmd_in(cmd_in),
  .first_table_en_in(first_table_en_in),
  .last_table_has_empty_in(last_table_has_empty_in),
  
  .valid_out(valid_out),
  .ready(ready),

  // .reinsert_write_ram_en(reinsert_write_ram_en),
  // .reinsert_entry_out(reinsert_entry_out),
  // .reinsert_success_out(reinsert_success_out),
  // .reinsert_table_has_emtpy(reinsert_table_has_emtpy),

  .insert_write_ram_en(insert_write_ram_en),
  .insert_entry_out(insert_entry_out),
  .insert_cmd_out(insert_cmd_out),
  .insert_success_out(insert_success_out),
  .insert_table_has_empty(insert_table_has_empty),

  .query_counter_out(query_counter_out),
  .query_success_out(query_success_out),
  .query_match_out(query_match_out),
  .query_cmd_out(query_cmd_out)
);

integer k1, k2, k3;
integer v1, v2, v3;
integer seed = 10;
integer start_loc, end_loc, len, mask;

initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, entry_test);
end

initial begin
  rst_n = 1;
  valid_in = 0;
  entry_in = 0;
  cmd_in = 0;
  first_table_en_in = 0;
  last_table_has_empty_in = 0;
  $display("Start the simulation...");

  // TestCase: check reset signal
  #2;
  rst_n = 0;
  #4;
  for (k1 = 0; k1 < 0; k1 = k1+1) begin
    #1;
    valid_in = 1;
    entry_in = $random(seed);
    cmd_in = $random(seed);
    first_table_en_in = $random(seed);
    last_table_has_empty_in = $random(seed);
    if (valid_out != 0 || ready != 1) begin
      $display("Error: valid_out = %d, ready = %d", valid_out, ready);
      $finish;
    end
  end

  // Testcase: check query
  rst_n = 1;
  valid_in = 0;
  #4;
  valid_in = 1;
  entry_in = { 6'd48, 5'd24, 4'd12, 3'd6, 2'd3, 8'd5, 8'd4, 8'd3, 8'd2, 8'd1, 4'd0};
  cmd_in = {2'b10, 20'd0, 8'd1, 12'd0, 6'd0}; // {op, h1_addr, aim_fp, insert_value, record_loc} = cmd;
  first_table_en_in = 1;
  last_table_has_empty_in = 0;
  // Output for the bucket with state=0
  for ( k1 = 0; k1 < 7; k1 = k1+1) begin
    fp_val = k1;
    cmd_in = {2'b10, 20'd0, fp_val, 12'd0, 6'd0};
    for ( k2 = 0; k2 < 3; k2 = k2+1) begin
      // $display("Clk: %5d, Ready: %d, valid_out: %d, query out: %3d, success: %d, query_match: %d, cmd_out: %x", k1*3+k2, ready, valid_out, query_counter_out, query_success_out, query_match_out, query_cmd_out);
      if (valid_out) begin
        `assert(query_success_out==1)
        v1 = query_cmd_out[18+7:18];
        `assert(v1 == fp_val)
        if (v1 >=1 && v1 <=5) begin
          `assert(query_match_out==1)
          `assert(query_counter_out == 3*(1<<(fp_val-1)))
        end else begin
          `assert(query_match_out==0)
        end
      end
      #2;
    end
  end
  // check the output for state=1-3
  for (k3 = 0; k3 < 3; k3 = k3+1) begin  
    entry_in = { 28'd0, 8'd4, 8'd3, 8'd2, 8'd1, 4'd0};
    // count bits, s1: 16, 5, 4, 3; s2: 13, 6, 5, 4; s3: 10, 7, 6, 5
    // with the count value as 24, 12, 6, 3
    entry_in[3:0] = k3+1;
    start_loc = 64; end_loc = start_loc - 16 + 3*k3;
    mask = (1<<start_loc) - (1<<end_loc);
    entry_in = (entry_in & ~mask) | (24<<end_loc);
    start_loc = end_loc; end_loc = start_loc - 5 - k3;
    mask = (1<<start_loc) - (1<<end_loc);
    entry_in = (entry_in & ~mask) | (12<<end_loc);
    start_loc = end_loc; end_loc = start_loc - 4 - k3;
    mask = (1<<start_loc) - (1<<end_loc);
    entry_in = (entry_in & ~mask) | (6<<end_loc);
    start_loc = end_loc; end_loc = start_loc - 3 - k3;
    mask = (1<<start_loc) - (1<<end_loc);
    entry_in = (entry_in & ~mask) | (3<<end_loc);

    for ( k1 = 0; k1 < 7; k1 = k1+1) begin
      fp_val = k1;
      cmd_in = {2'b10, 20'd0, fp_val, 12'd0, 6'd0};
      for ( k2 = 0; k2 < 3; k2 = k2+1) begin
        if (valid_out) begin
          `assert(query_success_out==1)
          v1 = query_cmd_out[18+7:18];
          `assert(v1 == fp_val)
          if (v1 >=1 && v1 <=4) begin
            `assert(query_match_out==1)
            `assert(query_counter_out == 3*(1<<(fp_val-1)))
          end else begin
            `assert(query_match_out==0)
          end
        end
        #2;
      end
    end
  end
  // Check the output for state = 4-11
  for (k3 = 0; k3 < 8; k3 = k3+1) begin  
    entry_in = { 36'd0, 8'd3, 8'd2, 8'd1, 4'd0};
    // count bits, 27, 5, 4; 25, 6, 5; ...
    // count values: 12, 6, 3
    entry_in[3:0] = k3+4;
    start_loc = 64; end_loc = start_loc - 27 + 2*k3;
    mask = (1<<start_loc) - (1<<end_loc);
    entry_in = (entry_in & ~mask) | (12<<end_loc);
    start_loc = end_loc; end_loc = start_loc - 5 - k3;
    mask = (1<<start_loc) - (1<<end_loc);
    entry_in = (entry_in & ~mask) | (6<<end_loc);
    start_loc = end_loc; end_loc = start_loc - 4 - k3;
    mask = (1<<start_loc) - (1<<end_loc);
    entry_in = (entry_in & ~mask) | (3<<end_loc);

    for ( k1 = 0; k1 < 7; k1 = k1+1) begin
      fp_val = k1;
      cmd_in = {2'b10, 20'd0, fp_val, 12'd0, 6'd0};
      for ( k2 = 0; k2 < 3; k2 = k2+1) begin
        if (valid_out) begin
          `assert(query_success_out==1)
          v1 = query_cmd_out[18+7:18];
          `assert(v1 == fp_val)
          if (v1 >=1 && v1 <=3) begin
            `assert(query_match_out==1)
            `assert(query_counter_out == 3*(1<<(fp_val-1)))
          end else begin
            `assert(query_match_out==0)
          end
        end
        #2;
      end
    end
  end
  $display("Successfully the query test...");

  // Testcase: check insert operations
  valid_in = 1;
  entry_in = { 6'd20, 5'd8, 4'd4, 3'd2, 2'd0, 8'd5, 8'd4, 8'd3, 8'd2, 8'd0, 4'd0};
  cmd_in = {2'b11, 20'd0, 8'd5, 12'd60, 6'd0}; // {op, h1_addr, aim_fp, insert_value, record_loc} = cmd;
  first_table_en_in = 1;
  last_table_has_empty_in = 0;
  // check the output for s1; no overflow, overflow and adjust locally, overflow and state cheange, find the empty entry
  first_table_en_in = 0;
  for ( k1 = 0; k1 < 7; k1 = k1+1) begin
    `assert(query_success_out==0)
    if (valid_out == 1) begin
      `assert(insert_success_out == 1)
      $display("Clk: %5d, insert IN: %x, OUT: %3x, write_en: %d, cmd_out: %x, empty: %d", k1, entry_in, insert_entry_out, insert_write_ram_en, insert_cmd_out, insert_table_has_empty);
      delta_mask = 0; delta_mask = ~delta_mask; delta_mask[3:0] = 0;
      delta_entry = (insert_entry_out & delta_mask) - (entry_in & delta_mask);
      tmp_val = (delta_entry[BUCKET_LEN-19: BUCKET_LEN-20]);
      $display("tmp_val: %d", tmp_val);
    end
    #2;
  end


  $display("Successfully stop the simulation...");
  $finish;

end

initial begin
  #2000000;
  $display("Stop the simulation...");
  $finish;
end

endmodule

module assert(input clk, input test);
    always @(posedge clk)
    begin
        if (test !== 1)
        begin
            $display("ASSERTION FAILED in %m");
            $finish;
        end
    end
endmodule