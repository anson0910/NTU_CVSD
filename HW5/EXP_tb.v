`timescale 1ns/10ps
`define CYCLE      10           	  
`define End_CYCLE  10000               
`define GOLD        "./golden.dat"     

module test_exp;

parameter N_DATAOUT   = 10*4; 

reg       clk;
reg       reset;
reg       input_valid;
reg [1:0] datain;
wire  busy;
wire  output_valid;
wire  finish;
wire  [9:0]   dataout;
reg   [9:0]   gol_mem   [0:N_DATAOUT-1];
reg   [9:0]   out_temp;

reg           stop;
integer       i, out_f, err, pass, exp_num, x, k;
reg           over;

   EXP EXP(clk, reset, datain, input_valid, dataout, output_valid, busy, finish);

initial	$readmemb (`GOLD, gol_mem);


initial begin
#0;
   clk         = 1'b0;
   reset       = 1'b0;
   input_valid = 1'b0;
   datain      = 'hz;

   err         = 0;
   pass        = 0;
   exp_num     = 0;
   x           = 0;            
   k           = 0;
   stop        = 1'b0; 
   over        = 1'b0;
end

always begin #(`CYCLE/2) clk = ~clk; end

initial begin
//$dumpfile("EXP.vcd");
//$dumpvars;
$fsdbDumpfile("EXP.fsdb");
$fsdbDumpvars(0, test_exp, "+mda");

   out_f = $fopen("out.dat");
   if (out_f == 0) begin
        $display("Output file open error !");
        $finish;
   end
end


initial begin
   @(negedge clk)  reset = 1'b1;
   #`CYCLE         reset = 1'b0;
   
   #(`CYCLE*2);   
   @(negedge clk) i=0;
    while (i <= 3) begin               
      if(!busy) begin
         datain = x;
         input_valid = 1'b1;
         i=i+1;
      end 
      else begin
         datain = 'hz; input_valid = 1'b0;
      end                    
      @(negedge clk); 
    end     
    input_valid = 0; datain ='hz;
end

always @(posedge clk)begin
   out_temp = gol_mem[exp_num];
   if(output_valid)begin
      $fdisplay(out_f,"%b", dataout);
      if(k == 0) begin
         $display("-----------------------------------------------------\n");
         $display("                    x = %d                           \n", x);
         $display("-----------------------------------------------------\n");
      end
      else if (k == 4) begin
         x = x + 1;
      end      
      if(dataout !== out_temp) begin
         $display("ERROR at k = %2d:output %b !=expect %b " , k, dataout, out_temp);
         err = err + 1 ;  
      end            
      else begin     
	 $display("Pass ! k =  %2d ; Dataout = %b ; ANS = %b " , k, dataout, out_temp); 
         pass = pass + 1 ;
      end      
      #1 exp_num = exp_num + 1;
      #1 k = (k + 1) % 10;
   end     
   if(exp_num === N_DATAOUT)  over = 1'b1;   
end

        
initial  begin
 #(`CYCLE * `End_CYCLE);
   
 $display("-----------------------------------------------------\n");
 $display("Error!!! Somethings' wrong with your code ...!\n");
 $display("-------------------------FAIL------------------------\n");
 $display("-----------------------------------------------------\n");
 
 $finish;
end

initial begin
      @(posedge over)      
      if((over) && (exp_num!='d0)) begin
         $display("------------------------------------------------------------\n");
         if (err == 0)  begin
            $display("Congratulations!! Your design has passed all the tests!!\n");
            $display("-------------------------PASS-------------------------------\n");
         end
         else begin
            $display("There are %d errors!\n", err);
            $display("-----------------------------------------------------\n");
         end
      end
      #(`CYCLE/2); $finish;
end
   
endmodule
