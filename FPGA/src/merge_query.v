module merge_query
 #(parameter ITEM_LENGTH = 30, ITEM_COUNTER_SIZE = 12,  QUEUE_LEN = 30)
(
    input clk,
    input rst_n,
    input valid_in,
    input [ITEM_LENGTH-1:0] item_in,
    input [ITEM_COUNTER_SIZE-1:0] item_counter_in,

    // Enable the output
    input output_ready,

    output reg valid_out,
    output reg[ITEM_LENGTH-1:0] item_out,
    output reg[ITEM_COUNTER_SIZE-1:0] item_counter,
    output reg queue_full_signal,
    output reg queue_emtpy_signal,
    output wire[5:0] dbg_item_size
);
function integer clogb2 (input integer bit_depth);
begin
for(clogb2=0; bit_depth>0; clogb2=clogb2+1)
bit_depth = bit_depth>>1;
end
endfunction

localparam QUEUE_LEN_WIDTH = clogb2(QUEUE_LEN);

reg [ITEM_LENGTH-1:0] item_queue[QUEUE_LEN:0];
reg [ITEM_COUNTER_SIZE-1:0] item_counter_queue[QUEUE_LEN:0];
reg [QUEUE_LEN:0] item_valid_queue;
// matched item
wire[QUEUE_LEN:0] match_flag_list;

wire [ITEM_LENGTH-1: 0] dbg_item_queue1;
assign dbg_item_queue1 = item_queue[0];

always@(posedge clk) begin
     item_queue[QUEUE_LEN] = 0;
     item_counter_queue[QUEUE_LEN] = 0;
     item_valid_queue[QUEUE_LEN] = 0;
end
assign match_flag_list[QUEUE_LEN] = 0;

wire has_match;
assign has_match = (match_flag_list != 0);
// queue length
reg[QUEUE_LEN_WIDTH:0] item_size;
reg[QUEUE_LEN_WIDTH:0] new_item_size;

assign dbg_item_size = item_size;
// match_flag_list, 1 means match
genvar i;
generate
for (i = 0; i < QUEUE_LEN; i = i + 1) begin: match_flag_blk
    get_match_res #(.ITEM_LENGTH(ITEM_LENGTH)) 
        match_res_inst( .rst_n(rst_n), .item1(item_queue[i]), .item2( item_in ), .valid_flag(item_valid_queue[i]&valid_in), .match_flag( match_flag_list[i] ) );
end
endgenerate

// full or empty
always@(*) begin
    queue_emtpy_signal = (item_size == 0);
    queue_full_signal = (item_size == QUEUE_LEN - 2);
end

wire queue_increase;
assign queue_increase = (valid_in == 1 && !has_match); // output and no matched item
always@(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
        item_size <= 0;
    end else if ( !queue_increase && output_ready == 1) begin
        // output and no input, -1
        if (item_size == 0) begin
            item_size <= 0;
        end else begin
            item_size <= item_size - 1;
        end
    end else if ( queue_increase && output_ready == 0) begin
        // input and no ouput, +1
        if (item_size == QUEUE_LEN) begin
            item_size <= QUEUE_LEN;
        end else begin
            item_size <= item_size + 1;
        end
    end else begin
        item_size <= item_size;
    end
end


generate
for (i = 0; i < QUEUE_LEN; i = i + 1) begin: item_queue_blk
    always@(posedge clk or negedge rst_n) begin
        if ( rst_n == 0 ) begin
            item_queue[i] <= 0;
            item_counter_queue[i] <= 0;
            item_valid_queue[i] <= 0;
        end else begin
            case({valid_in, output_ready})
            2'b00: begin
                // no input and no output
                item_queue[i] <= item_queue[i];
                item_counter_queue[i] <= item_counter_queue[i];
                item_valid_queue[i] <= item_valid_queue[i];
            end 
            2'b01: begin
                // output, no input, move forward the queue
                item_queue[i] <= item_queue[i+1];
                item_counter_queue[i] <= item_counter_queue[i+1];
                item_valid_queue[i] <= item_valid_queue[i+1];
            end 
            2'b10: begin
                // input, no ouput; try the merge
                if ( match_flag_list == 0 && i == item_size ) begin
                    // no match, and the tail item
                    item_queue[i] <= item_in;
                    item_counter_queue[i] <= item_counter_in;
                    item_valid_queue[i] <= 1;
                end else if ( match_flag_list == 0 && i != item_size) begin
                    item_queue[i] <= item_queue[i];
                    item_counter_queue[i] <= item_counter_queue[i];
                    item_valid_queue[i] <= item_valid_queue[i];
                end else if ( match_flag_list[i] == 1 ) begin
                    item_queue[i] <= item_queue[i];
                    item_counter_queue[i] <= item_counter_queue[i] + item_counter_in;
                    item_valid_queue[i] <= item_valid_queue[i];
                end else begin
                    item_queue[i] <= item_queue[i];
                    item_counter_queue[i] <= item_counter_queue[i];
                    item_valid_queue[i] <= item_valid_queue[i];
                end
            end 
            2'b11: begin
                // input and output
                if (match_flag_list == 0) begin
                    // no merge
                    if ( (item_size != 0 && i == item_size-1) ) begin 
                        // the tail
                        item_queue[i] <= item_in;
                        item_counter_queue[i] <= item_counter_in;
                        item_valid_queue[i] <= 1;
                    end else begin
                        // move forward
                        item_queue[i] <= item_queue[i+1];
                        item_counter_queue[i] <= item_counter_queue[i+1];
                        item_valid_queue[i] <= item_valid_queue[i+1];
                    end
                end else begin
                    // merge
                    if ( match_flag_list[i+1] == 1 ) begin
                        item_queue[i] <= item_queue[i+1];
                        item_counter_queue[i] <= item_counter_queue[i+1] + 1;
                        item_valid_queue[i] <= item_valid_queue[i+1];
                    end else begin
                        item_queue[i] <= item_queue[i+1];
                        item_counter_queue[i] <= item_counter_queue[i+1];
                        item_valid_queue[i] <= item_valid_queue[i+1];
                    end
                end
            end
            default: begin
                item_queue[i] <= item_queue[i];
                item_counter_queue[i] <= item_counter_queue[i];
                item_valid_queue[i] <= item_valid_queue[i];
            end
            endcase
        end
    end
end
endgenerate

// output reg valid_out,
// output reg[ITEM_LENGTH-1:0] item_out,
// output reg[ITEM_COUNTER_SIZE-1:0] item_counter,
always@(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
        valid_out <= 0;
        item_out <= 0;
        item_counter <= 0;
    end else if (output_ready == 1) begin
        if ( item_size == 0 && valid_in == 1 ) begin
            valid_out <= 1;
            item_out <= item_in;
            item_counter <= item_counter_in;
        end else if ( item_size > 0 ) begin    
            valid_out <= 1;
            item_out <= item_queue[0];
            if (match_flag_list[0] == 1) begin
                item_counter <= item_counter_queue[0] + item_counter_in;
            end else begin
                item_counter <= item_counter_queue[0];
            end
        end else begin
            valid_out <= 0;
            item_out <= 0;
            item_counter <= 0;
        end
    end else begin
        valid_out <= 0;
        item_out <= 0;
        item_counter <= 0;
    end
end

endmodule


module get_match_res
#(parameter ITEM_LENGTH = 30)
(
    input rst_n,
    input [ITEM_LENGTH-1:0] item1,
    input [ITEM_LENGTH-1:0] item2,
    input valid_flag,
    output reg match_flag
);
always@(*) begin
    if (rst_n == 0 || valid_flag == 0) begin
        match_flag = 0;
    end
    else if (item1 == item2) begin
        match_flag = 1;
    end
    else begin
        match_flag = 0;
    end
end

endmodule
