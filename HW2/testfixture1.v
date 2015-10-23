`timescale 1ns/10ps
`define CYCLE      10           	  // Modify your clock period here
`define End_CYCLE  1000000               // Modify cycle times once your design need more cycle times!
`define PAT        "./pattern1.dat"    
`define EXP        "./golden1.dat"     

module test_conv;

parameter N_DATAOUT   = 15*5; 
parameter N_DATAIN   = 16*5; 

reg   clk ;
reg   reset ;
reg   in_en;
reg   [3:0]   Din;
wire  busy;
wire  out_valid;
wire  [7:0]   Dout;
reg   [3:0]   pat_mem   [0:N_DATAIN-1];
reg   [7:0]   gol_mem   [0:N_DATAOUT-1];
reg   [7:0]   out_temp;

reg           stop;
integer       i, out_f, err, pass, exp_num, times;
reg           over;

   CONV CONV( .clk(clk), .reset(reset), .Din(Din), .in_en(in_en), .busy(busy), .out_valid(out_valid), .Dout(Dout));         
   


initial	$readmemh (`PAT, pat_mem);
initial	$readmemh (`EXP, gol_mem);


initial begin
#0;
   clk         = 1'b0;
   reset       = 1'b0;
   in_en       = 1'b0;   
   Din         = 'hz;
   stop        = 1'b0;  
   over        = 1'b0;
   exp_num     = 0;
   err         = 0;
   pass        = 0;
   times       = 1;            
end

always begin #(`CYCLE/2) clk = ~clk; end

initial begin
$dumpfile("CONV.vcd");
$dumpvars;
//$fsdbDumpfile("CONV.fsdb");
//$fsdbDumpvars;

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
    while (i <= N_DATAIN) begin               
      if(!busy) begin
         Din = pat_mem[i];
         in_en = 1'b1;
         i=i+1;
      end 
      else begin
         Din = 'hz; in_en = 1'b0;
      end                    
      @(negedge clk); 
    end     
    in_en = 0; Din='hz;
end

always @(posedge clk)begin
   out_temp = gol_mem[exp_num];
   if(out_valid)begin
      $fdisplay(out_f,"%2h", Dout);      
      if(Dout !== out_temp) begin
         $display("ERROR at %5d:output %2h !=expect %2h " ,exp_num, Dout, out_temp);
         err = err + 1 ;  
      end            
      else begin      
         pass = pass + 1 ;
      end      
      #1 exp_num = exp_num + 1;
   end     
   if(exp_num === N_DATAOUT)  over = 1'b1;   
end

always @(exp_num)begin  
  if(exp_num === 15 && err === 0)begin  
	  $display("-----------------------------------------------------\n");
      $display("Convolution of (Rectangular,Rectangular) are correct!\n");
	  $display("-----------------------------------------------------\n");
  end
  else if(exp_num === 30 && err === 0)begin  
	  $display("----------------------------------------------------\n");
	  $display("Convolution of (Rectangular,Upper Wave) are correct!\n");
	  $display("----------------------------------------------------\n");
  end
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
            $display("Congratulations! All data have been generated successfully!\n");
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









