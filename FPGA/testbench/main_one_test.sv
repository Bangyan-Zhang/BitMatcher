`timescale 1ns/1ns

module main_one_test( );

reg clk;

initial begin
    clk = 0;
    forever #1 clk =~clk;
end

integer clk_cnt;
initial begin
    clk_cnt = 0;
    forever begin
        @(posedge clk);
        clk_cnt = clk_cnt + 1;
    end
end

localparam CMD_LEN = 30;

reg rst_n;
reg cmd_in_valid;
reg [CMD_LEN-1:0] cmd_in;

wire valid_out;
wire [CMD_LEN-1:0] cmd_out;
wire success_out;
wire[26:0] counter_size;

main_one
#( .CMD_LEN(30))
   my_main
(
    .clk(clk),
    .rst_n(rst_n),
    .cmd_in_valid(cmd_in_valid),
    .cmd_in(cmd_in),

    .valid_out(valid_out),
    .cmd_out(cmd_out),
    .success_out(success_out),
    .counter_size(counter_size)
);

integer i, j, k;
integer valid_cnt;
integer start_time;
integer end_time;
integer total_start_clk, total_end_clk;

integer total_input_cnt;
reg  [7:0] fp_input;
reg  [19:0] addr_input;
initial begin
    total_input_cnt = 3;
    rst_n = 0;
    cmd_in_valid = 0;
    cmd_in = 0;
    #40;
    rst_n = 1;
    total_start_clk = clk_cnt;
    for (j = 0; j < 1000; j = j+1) begin
        start_time = clk_cnt;
        #2; cmd_in_valid = 1; cmd_in = {2'b11, 20'd10, 8'd1 }; // op, h1, aim_fp
        #2; cmd_in_valid = 1; cmd_in = {2'b11, 20'd129, 8'd2 }; // op, h1, aim_fp
        // #2; cmd_in_valid = 1; cmd_in = {2'b11, 20'd10, 8'd3 }; // insert a value with the same addr and different fp
        #2; cmd_in_valid = 1; cmd_in = {2'b11, 20'd189, 8'd3 }; // op, h1, aim_fp
        for(k=0; k < 50; k = k+1) begin
            fp_input = k + 1; // fp is not 0!
            addr_input = 20'd1096 + (k << 4);
            #2; cmd_in_valid = 1; cmd_in = {2'b11, addr_input, fp_input};
        end
        valid_cnt = 0;
        for (i = 0; i < 0; i = i + 1) begin
            #2; cmd_in_valid = 0; cmd_in = 0;
            if (valid_out) begin
                valid_cnt = valid_cnt + 1;
                // $display("%d: valid_out = %b, cmd_out = %b, success_out = %b, counter_size = %d", j, valid_out, cmd_out, success_out, counter_size);
                if (valid_cnt == total_input_cnt) begin
                    end_time = clk_cnt;
                    $display("All insert has been successful with time %d", end_time - start_time);
                    break;
                end
            end
        end
    end

    start_time = clk_cnt;
    #2; cmd_in_valid = 1; cmd_in = {2'b10, 20'd10, 8'd1 }; // query signal
    #2; cmd_in_valid = 1; cmd_in = {2'b10, 20'd129, 8'd2 };
    // #2; cmd_in_valid = 1; cmd_in = {2'b10, 20'd10, 8'd3 };
    #2; cmd_in_valid = 1; cmd_in = {2'b10, 20'd189, 8'd3 };
    #2; cmd_in_valid = 0; cmd_in = 0;
    valid_cnt = 0;
    for (i = 0; i < 1000; i = i + 1) begin
        #2;
        if (valid_out && cmd_out[CMD_LEN-1:CMD_LEN-2] == 2'b10) begin // query output
            valid_cnt = valid_cnt + 1;
            $display("%d: valid_out = %b, cmd_out = %b, success_out = %b, counter_size = %d", j, valid_out, cmd_out, success_out, counter_size);
            if (valid_cnt == total_input_cnt) begin
                end_time = clk_cnt;
                $display("All query has been successful with time %d with query needs extra %d", end_time - total_start_clk, end_time - start_time);
                break;
            end
        end
    end
    #10;
    // $display("The cmd_out is %x with %d with counter as %d", cmd_out, valid_out, counter_size);
    
    $finish(0);
end

endmodule
