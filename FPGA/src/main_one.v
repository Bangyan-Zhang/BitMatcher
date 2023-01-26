//`include "merge_query.v"
//`include "rw_solve_1clk.v"
//`include "entry_cal_1clk.v"

module main_one
#(parameter CMD_LEN = 30)
(
    input clk,
    input rst_n,
    input cmd_in_valid,
    input [CMD_LEN-1:0] cmd_in,

    output reg valid_out,
    output reg [CMD_LEN-1:0] cmd_out,
    output reg success_out,
    output reg [26:0] counter_size
);


localparam ENTRY_ADDR_LEN = 20;
localparam FP_ADDR_LEN = 8;
localparam COUNT_LEN = 12;
localparam LOC_LEN = 6;
localparam MERGE_ITEM_LEN = 30;

// cmd
wire [1:0] op;
wire [ENTRY_ADDR_LEN-1:0] h1_addr;
wire [FP_ADDR_LEN-1:0] aim_fp;
wire [COUNT_LEN-1:0] insert_value;
wire [LOC_LEN-1:0] record_loc;

assign {op, h1_addr, aim_fp} = cmd_in;

// FIFO for reinserting
/*
* module fifo_generator_built_in(clk, srst, din, wr_en, rd_en, dout, full, empty, valid, wr_rst_busy, rd_rst_busy);

input clk;
input srst;
input [41:0] din;
input wr_en;
input rd_en;
output [41:0] dout;
output reg full;
output reg empty;
output reg valid;
output reg wr_rst_busy;
output reg rd_rst_busy;
endmodule
*/

localparam TOTAL_CMD_LEN = 42;

reg reinsert_wr_en;
reg reinsert_rd_en;
reg[TOTAL_CMD_LEN-1:0] reinsert_din;
wire[TOTAL_CMD_LEN-1:0] reinsert_dout;
wire reinsert_full;
wire reinsert_empty;
wire reinsert_dout_valid;

fifo_generator_built_in fifo_reinsert(
    .clk(clk),
    .srst(~rst_n),
    .din( reinsert_din ),
    .wr_en( reinsert_wr_en  ),
    .rd_en( reinsert_rd_en & rst_n ),

    .dout( reinsert_dout ),
    .prog_full( reinsert_full ), // prog_full for the input as 10
    .empty( reinsert_empty ),
    .valid( reinsert_dout_valid )
);

// merge the input
reg cmd1_merge_ready;
wire cmd1_merge_valid_out;
wire [CMD_LEN-1:0] cmd1_merge_out;
wire [COUNT_LEN-1:0] cmd1_merge_cnt_out;
wire cmd1_merge_queue_full_out;
wire cmd1_merge_queue_empty_out;
wire[5:0] cmd1_dbg_item_size;


always@(posedge clk) begin
    if (rst_n == 1'b0) begin
        cmd1_merge_ready <= 1'b0;
    end else if (cmd1_dbg_item_size >= 10 ) begin
        cmd1_merge_ready <= 1'b1; // the queue is high
    end else if (reinsert_full == 1'b1) begin
        cmd1_merge_ready <= 1'b0; // when reinsert queue is full, stop reading from cmd_in
    end else begin
        cmd1_merge_ready <= 1'b1;
    end
end

merge_query #( .ITEM_LENGTH(30), .ITEM_COUNTER_SIZE(12), .QUEUE_LEN(30) )
    cmd1_in_merge
(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in( cmd_in_valid ),
    .item_in( cmd_in ),
    .item_counter_in( 1 ),
    // Enable the output
    .output_ready( cmd1_merge_ready ),
    // Output the items
    .valid_out( cmd1_merge_valid_out ),
    .item_out( cmd1_merge_out ),
    .item_counter( cmd1_merge_cnt_out ),
    .queue_full_signal( cmd1_merge_queue_full_out ),
    .queue_emtpy_signal( cmd1_merge_queue_empty_out ),
    .dbg_item_size( cmd1_dbg_item_size )
);

reg cmd1_valid_out_delay;
reg [CMD_LEN-1:0] cmd1_out_delay;
reg [COUNT_LEN-1:0] cmd1_cnt_out_delay;

always@(posedge clk) begin
    if (rst_n == 1'b0) begin
        cmd1_valid_out_delay <= 1'b0;
        cmd1_out_delay <= 0;
        cmd1_cnt_out_delay <= 0;
    end else begin
        cmd1_valid_out_delay <= cmd1_merge_valid_out;
        cmd1_out_delay <= cmd1_merge_out;
        cmd1_cnt_out_delay <= cmd1_merge_cnt_out;
    end
end


always@(*) begin
    if (rst_n == 0) begin
        reinsert_rd_en = 0;
    end else begin
        reinsert_rd_en = ~cmd1_merge_valid_out;
    end
end

// whether to use the module input or FIFO output
reg merge_valid_in;
reg [MERGE_ITEM_LEN-1:0] merge_cmd_in;
reg [COUNT_LEN-1:0] merge_cnt_in;

always@(*) begin
    if (rst_n == 0) begin
        merge_valid_in = 0;
        merge_cmd_in = 0;
        merge_cnt_in = 0;
    end else begin
        if ( cmd1_valid_out_delay == 1 ) begin
            merge_valid_in = cmd1_valid_out_delay;
            { merge_cmd_in, merge_cnt_in} = { cmd1_out_delay, cmd1_cnt_out_delay };
        end else begin
            merge_valid_in = reinsert_dout_valid;
            {merge_cmd_in, merge_cnt_in} = reinsert_dout; // 30b: item, 12b: count
        end
    end
end


wire merge_out_valid;
wire [CMD_LEN-1:0] merge_cmd_out;
wire [COUNT_LEN-1:0] merge_cnt_out;
wire merge_queue_full_out;
wire merge_queue_empty_out;
wire[5:0] dbg_item_size;

reg merge_queue_enable_output;

// input cmd_in
merge_query #( .ITEM_LENGTH(30), .ITEM_COUNTER_SIZE(12), .QUEUE_LEN(30) )
    merge_queue
(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in( merge_valid_in ),
    .item_in( merge_cmd_in ),
    .item_counter_in( merge_cnt_in ),
    // Enable the output
    .output_ready( merge_queue_enable_output ),
    // Output the items
    .valid_out( merge_out_valid ),
    .item_out( merge_cmd_out ),
    .item_counter( merge_cnt_out ),
    .queue_full_signal( merge_queue_full_out ),
    .queue_emtpy_signal( merge_queue_empty_out ),
    .dbg_item_size( dbg_item_size )
);

// 2. rw_conflict? 4K address(4K*8B=32KB; 32KB*2=64KB; one module for 64KB)

reg rw_del_valid_in;
reg [LOC_LEN-1:0] rw_del_loc;

// new cmd
wire [19:0] data1;
wire [19:0] data2;
wire [TOTAL_CMD_LEN-1:0] total_cmd_in;

wire [1:0] op_tmp1;
wire [ENTRY_ADDR_LEN-1:0] h1_addr_tmp1;
wire [FP_ADDR_LEN-1:0] aim_fp_tmp1;

assign {op_tmp1, h1_addr_tmp1, aim_fp_tmp1} = merge_cmd_out;
assign data1 = h1_addr_tmp1;
assign data2 = {h1_addr_tmp1[ENTRY_ADDR_LEN-1: FP_ADDR_LEN], aim_fp_tmp1 ^ h1_addr_tmp1[FP_ADDR_LEN-1:0]  };

assign total_cmd_in = {merge_cmd_out, merge_cnt_out};

wire rw_valid_out;
wire [TOTAL_CMD_LEN-1:0] total_cmd_out;
wire rw_insert_success_out;
wire [LOC_LEN-1:0] rw_insert_loc_out;

rw_solve_1clk
 #( .DATA1_LEN(20), .DATA2_LEN(20), .QUEUE_LEN(64), .LOC_WIDTH(LOC_LEN), .OTHER_INFO(TOTAL_CMD_LEN) )
rw_inst
(
    .clk( clk ),
    .rst_n( rst_n ),

    .valid_insert( merge_out_valid ),
    .data1( data1 ),
    .data2( data2 ),
    .other_info( total_cmd_in ),

    .valid_delete( rw_del_valid_in  ),
    .del_loc_in( rw_del_loc ),

    .valid_out( rw_valid_out ),
    .other_info_out( total_cmd_out ),
    .insert_success( rw_insert_success_out ),
    .insert_loc( rw_insert_loc_out )
);


// rw fails, put it into the FIFO
always@(*) begin
    if( rst_n && rw_valid_out && (~rw_insert_success_out) ) begin
        reinsert_wr_en = 1;
        reinsert_din = total_cmd_out;
    end else begin
        reinsert_wr_en = 0;
        reinsert_din = 0;
    end
end

// update merge_queue
always @(posedge clk or negedge rst_n ) begin
    if (rst_n == 0) begin
        merge_queue_enable_output <= 0;
    end else begin
        if ( ~rw_valid_out || merge_queue_full_out || dbg_item_size > 15 ) begin
            merge_queue_enable_output <= 1;
        end else begin
            if ( (rw_valid_out && ~rw_insert_success_out) || reinsert_full ) begin
                merge_queue_enable_output <= 0;
            end else begin
                merge_queue_enable_output <= 1;
            end
        end
    end
end

wire to_bkt_valid;
wire [TOTAL_CMD_LEN-1:0] to_bkt_cmd;  // {op, h1, aim_fp, cnt}  42bit
wire [LOC_LEN-1:0] to_bkt_record_loc; // {record_loc}  6bit

assign to_bkt_valid = rw_valid_out & rw_insert_success_out;
assign to_bkt_cmd = total_cmd_out;
assign to_bkt_record_loc = rw_insert_loc_out;

localparam BUCKET_ADDR_LEN = 13;
// RAM
reg ena_1;
wire enb_1;
reg[BUCKET_ADDR_LEN-1:0] adda_1; // set address
reg[63:0] dina_1; // set data
wire[BUCKET_ADDR_LEN-1:0] addb_1;  // get address
wire[63:0] doutb_1; // get date

assign enb_1 = to_bkt_valid;
assign addb_1 = to_bkt_cmd[TOTAL_CMD_LEN-3:TOTAL_CMD_LEN-2-ENTRY_ADDR_LEN];

blk_mem_gen_64_4K mem1 (
    .clka(clk),     // input wire clka
    .ena( ena_1 ),        // input wire ena
    .wea( ena_1 ),
    .addra( adda_1 ),       // input wire[11:0] addra
    .dina( dina_1 ),    // input wire[63:0] dina
    .clkb( clk ),     // input wire clkb
    .enb( enb_1 ),        // input wire enb
    .addrb( addb_1 ),       // input wire[11:0] addrb
    .doutb( doutb_1 )  // output wire[63:0] doutb
    // .rstb( ~rst_n )
);

reg cal_valid;
reg [47:0] cmd_with_loc;
always@(posedge clk or negedge rst_n) begin
    if(rst_n == 0) begin
        cal_valid <= 0;
        cmd_with_loc <= 0;
    end else begin
        cal_valid <= to_bkt_valid;
        cmd_with_loc <= {to_bkt_cmd, to_bkt_record_loc};
    end
end

wire valid_out_1;
wire insert_write_ram_en_1;
wire [63:0] insert_entry_out_1;
wire [47:0] insert_cmd_out_1;
wire insert_success_out_1;
wire insert_nxt_op_out_1;
wire insert_table_has_empty_1;

// Output for query operation
wire[26:0] query_counter_out_1;
wire query_success_out_1;
wire query_match_out_1;
wire[47:0] query_cmd_out_1;


entry_cal_3clk
  #( .BUCKET_LEN(64), .CMD_LEN(48) ) 
  cal1
(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(cal_valid), // entry, fp and collision_addr are all input
    .entry_in( doutb_1 ),
    .cmd_in( cmd_with_loc ),
    .first_table_en_in(1),
    .last_table_has_empty_in(0),

    .valid_out(valid_out_1),

    // Output for insert operation
    .insert_write_ram_en( insert_write_ram_en_1 ),
    .insert_entry_out( insert_entry_out_1 ),
    .insert_cmd_out( insert_cmd_out_1 ),
    .insert_success_out( insert_success_out_1 ),
    .insert_need_next_op_out( insert_nxt_op_out_1 ),
    .insert_table_has_empty( insert_table_has_empty_1 ),
    
    // Output for query operation
    .query_counter_out( query_counter_out_1 ),
    .query_success_out( query_success_out_1 ),
    .query_match_out( query_match_out_1 ),
    .query_cmd_out( query_cmd_out_1 )
);

// Update RAM
always@(*) begin
    if(rst_n == 1 && valid_out_1 && insert_success_out_1 && insert_write_ram_en_1 ) begin
        ena_1 = 1;
        adda_1 = insert_cmd_out_1[48-3:48-2-ENTRY_ADDR_LEN];
        dina_1 = insert_entry_out_1;
    end else begin
        ena_1 = 0; // not write data
        adda_1 = 0; dina_1 = 0;
    end
end

// second table

// RAM
reg ena_2;
reg enb_2;
reg[BUCKET_ADDR_LEN-1:0] adda_2; // set
reg[63:0] dina_2; // set
reg[BUCKET_ADDR_LEN-1:0] addb_2;  // get
wire[63:0] doutb_2; // get

always@(*) begin
    casex({valid_out_1, query_success_out_1, query_match_out_1, insert_success_out_1, insert_nxt_op_out_1 })
        5'b110xx: enb_2 = 1; // query, without match
        5'b111xx: enb_2 = 0; // query, with match
        5'b10x11: enb_2 = 1; // insert, need the following
        5'b10x10: enb_2 = 0; // insert, do not need the following
        default: enb_2 = 0;
    endcase
    if (query_success_out_1 && ~query_match_out_1) begin
        addb_2 = query_cmd_out_1[48-3:48-2-ENTRY_ADDR_LEN] ^ { 12'd0, query_cmd_out_1[48-2-ENTRY_ADDR_LEN-1 : 48-2-ENTRY_ADDR_LEN-FP_ADDR_LEN] };
    end else if (insert_success_out_1 && insert_nxt_op_out_1) begin
        addb_2 = insert_cmd_out_1[48-3:48-2-ENTRY_ADDR_LEN] ^ { 12'd0, insert_cmd_out_1[48-2-ENTRY_ADDR_LEN-1 : 48-2-ENTRY_ADDR_LEN-FP_ADDR_LEN] }; // xor for new table address
    end else begin
        addb_2 = 0;
    end
end


reg valid_in_cal_2;
reg [47:0] cmd_in_2;
reg table_has_empty_in_2;

always @(posedge clk) begin
    if (rst_n == 1 && valid_out_1 ) begin
        valid_in_cal_2 <= enb_2; 
        if (query_success_out_1 && ~query_match_out_1) begin
            cmd_in_2 <= query_cmd_out_1;
        end else if (insert_success_out_1 && insert_nxt_op_out_1) begin
            cmd_in_2 <= insert_cmd_out_1;
        end else begin
            cmd_in_2 <= 0;
        end
        table_has_empty_in_2 <= insert_table_has_empty_1;
    end else begin
        valid_in_cal_2 <= 0;
        cmd_in_2 <= 0;
        table_has_empty_in_2 <= 0;
    end
end


blk_mem_gen_64_4K mem2 (
    .clka(clk),     // input wire clka
    .ena( ena_2 ),        // input wire ena
    .wea( ena_2 ),
    .addra( adda_2 ),       // input wire[11:0] addra
    .dina( dina_2 ),    // input wire[63:0] dina
    .clkb( clk ),     // input wire clkb
    .enb( enb_2 ),        // input wire enb
    .addrb( addb_2 ),       // input wire[11:0] addrb
    .doutb( doutb_2 )  // output wire[63:0] doutb
    // .rstb( ~rst_n )
);


wire valid_out_2;
wire insert_write_ram_en_2;
wire [63:0] insert_entry_out_2;
wire [47:0] insert_cmd_out_2;
wire insert_success_out_2;
wire insert_nxt_op_out_2;
wire insert_table_has_empty_2;
wire [7:0] origin_fp;

// Output for query operation
wire[26:0] query_counter_out_2;
wire query_success_out_2;
wire query_match_out_2;
wire[47:0] query_cmd_out_2;

entry_cal_3clk
  #( .BUCKET_LEN(64), .CMD_LEN(48) ) 
  cal2
(
    .clk(clk),
    .rst_n(rst_n),
    .valid_in( valid_in_cal_2 ), // entry, fp and collision_addr are all input
    .entry_in( doutb_2 ),
    .cmd_in( cmd_in_2 ),
    .first_table_en_in(0),
    .last_table_has_empty_in( table_has_empty_in_2 ),

    .valid_out( valid_out_2  ),

    // Output for insert operation
    .insert_write_ram_en( insert_write_ram_en_2 ),
    .insert_entry_out( insert_entry_out_2 ),
    .insert_cmd_out( insert_cmd_out_2 ),
    .insert_success_out( insert_success_out_2 ),
    .insert_need_next_op_out( insert_nxt_op_out_2 ),
    .insert_table_has_empty( insert_table_has_empty_2 ),
    .insert_fp(origin_fp),
    
    // Output for query operation
    .query_counter_out( query_counter_out_2 ),
    .query_success_out( query_success_out_2 ),
    .query_match_out( query_match_out_2 ),
    .query_cmd_out( query_cmd_out_2 )
);

always@(*) begin
    if(rst_n == 1 && valid_out_2 && insert_success_out_2 && insert_write_ram_en_2 ) begin
        ena_2 = 1;
        adda_2 = insert_cmd_out_2[48-3:48-2-ENTRY_ADDR_LEN] ^ {12'd0, origin_fp}; 
        dina_2 = insert_entry_out_2;
    end else begin
        ena_2 = 0; 
        adda_2 = 0; dina_2 = 0;
    end
end

// 4. back to the rw module to release the lock


reg valid_candidate_1;
reg [47:0] cmd_out_candidate_1;
reg [26:0] counter_candidate_1;

always@(*) begin
    casex({valid_out_1, query_success_out_1, query_match_out_1, insert_success_out_1, insert_nxt_op_out_1 })
        5'b111xx: begin 
            valid_candidate_1 = 1;
            cmd_out_candidate_1 = query_cmd_out_1;
            counter_candidate_1 = query_counter_out_1;
        end
        5'b10x10: begin 
            valid_candidate_1 = 1;
            cmd_out_candidate_1 = insert_cmd_out_1;
            counter_candidate_1 = 0;
        end
        default: begin
            valid_candidate_1 = 0;
            cmd_out_candidate_1 = 0;
            counter_candidate_1 = 0;
        end
    endcase
end

reg valid_candidate_2;
reg [47:0] cmd_out_candidate_2;
reg [26:0] counter_candidate_2;

always@(*) begin
    casex({valid_out_2, query_success_out_2, query_match_out_2, insert_success_out_2, insert_nxt_op_out_2 })
        5'b11xxx: begin 
            valid_candidate_2 = 1;
            cmd_out_candidate_2 = query_cmd_out_2;
            counter_candidate_2 = query_counter_out_2;
        end
        5'b10x1x: begin 
            valid_candidate_2 = 1;
            cmd_out_candidate_2 = insert_cmd_out_2;
            counter_candidate_2 = 0;
        end
        default: begin
            valid_candidate_2 = 0;
            cmd_out_candidate_2 = 0;
            counter_candidate_2 = 0;
        end
    endcase
end

localparam OUTPUT_FIFO_LEN = 48+27;

reg output_fifo_rd_en1, output_fifo_rd_en2;

wire [OUTPUT_FIFO_LEN-1:0] output_fifo_dout1;
wire [OUTPUT_FIFO_LEN-1:0] output_fifo_dout2;
wire output_fifo_valid1, output_fifo_valid2;
wire output_fifo_empty1, output_fifo_empty2;


fifo_built_in_75 U_output_FIFO_1 (
    .clk( clk ),
    .srst( ~rst_n ), 
    .din( {cmd_out_candidate_1, counter_candidate_1} ), //input [74:0] din
    .wr_en(  valid_candidate_1 ), //input wr_en
    .rd_en( output_fifo_rd_en1 & rst_n ), //input rd_en
    .dout( output_fifo_dout1 ), //output [74:0] dout
    .valid( output_fifo_valid1 ), //output valid
    // .full( ), //output full
    .empty( output_fifo_empty1 ) //output empty
    // .wr_rst_busy(),
    // .rd_rst_busy()
);

fifo_built_in_75 U_output_FIFO_2 (
    .clk( clk ),
    .srst( ~rst_n ), 
    .din( {cmd_out_candidate_2, counter_candidate_2} ), //input [74:0] din
    .wr_en(  valid_candidate_2 ), //input wr_en
    
    .rd_en( output_fifo_rd_en2 & ~(output_fifo_empty1 == 0 || output_fifo_valid1 == 1) & rst_n ), //input rd_en
    .dout( output_fifo_dout2 ), //output [74:0] dout
    .valid( output_fifo_valid2 ), //output valid
    // .full( ), //output full
    .empty( output_fifo_empty2 ) //output empty
    // .wr_rst_busy(),
    // .rd_rst_busy()
);

always@(posedge clk or negedge rst_n) begin
    if(rst_n == 0) begin
        output_fifo_rd_en1 <= 0; output_fifo_rd_en2 <= 0;
    end else begin
        if (output_fifo_valid1 == 1 ) begin
            // 1st FIFO has output
            output_fifo_rd_en1 <= ~output_fifo_empty1; // continue the FIFO
            output_fifo_rd_en2 <= output_fifo_empty1;  // or the second FIFO
            valid_out <= 1; // output
            cmd_out <= output_fifo_dout1[OUTPUT_FIFO_LEN-1:OUTPUT_FIFO_LEN-30];
            success_out <= 1;
            counter_size <= output_fifo_dout1[27-1:0];
            rw_del_valid_in <= 1; // delete one lock
            rw_del_loc <= output_fifo_dout1[27+5:27+0];
        end else if (output_fifo_valid2 == 1) begin
            // 2nd FIFO
            output_fifo_rd_en2 <= ~output_fifo_empty2;
            output_fifo_rd_en1 <= output_fifo_empty2;
            valid_out <= 1; 
            cmd_out <= output_fifo_dout2[OUTPUT_FIFO_LEN-1:OUTPUT_FIFO_LEN-30];
            success_out <= 1;
            counter_size <= output_fifo_dout2[27-1:0];
            rw_del_valid_in <= 1;
            rw_del_loc <= output_fifo_dout2[27+5:27+0];
        end else begin
            valid_out <= 0;
            cmd_out <= 0; 
            success_out <= 0; 
            counter_size <= 0;
            rw_del_valid_in <= 0;
            rw_del_loc <= 0;

            if (output_fifo_empty1 == 0) begin
                // the table is not emtpy
                output_fifo_rd_en1 <= 1;
                output_fifo_rd_en2 <= 0;
            end else begin
                // read 2nd FIFO; CRITICAL: only one FIFO one time
                output_fifo_rd_en1 <= 0;
                output_fifo_rd_en2 <= 1;
            end
        end
           
    end
end

endmodule


// 1 engine: 200Mpps <--> 128KB/256KB
// 4 engine: 800Mpps <--> 256KB*4 = 1MB

// BRAM: 2K * 32Kb = 8MB 
// URAM: 960 * 4K*8B = 32MB 

