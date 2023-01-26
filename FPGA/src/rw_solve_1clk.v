module rw_solve_1clk
 #(parameter DATA1_LEN = 12, DATA2_LEN = 12, QUEUE_LEN = 64, LOC_WIDTH = 6, OTHER_INFO = 30)
(
    input clk,
    input rst_n,

    input valid_insert,
    input [DATA1_LEN-1:0] data1,
    input [DATA2_LEN-1:0] data2,
    input [OTHER_INFO-1:0] other_info,

    input valid_delete,
    input [LOC_WIDTH-1:0] del_loc_in,

    output reg valid_out,
    output reg [DATA1_LEN-1:0] data1_out,
    output reg [DATA2_LEN-1:0] data2_out,
    output reg [OTHER_INFO-1:0] other_info_out,
    output reg insert_success,
    output reg [LOC_WIDTH-1:0] insert_loc
);

reg [LOC_WIDTH-1:0] empty_loc_queue[QUEUE_LEN-1:0];
reg [LOC_WIDTH-1:0] start_idx;
reg [LOC_WIDTH-1:0] end_idx;

reg [DATA1_LEN-1:0] data1_array[QUEUE_LEN-1:0];
reg [DATA2_LEN-1:0] data2_array[QUEUE_LEN-1:0]; 
reg [1:0] tag_array[QUEUE_LEN-1:0]; 

// wire [DATA1_LEN-1:0] to_match_data1;
// wire [DATA2_LEN-1:0] to_match_data2;
reg [LOC_WIDTH-1:0] last_loc;
reg [QUEUE_LEN-1:0] match_signal; 

localparam TAG_UNVALID = 2'b00;
localparam TAG_READY = 2'b01;
localparam TAG_VALID = 2'b11;

integer i;

// assign to_match_data1 = data1;
// assign to_match_data2 = data2;


genvar gen_i;
generate
    for (gen_i = 0; gen_i < QUEUE_LEN; gen_i = gen_i + 1) begin: match_module
        always @(*) begin
            match_signal[gen_i] = ( (data1_array[gen_i] == data1) || (data2_array[gen_i] == data2) ) && ( (tag_array[gen_i] == TAG_READY) || (tag_array[gen_i] == TAG_VALID) ) && ( gen_i != last_loc ) && ~(gen_i == del_loc_in && valid_delete) ; // 对于要删除的条目, 不进行匹配 (如果valid_delete为1且是对应删除位置, signal置0, 否则忽略该情况)
        end
    end
endgenerate

always @(posedge clk) begin
    if (rst_n == 0) begin
        // reset empty queue
        for (i=0; i < QUEUE_LEN; i = i+1) begin
            empty_loc_queue[i] <= i;
        end
        start_idx <= 0;
        end_idx <= QUEUE_LEN-1;
        last_loc <= 0;
        for (i=0; i < QUEUE_LEN; i = i+1) begin
            data1_array[i] <= 0;
            data2_array[i] <= 0;
            tag_array[i] <= TAG_UNVALID;
        end
        valid_out <= 0; data1_out <= 0; data2_out <= 0; other_info_out <= 0;
        insert_success <= 0; insert_loc <= 0;
    end else begin
        if (valid_insert) begin
            valid_out <= 1;
            data1_out <= data1;
            data2_out <= data2;
            other_info_out <= other_info;
        end else begin
            valid_out <= 0; data1_out <= 0; data2_out <= 0; other_info_out <= 0;
        end
        // insert data
        if (valid_insert && (match_signal == 0) ) begin
            data1_array[last_loc] <= data1;
            data2_array[last_loc] <= data2;
            tag_array[last_loc] <= TAG_VALID;
            insert_success <= 1;
            insert_loc <= last_loc;
            // move the queue
            start_idx <= start_idx + 1;
            last_loc <= empty_loc_queue[start_idx+1];
        end else begin
            insert_success <= 0;
            insert_loc <= 0;
            tag_array[last_loc] <= TAG_UNVALID;
        end

        // delete the data
        if (valid_delete) begin
            data1_array[del_loc_in] <= 0;
            data2_array[del_loc_in] <= 0;
            tag_array[del_loc_in] <= TAG_UNVALID;
            // add empty slot
            end_idx <= end_idx + 1;
            empty_loc_queue[end_idx+1] <= del_loc_in;
        end
    end
end

endmodule

