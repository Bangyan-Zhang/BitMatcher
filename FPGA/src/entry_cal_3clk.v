`include "macro.v"
module bucket_cal_3clk
  #(parameter BUCKET_LEN = 64, CMD_LEN = 48) // table2 is to indict whether we need to use h2 = h1 ^ fp
(
    input clk,
    input rst_n,
    input valid_in, // bucket_clk1, fp and collision_addr are all input
    input [BUCKET_LEN-1:0] bucket_in,
    input [CMD_LEN-1:0] cmd_in,
    input first_table_en_in, // Whether the table is the first
    input last_table_has_empty_in,

    output reg valid_out,

    // Output for insert operation
    output reg insert_write_ram_en,
    output reg [BUCKET_LEN-1:0] insert_bucket_out,
    output reg [CMD_LEN-1:0] insert_cmd_out,
    output reg insert_success_out,
    output reg insert_need_next_op_out,
    output reg insert_table_has_empty,
    output reg [7:0] insert_fp,
    
    // Output for query operation
    output reg [26:0] query_counter_out,
    output reg query_success_out,
    output reg query_match_out,
    output reg [CMD_LEN-1:0] query_cmd_out
);
localparam BUCKET_ADDR_LEN = 20;
localparam FP_ADDR_LEN = 8;
localparam VALUE_LEN = 12;
localparam LOC_LEN = 6;
localparam MAX_COUNTER_LEN = 27;
localparam MAX_COUNTER = (1<<MAX_COUNTER_LEN) - 1;

// States
localparam OP_NOP = 2'b00;
localparam OP_QUERY = 2'b10;
localparam OP_REINSERT = 2'b01;
localparam OP_INSERT = 2'b11;

// Store the input with 1 clk delay
(* max_fanout="20" *)  reg [BUCKET_LEN-1:0] bucket_clk1;
(* max_fanout="20" *)  reg [CMD_LEN-1:0] cmd_clk1;
reg first_table_en_clk1;
reg last_table_has_empty_clk1;

// 2 clk delay
(* max_fanout="20" *)  reg [BUCKET_LEN-1:0] bucket_clk2;
(* max_fanout="20" *)  reg [CMD_LEN-1:0] cmd_clk2;
reg first_table_en_clk2;
reg last_table_has_empty_clk2;

// 3 clk delay
(* max_fanout="20" *)  reg [BUCKET_LEN-1:0] bucket_clk3;
(* max_fanout="20" *)  reg [CMD_LEN-1:0] cmd_clk3;
reg first_table_en_clk3;
reg last_table_has_empty_clk3;

reg valid_clk1, valid_clk2, valid_clk3;
always@(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0) begin
        valid_out <= 1'b0;
        {valid_clk1, valid_clk2, valid_clk3} <= 3'b0;
    end else begin
        valid_clk1 <= valid_in;
        valid_clk2 <= valid_clk1;
        valid_clk3 <= valid_clk2;
        valid_out <= valid_clk3;
    end
end

// Get the delayed input
always@(posedge clk) begin
  if(!rst_n) begin
    bucket_clk1 <= 0; cmd_clk1 <= 0; first_table_en_clk1 <= 0; last_table_has_empty_clk1 <= 0;
    bucket_clk2 <= 0; cmd_clk2 <= 0; first_table_en_clk2 <= 0; last_table_has_empty_clk2 <= 0;
    bucket_clk3 <= 0; cmd_clk3 <= 0; first_table_en_clk3 <= 0; last_table_has_empty_clk3 <= 0;
  end
  else begin
      {bucket_clk1, cmd_clk1, first_table_en_clk1, last_table_has_empty_clk1} <= {bucket_in, cmd_in, first_table_en_in, last_table_has_empty_in};
      {bucket_clk2, cmd_clk2, first_table_en_clk2, last_table_has_empty_clk2} <= {bucket_clk1, cmd_clk1, first_table_en_clk1, last_table_has_empty_clk1};
      {bucket_clk3, cmd_clk3, first_table_en_clk3, last_table_has_empty_clk3} <= {bucket_clk2, cmd_clk2, first_table_en_clk2, last_table_has_empty_clk2};
  end
end


// Parse the command
wire [1:0] op_clk1, op_clk2, op_clk3;
wire [BUCKET_ADDR_LEN-1:0] h1_addr_clk1, h1_addr_clk2, h1_addr_clk3;
wire [FP_ADDR_LEN-1:0] aim_fp_clk1, aim_fp_clk2, aim_fp_clk3;
wire [VALUE_LEN-1:0] insert_value_clk1, insert_value_clk2, insert_value_clk3;
wire [LOC_LEN-1:0] record_loc_clk1, record_loc_clk2, record_loc_clk3;

assign {op_clk1, h1_addr_clk1, aim_fp_clk1, insert_value_clk1, record_loc_clk1} = cmd_clk1;
assign {op_clk2, h1_addr_clk2, aim_fp_clk2, insert_value_clk2, record_loc_clk2} = cmd_clk2;
assign {op_clk3, h1_addr_clk3, aim_fp_clk3, insert_value_clk3, record_loc_clk3} = cmd_clk3;

// Entry: type, fp[], count[]

// Clock 1: parse bucket
reg [2:0] fp_size_clk2; // #fingerprint: 3-5 
reg [FP_ADDR_LEN-1:0] fp_list_clk2[4:0]; // fingerprint list
reg [MAX_COUNTER_LEN-1:0] cnt_list_clk2[4:0]; // cnt list
reg [MAX_COUNTER_LEN-1:0] cnt_max_list_clk2[4:0]; // the list for the max available cnt
// reg [4:0] cnt_list_clk2; // Get the mask according to the fp_size
reg [4:0] type_cnt_mask_clk2;

// parse fingerprint
always@(posedge clk) begin
  if (rst_n == 0) begin
      fp_size_clk2 <= 0; {fp_list_clk2[4], fp_list_clk2[3], fp_list_clk2[2], fp_list_clk2[1], fp_list_clk2[0]} <= {8'd0, 8'd0, 8'd0, 8'd0, 8'd0};
  end else begin
    case(bucket_clk1[3:0])
      4'd0: begin
        fp_size_clk2 <= 5;
        {fp_list_clk2[4], fp_list_clk2[3], fp_list_clk2[2], fp_list_clk2[1], fp_list_clk2[0] } <= bucket_clk1[4+FP_ADDR_LEN*5-1:4];
      end
      4'd1, 4'd2, 4'd3: begin
        fp_size_clk2 <= 4;
        {fp_list_clk2[3], fp_list_clk2[2], fp_list_clk2[1], fp_list_clk2[0] } <= bucket_clk1[4+FP_ADDR_LEN*4-1:4];
        fp_list_clk2[4] <= 0;
      end
      4'd4, 4'd5, 4'd6, 4'd7, 4'd8, 4'd9, 4'd10, 4'd11: begin
        fp_size_clk2 <= 3;
        {fp_list_clk2[2], fp_list_clk2[1], fp_list_clk2[0] } <= bucket_clk1[4+FP_ADDR_LEN*3-1:4];
        {fp_list_clk2[4], fp_list_clk2[3] } <= 0;
      end
      default: begin // Error! Nothing is done.
        fp_size_clk2 <= 0;
        {fp_list_clk2[4], fp_list_clk2[3], fp_list_clk2[2], fp_list_clk2[1], fp_list_clk2[0] } <= 0;
      end
    endcase
  end
end

// Get mask from fp_size
always@(fp_size_clk2) begin
  case(fp_size_clk2)
    5: type_cnt_mask_clk2 = 5'b11111;
    4: type_cnt_mask_clk2 = 5'b01111;
    3: type_cnt_mask_clk2 = 5'b00111;
    default: type_cnt_mask_clk2 = 5'b00000;
  endcase
end

// Parse counter
always@(posedge clk) begin
  if (rst_n == 0) begin
    {cnt_list_clk2[4], cnt_list_clk2[3], cnt_list_clk2[2], cnt_list_clk2[1], cnt_list_clk2[0]} <= {27'd0, 27'd0, 27'd0, 27'd0, 27'd0};
  end else begin
    case(bucket_clk1[3:0])
      4'd0: begin
        {cnt_list_clk2[4][5:0], cnt_list_clk2[3][4:0], cnt_list_clk2[2][3:0], cnt_list_clk2[1][2:0], cnt_list_clk2[0][1:0]} <= bucket_clk1[BUCKET_LEN-1:4+FP_ADDR_LEN*5];
        {cnt_list_clk2[4][MAX_COUNTER_LEN-1:6], cnt_list_clk2[3][MAX_COUNTER_LEN-1:5], cnt_list_clk2[2][MAX_COUNTER_LEN-1:4], cnt_list_clk2[1][MAX_COUNTER_LEN-1:3], cnt_list_clk2[0][MAX_COUNTER_LEN-1:2]} <= 0;
      end

      `define GET_COUNTER_4(type_id) type_id: begin\
      {cnt_list_clk2[3][18-3*(type_id):0], cnt_list_clk2[2][(type_id+3):0], cnt_list_clk2[1][(type_id+2):0], cnt_list_clk2[0][(type_id+1):0]} <= bucket_clk1[BUCKET_LEN-1:4+FP_ADDR_LEN*4]; \
      {cnt_list_clk2[4], cnt_list_clk2[3][MAX_COUNTER_LEN-1:(18-3*(type_id)+1)], cnt_list_clk2[2][MAX_COUNTER_LEN-1:(type_id+4)], cnt_list_clk2[1][MAX_COUNTER_LEN-1:(type_id+3)], cnt_list_clk2[0][MAX_COUNTER_LEN-1:(type_id+2)]} <= 0; \
      end

      `GET_COUNTER_4(4'd1)
      `GET_COUNTER_4(4'd2)
      `GET_COUNTER_4(4'd3)

      `define GET_COUNTER_3(type_id) type_id: begin \
      {cnt_list_clk2[2][34-2*(type_id):0], cnt_list_clk2[1][(type_id):0], cnt_list_clk2[0][(type_id-1):0]} <= bucket_clk1[BUCKET_LEN-1:4+FP_ADDR_LEN*3]; \
      {cnt_list_clk2[4], cnt_list_clk2[3], cnt_list_clk2[2][MAX_COUNTER_LEN-1:35-2*(type_id)], cnt_list_clk2[1][MAX_COUNTER_LEN-1:(type_id+1)], cnt_list_clk2[0][MAX_COUNTER_LEN-1:(type_id)]} <= 0; \
      end

      4'd4: begin
        {cnt_list_clk2[2][MAX_COUNTER_LEN-1:0], cnt_list_clk2[1][4:0], cnt_list_clk2[0][3:0]} <= bucket_clk1[BUCKET_LEN-1:4+FP_ADDR_LEN*3];
        {cnt_list_clk2[4], cnt_list_clk2[3], cnt_list_clk2[1][MAX_COUNTER_LEN-1:5], cnt_list_clk2[0][MAX_COUNTER_LEN-1:4]} <= 0;
      end
      `GET_COUNTER_3(4'd5)
      `GET_COUNTER_3(4'd6)
      `GET_COUNTER_3(4'd7)
      `GET_COUNTER_3(4'd8)
      `GET_COUNTER_3(4'd9)
      `GET_COUNTER_3(4'd10)
      `GET_COUNTER_3(4'd11)
      
      default: begin     // Error! Nothing is done.
        {cnt_list_clk2[4], cnt_list_clk2[3], cnt_list_clk2[2], cnt_list_clk2[1], cnt_list_clk2[0] } <= {27'd0, 27'd0, 27'd0, 27'd0, 27'd0};
      end
    endcase
  end
end

// Parse the max value of the counts
always @(posedge clk) begin
  if (rst_n == 0) begin
    {cnt_max_list_clk2[4], cnt_max_list_clk2[3], cnt_max_list_clk2[2], cnt_max_list_clk2[1], cnt_max_list_clk2[0]} <= {27'd0, 27'd0, 27'd0, 27'd0, 27'd0};
  end else begin
    case(bucket_clk1[3:0])
      4'd0: begin 
        cnt_max_list_clk2[4] <= (1<<6)-1;
        cnt_max_list_clk2[3] <= (1<<5)-1;
        cnt_max_list_clk2[2] <= (1<<4)-1;
        cnt_max_list_clk2[1] <= (1<<3)-1;
        cnt_max_list_clk2[0] <= (1<<2)-1;
      end
      `define SET_COUNTER_MAX_4(type_id) type_id: begin \
            cnt_max_list_clk2[4] <= 0; \
            cnt_max_list_clk2[3] <= (1<<( 19-3*(type_id)))-1; \
            cnt_max_list_clk2[2] <= (1<<(type_id+4))-1; \
            cnt_max_list_clk2[1] <= (1<<(type_id+3))-1; \
            cnt_max_list_clk2[0] <= (1<<(type_id+2))-1; \
      end
      
      `SET_COUNTER_MAX_4(4'd1)
      `SET_COUNTER_MAX_4(4'd2)
      `SET_COUNTER_MAX_4(4'd3)

      `define SET_COUNTER_MAX_3(type_id) type_id: begin \
            cnt_max_list_clk2[4] <= 0; \
            cnt_max_list_clk2[3] <= 0; \
            cnt_max_list_clk2[2] <= (1<<( 35-(type_id)*2 ))-1; \
            cnt_max_list_clk2[1] <= (1<<(type_id+1))-1; \
            cnt_max_list_clk2[0] <= (1<<(type_id))-1; \
          end

      `SET_COUNTER_MAX_3(4'd4)
      `SET_COUNTER_MAX_3(4'd5)
      `SET_COUNTER_MAX_3(4'd6)
      `SET_COUNTER_MAX_3(4'd7)
      `SET_COUNTER_MAX_3(4'd8)
      `SET_COUNTER_MAX_3(4'd9)
      `SET_COUNTER_MAX_3(4'd10)
      `SET_COUNTER_MAX_3(4'd11)

      default: begin
        {cnt_max_list_clk2[4], cnt_max_list_clk2[3], cnt_max_list_clk2[2], cnt_max_list_clk2[1], cnt_max_list_clk2[0]} <= {27'd0, 27'd0, 27'd0, 27'd0, 27'd0};
      end
    endcase
  end
end


// Clock 2: Get the results
reg[4:0] match_flag_clk3;
reg[4:0] empty_flag_clk3;
reg has_match_clk3;
reg has_empty_clk3;

// delay the results from clk2 to clk3
reg [2:0] fp_size_clk3;
reg [FP_ADDR_LEN-1:0] fp_list_clk3[4:0];
reg [MAX_COUNTER_LEN-1:0] cnt_list_clk3[4:0]; 
reg [MAX_COUNTER_LEN-1:0] cnt_max_list_clk3[4:0];
// reg[4:0] cnt_list_clk3;
reg [4:0] type_cnt_mask_clk3;
always@(posedge clk) begin
  if (rst_n == 0) begin
    fp_size_clk3 <= 0; 
    {fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]} <= {27'd0, 27'd0, 27'd0, 27'd0, 27'd0};
    {cnt_list_clk3[4], cnt_list_clk3[3], cnt_list_clk3[2], cnt_list_clk3[1], cnt_list_clk3[0]} <= {27'd0, 27'd0, 27'd0, 27'd0, 27'd0};
    {cnt_max_list_clk3[4], cnt_max_list_clk3[3], cnt_max_list_clk3[2], cnt_max_list_clk3[1], cnt_max_list_clk3[0]} <= {27'd0, 27'd0, 27'd0, 27'd0};
    type_cnt_mask_clk3 <= 0;
  end else begin
    fp_size_clk3 <= fp_size_clk2;
    {fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]} <= {fp_list_clk2[4], fp_list_clk2[3], fp_list_clk2[2], fp_list_clk2[1], fp_list_clk2[0]};
    {cnt_list_clk3[4], cnt_list_clk3[3], cnt_list_clk3[2], cnt_list_clk3[1], cnt_list_clk3[0]} <= {cnt_list_clk2[4], cnt_list_clk2[3], cnt_list_clk2[2], cnt_list_clk2[1], cnt_list_clk2[0]};
    {cnt_max_list_clk3[4], cnt_max_list_clk3[3], cnt_max_list_clk3[2], cnt_max_list_clk3[1], cnt_max_list_clk3[0]} <=  {cnt_max_list_clk2[4], cnt_max_list_clk2[3], cnt_max_list_clk2[2], cnt_max_list_clk2[1], cnt_max_list_clk2[0]};
  end
end


reg [MAX_COUNTER_LEN-1:0] out_cnt_clk3; // new cnt
reg [MAX_COUNTER_LEN-1:0] cnt_max_clk3;
reg [2:0] match_pos_clk3;
reg [2:0] empty_pos_clk3;

reg [5:0] type_cnt_mask_clk3; // new cnt_mask
// delay type_cnt_mask
always@(posedge clk) begin
  if (rst_n == 0)
    type_cnt_mask_clk3 <= 0;
  else
    type_cnt_mask_clk3 <= type_cnt_mask_clk2;
end

// whether match or empty for each slot
genvar i;
generate
  for (i = 0; i < 5; i = i + 1) begin
    always@(posedge clk) begin
      if (rst_n == 0) begin
        match_flag_clk3[i] <= 0;
        empty_flag_clk3[i] <= 0;
      end else begin
        match_flag_clk3[i] <= (fp_list_clk2[i] == aim_fp_clk2)? 1 : 0;
        empty_flag_clk3[i] <= (fp_list_clk2[i] == 0)? 1 : 0;
      end
    end
  end
endgenerate

// reduce all match_flag and empty_flag
always @(*) begin
  has_match_clk3 = ((match_flag_clk3 & type_cnt_mask_clk3) == 5'b00000)? 0 : 1;
  has_empty_clk3 = ((empty_flag_clk3 & type_cnt_mask_clk3) == 5'b00000)? 0 : 1;
end

// Get the matched count
always @(*) begin
  casex(match_flag_clk3)
        5'b1????: begin 
          out_cnt_clk3 = cnt_list_clk3[4];
          cnt_max_clk3 =  cnt_max_list_clk3[4];
          match_pos_clk3 = 4;
        end
        5'b01???: begin
          out_cnt_clk3 = cnt_list_clk3[3];
          cnt_max_clk3 = cnt_max_list_clk3[3];
          match_pos_clk3 = 3;
        end
        5'b001??: begin
          out_cnt_clk3 = cnt_list_clk3[2];
          cnt_max_clk3 = cnt_max_list_clk3[2];
          match_pos_clk3 = 2;
        end
        5'b0001?: begin
          out_cnt_clk3 = cnt_list_clk3[1];
          cnt_max_clk3 = cnt_max_list_clk3[1];
          match_pos_clk3 = 1;
        end
        5'b00001: begin
          out_cnt_clk3 = cnt_list_clk3[0];
          cnt_max_clk3 = cnt_max_list_clk3[0];
          match_pos_clk3 = 0;
        end
        default: begin
          out_cnt_clk3 = 0;
          cnt_max_clk3 = 0;
          match_pos_clk3 = 7;
        end
  endcase
end

// Get the empty location
always @(*) begin
  casex(empty_flag_clk3)
        5'b1????: empty_pos_clk3 = 4;
        5'b01???: empty_pos_clk3 = 3;
        5'b001??: empty_pos_clk3 = 2;
        5'b0001?: empty_pos_clk3 = 1;
        5'b00001: empty_pos_clk3 = 0;
        default:  empty_pos_clk3 = 7;
  endcase
end

// Clock 3: For query, output
always @(posedge clk) begin
  if (valid_clk3 && rst_n) begin
    query_cmd_out <= cmd_clk3;
    if ( op_clk3 == OP_QUERY && has_match_clk3) begin
        query_success_out <= 1'b1;
        query_counter_out <= out_cnt_clk3;
        query_match_out <= 1'b1; // match
    end else if ( op_clk3 == OP_QUERY && !has_match_clk3) begin
        query_success_out <= 1'b1;
        query_counter_out <= 0;
        query_match_out <= 1'b0; // not match
    end else begin
        query_success_out <= 1'b0;
        query_counter_out <= 0;
        query_match_out <= 1'b0;
    end
  end else begin
    query_cmd_out <= 0;
    query_success_out <= 1'b0;
    query_counter_out <= 0;
    query_match_out <= 1'b0;
  end
end

// Clock 3: For insert, increase counter to get the new
reg [MAX_COUNTER_LEN-1:0] new_cnt_clk3;
reg new_cnt_overflow_clk3;
always @(*) begin
  new_cnt_clk3 = out_cnt_clk3 + insert_value_clk3;
  if (cnt_max_clk3 - out_cnt_clk3 >= insert_value_clk3 && out_cnt_clk3 != 0 ) begin
    new_cnt_overflow_clk3 = 0;
  end else begin
    new_cnt_overflow_clk3 = 1;
  end
end

// Without overflow, get the new bucket
reg [BUCKET_LEN-1:0] bucket_new_insert_no_overflow;
always @(*) begin
  case(bucket_clk3[3:0])
    4'd0: begin 
      case(match_pos_clk3)
        3'd4: bucket_new_insert_no_overflow = { new_cnt_clk3[5:0] , bucket_clk3[BUCKET_LEN-7:0] };
        3'd3: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-6], new_cnt_clk3[4:0], bucket_clk3[BUCKET_LEN-12:0] };
        3'd2: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-11], new_cnt_clk3[3:0], bucket_clk3[BUCKET_LEN-16:0] };
        3'd1: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-15], new_cnt_clk3[2:0], bucket_clk3[BUCKET_LEN-19:0] };
        3'd0: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-18], new_cnt_clk3[1:0], bucket_clk3[BUCKET_LEN-21:0] };
        default: bucket_new_insert_no_overflow = bucket_clk3;
      endcase
    end
    4'd1: begin
      case(match_pos_clk3)
        3'd3: bucket_new_insert_no_overflow = { new_cnt_clk3[15:0], bucket_clk3[BUCKET_LEN-17:0] };
        3'd2: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-16], new_cnt_clk3[4:0], bucket_clk3[BUCKET_LEN-22:0] };
        3'd1: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-21], new_cnt_clk3[3:0], bucket_clk3[BUCKET_LEN-26:0] };
        3'd0: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-25], new_cnt_clk3[2:0], bucket_clk3[BUCKET_LEN-29:0] };
        default: bucket_new_insert_no_overflow = bucket_clk3;
      endcase
    end
    4'd2: begin
        case(match_pos_clk3)
          3'd3: bucket_new_insert_no_overflow = { new_cnt_clk3[12:0], bucket_clk3[BUCKET_LEN-14:0] }; 
          3'd2: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-13], new_cnt_clk3[5:0], bucket_clk3[BUCKET_LEN-20:0] };
          3'd1: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-19], new_cnt_clk3[4:0], bucket_clk3[BUCKET_LEN-26:0] };
          3'd0: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-25], new_cnt_clk3[3:0], bucket_clk3[BUCKET_LEN-29:0] };
          default: bucket_new_insert_no_overflow = bucket_clk3;
        endcase
    end
    4'd3: begin
     case(match_pos_clk3)
        3'd3: bucket_new_insert_no_overflow = { new_cnt_clk3[9:0], bucket_clk3[BUCKET_LEN-11:0] };
        3'd2: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-10], new_cnt_clk3[6:0], bucket_clk3[BUCKET_LEN-20:0] };
        3'd1: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-19], new_cnt_clk3[5:0], bucket_clk3[BUCKET_LEN-26:0] };
        3'd0: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-25], new_cnt_clk3[4:0], bucket_clk3[BUCKET_LEN-29:0] };
        default: bucket_new_insert_no_overflow = bucket_clk3;
      endcase
    end
    `define GET_NO_OVERFLOW_BUCKET_3(type_id) type_id: begin \
    case(match_pos_clk3) \
    3'd2: bucket_new_insert_no_overflow = { new_cnt_clk3[34-2*(type_id):0], bucket_clk3[BUCKET_LEN-(36-2*(type_id)):0] }; \
    3'd1: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-(35-2*(type_id))], new_cnt_clk3[(type_id):0], bucket_clk3[BUCKET_LEN-(25+type_id):0] }; \
    3'd0: bucket_new_insert_no_overflow = { bucket_clk3[BUCKET_LEN-1: BUCKET_LEN-(36-type_id)], new_cnt_clk3[(type_id-1):0], bucket_clk3[BUCKET_LEN-37:0] }; \
    default: bucket_new_insert_no_overflow = bucket_clk3; \
    endcase end

    `GET_NO_OVERFLOW_BUCKET_3(4'd4)
    `GET_NO_OVERFLOW_BUCKET_3(4'd5)
    `GET_NO_OVERFLOW_BUCKET_3(4'd6)
    `GET_NO_OVERFLOW_BUCKET_3(4'd7)
    `GET_NO_OVERFLOW_BUCKET_3(4'd8)
    `GET_NO_OVERFLOW_BUCKET_3(4'd9)
    `GET_NO_OVERFLOW_BUCKET_3(4'd10)
    `GET_NO_OVERFLOW_BUCKET_3(4'd11)

    default: begin
      bucket_new_insert_no_overflow = bucket_clk3;
    end
  endcase
end


// adjust locally?
reg [2:0] local_sw_pos_clk3;
reg local_sw_en_clk3;
always @(*) begin
  // If we can exchange with the fp[3]
  //   Here we do not need to judge the number in count_list, because cnt_max_list_clk3[3] = 0 if there is only 3 fps in the bucket
  if (cnt_max_list_clk3[4] > new_cnt_clk3 && (empty_flag_clk3[4] == 1 || (cnt_max_clk3 > cnt_list_clk3[4])) ) begin
    local_sw_en_clk3 = 1;
    local_sw_pos_clk3 = 4;
  end else if (cnt_max_list_clk3[3] > new_cnt_clk3 && (empty_flag_clk3[3] == 1 || cnt_max_clk3 > cnt_list_clk3[3]) ) begin
    local_sw_en_clk3 = 1;
    local_sw_pos_clk3 = 3;
  end else if (cnt_max_list_clk3[2] > new_cnt_clk3 && (empty_flag_clk3[2] == 1 || cnt_max_clk3 > cnt_list_clk3[2]) ) begin
    local_sw_en_clk3 = 1;
    local_sw_pos_clk3 = 2;
  end else if (cnt_max_list_clk3[1] > new_cnt_clk3 && (empty_flag_clk3[1] == 1 || cnt_max_clk3 > cnt_list_clk3[1]) ) begin
    local_sw_en_clk3 = 1;
    local_sw_pos_clk3 = 1;
  end else begin
    local_sw_en_clk3 = 0;
    local_sw_pos_clk3 = 0;
  end
end

// new bucket for overflow without state transfer
reg [BUCKET_LEN-1:0] bucket_new_insert_local_adjust;
always @(*) begin
  if (!local_sw_en_clk3) begin
    bucket_new_insert_local_adjust = 0;
  end else begin
    case(bucket_clk3[3:0])
      4'd0: begin
        case({match_pos_clk3, local_sw_pos_clk3})
        // bucket_new_insert_local_adjust = { {cnt_list_clk3[4][5:0], cnt_list_clk3[3][4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
          {3'd0, 3'd1}:
            bucket_new_insert_local_adjust = { {cnt_list_clk3[4][5:0], cnt_list_clk3[3][4:0], cnt_list_clk3[2][3:0], new_cnt_clk3[2:0],cnt_list_clk3[1][1:0]}, {fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[0], fp_list_clk3[1]}, bucket_clk3[3:0] };
          {3'd0, 3'd2}:
            bucket_new_insert_local_adjust = { {cnt_list_clk3[4][5:0], cnt_list_clk3[3][4:0], new_cnt_clk3[3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[2][1:0]}, {fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[0], fp_list_clk3[1], fp_list_clk3[2]}, bucket_clk3[3:0] };
          {3'd0, 3'd3}: 
            bucket_new_insert_local_adjust = { {cnt_list_clk3[4][5:0], new_cnt_clk3[4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[3][1:0]}, {fp_list_clk3[4], fp_list_clk3[0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[3]}, bucket_clk3[3:0] };
          {3'd0, 3'd4}:
            bucket_new_insert_local_adjust = { {new_cnt_clk3[5:0], cnt_list_clk3[3][4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[4][1:0]}, {fp_list_clk3[0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[4]}, bucket_clk3[3:0] };
          {3'd1, 3'd2}:
            bucket_new_insert_local_adjust = { {cnt_list_clk3[4][5:0], cnt_list_clk3[3][4:0], new_cnt_clk3[3:0], cnt_list_clk3[2][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[1], fp_list_clk3[2], fp_list_clk3[0]}, bucket_clk3[3:0] };
          {3'd1, 3'd3}:
            bucket_new_insert_local_adjust = { {cnt_list_clk3[4][5:0], new_cnt_clk3[4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[3][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[4], fp_list_clk3[1], fp_list_clk3[2], fp_list_clk3[3], fp_list_clk3[0]}, bucket_clk3[3:0] };
          {3'd1, 3'd4}:
            bucket_new_insert_local_adjust = { {new_cnt_clk3[5:0], cnt_list_clk3[3][4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[4][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[1], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[4], fp_list_clk3[0]}, bucket_clk3[3:0] };
          {3'd2, 3'd3}:
            bucket_new_insert_local_adjust = { {cnt_list_clk3[4][5:0], new_cnt_clk3[4:0], cnt_list_clk3[3][3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[4], fp_list_clk3[2], fp_list_clk3[3], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
          {3'd2, 3'd4}:
            bucket_new_insert_local_adjust = { {new_cnt_clk3[5:0], cnt_list_clk3[3][4:0], cnt_list_clk3[4][3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[2], fp_list_clk3[3], fp_list_clk3[4], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
          {3'd3, 3'd4}:
            bucket_new_insert_local_adjust = { {new_cnt_clk3[5:0], cnt_list_clk3[4][4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[3], fp_list_clk3[4], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
          default: 
            bucket_new_insert_local_adjust = 0;
        endcase
      end

      // bucket_new_insert_local_adjust = { {cnt_list_clk3[3][15:0], cnt_list_clk3[2][4:0], cnt_list_clk3[1][3:0], cnt_list_clk3[0][2:0]}, {fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
      `define CASE_FOUR(type_id) type_id: begin \
      case({match_pos_clk3, local_sw_pos_clk3}) \
      {3'd0, 3'd1}: bucket_new_insert_local_adjust = { {cnt_list_clk3[3][(18-3*type_id):0], cnt_list_clk3[2][(type_id+3):0], new_cnt_clk3[(type_id+2):0], cnt_list_clk3[1][(type_id+1):0]}, {fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[0], fp_list_clk3[1]}, bucket_clk3[3:0] }; \
      {3'd0, 3'd2}: bucket_new_insert_local_adjust = { {cnt_list_clk3[3][(18-3*type_id):0], new_cnt_clk3[(type_id+3):0], cnt_list_clk3[1][(type_id+2):0],cnt_list_clk3[2][(type_id+1):0]}, {fp_list_clk3[3], fp_list_clk3[0], fp_list_clk3[1], fp_list_clk3[2]}, bucket_clk3[3:0] }; \
      {3'd0, 3'd3}: bucket_new_insert_local_adjust = { {new_cnt_clk3[(18-3*type_id):0], cnt_list_clk3[2][(type_id+3):0], cnt_list_clk3[1][(type_id+2):0],cnt_list_clk3[3][(type_id+1):0]}, {fp_list_clk3[0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[3]}, bucket_clk3[3:0] }; \
      {3'd1, 3'd2}: bucket_new_insert_local_adjust = { {cnt_list_clk3[3][(18-3*type_id):0], new_cnt_clk3[(type_id+3):0], cnt_list_clk3[2][(type_id+2):0],cnt_list_clk3[0][(type_id+1):0]}, {fp_list_clk3[3], fp_list_clk3[1], fp_list_clk3[2], fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      {3'd1, 3'd3}: bucket_new_insert_local_adjust = { {new_cnt_clk3[(18-3*type_id):0], cnt_list_clk3[2][(type_id+3):0], cnt_list_clk3[3][(type_id+2):0],cnt_list_clk3[0][(type_id+1):0]}, {fp_list_clk3[1], fp_list_clk3[2], fp_list_clk3[3], fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      {3'd2, 3'd3}: bucket_new_insert_local_adjust = { {new_cnt_clk3[(18-3*type_id):0], cnt_list_clk3[3][(type_id+3):0], cnt_list_clk3[1][(type_id+2):0],cnt_list_clk3[0][(type_id+1):0]}, {fp_list_clk3[2], fp_list_clk3[3], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      default: bucket_new_insert_local_adjust = 0; \
      endcase end

      `CASE_FOUR(4'd1)
      `CASE_FOUR(4'd2)
      `CASE_FOUR(4'd3)

      `define CASE_THREE(type_id) type_id: begin \
      case({match_pos_clk3, local_sw_pos_clk3}) \
      {3'd0, 3'd1}: bucket_new_insert_local_adjust = { {cnt_list_clk3[2][34-2*(type_id):0], new_cnt_clk3[type_id:0], cnt_list_clk3[1][type_id-1:0]}, {fp_list_clk3[2], fp_list_clk3[0], fp_list_clk3[1]}, bucket_clk3[3:0] }; \
      {3'd0, 3'd2}: bucket_new_insert_local_adjust = { {new_cnt_clk3[34-2*(type_id):0], cnt_list_clk3[1][type_id:0],cnt_list_clk3[2][type_id-1:0]}, {fp_list_clk3[0], fp_list_clk3[1], fp_list_clk3[2]}, bucket_clk3[3:0] }; \
      {3'd1, 3'd2}: bucket_new_insert_local_adjust = { {new_cnt_clk3[34-2*(type_id):0], cnt_list_clk3[2][type_id:0],cnt_list_clk3[0][type_id-1:0]}, {fp_list_clk3[1], fp_list_clk3[2], fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      default: bucket_new_insert_local_adjust = 0; \
      endcase end

      `CASE_THREE(4'd4)
      `CASE_THREE(4'd5)
      `CASE_THREE(4'd6)
      `CASE_THREE(4'd7)
      `CASE_THREE(4'd8)
      `CASE_THREE(4'd9)
      `CASE_THREE(4'd10)
      `CASE_THREE(4'd11)
      default: begin
        bucket_new_insert_local_adjust = 0;
      end
    endcase
  end
end


// new bucket for overflow after state transfer
reg type_change;
reg has_kickout;
reg [FP_ADDR_LEN-1:0] kickout_fp;
reg [MAX_COUNTER_LEN-1:0] kickout_count;
reg [BUCKET_LEN-1:0] bucket_new_insert_type_adjust;
always @(*) begin
  case(bucket_clk3[3:0])
      4'd0: begin
        kickout_fp = fp_list_clk3[0]; kickout_count = cnt_list_clk3[0]; has_kickout = 1;
        case(match_pos_clk3)
            3'd4: begin
               bucket_new_insert_type_adjust = {new_cnt_clk3[15:0], cnt_list_clk3[3][4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0], fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'd1 } ;// highest location
            end
            3'd0: begin
               bucket_new_insert_type_adjust = {cnt_list_clk3[4][5:0], cnt_list_clk3[3][4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0], cnt_list_clk3[0][1:0], fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 8'd0, 4'd0 } ; // lowest location, kickout
               kickout_count = new_cnt_clk3;
            end
            3'd1: begin
               if (new_cnt_clk3[MAX_COUNTER_LEN-1:4] != 0 ) begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[4][12:0], cnt_list_clk3[3][5:0], cnt_list_clk3[2][4:0], 4'b1111, fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'd2 };
               end else begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[4][12:0], cnt_list_clk3[3][5:0], cnt_list_clk3[2][4:0], new_cnt_clk3[3:0], fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'd2 };
               end
            end
            3'd2: begin
               if (new_cnt_clk3[MAX_COUNTER_LEN-1:5] != 0 ) begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[4][12:0], cnt_list_clk3[3][5:0], 5'b11111, cnt_list_clk3[1][3:0], fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'd2 };
               end else begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[4][12:0], cnt_list_clk3[3][5:0], cnt_list_clk3[2][4:0], new_cnt_clk3[3:0], fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'd2 };
               end
            end
            default: bucket_new_insert_type_adjust = bucket_clk3;
        endcase
      end

      4'd1: begin
        case(match_pos_clk3)
          3'd3: begin
            bucket_new_insert_type_adjust = {new_cnt_clk3[26:0], cnt_list_clk3[2][4:0], cnt_list_clk3[1][3:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'b0100 };
            kickout_fp = fp_list_clk3[0]; kickout_count = cnt_list_clk3[0]; has_kickout = 1;
          end

          3'd2: begin
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
            if( cnt_list_clk3[3][15:13] == 0 ) begin
                // reduce the max count to 13bits
                if (new_cnt_clk3[MAX_COUNTER_LEN-1:6] == 0) begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], new_cnt_clk3[5:0], cnt_list_clk3[1][4:0], cnt_list_clk3[0][3:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
                end else begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], 6'b111111, cnt_list_clk3[1][4:0], cnt_list_clk3[0][3:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
                end
            end else begin
              // can not reduce the max count
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][15:0], 5'b11111, cnt_list_clk3[1][3:0], cnt_list_clk3[0][2:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd1 };
            end
          end

          3'd1: begin
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
            if( cnt_list_clk3[3][15:13] == 0 ) begin
                if (new_cnt_clk3[MAX_COUNTER_LEN-1:5] == 0) begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], cnt_list_clk3[2][5:0], new_cnt_clk3[4:0], cnt_list_clk3[0][3:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
                end else begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], cnt_list_clk3[2][5:0], 5'd31, cnt_list_clk3[0][3:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
                end
            end else begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][15:0], cnt_list_clk3[2][4:0], 4'b1111, cnt_list_clk3[0][2:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd1 };
            end
          end

          3'd0: begin
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
            if( cnt_list_clk3[3][15:13] == 0 ) begin
                if (new_cnt_clk3[MAX_COUNTER_LEN-1:4] == 0) begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], cnt_list_clk3[2][5:0], cnt_list_clk3[1][4:0], new_cnt_clk3[3:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
                end else begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], cnt_list_clk3[2][5:0], cnt_list_clk3[1][4:0], 4'd15, fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
                end
            end else begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][15:0], cnt_list_clk3[2][4:0], cnt_list_clk3[1][4:0], 3'b111, fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd1 };            
            end
          end
          
          default: begin 
            bucket_new_insert_type_adjust = bucket_clk3; 
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
          end
        endcase
      end

      4'd2: begin
        case(match_pos_clk3)
          3'd3: begin
            bucket_new_insert_type_adjust = {new_cnt_clk3[24:0], cnt_list_clk3[2][5:0], cnt_list_clk3[1][4:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'b0101};
            kickout_fp = fp_list_clk3[0];
            kickout_count = cnt_list_clk3[0];
            has_kickout = 1;
          end

          3'd2: begin
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
            if( cnt_list_clk3[3][12:10] == 0 ) begin
                if (new_cnt_clk3[MAX_COUNTER_LEN-1:7] == 0) begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][9:0], new_cnt_clk3[6:0], cnt_list_clk3[1][5:0], cnt_list_clk3[0][4:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd3 };
                end else begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][9:0], 7'b111_1111, cnt_list_clk3[1][5:0], cnt_list_clk3[0][4:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd3 };
                end
            end else begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], 6'b11_1111, cnt_list_clk3[1][4:0], cnt_list_clk3[0][3:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
            end
          end

          3'd1: begin
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
            if( cnt_list_clk3[3][12:10] == 0 ) begin
                if (new_cnt_clk3[MAX_COUNTER_LEN-1:7] == 0) begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][9:0], cnt_list_clk3[2][6:0], new_cnt_clk3[5:0], cnt_list_clk3[0][4:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd3};
                end else begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][9:0], cnt_list_clk3[2][6:0], 6'b11_1111, cnt_list_clk3[0][4:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd3};
                end
            end else begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], cnt_list_clk3[2][5:0], 5'b1_1111, cnt_list_clk3[0][3:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
            end
          end

          3'd0: begin
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
            if( cnt_list_clk3[3][12:10] == 0 ) begin
                if (new_cnt_clk3[MAX_COUNTER_LEN-1:7] == 0) begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][9:0], cnt_list_clk3[2][6:0], cnt_list_clk3[1][5:0], new_cnt_clk3[4:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd3 };
                end else begin
                  bucket_new_insert_type_adjust = {cnt_list_clk3[3][9:0], cnt_list_clk3[2][6:0], cnt_list_clk3[1][5:0], 5'b1_1111, fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd3 };
                end
            end else begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][12:0], cnt_list_clk3[2][5:0], cnt_list_clk3[1][4:0], 4'b1111, fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd2 };
            end
          end
          
          default: begin 
            bucket_new_insert_type_adjust = bucket_clk3; 
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
          end
        endcase
      end

      4'd3: begin
        case(match_pos_clk3)
          3'd3: begin
            bucket_new_insert_type_adjust = {new_cnt_clk3[22:0], cnt_list_clk3[2][6:0], cnt_list_clk3[1][5:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'b0110};
            kickout_fp = fp_list_clk3[0]; kickout_count = cnt_list_clk3[0]; has_kickout = 1;
          end

          3'd2: begin
            kickout_fp = fp_list_clk3[0]; kickout_count = cnt_list_clk3[0]; has_kickout = 1;
            if (new_cnt_clk3[MAX_COUNTER_LEN-1:8] == 0) begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][20:0], new_cnt_clk3[7:0], cnt_list_clk3[1][6:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'b0111};
            end else begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][20:0], 8'b1111_1111, cnt_list_clk3[1][6:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'b0111};
            end
          end

          3'd1: begin
            kickout_fp = fp_list_clk3[0]; kickout_count = cnt_list_clk3[0]; has_kickout = 1;
            if (new_cnt_clk3[MAX_COUNTER_LEN-1:7] == 0) begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][20:0], cnt_list_clk3[2][7:0], new_cnt_clk3[6:0], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'b0111};
            end else begin
              bucket_new_insert_type_adjust = {cnt_list_clk3[3][20:0], cnt_list_clk3[2][7:0], 7'b111_1111, fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 4'b0111};
            end
          end

          3'd0: begin
            kickout_fp = fp_list_clk3[0]; kickout_count = cnt_list_clk3[0]; has_kickout = 1;
            bucket_new_insert_type_adjust = {cnt_list_clk3[3][9:0], cnt_list_clk3[2][6:0], cnt_list_clk3[1][5:0], 5'd0, fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], 8'd0, 4'b0011};
          end
          
          default: begin 
            bucket_new_insert_type_adjust = bucket_clk3; 
            kickout_fp = 0; kickout_count = 0; has_kickout = 0;
          end
        endcase
      end

      `define SET_NEW_TYPE_3_BUCKET(type_id) type_id: begin \
      case(match_pos_clk3) \
      3'd2: begin \
        bucket_new_insert_type_adjust = { MAX_COUNTER[(34-2*type_id):0], cnt_list_clk3[1][(type_id):0], cnt_list_clk3[0][(type_id-1):0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], (type_id)}; \
        kickout_fp = 0; kickout_count = 0; has_kickout = 0; \
      end \
      3'd1: begin \
        kickout_fp = 0; kickout_count = 0; has_kickout = 0; \
        if (new_cnt_clk3[MAX_COUNTER_LEN-1: ((type_id)+2)] == 0) begin \
          bucket_new_insert_type_adjust = {cnt_list_clk3[2][(32-2*type_id):0], new_cnt_clk3[(type_id)+1:0], cnt_list_clk3[0][(type_id):0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], (type_id)+4'd1}; \
        end else begin \
          bucket_new_insert_type_adjust = {cnt_list_clk3[2][(32-2*type_id):0], MAX_COUNTER[(type_id)+1:0], cnt_list_clk3[0][(type_id):0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], (type_id)+4'd1};\
        end \
      end \
      3'd0: begin\
        kickout_fp = 0; kickout_count = 0; has_kickout = 0; \
        if (new_cnt_clk3[MAX_COUNTER_LEN-1: ((type_id)+1)] == 0) begin \
          bucket_new_insert_type_adjust = {cnt_list_clk3[2][(32-2*type_id):0], cnt_list_clk3[1][(type_id)+1:0], new_cnt_clk3[(type_id):0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], (type_id)+4'd1}; \
        end else begin \
          bucket_new_insert_type_adjust = {cnt_list_clk3[2][(32-2*type_id):0], cnt_list_clk3[1][(type_id)+1:0], MAX_COUNTER[(type_id):0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], (type_id)+4'd1}; \
        end \
      end \
      default: begin \
        bucket_new_insert_type_adjust = bucket_clk3; \
        kickout_fp = 0; kickout_count = 0; has_kickout = 0; \
      end \
      endcase \
      end

      `SET_NEW_TYPE_3_BUCKET(4'd4)
      `SET_NEW_TYPE_3_BUCKET(4'd5)
      `SET_NEW_TYPE_3_BUCKET(4'd6)
      `SET_NEW_TYPE_3_BUCKET(4'd7)
      `SET_NEW_TYPE_3_BUCKET(4'd8)
      `SET_NEW_TYPE_3_BUCKET(4'd9)
      `SET_NEW_TYPE_3_BUCKET(4'd10)

      4'd11: begin
        kickout_fp = 0; kickout_count = 0; has_kickout = 0;
        case(match_pos_clk3) 
          3'd2: bucket_new_insert_type_adjust = { MAX_COUNTER[12:0], cnt_list_clk3[1][11:0], cnt_list_clk3[0][10:0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd11}; 
          3'd1: bucket_new_insert_type_adjust = { cnt_list_clk3[2][12:0],  MAX_COUNTER[11:0], cnt_list_clk3[0][10:0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd11}; 
          3'd0: bucket_new_insert_type_adjust = {  cnt_list_clk3[2][12:0], cnt_list_clk3[1][11:0], MAX_COUNTER[10:0], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0], 4'd11}; 
          default: bucket_new_insert_type_adjust = bucket_clk3;
        endcase
      end
      
      default: begin
        bucket_new_insert_type_adjust = bucket_clk3;
        kickout_fp = 0; kickout_count = 0; has_kickout = 0;
      end
    endcase
end

// new bucket with empty value here 
reg [BUCKET_LEN-1:0] bucket_new_insert_has_empty;
always @(*) begin
  if (has_match_clk3 == 1 || has_empty_clk3 == 0) begin
    bucket_new_insert_has_empty = 0;
  end else begin
    // match:0, empty:1;
    case(bucket_clk3[3:0])
      4'd0: begin
        case(empty_pos_clk3)
          3'd4:
            bucket_new_insert_has_empty = { {new_cnt_clk3[5:0], insert_value_clk3[4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[0][1:0]}, {aim_fp_clk3, fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
          3'd3:
            bucket_new_insert_has_empty = { {cnt_list_clk3[4][5:0], insert_value_clk3[4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[4], aim_fp_clk3, fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
          3'd2:
            bucket_new_insert_has_empty = { {cnt_list_clk3[4][5:0], cnt_list_clk3[3][4:0], insert_value_clk3[3:0], cnt_list_clk3[1][2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[4], fp_list_clk3[3], aim_fp_clk3, fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
          3'd1:
            bucket_new_insert_has_empty = { {cnt_list_clk3[4][5:0], cnt_list_clk3[3][4:0], cnt_list_clk3[2][3:0], insert_value_clk3[2:0],cnt_list_clk3[0][1:0]}, {fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], aim_fp_clk3, fp_list_clk3[0]}, bucket_clk3[3:0] };
          3'd0:
            bucket_new_insert_has_empty = { {cnt_list_clk3[4][5:0], cnt_list_clk3[3][4:0], cnt_list_clk3[2][3:0], cnt_list_clk3[1][2:0],insert_value_clk3[1:0]}, {fp_list_clk3[4], fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], aim_fp_clk3}, bucket_clk3[3:0] };
          default: 
            bucket_new_insert_has_empty = bucket_clk3;
        endcase
      end

      // bucket_new_insert_local_adjust = { {cnt_list_clk3[3][15:0], cnt_list_clk3[2][4:0], cnt_list_clk3[1][3:0], cnt_list_clk3[0][2:0]}, {fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] };
      `define CASE_FOUR_HAS_EMPTY(type_id) type_id: begin \
      case(empty_pos_clk3) \
      3'd3: bucket_new_insert_has_empty = { {new_cnt_clk3[(18-3*type_id):0], cnt_list_clk3[2][(type_id+3):0], cnt_list_clk3[1][(type_id+2):0], cnt_list_clk3[0][(type_id+1):0]}, {aim_fp_clk3, fp_list_clk3[2], fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      3'd2: bucket_new_insert_has_empty = { {cnt_list_clk3[3][(18-3*type_id):0], new_cnt_clk3[(type_id+3):0], cnt_list_clk3[1][(type_id+2):0],cnt_list_clk3[0][(type_id+1):0]}, {fp_list_clk3[3], aim_fp_clk3, fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      3'd1: bucket_new_insert_has_empty = { {cnt_list_clk3[3][(18-3*type_id):0], cnt_list_clk3[2][(type_id+3):0], new_cnt_clk3[(type_id+2):0],cnt_list_clk3[0][(type_id+1):0]}, {fp_list_clk3[3], fp_list_clk3[2], aim_fp_clk3, fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      3'd0: bucket_new_insert_has_empty = { {cnt_list_clk3[3][(18-3*type_id):0], cnt_list_clk3[2][(type_id+3):0], cnt_list_clk3[1][(type_id+2):0],new_cnt_clk3[(type_id+1):0]}, {fp_list_clk3[3], fp_list_clk3[2], fp_list_clk3[1], aim_fp_clk3}, bucket_clk3[3:0] }; \
      default: bucket_new_insert_has_empty = bucket_clk3; \
      endcase end

      `CASE_FOUR_HAS_EMPTY(4'd1)
      `CASE_FOUR_HAS_EMPTY(4'd2)
      `CASE_FOUR_HAS_EMPTY(4'd3)

      `define CASE_THREE_HAS_EMPTY(type_id) type_id: begin \
      case(empty_pos_clk3) \
      3'd2: bucket_new_insert_has_empty = { {new_cnt_clk3[34-2*(type_id):0], cnt_list_clk3[1][type_id:0], cnt_list_clk3[0][type_id-1:0]}, {aim_fp_clk3, fp_list_clk3[1], fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      3'd1: bucket_new_insert_has_empty = { {cnt_list_clk3[2][34-2*(type_id):0], new_cnt_clk3[type_id:0],cnt_list_clk3[0][type_id-1:0]}, {fp_list_clk3[2], aim_fp_clk3, fp_list_clk3[0]}, bucket_clk3[3:0] }; \
      3'd0: bucket_new_insert_has_empty = { {cnt_list_clk3[2][34-2*(type_id):0], cnt_list_clk3[1][type_id:0], new_cnt_clk3[type_id-1:0]}, {fp_list_clk3[2], fp_list_clk3[1], aim_fp_clk3}, bucket_clk3[3:0] }; \
      default: bucket_new_insert_has_empty = bucket_clk3; \
      endcase end

      `CASE_THREE_HAS_EMPTY(4'd4)
      `CASE_THREE_HAS_EMPTY(4'd5)
      `CASE_THREE_HAS_EMPTY(4'd6)
      `CASE_THREE_HAS_EMPTY(4'd7)
      `CASE_THREE_HAS_EMPTY(4'd8)
      `CASE_THREE_HAS_EMPTY(4'd9)
      `CASE_THREE_HAS_EMPTY(4'd10)
      `CASE_THREE_HAS_EMPTY(4'd11)
      default: begin
        bucket_new_insert_has_empty = bucket_clk3;
      end
    endcase
  end
end

always @(posedge clk) begin
  if (valid_clk3 & rst_n) begin
    insert_fp <= aim_fp_clk3; // output original fp
    if ( op_clk3 == OP_INSERT && ~has_match_clk3 && first_table_en_clk3 ) begin
        insert_success_out <= 1'b1; // first table without match
        insert_write_ram_en <= 1'b0;
        insert_need_next_op_out <= 1'b1;
        insert_bucket_out <= bucket_clk3;
        insert_cmd_out <= cmd_clk3;
        insert_table_has_empty <= has_empty_clk3;
    end else if ( op_clk3 == OP_INSERT && has_match_clk3 && !new_cnt_overflow_clk3) begin
        insert_success_out <= 1'b1; // match and no overflow
        insert_write_ram_en <= 1'b1;
        insert_need_next_op_out <= 1'b0;
        insert_table_has_empty <= has_empty_clk3;
        insert_cmd_out <= cmd_clk3;
        insert_bucket_out <= bucket_new_insert_no_overflow;
    end else if ( op_clk3 == OP_INSERT && has_match_clk3 && local_sw_en_clk3 ) begin
        insert_success_out <= 1'b1; // match and exchange with others locally
        insert_write_ram_en <= 1'b1;
        insert_need_next_op_out <= 1'b0;
        insert_table_has_empty <= has_empty_clk3;
        insert_cmd_out <= cmd_clk3;
        insert_bucket_out <= bucket_new_insert_local_adjust;
    end else if ( op_clk3 == OP_INSERT && has_match_clk3 ) begin
        insert_success_out <= 1'b1; // match and fail for the local exchange
        insert_write_ram_en <= 1'b1;
        insert_table_has_empty <= has_empty_clk3;
        if (has_kickout && kickout_fp != 0) begin        
            insert_cmd_out <= {OP_REINSERT, h1_addr_clk3, kickout_fp, kickout_count[VALUE_LEN-1:0], record_loc_clk3};
            insert_need_next_op_out <= 1'b1;
        end else begin
            insert_cmd_out <= cmd_clk3;
            insert_need_next_op_out <= 1'b0;
        end
        insert_bucket_out <= bucket_new_insert_type_adjust;
    end else if ( (op_clk3 == OP_INSERT && ~has_match_clk3 && has_empty_clk3 && ~first_table_en_clk3) || (op_clk3 == OP_REINSERT && ~has_match_clk3 && has_empty_clk3) )begin
        insert_success_out <= 1'b1;
        insert_write_ram_en <= 1'b1;
        insert_need_next_op_out <= 1'b0;
        insert_table_has_empty <= has_empty_clk3;
        insert_cmd_out <= cmd_clk3;
        insert_bucket_out <= bucket_new_insert_has_empty;
    end else begin
        insert_success_out <= 1'b0;
        insert_write_ram_en <= 1'b0;
        insert_need_next_op_out <= 1'b1;
        insert_bucket_out <= 0;
        insert_cmd_out <= cmd_clk3;
        insert_table_has_empty <= has_empty_clk3;
    end
  end else begin
        insert_success_out <= 1'b0;
        insert_write_ram_en <= 1'b0;
        insert_need_next_op_out <= 1'b0;
        insert_bucket_out <= 0;
        insert_cmd_out <= 0;
        insert_table_has_empty <= has_empty_clk3;
        insert_fp <= 0;
  end
end
    
endmodule