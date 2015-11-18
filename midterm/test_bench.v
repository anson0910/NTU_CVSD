`timescale 1ns/10ps
`define CYCLE 10 					// Modify your clock period here
`define SDFFILE "./DUT_syn.sdf"		// Modify your sdf file name
`define DATA "./datain.dat"
`define EXPECT "./golden.dat"

module test;
	parameter DATA_N_PAT = 24;
	parameter ANS_N_PAT = 8;
	parameter t_reset = `CYCLE*2;

	reg clock;
	reg reset;
	reg start;
	reg	[7:0] in;
	wire ready;
	wire [17:0] out;

	reg [7:0] data_mem [0:DATA_N_PAT-1];
	reg [17:0] ans_mem [0:ANS_N_PAT-1];
	reg [17:0] out_tmp;

	integer i, vec_err_num, med_err_num, pass_num, pat_num;
	integer n;
	reg over;

		DUT DUT(.clock(clock), .reset(reset), .start(start), .in(in), 
					.ready(ready), .out(out));

	`ifdef SDF
		initial $sdf_annotate(`SDFFILE, DUT);
	`endif

	initial begin
		$dumpfile("DUT.vcd");
		$dumpvars;
		$fsdbDumpfile("DUT.fsdb");
		$fsdbDumpvars(0, test, "+mda");

	end

	initial $readmemh (`DATA, data_mem);
	initial $readmemh (`EXPECT, ans_mem);

	initial begin
		clock 		= 1'b0;
		reset       = 1'b0;
		start       = 1'b0;
		over  		= 1'b0;

		vec_err_num = 0;
		med_err_num = 0;
		pass_num    = 0;
		pat_num     = 0;
		n           = 0;
	end

	always begin #(`CYCLE/2) clock = ~clock; end

	initial begin
		@(negedge clock)  reset = 1'b1;
  		#t_reset        reset = 1'b0;

		@(negedge clock) i = 0;

		while (i <= DATA_N_PAT) begin
			@(negedge clock) 
			start = 1'b1;
			in = data_mem[i];
			i = i+1;			
		end

		#1 start = 1'b0;
	end

	always @(negedge clock) begin
		out_tmp = ans_mem[pat_num];

		
		if(ready == 1'b1) begin
			if (n < 3) begin
				if (out !== out_tmp) begin
        			$display("Data %d: ERROR at Y %d :output %h != expect %h ", (pat_num/4)+1, n, out, out_tmp);
        			vec_err_num = vec_err_num + 1;
				end
				else begin
					pass_num = pass_num + 1;
				end
				n = n + 1;
			end
			else begin
				if (out !== out_tmp) begin
        			$display("Data %d: ERROR at Y median :output %h != expect %h ", (pat_num/4)+1, out, out_tmp);
        			med_err_num = med_err_num + 1;
				end
				else begin
					pass_num = pass_num + 1;
				end
				n = 0;
			end

			pat_num = pat_num + 1;
		end

		#1 if (pat_num === ANS_N_PAT) over = 1'b1; // tricks for only one time check
		
	end

	initial begin
		@(posedge over)
		if (pass_num === ANS_N_PAT) begin
			$display("-----------------------------------------------------------\n");
			$display("Congratulations! All data have been generated successfully!\n");
			$display("-------------------------PASS------------------------------\n");
		end
		else begin
            $display("-----------------------------------------------------------\n");
            $display("            There are %d errors for Y value!\n", vec_err_num);
            $display("            There are %d errors for Y median value!\n", med_err_num);
            $display("-----------------------------------------------------------\n");
      	end
      	$finish;
	end

	initial begin
	  #(`CYCLE*5000);
	      $display("---------------------WARRNING------------------------\n");
	      $display("Simulation STOP! Maybe your circuit has some problem!\n");
	      $display("Please check your ciruit again ...                   \n");
	      $display("-----------------------------------------------------\n");
	      $finish;
	end
endmodule

// "`"-> system instruction
// 1'b0 means reminding treat it as an reg (signal)
// int variable usually control the mem arr addr
