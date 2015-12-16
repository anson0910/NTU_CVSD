module EXP(clk, reset, datain, input_valid, dataout, output_valid, busy, finish);
input           clk;
input           reset;
input   [1:0]   datain;
input           input_valid;
output  [9:0]   dataout;
output          output_valid;
output          busy;
output			finish;

parameter IDLE = 2'd0;
parameter CAL = 2'd1;
parameter OUT = 2'd2;
parameter DONE = 2'd3;

reg [1:0] x;
reg [9:0] exp_x, nxt_exp_x;  // result of calculation (dataout)
reg [1:0] state, nxt_state;
reg [3:0] counter, nxt_counter;	// used to calculate factorial
reg [14:0] x_power,nxt_x_power;
reg [18:0] factorial,nxt_factorial;
reg [9:0] dataout;
reg output_valid,busy,finish;


always @(posedge clk or posedge reset) begin
	if (reset) begin
		x <= 2'd0;
		exp_x <= 10'd0;
		state <= 2'd0;
		counter <= 1'b0;
		x_power <= 15'd1;
		factorial <= 19'd1;
	end
	else begin
		if (input_valid)
			x <= datain;
		else
			x <= x;
		exp_x <= nxt_exp_x;
		state <= nxt_state;
		counter <= nxt_counter;
		x_power <= nxt_x_power;
		factorial <= nxt_factorial;
	end
end

always @(*) begin // FSM, nxt_counter
	case (state)
	IDLE: begin
		if (input_valid)
			nxt_state = CAL;
		else
			nxt_state = IDLE;
		nxt_counter = 4'd0;
	end
	CAL: begin
		nxt_state = OUT;
		nxt_counter = counter;
	end
	OUT: begin
		if (counter==4'd9)
			nxt_state = DONE;
		else
			nxt_state = CAL;
		nxt_counter = counter+1;
	end
	DONE: begin
		nxt_state = IDLE;
		nxt_counter = 4'd0;
	end
	endcase
end

always @(*) begin // nxt_exp_x, nxt_x_power, nxt_factorial
	if (state==CAL) begin
		nxt_x_power = x_power*x;
		nxt_factorial = factorial*(counter+1);
		nxt_exp_x = (exp_x + ((x_power*32)/factorial));
	end
	else if (state==DONE) begin
		nxt_x_power = 15'd1;
		nxt_factorial = 19'd1;
		nxt_exp_x = 10'd0;
	end
	else begin
		nxt_x_power = x_power;
		nxt_factorial = factorial;
		nxt_exp_x = exp_x;
	end
end

always @(*) begin // dataout, output_valid
	if (state==OUT) begin
		dataout = exp_x;
		output_valid = 1'b1;
	end
	else begin
		dataout = 10'd0;
		output_valid = 1'b0;
	end
end

always @(*) begin // busy, finish
	if (state==IDLE)
		busy = 1'b0;
	else
		busy = 1'b1;
end

always @(*) begin //  finish
	if (state==DONE)
		finish = 1'b1;
	else
		finish = 1'b0;
end

endmodule
