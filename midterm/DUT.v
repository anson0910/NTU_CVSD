module DUT (clock, reset, start, in, ready, out);
	input clock, reset, start;
	input [7:0] in;
	output ready;
	output [17:0] out;
	
	reg			ready, ready_n;
	reg [17:0]  out, out_n;
	reg signed [17:0]  outData1 [0:3];
	reg signed [17:0]  outData1_n [0:3];
	reg [3:0]	outputCount, outputCount_n;

	reg signed [7:0]	inData1 [0:11];
	reg signed [7:0]	inData1_n [0:11];
	reg signed [7:0]	inData2 [0:11];
    reg signed [7:0]	inData2_n [0:11];
	reg [4:0]	inputCount, inputCount_n;

	reg			readyToOutput, readyToOutput_n;
	reg         readyToCalc, readyToCalc_n;

	reg [3:0]	state, state_n;

	integer i;
	parameter idle = 4'd0, input_data = 4'd1, output_data_1 = 4'd2, calc_data = 4'd3,
				output_data_2 = 4'd4;

	always @ (posedge clock or posedge reset)	begin
		if (reset)	begin
			ready <= 0;
			out <= 0;
			for (i=0;i<4;i=i+1)	begin
				outData1[i] <= 0;
			end
			for (i=0;i<12;i=i+1)	begin
				inData1[i] <= 0;
            	inData2[i] <= 0;
            end
			outputCount <= 0;
			inputCount <= 0;
			readyToOutput <= 0;
			readyToCalc <= 0;
			state <= idle;

		end

		else	begin
			ready <= ready_n;
            out <= out_n;
            for (i=0;i<4;i=i+1)	begin
            	outData1[i] <= outData1_n[i];
            end
            for (i=0;i<12;i=i+1)	begin
            	inData1[i] <= inData1_n[i];
            	inData2[i] <= inData2_n[i];
            end
            outputCount <= outputCount_n;
            inputCount <= inputCount_n;
            readyToOutput <= readyToOutput_n;
			readyToCalc <= readyToCalc_n;
            state <= state_n;
		end
	end

	always @ (*)	begin
		case (state)	
			idle:
				state_n = input_data;
			input_data:
				state_n = (readyToOutput) ? output_data_1 : input_data;
			output_data_1:
				state_n = (readyToCalc) ? calc_data : output_data_1;
			calc_data:
				state_n = (readyToOutput) ? output_data_2 : calc_data;
			output_data_2:
				state_n = (readyToCalc) ? idle : output_data_2;
			default:
				state_n = state;
		endcase
	end

	always @ (*)	begin
		case (state)	
			idle:	begin
				ready_n = 0;
				out_n = 0;
				for (i=0;i<4;i=i+1)	begin
					outData1_n[i] = outData1[i];
				end
				outputCount_n = 0;
				for (i=0;i<12;i=i+1)	begin
					inData1_n[i] = inData1[i];
					inData2_n[i] = inData2[i];
				end
				inputCount_n = 0;
				readyToOutput_n = 0;
				readyToCalc_n = 0;
				
			end

			input_data:	begin
				ready_n = 0;
                out_n = 0;
				outData1_n[0] = inData1[0]*inData1[9] + inData1[1]*inData1[10] + inData1[2]*inData1[11];
                outData1_n[1] = inData1[3]*inData1[9] + inData1[4]*inData1[10] + inData1[5]*inData1[11];
				outData1_n[2] = inData1[6]*inData1[9] + inData1[7]*inData1[10] + inData1[8]*inData1[11];

				if ((outData1[0] < outData1[1] && outData1[0] > outData1[2]) ||
					(outData1[0] > outData1[1] && outData1[0] < outData1[2]))
					outData1_n[3] = outData1[0];
				else if ((outData1[1] < outData1[0] && outData1[1] > outData1[2]) ||
                         (outData1[1] > outData1[0] && outData1[1] < outData1[2]))
                         outData1_n[3] = outData1[1];
				else
					outData1_n[3] = outData1[2];
				
				outputCount_n = 0;
                for (i=0;i<12;i=i+1)	begin
                	inData1_n[i] = inData1[i];
                	inData2_n[i] = inData2[i];
                end
				if (inputCount < 12)
					inData1_n[inputCount] = in;
				else if (inputCount < 24)
					inData2_n[inputCount - 12] = in;

                inputCount_n = (start) ? inputCount + 1 : inputCount;
                readyToOutput_n = (inputCount > 23) ? 1 : 0;
                readyToCalc_n = 0;

			end
			
			output_data_1:	begin
				ready_n = (outputCount < 4) ? 1 : 0;
                out_n = outData1[outputCount];
                for (i=0;i<4;i=i+1)	begin
                	outData1_n[i] = outData1[i];
                end
                outputCount_n = outputCount + 1;
                for (i=0;i<12;i=i+1)	begin
                	inData1_n[i] = inData1[i];
                	inData2_n[i] = inData2[i];
                end
                inputCount_n = 0;
                readyToOutput_n = 0;
                readyToCalc_n = (outputCount > 3) ? 1 : 0;

			end
			
			calc_data:	begin
				ready_n = 0;
                out_n = 0;
                outData1_n[0] = inData2[0]*inData2[9] + inData2[1]*inData2[10] + inData2[2]*inData2[11];
                outData1_n[1] = inData2[3]*inData2[9] + inData2[4]*inData2[10] + inData2[5]*inData2[11];
                outData1_n[2] = inData2[6]*inData2[9] + inData2[7]*inData2[10] + inData2[8]*inData2[11];
                if ((outData1[0] < outData1[1] && outData1[0] > outData1[2]) ||
                	(outData1[0] > outData1[1] && outData1[0] < outData1[2]))
                	outData1_n[3] = outData1[0];
                else if ((outData1[1] < outData1[0] && outData1[1] > outData1[2]) ||
                         (outData1[1] > outData1[0] && outData1[1] < outData1[2]))
                         outData1_n[3] = outData1[1];
                else
                	outData1_n[3] = outData1[2];
                outputCount_n = 0;
                for (i=0;i<12;i=i+1)	begin
                	inData1_n[i] = inData1[i];
                	inData2_n[i] = inData2[i];
                end
                inputCount_n = 0;
                readyToOutput_n = 1;
                readyToCalc_n = 0;
			end
			output_data_2:	begin
				ready_n = (outputCount < 4) ? 1 : 0;
                out_n = outData1[outputCount];
                for (i=0;i<4;i=i+1)	begin
                	outData1_n[i] = outData1[i];
                end
                outputCount_n = outputCount + 1;
                for (i=0;i<12;i=i+1)	begin
                	inData1_n[i] = inData1[i];
                	inData2_n[i] = inData2[i];
                end
                inputCount_n = 0;
                readyToOutput_n = 0;
                readyToCalc_n = (outputCount > 3) ? 1 : 0;


			end
			default:	begin
				ready_n = ready;	
                out_n = out;
                for (i=0;i<4;i=i+1)	begin
                	outData1_n[i] = outData1[i];
                end
                outputCount_n = outputCount;
                for (i=0;i<12;i=i+1)	begin
                	inData1_n[i] = inData1[i];
                	inData2_n[i] = inData2[i];
                end
                inputCount_n = inputCount;
                readyToOutput_n = readyToOutput;
                readyToCalc_n = readyToCalc;





			end



		endcase


	end





	

	
	
	
	



endmodule
