module CONV ( clk, reset, Din, in_en, busy, out_valid, Dout);
input   clk;
input   reset;
input   in_en;
output  busy;
output  out_valid;
input   [3:0]  Din;
output  [7:0]  Dout;

// ==============================================================
`define  INPUT_LENGTH 8
`define  OUTPUT_LENGTH 15

parameter  idle = 3'd0, input_data = 3'd1, calculate = 3'd2, output_data = 3'd3;

integer i;

reg		  busy, busy_n;
reg		  out_valid, out_valid_n;
reg [7:0] Dout, Dout_n;
reg [3:0] f [0:`INPUT_LENGTH - 1];		// buffers for input data
reg [3:0] f_n [0:`INPUT_LENGTH - 1];
reg [3:0] g [0:`INPUT_LENGTH - 1];
reg [3:0] g_n [0:`INPUT_LENGTH - 1];
reg [7:0] result [0:`OUTPUT_LENGTH - 1];
reg [7:0] result_n [0:`OUTPUT_LENGTH - 1];
reg [4:0] input_count, input_count_n, output_count, output_count_n;

reg [2:0] state, state_n;

reg       ready_to_input, ready_to_input_n;
reg       ready_to_output, ready_to_output_n;

// ========= for debugging =========
wire [7:0]  result_0 = result[0];
wire [7:0]  result_1 = result[1];
wire [7:0]  result_2 = result[2];
wire [7:0]  result_3 = result[3];
wire [7:0]  result_4 = result[4];
wire [7:0]  result_5 = result[5];
wire [7:0]  result_6 = result[6];
wire [7:0]  result_7 = result[7];
wire [7:0]  result_8 = result[8];
wire [7:0]  result_9 = result[9];
wire [7:0]  result_10 = result[10];
wire [7:0]  result_11 = result[11];
wire [7:0]  result_12 = result[12];
wire [7:0]  result_13 = result[13];
wire [7:0]  result_14 = result[14];

wire [3:0]  f_0 = f[0];
wire [3:0]  f_1 = f[1];
wire [3:0]  f_2 = f[2];
wire [3:0]  f_3 = f[3];
wire [3:0]  f_4 = f[4];
wire [3:0]  f_5 = f[5];
wire [3:0]  f_6 = f[6];
wire [3:0]  f_7 = f[7];

wire [3:0]  g_0 = g[0];
wire [3:0]  g_1 = g[1];
wire [3:0]  g_2 = g[2];
wire [3:0]  g_3 = g[3];
wire [3:0]  g_4 = g[4];
wire [3:0]  g_5 = g[5];
wire [3:0]  g_6 = g[6];
wire [3:0]  g_7 = g[7];


// =========== CS ===========
always @ ( posedge clk or posedge reset) begin
	if ( reset ) begin
		busy <= 1;
		out_valid <= 0;
		Dout <= 0;
		for (i = 0; i < `INPUT_LENGTH; i = i + 1) begin
			f[i] <= 0;		
			g[i] <= 0;
		end
		
		for (i = 0; i < `OUTPUT_LENGTH; i = i + 1) begin
			result[i] <= 0;
		end
		input_count <= 0;
		output_count <= 0;
		state <= idle;
		ready_to_input <= 0;
		ready_to_output <= 0;
	end
	else	begin
		busy <= busy_n;
		out_valid <= out_valid_n;
		Dout <= Dout_n;
        for (i = 0; i < `INPUT_LENGTH; i = i + 1) begin
            f[i] <= f_n[i];
            g[i] <= g_n[i];
        end

        for (i = 0; i < `OUTPUT_LENGTH; i = i + 1) begin
            result[i] <= result_n[i];
        end
		
		input_count <= input_count_n;
		output_count <= output_count_n;			
        state <= state_n;
		ready_to_input <= ready_to_input_n;
		ready_to_output <= ready_to_output_n;
	end
end

// ========== NS ===========
always @ (*)	begin
	case ( state )
		idle: state_n = ready_to_input ? input_data : idle;
		input_data:	state_n = ( input_count == 15 ) ? calculate : input_data;
		calculate: state_n = ready_to_output ? output_data : calculate;
		output_data: state_n = ( output_count == 14 ) ? idle : output_data;
	endcase					
end

// ========= OL =============
always @ (*)	begin
	case ( state )
		idle:	begin
			busy_n = 1;
			out_valid_n = 0;
			Dout_n = 0;
			for (i = 0; i < `INPUT_LENGTH; i = i + 1) begin
				f_n[i] = 0;
	            g_n[i] = 0; 
		    end
			for (i = 0; i < `OUTPUT_LENGTH; i = i + 1) begin
				result_n[i] = 0;
			end
			input_count_n = 0;
			output_count_n = 0;
			ready_to_input_n = 1;
			ready_to_output_n = 0;
		end

		input_data:	begin
				if ( input_count < 15 )
					busy_n = 0;
				else
					busy_n = 1;
				out_valid_n = 0;                               	
				Dout_n = 0;                                    	
				for (i = 0; i < `INPUT_LENGTH; i = i + 1) begin 	
					f_n[i] = f[i];
		            g_n[i] = g[i];                         	
			    end                            
				
                if ( in_en == 1 )	begin
					if ( input_count < 8 )				
						f_n[input_count] = Din; 
					else if ( input_count < 16 )
						g_n[input_count - `INPUT_LENGTH] = Din;
					input_count_n = input_count + 1;
				end
				else
					input_count_n = 0;

				for (i = 0; i < `OUTPUT_LENGTH; i = i + 1) begin	
					result_n[i] = 0;                           	
				end                                            	
				output_count_n = 0;                            
				ready_to_input_n = 0;
				ready_to_output_n = 0;	
		end

		calculate:	begin
			busy_n = 1;
			out_valid_n = 0;
			Dout_n = 0;
			for (i = 0; i < `INPUT_LENGTH; i = i + 1) begin
				f_n[i] = f[i];
	            g_n[i] = g[i]; 
		    end
			result_n[0] = f[0] * g[0];
			result_n[1] = f[0] * g[1] + f[1] * g[0];
			result_n[2] = f[0] * g[2] + f[1] * g[1] + f[2] * g[0];
			result_n[3] = f[0] * g[3] + f[1] * g[2] + f[2] * g[1] + f[3] * g[0];
			result_n[4] = f[0] * g[4] + f[1] * g[3] + f[2] * g[2] + f[3] * g[1] + f[4] * g[0];
			result_n[5] = f[0] * g[5] + f[1] * g[4] + f[2] * g[3] + f[3] * g[2] + f[4] * g[1] + f[5] * g[0];
			result_n[6] = f[0] * g[6] + f[1] * g[5] + f[2] * g[4] + f[3] * g[3] + f[4] * g[2] + f[5] * g[1] + f[6] * g[0];
			result_n[7] = f[0] * g[7] + f[1] * g[6] + f[2] * g[5] + f[3] * g[4] + f[4] * g[3] + f[5] * g[2] + f[6] * g[1] 
						+ f[7] * g[0];
			result_n[8] = f[1] * g[7] + f[2] * g[6] + f[3] * g[5] + f[4] * g[4] + f[5] * g[3] + f[6] * g[2] + f[7] * g[1];
			result_n[9] = f[2] * g[7] + f[3] * g[6] + f[4] * g[5] + f[5] * g[4] + f[6] * g[3] + f[7] * g[2];
			result_n[10]= f[3] * g[7] + f[4] * g[6] + f[5] * g[5] + f[6] * g[4] + f[7] * g[3];
			result_n[11]= f[4] * g[7] + f[5] * g[6] + f[6] * g[5] + f[7] * g[4];
			result_n[12]= f[5] * g[7] + f[6] * g[6] + f[7] * g[5];
			result_n[13]= f[6] * g[7] + f[7] * g[6];
			result_n[14]= f[7] * g[7];
					
			input_count_n = 0;
			output_count_n = 0;
			ready_to_input_n = 0;
			ready_to_output_n = 1;
		end

		output_data:	begin
				busy_n = 1;	
    			//out_valid_n = ( output_count == 16 ) ? 0 : 1;
				out_valid_n = ( output_count < 15 ) ? 1 : 0;
    			Dout_n = result[output_count];
    			for (i = 0; i < `INPUT_LENGTH; i = i + 1) begin
    				f_n[i] = f[i];
    	            g_n[i] = g[i]; 
    		    end
    			for (i = 0; i < `OUTPUT_LENGTH; i = i + 1) begin
    				result_n[i] = result[i];
    			end
    			input_count_n = 0;
    			output_count_n = output_count + 1;
				ready_to_input_n = 0;
				ready_to_output_n = 0;
		end
	endcase
end

endmodule








