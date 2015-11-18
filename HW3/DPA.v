module DPA (clk,reset,IM_A, IM_Q,IM_D,IM_WEN,CR_A,CR_Q);
input clk;
input reset;
output [19:0] IM_A;
input [23:0] IM_Q;
output [23:0] IM_D;
output IM_WEN;
output [8:0] CR_A;
input [12:0] CR_Q;

`define IMAGE_BUFFER_LENGTH 16
`define OUTPUT_BUFFER_LENGTH 18

parameter  idle = 5'd0, read_time = 5'd1, read_FB_addr = 5'd2, read_photo_num = 5'd3,
		   read_p1_addr = 5'd4, read_p1_size = 5'd5, read_p2_addr = 5'd6, read_p2_size = 5'd7,
		   read_p3_addr = 5'd8, read_p3_size = 5'd9, read_p4_addr = 5'd10, read_p4_size = 5'd11,
		   read_char_image = 5'd12, read_image_128_t = 5'd13, read_image_128_f = 5'd14,
		   read_image_256_t = 5'd15, read_image_256_f = 5'd16, read_image_512_t = 5'd17, read_image_512_f = 5'd18,
		   ready_to_input = 5'd19, output_image_256_t = 5'd20, output_image_256_f = 5'd21,
		   output_image_128_t = 5'd27, output_image_128_f = 5'd22, output_image_512_t = 5'd23, output_image_512_f = 5'd24,
		   output_time = 5'd25, wait_check = 5'd26;
			// _t means states to read/output before transfer image
		
integer i;

wire [23:0]   IM_Q;		// data read from image memory
wire [12:0]   CR_Q;		// data read from char rom

reg        IM_WEN, IM_WEN_n;	// image memory write enable signal, low to write, high to read
reg [19:0] IM_A, IM_A_n;		// image memory address
reg [23:0] IM_D, IM_D_n;		// data to write to image memory
reg [8:0]  CR_A, CR_A_n;		// char rom address

reg [23:0] sysTime, sysTime_n;	// system initial time
reg [19:0] fbAddr, fbAddr_n;		// frame buffer address
reg [2:0]  photoNum, photoNum_n;    // number of photos, should be between 1~4
reg [2:0]  photoToRead, photoToRead_n;	// next photo to read from buffer
reg [19:0] photoAddr   [1:4];
reg [19:0] photoAddr_n [1:4];
reg [9:0]  photoSize   [1:4];
reg [9:0]  photoSize_n [1:4];
reg [12:0] charImage   [0:23];		// 1 character image, representing number or colon
reg [12:0] charImage_n [0:23];
reg [19:0] elapsedCycles, elapsedCycles_n;	// cycles elapsed since last second, initialize to 0 each second
reg [6:0]  elapsedSeconds, elapsedSeconds_n;// seconds elapsed since initial time
reg        flipSignal, flipSignal_n;	// use to read from image memory since each read takes 2 cycles
reg [25:0] imageBuffer[0:`IMAGE_BUFFER_LENGTH - 1];		// read 4 pixels, then calculate and output
reg [25:0] imageBuffer_n[0:`IMAGE_BUFFER_LENGTH - 1];
reg [4:0]  imageBufferCount, imageBufferCount_n;	// keep track of which index of buffer to store
reg        firstRead, firstRead_n;		// similar use to flipSignal, but for reading photos
reg [8:0]  rowRead, rowRead_n, colRead, colRead_n;	// keep track of current rowWrite, colWrite to read
reg [8:0]  rowWrite, rowWrite_n, colWrite, colWrite_n;		// keep track of current rowWrite, colWrite to output
reg [19:0] addrToRead, addrToRead_n;	// keep track of address to read
reg [19:0] addrToWrite, addrToWrite_n;	// keep track of address to write

reg        readyToOutput, readyToOutput_n;		// ready to output after reading 4 pixels to image buffer
reg [4:0]  outputCount, outputCount_n;
reg        firstWrite, firstWrite_n;
reg        readyToInput, readyToInput_n;		// ready to input after outputting
reg        readyReadChar, readyReadChar_n;
reg [4:0]  readCharCount, readCharCount_n;		// counter for reading single char (0 ~ 23)
reg [8:0]  outputCharCount, outputCharCount_n;	//             outputting          (0 ~ 24*13 - 1)
reg [3:0]  outputTimeCount, outputTimeCount_n;	// counter for outputting 8 digits
reg [3:0]  charCol, charCol_n;					// 0 ~ 12 counter for outputting single char
reg [4:0]  charRow, charRow_n;					// 0 ~ 23
reg        readyWaitCheck, readyWaitCheck_n;	// ready signal after outputting all time digits
reg        finishTransCheck, finishTransCheck_n;// 1 when finish transfer checking
reg        finishPhotoCheck, finishPhotoCheck_n;
reg        finishTimeCheck, finishTimeCheck_n;
reg        finishMidTimeCheck, finishMidTimeCheck_n;	// finish check for 0.4 second checks
reg        preTransCheck, preTransCheck_n;		// current objective is to prepare for trans check
reg        prePhotoCheck, prePhotoCheck_n;
reg        preTimeCheck, preTimeCheck_n;
reg        preMidTimeCheck, preMidTimeCheck_n;
reg [23:0] outputBuffer[0:`OUTPUT_BUFFER_LENGTH - 1];
reg [23:0] outputBuffer_n[0:`OUTPUT_BUFFER_LENGTH - 1];


reg [4:0]  state, state_n;

wire[3:0]  timeDigits [0:7];

assign  timeDigits[0] = (sysTime[23:16] < 10) ? 0 :
						(sysTime[23:16] < 20) ? 1 : 2;
assign  timeDigits[1] = (sysTime[23:16] < 10) ? sysTime[23:16] :
                        (sysTime[23:16] < 20) ? sysTime[23:16] - 10 : sysTime[23:16] - 20;
assign  timeDigits[2] = 10;		// :
assign  timeDigits[3] = (sysTime[15:8] < 10) ? 0 :
                        (sysTime[15:8] < 20) ? 1 :
						(sysTime[15:8] < 30) ? 2 :
                        (sysTime[15:8] < 40) ? 3 :
						(sysTime[15:8] < 50) ? 4 : 5;
assign  timeDigits[4] = (sysTime[15:8] < 10) ? sysTime[15:8] :
                        (sysTime[15:8] < 20) ? sysTime[15:8] - 10 :
                        (sysTime[15:8] < 30) ? sysTime[15:8] - 20 :
                        (sysTime[15:8] < 40) ? sysTime[15:8] - 30 :
                        (sysTime[15:8] < 50) ? sysTime[15:8] - 40 : sysTime[15:8] - 50;
assign  timeDigits[5] = 10;
assign  timeDigits[6] = (sysTime[7:0] < 10) ? 0 :
                        (sysTime[7:0] < 20) ? 1 :
                        (sysTime[7:0] < 30) ? 2 :
                        (sysTime[7:0] < 40) ? 3 :
                        (sysTime[7:0] < 50) ? 4 : 5;
assign  timeDigits[7] = (sysTime[7:0] < 10) ? sysTime[7:0] :
                        (sysTime[7:0] < 20) ? sysTime[7:0] - 10 :
                        (sysTime[7:0] < 30) ? sysTime[7:0] - 20 :
                        (sysTime[7:0] < 40) ? sysTime[7:0] - 30 :
                        (sysTime[7:0] < 50) ? sysTime[7:0] - 40 : sysTime[7:0] - 50;
// =========== CS ===========
always @ ( posedge clk or posedge reset) begin
	if ( reset ) begin
		IM_WEN <= 1;
		IM_A <= 0;
		IM_D <= 0;
		CR_A <= 0;
		sysTime <= 0;
		fbAddr <= 0;
		photoNum <= 0;
		photoToRead <= 1;
		for (i= 1; i < 5; i = i + 1)  begin
			photoAddr[i] <= 0;
			photoSize[i] <= 0;
		end
		for (i= 0; i < 24; i = i + 1)  begin
        	charImage[i] <= 0;
        end
		for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
			imageBuffer[i] <= 0;
		end	
		imageBufferCount <= 0;
		for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
        	outputBuffer[i] <= 0;
        end	
		elapsedCycles <= 0;
		elapsedSeconds <= 0;
		state <= idle;
		flipSignal <= 0;
		firstRead <= 0;
		rowRead <= 0;
		colRead <= 0;
		rowWrite <= 0;
		colWrite <= 1;
		addrToRead <= 0;
		addrToWrite <= 0;
		readyToOutput <= 0;
		outputCount <= 0;
		firstWrite <= 0;
		readyToInput <= 0;
		readyReadChar <= 0;
		readCharCount <= 0;
		outputCharCount <= 0;
		outputTimeCount <= 0;
		charCol <= 0;
		charRow <= 0;
		readyWaitCheck <= 0;
		finishTransCheck <= 0;
		finishPhotoCheck <= 0;
		finishTimeCheck <= 0;
		finishMidTimeCheck <= 0;
		preTransCheck <= 0;
		prePhotoCheck <= 0;
		preTimeCheck <= 0;
		preMidTimeCheck <= 0;
	end
	else	begin
		IM_WEN <= IM_WEN_n;
		IM_A <= IM_A_n;
		IM_D <= IM_D_n;
		CR_A <= CR_A_n;
		sysTime <= sysTime_n;
		fbAddr <= fbAddr_n;
		photoNum <= photoNum_n;
		photoToRead <= photoToRead_n;
		for (i= 1; i < 5; i = i + 1)  begin
			photoAddr[i] <= photoAddr_n[i];
			photoSize[i] <= photoSize_n[i];
		end
		for (i= 0; i < 24; i = i + 1)  begin
			charImage[i] <= charImage_n[i];
        end
		for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
        	imageBuffer[i] <= imageBuffer_n[i];
        end	
        imageBufferCount <= imageBufferCount_n;
		for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
        	outputBuffer[i] <= outputBuffer_n[i];
        end	
		elapsedCycles <= elapsedCycles_n;
		elapsedSeconds <= elapsedSeconds_n;
		state <= state_n;
		flipSignal <= flipSignal_n;
		firstRead <= firstRead_n;
		rowRead <= rowRead_n;
		colRead <= colRead_n;
		rowWrite <= rowWrite_n;
		colWrite <= colWrite_n;
		addrToRead <= addrToRead_n;
		addrToWrite <= addrToWrite_n;
		readyToOutput <= readyToOutput_n;
		outputCount <= outputCount_n;
		firstWrite <= firstWrite_n;
		readyToInput <= readyToInput_n;
		readyReadChar <= readyReadChar_n;
		readCharCount <= readCharCount_n;
        outputCharCount <= outputCharCount_n;
        outputTimeCount <= outputTimeCount_n;
		charCol <= charCol_n;
		charRow <= charRow_n;
		readyWaitCheck <= readyWaitCheck_n;
		finishTransCheck <= finishTransCheck_n;
        finishPhotoCheck <= finishPhotoCheck_n;
        finishTimeCheck <= finishTimeCheck_n;
		finishMidTimeCheck <= finishMidTimeCheck_n;
        preTransCheck <= preTransCheck_n;
        prePhotoCheck <= prePhotoCheck_n;
        preTimeCheck <= preTimeCheck_n;
		preMidTimeCheck <= preMidTimeCheck_n;
	end
end

// ========== NS ===========
always @ (*)	begin
	case ( state )
		idle:	state_n = read_time;
		read_time:	state_n = flipSignal ? read_FB_addr : state;
		read_FB_addr:	state_n = flipSignal ? read_photo_num : state;
		read_photo_num:	state_n = flipSignal ? read_p1_addr : state;
		read_p1_addr:	state_n = flipSignal ? read_p1_size : state;
		read_p1_size:	begin
				if (flipSignal)
					if (photoNum > 1)
						state_n = read_p2_addr;
					else
						state_n = ready_to_input;
				else
					state_n = state;
		end
		read_p2_addr:	state_n = flipSignal ? read_p2_size : state;
		read_p2_size:	begin
				if (flipSignal)
					if (photoNum > 2)
						state_n = read_p3_addr;
					else
						state_n = ready_to_input;
				else
					state_n = state;
		end
		read_p3_addr:	state_n = flipSignal ? read_p3_size : state;
		read_p3_size:	begin
				if (flipSignal)
                	if (photoNum > 3)
                		state_n = read_p4_addr;
	            	else
                		state_n = ready_to_input;
                else
                	state_n = state;
		end	
		read_p4_addr:	state_n = flipSignal ? read_p4_size : state;	
		read_p4_size:	begin
				if (flipSignal)
                	state_n = ready_to_input;
                else
                	state_n = state;
		end
		ready_to_input:	begin
				if (photoSize[photoToRead] == 128)
					state_n = read_image_128_t;
				else if (photoSize[photoToRead] == 256)
					state_n = read_image_256_t;
				else
					state_n = read_image_512_t;					
		end
		
		read_image_128_t:	begin
        		state_n = (readyToOutput) ? output_image_128_t : read_image_128_t;
        end
        output_image_128_t:	begin
        		if (readyReadChar)
        			state_n = read_char_image;
        		else
        			state_n = (readyToInput) ? read_image_128_t : output_image_128_t;
        end

		read_image_256_t:	begin
				state_n = (readyToOutput) ? output_image_256_t : read_image_256_t;
		end
		output_image_256_t:	begin
				if (readyReadChar)
					state_n = read_char_image;
				else
					state_n = (readyToInput) ? read_image_256_t : output_image_256_t;
		end

		read_image_512_t:	begin
        		state_n = (readyToOutput) ? output_image_512_t : read_image_512_t;
        end
        output_image_512_t:	begin
        		if (readyReadChar)
        			state_n = read_char_image;
        		else
        			state_n = (readyToInput) ? read_image_512_t : output_image_512_t;
        end

		read_char_image:	begin
				if (readyWaitCheck)
					state_n = wait_check;
				else	
					state_n = (readyToOutput) ? output_time : read_char_image;
		end

		output_time:	begin
				if (readyWaitCheck)
                   	state_n = wait_check;
				else
					state_n = (readyReadChar) ? read_char_image : output_time;
		end

		wait_check:	begin
			// after trans check, next check must be photo check
			if (finishTransCheck)	begin
				if (photoSize[photoToRead] == 128)	
                	state_n = read_image_128_f;
                else if (photoSize[photoToRead] == 256)
                	state_n = read_image_256_f;
                else
					state_n = read_image_512_f;
			end
			// after photo or midtime check, next check must be time check
			else if (finishPhotoCheck || finishMidTimeCheck)	
				state_n = wait_check;	
			else if (finishTimeCheck && preMidTimeCheck)	
				state_n = read_char_image;
			else if (finishTimeCheck && preTransCheck)	
				state_n = ready_to_input;
			else
				state_n = wait_check;
		end

		read_image_128_f:	begin
        		state_n = (readyToOutput) ? output_image_128_f : read_image_128_f;
        end
        output_image_128_f:	begin
        		if (readyReadChar)
        			state_n = read_char_image;
        		else
        			state_n = (readyToInput) ? read_image_128_f : output_image_128_f;
        end

		read_image_256_f:	begin
        		state_n = (readyToOutput) ? output_image_256_f : read_image_256_f;
        end
        output_image_256_f:	begin
        		if (readyReadChar)
        			state_n = read_char_image;
        		else
        			state_n = (readyToInput) ? read_image_256_f : output_image_256_f;
        end

		read_image_512_f:	begin
        		state_n = (readyToOutput) ? output_image_512_f : read_image_512_f;
        end
        output_image_512_f:	begin
        		if (readyReadChar)
        			state_n = read_char_image;
        		else
        			state_n = (readyToInput) ? read_image_512_f : output_image_512_f;
        end

		default:
				state_n = state;
		
	endcase
end

// ========= OL =============
always @ (*)	begin
	case ( state ) //synopsys full_case
		idle:	begin
			IM_WEN_n = 1;
			IM_A_n = 0;		// address of init time
			IM_D_n = IM_D;
			CR_A_n = CR_A;
			fbAddr_n = fbAddr;
			photoNum_n = photoNum;
			photoToRead_n = photoToRead;
			for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
			for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			imageBufferCount_n = imageBufferCount;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
			sysTime_n = sysTime;
			elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = 0;
			flipSignal_n = 0;
			firstRead_n = 0;
			rowRead_n = 0;
			colRead_n = 0;
			rowWrite_n = 0;
			colWrite_n = 1;
			addrToRead_n = 0;
			addrToWrite_n = 0;
			readyToOutput_n = 0;
			outputCount_n = 0;
			firstWrite_n = 0;
			readyToInput_n = 0;
			readyReadChar_n = 0;
			readCharCount_n = 0;
			outputCharCount_n = 0;
			outputTimeCount_n = 0;
			charCol_n = 0;
			charRow_n = 0;
			readyWaitCheck_n = 0;
			finishTransCheck_n = 0;
			finishPhotoCheck_n = 0;
			finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
			preTransCheck_n = 0;
			prePhotoCheck_n = 0;
			preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
		end	// end of case idle

		read_time:	begin
			IM_WEN_n = 1;
            IM_A_n = 1;		// address of FB_addr
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = flipSignal ? sysTime : IM_Q;	// read init time
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			imageBufferCount_n = imageBufferCount;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = 0;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
		    colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			readyToOutput_n = readyToOutput;
			outputCount_n = outputCount;
			firstWrite_n = firstWrite;
			readyToInput_n = readyToInput;
			readyReadChar_n = readyReadChar;
			readCharCount_n = readCharCount;
			outputCharCount_n = outputCharCount;
			outputTimeCount_n = outputTimeCount;
			charCol_n = charCol;
			charRow_n = charRow;
			readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
		end	// end of case read_time

		read_FB_addr:	begin
			IM_WEN_n = 1;
            IM_A_n = 2;		// address of photo_num
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = flipSignal ? fbAddr : IM_Q;	// read FB_addr
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
			imageBufferCount_n = imageBufferCount;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = 0;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
			readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
		end	// end of case read_FB_addr
		
		read_photo_num:	begin
			IM_WEN_n = 1;	
            IM_A_n = 3;		// address of p1_addr
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;
            photoNum_n = flipSignal ? photoNum : IM_Q[2:0];	// read photo_num
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			imageBufferCount_n = imageBufferCount;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = 0;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = fbAddr + 1;		// first pixel to write must be 0th rowWrite 1st colWrite
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
		end

		read_p1_addr:	begin
			IM_WEN_n = 1;
            IM_A_n = 4;		// address of p1_size
            IM_D_n = IM_D;	
		    CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;	
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
			photoAddr_n[1] = flipSignal ? photoAddr[1] : IM_Q;	// read p1_addr
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end	
			imageBufferCount_n = imageBufferCount;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = 0;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;			
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
		end

		read_p1_size:	begin
			IM_WEN_n = 1;
            IM_A_n = 5;		// address of p2_addr
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
			photoSize_n[1] = flipSignal ? photoSize[1] : IM_Q[9:0];
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end	
			imageBufferCount_n = imageBufferCount;			
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
		end

		read_p2_addr:	begin
        	IM_WEN_n = 1;
            IM_A_n = 6;		// address of p2_size
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;	
            photoNum_n = photoNum;
			photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
			photoAddr_n[2] = flipSignal ? photoAddr[2] : IM_Q;
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end	
			imageBufferCount_n = imageBufferCount;			
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
        end

                                                      
        read_p2_size:	begin
        	IM_WEN_n = 1;
            IM_A_n = 7;		// address of p3_addr
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
			photoSize_n[2] = flipSignal ? photoSize[2] : IM_Q[9:0];
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			imageBufferCount_n = imageBufferCount;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
		end

		read_p3_addr:	begin
        	IM_WEN_n = 1;
            IM_A_n = 8;		// address of p3_size
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;	
            photoNum_n = photoNum;	// read photo_num
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
			photoAddr_n[3] = flipSignal ? photoAddr[3] : IM_Q;
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			imageBufferCount_n = imageBufferCount;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin	
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
        end
                                                      
        read_p3_size:	begin
        	IM_WEN_n = 1;
            IM_A_n = 9;		// address of p4_addr
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
			photoSize_n[3] = flipSignal ? photoSize[3] : IM_Q[9:0];
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			imageBufferCount_n = imageBufferCount;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
        end

		read_p4_addr:	begin
        	IM_WEN_n = 1;
            IM_A_n = 10;		// address of p4_size
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;	
            photoNum_n = photoNum;	// read photo_num
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
			photoAddr_n[4] = flipSignal ? photoAddr[4] : IM_Q;
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end	
			imageBufferCount_n = imageBufferCount;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
        end

        read_p4_size:	begin
        	IM_WEN_n = 1;
            IM_A_n = 0;
            IM_D_n = IM_D;	
            CR_A_n = CR_A;
            sysTime_n = sysTime;	
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
			end
			photoSize_n[4] = flipSignal ? photoSize[4] : IM_Q[9:0];
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end	
			imageBufferCount_n = imageBufferCount;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = ~flipSignal;
			firstRead_n = 0;
			rowRead_n = rowRead;
            colRead_n = colRead;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
            addrToRead_n = addrToRead;
            addrToWrite_n = addrToWrite;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
        end
		
		ready_to_input:	begin
        	IM_WEN_n = 1;
            IM_D_n = IM_D;
            CR_A_n = CR_A;
            sysTime_n = sysTime;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
        	for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end	
            imageBufferCount_n = imageBufferCount;
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
            flipSignal_n = 0;
			firstRead_n = 0;
			case (photoSize[photoToRead])
				10'd128:	begin						
                		IM_A_n = photoAddr[photoToRead];
                		addrToRead_n = photoAddr[photoToRead];
                		rowRead_n = 0;
                		colRead_n = 0;
                	end
				10'd256:	begin						
						IM_A_n = photoAddr[photoToRead] + 1;
						addrToRead_n = photoAddr[photoToRead] + 1;
						rowRead_n = 0;
						colRead_n = 1;
					end
				10'd512:	begin
						IM_A_n = photoAddr[photoToRead] + 2;
						addrToRead_n = photoAddr[photoToRead] + 2;
						rowRead_n = 0;
						colRead_n = 2;
					end
				default:	begin
						IM_A_n = IM_A;		
                        addrToRead_n = addrToRead;
                        rowRead_n = rowRead;
                        colRead_n = colRead;
					end
			endcase
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
            readyToOutput_n = readyToOutput;
            outputCount_n = outputCount;
            firstWrite_n = firstWrite;
            readyToInput_n = readyToInput;
            readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			rowWrite_n = 0;
			colWrite_n = 1;	
			addrToWrite_n = fbAddr + 1;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
        end

		read_image_128_t:	begin
        	IM_WEN_n = (imageBufferCount > 8) ? 0 : 1;
        	if (imageBufferCount == 1 || imageBufferCount == 4)	begin
        		colRead_n = colRead - 2;
        		rowRead_n = rowRead + 1;
        		IM_A_n = addrToRead + 126;
        		addrToRead_n = addrToRead + 126;
        	end
        	else if (imageBufferCount < 7)	begin	// firstRead actually means not first read..
        		colRead_n = colRead + 1;
        		rowRead_n = rowRead;
        		IM_A_n = addrToRead + 1;
        		addrToRead_n = addrToRead + 1;
        	end
        	else if (imageBufferCount < 8) begin
				if (colRead == 9'd126)	begin
					colRead_n = 125;
                    rowRead_n = rowRead - 2;
                    IM_A_n = addrToRead - 257;
                    addrToRead_n = addrToRead - 257;
				end
        		else if (colRead == 9'd127)     	begin
					if (rowRead == 9'd126)	begin
						colRead_n = 0;
                        rowRead_n = 125;
                        IM_A_n = addrToRead - 255;
                        addrToRead_n = addrToRead - 255;
					end
					else	begin
						colRead_n = 0;
	                	rowRead_n = rowRead;
		            	IM_A_n = addrToRead - 127;
			        	addrToRead_n = addrToRead - 127;
					end
				end
                else	begin
                	colRead_n = colRead;
                	rowRead_n = rowRead - 2;
                	IM_A_n = addrToWrite;
                	addrToRead_n = addrToRead - 256;
               	end
        	end
        	else	begin
        		colRead_n = colRead;
                rowRead_n = rowRead;
                IM_A_n = addrToWrite;
                addrToRead_n = addrToRead;
        	end

        	imageBufferCount_n = firstRead ? imageBufferCount + 1 : imageBufferCount;			
            IM_D_n = outputBuffer[0];
            CR_A_n = CR_A;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
        	for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
        	if (imageBufferCount < 9)
        		imageBuffer_n[imageBufferCount] = IM_Q;
        	// read pixel into image buffer	
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
        	elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
        	if (imageBufferCount < 9)
        		firstRead_n = 1;
        	else
        		firstRead_n = 0;
        	rowWrite_n = rowWrite;
        	colWrite_n = colWrite;
        	addrToWrite_n = addrToWrite;
        	readyToOutput_n = (imageBufferCount == 8) ? 1 : 0;
        	outputCount_n = 1;
        	firstWrite_n = 0;
        	readyToInput_n = 0;
			readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
        	finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
        	finishMidTimeCheck_n = 0;
            preTransCheck_n = 1;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
        	preMidTimeCheck_n = 0;
        	outputBuffer_n[0] = (imageBuffer[0] + imageBuffer[1]) >> 1;
        	outputBuffer_n[1] = (imageBuffer[1] + imageBuffer[2]) >> 1;
        	outputBuffer_n[2] = imageBuffer[2];
        	outputBuffer_n[3] = (imageBuffer[0] + imageBuffer[3]) >> 1;
			outputBuffer_n[4] = (imageBuffer[1] + imageBuffer[4]) >> 1;
            outputBuffer_n[5] = (imageBuffer[2] + imageBuffer[5]) >> 1;
            outputBuffer_n[6] = (imageBuffer[3] + imageBuffer[4]) >> 1;
            outputBuffer_n[7] = (imageBuffer[4] + imageBuffer[5]) >> 1;
			outputBuffer_n[8] = imageBuffer[5];
            outputBuffer_n[9] = (imageBuffer[3] + imageBuffer[6]) >> 1;
            outputBuffer_n[10] = (imageBuffer[4] + imageBuffer[7]) >> 1;
            outputBuffer_n[11] = (imageBuffer[5] + imageBuffer[8]) >> 1;
			outputBuffer_n[12] = (imageBuffer[6] + imageBuffer[7]) >> 1;
            outputBuffer_n[13] = (imageBuffer[7] + imageBuffer[8]) >> 1;
            outputBuffer_n[14] = imageBuffer[8];
            outputBuffer_n[15] = imageBuffer[6];
			outputBuffer_n[16] = imageBuffer[7];
            outputBuffer_n[17] = imageBuffer[8];
        end

        output_image_128_t:	begin
			if (outputCount == 3 || outputCount == 9 || outputCount == 15)	begin
				colWrite_n = colWrite - 5;
                rowWrite_n = rowWrite + 1;
                IM_A_n = addrToWrite + 251;
                addrToWrite_n = addrToWrite + 251;
			end
			else if (outputCount == 6 || outputCount == 12)	begin
				colWrite_n = colWrite - 3;	
                rowWrite_n = rowWrite + 1;
                IM_A_n = addrToWrite + 253;
                addrToWrite_n = addrToWrite + 253;
			end
			else if (outputCount == 18)	begin
            	if (colWrite == 252)	begin
            		colWrite_n = colWrite - 1;
                    rowWrite_n = rowWrite - 5;
                    IM_A_n = addrToWrite - 1281;
                    addrToWrite_n = addrToWrite - 1281;
            	end
            	else if (colWrite == 254)	begin
            		if (rowWrite == 253)	begin
            			colWrite_n = 1;	
                        rowWrite_n = rowWrite - 3;
                        IM_A_n = addrToWrite - 1021;
            	        addrToWrite_n = addrToWrite - 1021;
            		end
            		else	begin
            			colWrite_n = 1;	
                        rowWrite_n = rowWrite - 1;
                        IM_A_n = addrToWrite - 509;
                        addrToWrite_n = addrToWrite - 509;
            		end
            	end
            	else	begin
            		colWrite_n = colWrite + 1;
                    rowWrite_n = rowWrite - 5;
                    IM_A_n = addrToRead;
                    addrToWrite_n = addrToWrite - 1279;
            	end
            end
			else if (outputCount < 18)	begin
            	colWrite_n = colWrite + 2;
                rowWrite_n = rowWrite;
                IM_A_n = addrToWrite + 2;
                addrToWrite_n = addrToWrite + 2;
            end
			else	begin
				colWrite_n = colWrite;
                rowWrite_n = rowWrite;
                IM_A_n = addrToRead;
                addrToWrite_n = addrToWrite;
			end
						
        	outputCount_n = outputCount + 1;
            IM_D_n = outputBuffer[outputCount];
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
        	elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
            if (outputCount < 18)
            	firstWrite_n = 1;
            else
            	firstWrite_n = 0;
        	imageBufferCount_n = 0;
        	firstRead_n = 0;
        	rowRead_n = rowRead;
        	colRead_n = colRead;
        	addrToRead_n = addrToRead;
        	readyToOutput_n = 0;
        	if (rowWrite == 255 && colWrite > 151) begin
        		IM_WEN_n = 1;
        		readyReadChar_n = 1;
        		readyToInput_n = 0;
        		CR_A_n = 24 * timeDigits[0];	// first digit of hour
        		rowWrite_n = 0;
        		colWrite_n = 0;
        		IM_A_n = fbAddr + 59544;	// first pixel of time block				
        	end	
        	else begin
        		IM_WEN_n = (outputCount > 17) ? 1 : 0;
        		readyReadChar_n = 0;
        		readyToInput_n = (outputCount == 18) ? 1 : 0;
        		CR_A_n = CR_A;
        	end
			////
			readCharCount_n = readCharCount;
			outputCharCount_n = outputCharCount;
			outputTimeCount_n = outputTimeCount;
			charCol_n = charCol;
			charRow_n = charRow;
			readyWaitCheck_n = readyWaitCheck;
			///
        	finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
        	finishMidTimeCheck_n = 0;
            preTransCheck_n = 1;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;		
        	preMidTimeCheck_n = 0;
			outputBuffer_n[0] = (imageBuffer[0] + imageBuffer[1]) >> 1;
            outputBuffer_n[1] = (imageBuffer[1] + imageBuffer[2]) >> 1;
            outputBuffer_n[2] = imageBuffer[2];
            outputBuffer_n[3] = (imageBuffer[0] + imageBuffer[3]) >> 1;
            outputBuffer_n[4] = (imageBuffer[1] + imageBuffer[4]) >> 1;
            outputBuffer_n[5] = (imageBuffer[2] + imageBuffer[5]) >> 1;
            outputBuffer_n[6] = (imageBuffer[3] + imageBuffer[4]) >> 1;
            outputBuffer_n[7] = (imageBuffer[4] + imageBuffer[5]) >> 1;
            outputBuffer_n[8] = imageBuffer[5];
            outputBuffer_n[9] = (imageBuffer[3] + imageBuffer[6]) >> 1;
            outputBuffer_n[10] = (imageBuffer[4] + imageBuffer[7]) >> 1;
            outputBuffer_n[11] = (imageBuffer[5] + imageBuffer[8]) >> 1;
            outputBuffer_n[12] = (imageBuffer[6] + imageBuffer[7]) >> 1;
            outputBuffer_n[13] = (imageBuffer[7] + imageBuffer[8]) >> 1;
            outputBuffer_n[14] = imageBuffer[8];
            outputBuffer_n[15] = imageBuffer[6];
            outputBuffer_n[16] = imageBuffer[7];
            outputBuffer_n[17] = imageBuffer[8];
        end

		read_image_256_t:	begin
			IM_WEN_n = (imageBufferCount > 3) ? 0 : 1;
			if ( imageBufferCount < 3)	begin	// firstRead actually means not first read..			
				case (colRead)
					9'd255:	begin
						colRead_n = 0;
						rowRead_n = rowRead + 1;
						IM_A_n = addrToRead + 1;
						addrToRead_n = addrToRead + 1;
					end
					9'd254:	begin
						colRead_n = 1;
						rowRead_n = rowRead + 1;
						IM_A_n = addrToRead + 3;
						addrToRead_n = addrToRead + 3;
					end
					default:	begin
						colRead_n = colRead + 2;
						rowRead_n = rowRead;
						IM_A_n = addrToRead + 2;
						addrToRead_n = addrToRead + 2;
					end
				endcase
			end
			else  begin
				colRead_n = colRead;
				rowRead_n = rowRead;
				IM_A_n = addrToRead;
				addrToRead_n = addrToRead;
			end

			imageBufferCount_n = firstRead ? imageBufferCount + 1 : imageBufferCount;			
            IM_D_n = imageBuffer[0];
            CR_A_n = CR_A;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
			for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			if (imageBufferCount < 4)
				imageBuffer_n[imageBufferCount] = IM_Q;
			// read pixel into image buffer	
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
			if (imageBufferCount < 4)
				firstRead_n = 1;
			else
				firstRead_n = 0;
			rowWrite_n = rowWrite;
			colWrite_n = colWrite;
			addrToWrite_n = addrToWrite;
			if (imageBufferCount > 2)
				IM_A_n = addrToWrite;
			readyToOutput_n = (imageBufferCount == 3) ? 1 : 0;
			outputCount_n = 1;
			firstWrite_n = 0;
			readyToInput_n = 0;
			readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
	        finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 1;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
			preMidTimeCheck_n = 0;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end
		end

		output_image_256_t:	begin
            if (outputCount < 5)	begin			
            	case (colWrite)
            		9'd255:	begin
            			colWrite_n = 0;
            			rowWrite_n = rowWrite + 1;
            			IM_A_n = addrToWrite + 1;
            			addrToWrite_n = addrToWrite + 1;
            		end
            		9'd254:	begin
            			colWrite_n = 1;
            			rowWrite_n = rowWrite + 1;
            			IM_A_n = addrToWrite + 3;
            			addrToWrite_n = addrToWrite + 3;
            		end
            		default:	begin
            			colWrite_n = colWrite + 2;
            			rowWrite_n = rowWrite;
            			IM_A_n = addrToWrite + 2;
            			addrToWrite_n = addrToWrite + 2;
            		end
            	endcase
            end
            else  begin
            	colWrite_n = colWrite;
            	rowWrite_n = rowWrite;
            	IM_A_n = addrToWrite;
				addrToWrite_n = addrToWrite;
            end
			outputCount_n = outputCount + 1;
            IM_D_n = imageBuffer[outputCount];
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
            if (outputCount < 4)
            	firstWrite_n = 1;
            else
            	firstWrite_n = 0;
			imageBufferCount_n = 0;
			firstRead_n = 0;
			rowRead_n = rowRead;
			colRead_n = colRead;
			addrToRead_n = addrToRead;
			readyToOutput_n = 0;
            if (outputCount > 3)
            	IM_A_n = addrToRead;
			if (rowWrite == 255 && colWrite > 151) begin
				IM_WEN_n = 1;
				readyReadChar_n = 1;
				readyToInput_n = 0;
				CR_A_n = 24 * timeDigits[0];	// first digit of hour
				rowWrite_n = 0;
				colWrite_n = 0;
				IM_A_n = fbAddr + 59544;	// first pixel of time block				
			end	
			else begin
				IM_WEN_n = (outputCount > 3) ? 1 : 0;
				readyReadChar_n = 0;
				readyToInput_n = (outputCount == 4) ? 1 : 0;
				CR_A_n = CR_A;
			end
			///
			readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			///
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = 1;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;		
			preMidTimeCheck_n = 0;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
		end

		read_image_512_t:	begin
        	IM_WEN_n = (imageBufferCount > 15) ? 0 : 1;
			if (!firstRead && imageBufferCount == 0)	begin
				colRead_n = colRead + 1;	
                rowRead_n = rowRead;
                IM_A_n = addrToRead + 1;
                addrToRead_n = addrToRead + 1;
			end
			else if (imageBufferCount == 6)	begin
				colRead_n = colRead - 13;
				rowRead_n = rowRead + 1;
				IM_A_n = addrToRead + 499;
				addrToRead_n = addrToRead + 499;
			end
        	else if (imageBufferCount < 14)	begin	// firstRead actually means not first read..
				if (imageBufferCount[0] == 1'b1)	begin
					colRead_n = colRead + 1;
					rowRead_n = rowRead;
					IM_A_n = addrToRead + 1;
					addrToRead_n = addrToRead + 1;
				end
				else	begin
					colRead_n = colRead + 3;
					rowRead_n = rowRead;
					IM_A_n = addrToRead + 3;
					addrToRead_n = addrToRead + 3;
				end	
        	end
			else if (imageBufferCount < 15) begin
				case (colRead)
                	9'd511:	begin
                		colRead_n = 0;
                		rowRead_n = rowRead + 1;
                		IM_A_n = addrToRead + 1;
                		addrToRead_n = addrToRead + 1;
                	end
                	9'd509:	begin
                		colRead_n = 2;
                		rowRead_n = rowRead + 1;
                		IM_A_n = addrToRead + 5;
                		addrToRead_n = addrToRead + 5;
                	end
                	default:	begin
                		colRead_n = colRead + 3;
                		rowRead_n = rowRead - 1;
                		IM_A_n = addrToWrite;
                		addrToRead_n = addrToRead - 509;
                	end
                endcase
        	end
			else	begin
				colRead_n = colRead;
                rowRead_n = rowRead;
                IM_A_n = addrToWrite;
                addrToRead_n = addrToRead;
			end

        	imageBufferCount_n = firstRead ? imageBufferCount + 1 : imageBufferCount;			
            IM_D_n = outputBuffer[0];
            CR_A_n = CR_A;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
        	for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
        	if (imageBufferCount < 16)
        		imageBuffer_n[imageBufferCount] = IM_Q;
        	// read pixel into image buffer	
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
        	elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
        	if (imageBufferCount < 16)
        		firstRead_n = 1;
        	else
        		firstRead_n = 0;
        	rowWrite_n = rowWrite;
        	colWrite_n = colWrite;
        	addrToWrite_n = addrToWrite;
        	readyToOutput_n = (imageBufferCount == 15) ? 1 : 0;
        	outputCount_n = 1;
        	firstWrite_n = 0;
        	readyToInput_n = 0;
			readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
        	finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
        	finishMidTimeCheck_n = 0;
            preTransCheck_n = 1;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;
        	preMidTimeCheck_n = 0;
			outputBuffer_n[0] = (imageBuffer[0] + imageBuffer[1] + imageBuffer[8] + imageBuffer[9]) >> 2;
			outputBuffer_n[1] = (imageBuffer[2] + imageBuffer[3] + imageBuffer[10] + imageBuffer[11]) >> 2;	
			outputBuffer_n[2] = (imageBuffer[4] + imageBuffer[5] + imageBuffer[12] + imageBuffer[13]) >> 2;
			outputBuffer_n[3] = (imageBuffer[6] + imageBuffer[7] + imageBuffer[14] + imageBuffer[15]) >> 2;
			for (i= 4; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end
        end

        output_image_512_t:	begin
            if (outputCount < 5)	begin			
            	case (colWrite)
            		9'd255:	begin
            			colWrite_n = 0;
            			rowWrite_n = rowWrite + 1;
            			IM_A_n = addrToWrite + 1;
            			addrToWrite_n = addrToWrite + 1;
            		end
            		9'd254:	begin
            			colWrite_n = 1;
            			rowWrite_n = rowWrite + 1;
            			IM_A_n = addrToWrite + 3;
            			addrToWrite_n = addrToWrite + 3;
            		end
            		default:	begin
            			colWrite_n = colWrite + 2;
            			rowWrite_n = rowWrite;
            			IM_A_n = addrToWrite + 2;
            			addrToWrite_n = addrToWrite + 2;
            		end
            	endcase
            end
            else  begin
            	colWrite_n = colWrite;
            	rowWrite_n = rowWrite;
            	IM_A_n = addrToWrite;
        		addrToWrite_n = addrToWrite;
            end
        	outputCount_n = outputCount + 1;
            IM_D_n = outputBuffer[outputCount];
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
        	elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
            if (outputCount < 4)
            	firstWrite_n = 1;
            else
            	firstWrite_n = 0;
        	imageBufferCount_n = 0;
        	firstRead_n = 0;
        	rowRead_n = rowRead;
        	colRead_n = colRead;
        	addrToRead_n = addrToRead;
        	readyToOutput_n = 0;
            if (outputCount > 3)
            	IM_A_n = addrToRead;
        	if (rowWrite == 255 && colWrite > 151) begin
        		IM_WEN_n = 1;
        		readyReadChar_n = 1;
        		readyToInput_n = 0;
        		CR_A_n = 24 * timeDigits[0];	// first digit of hour
        		rowWrite_n = 0;
        		colWrite_n = 0;
        		IM_A_n = fbAddr + 59544;	// first pixel of time block				
        	end	
        	else begin
        		IM_WEN_n = (outputCount > 3) ? 1 : 0; ////
        		readyReadChar_n = 0;
        		readyToInput_n = (outputCount == 4) ? 1 : 0;
        		CR_A_n = CR_A;
        	end
			///
			readCharCount_n = readCharCount;	
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			///
        	finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
        	finishMidTimeCheck_n = 0;
            preTransCheck_n = 1;
            prePhotoCheck_n = 0;
            preTimeCheck_n = 0;		
        	preMidTimeCheck_n = 0;
			outputBuffer_n[0] = (imageBuffer[0] + imageBuffer[1] + imageBuffer[8] + imageBuffer[9]) >> 2;
            outputBuffer_n[1] = (imageBuffer[2] + imageBuffer[3] + imageBuffer[10] + imageBuffer[11]) >> 2;	
            outputBuffer_n[2] = (imageBuffer[4] + imageBuffer[5] + imageBuffer[12] + imageBuffer[13]) >> 2;
            outputBuffer_n[3] = (imageBuffer[6] + imageBuffer[7] + imageBuffer[14] + imageBuffer[15]) >> 2;
			for (i= 4; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
        end

		read_char_image:	begin
			IM_WEN_n = (readCharCount > 23) ? 0 : 1;
            colRead_n = colRead;
            rowRead_n = rowRead;
            IM_A_n = fbAddr + 59544 + 13 * outputTimeCount;
			imageBufferCount_n = 0;
            readCharCount_n = firstRead ? readCharCount + 1 : readCharCount;
			if (charImage[0][12] == 1)
				IM_D_n = 24'hffffff;
			else
				IM_D_n = 24'h000000;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
            charImage_n[readCharCount] = CR_Q;		
            // read pixel into image buffer	
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
            if (readCharCount < 24)
            	firstRead_n = 1;
            else
            	firstRead_n = 0;
            rowWrite_n = rowWrite;
            colWrite_n = colWrite;
			addrToRead_n = addrToRead;	//////
            addrToWrite_n = addrToWrite;
            if (readCharCount > 23)
            	CR_A_n = 24 * timeDigits[outputTimeCount + 1];
			else
				CR_A_n = CR_A + 1;
            readyToOutput_n = (readCharCount == 24) ? 1 : 0;
            outputCount_n = 0;
            firstWrite_n = 0;
            readyToInput_n = 0;
			readyReadChar_n = 0;
			outputCharCount_n = 0;
			outputTimeCount_n = outputTimeCount;
			charCol_n = 0;
			charRow_n = 0;
			readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = preTransCheck;
            prePhotoCheck_n = prePhotoCheck;
            preTimeCheck_n = preTimeCheck;
			preMidTimeCheck_n = preMidTimeCheck;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
		end

		output_time:	begin
			IM_WEN_n = (outputCharCount > 311) ? 1 : 0;
			if (charCol < 12)	begin
				charCol_n = charCol + 1;
				charRow_n = charRow;
				IM_A_n = fbAddr + 59544 + outputTimeCount * 13 + charRow * 256 + charCol + 1;
			end
			else if (charCol == 12 && charRow == 23)	begin
				charCol_n = 0;
				charRow_n = 0;
				IM_A_n = IM_A;
			end
			else	begin
				charCol_n = 0;
				charRow_n = charRow + 1;
				IM_A_n = fbAddr + 59544 + outputTimeCount * 13 + (charRow + 1) * 256;
			end
			outputCharCount_n = outputCharCount + 1;
			if (charImage[charRow_n][12 - charCol_n] == 1)				
				IM_D_n = 24'hffffff;
			else
				IM_D_n = 24'h000000;
			CR_A_n = CR_A;
            colRead_n = colRead;
            rowRead_n = rowRead;
			rowWrite_n = rowWrite; //
			colWrite_n = colWrite; //
            imageBufferCount_n = imageBufferCount;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;	
            if (outputCharCount < 312)
            	firstWrite_n = 1;
            else
            	firstWrite_n = 0;
			addrToRead_n = addrToRead; //
            addrToWrite_n = addrToWrite;
            readyToOutput_n = 0;
            outputCount_n = 0;
            firstRead_n = 0;
            readyToInput_n = 0;
			readCharCount_n = 0;
			if (outputTimeCount == 8)	begin
				outputTimeCount_n = 0;
                readyReadChar_n = 0;
                readyWaitCheck_n = 1;
			end
			else if (outputCharCount == 311 )	begin
				outputTimeCount_n = outputTimeCount + 1;
                readyReadChar_n = 1;
				readyWaitCheck_n = 0;
			end
			else	begin
				outputTimeCount_n = outputTimeCount;
				readyReadChar_n = 0;
				readyWaitCheck_n = 0;
			end
			finishTransCheck_n = 0;	
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
			finishMidTimeCheck_n = 0;
            preTransCheck_n = preTransCheck;
            prePhotoCheck_n = prePhotoCheck;
            preTimeCheck_n = preTimeCheck;
			preMidTimeCheck_n = preMidTimeCheck;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
		end

		wait_check:	begin
			IM_WEN_n = 1;
            IM_D_n = IM_D;
			CR_A_n = 24 * timeDigits[0];    // first digit of hour
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end	
            imageBufferCount_n = 0;
            if (preTransCheck && elapsedCycles > 200000)	begin
				sysTime_n = sysTime;
                elapsedCycles_n = elapsedCycles + 1;
				elapsedSeconds_n = elapsedSeconds;
				addrToWrite_n = fbAddr;
				finishTransCheck_n = 1;
				finishPhotoCheck_n = 0;
				finishTimeCheck_n = 0;
				finishMidTimeCheck_n = 0;
				preTransCheck_n = 0;
                prePhotoCheck_n = 1;
                preTimeCheck_n = 0;
				preMidTimeCheck_n = 0;
			end
			else if (prePhotoCheck && elapsedCycles > 400000)	begin
				sysTime_n = sysTime;	
                elapsedCycles_n = elapsedCycles + 1;
				elapsedSeconds_n = elapsedSeconds;
				addrToWrite_n = 0;
				finishTransCheck_n = 0;
                finishPhotoCheck_n = 1;
                finishTimeCheck_n = 0;
				finishMidTimeCheck_n = 0;
				preTransCheck_n = 0;
                prePhotoCheck_n = 0;
                preTimeCheck_n = 1;
				preMidTimeCheck_n = 0;
			end
			else if (preMidTimeCheck && elapsedCycles > 400000)	begin
				sysTime_n = sysTime;	
                elapsedCycles_n = elapsedCycles + 1;
				elapsedSeconds_n = elapsedSeconds;
				addrToWrite_n = 0;
                finishTransCheck_n = 0;
                finishPhotoCheck_n = 0;
                finishTimeCheck_n = 0;
                finishMidTimeCheck_n = 1;
                preTransCheck_n = 0;
                prePhotoCheck_n = 0;
                preTimeCheck_n = 1;
                preMidTimeCheck_n = 0;
			end
			else if (preTimeCheck && elapsedCycles > 1000000)	begin
				if (sysTime[7:0] == 59)	begin
					if (sysTime[15:8] == 59)	begin
						if (sysTime[23:16] == 23)
							sysTime_n = 24'd0;
						else
							sysTime_n = {sysTime[23:16] + 1, 16'd0};
					end
					else
						sysTime_n = {sysTime[23:8] + 1, 8'd0};
				end
				else
					sysTime_n = sysTime + 1;
				elapsedCycles_n = 2;
				elapsedSeconds_n = elapsedSeconds + 1;
				addrToWrite_n = 0;
				finishTransCheck_n = 0;	
                finishPhotoCheck_n = 0;
                finishTimeCheck_n = 1;
				finishMidTimeCheck_n = 0;
				// when previous second is even, next check is 0.4 second time check
				if (elapsedSeconds[0] == 0)	begin	
					preTransCheck_n = 0;
					preMidTimeCheck_n = 1;
				end
				// when previous second is odd, next check is trans check
				else	begin
					preTransCheck_n = 1;
					preMidTimeCheck_n = 0;	
				end					
                prePhotoCheck_n = 0;
                preTimeCheck_n = 0;
			end
			else	begin
				sysTime_n = sysTime;
				elapsedCycles_n = elapsedCycles + 1;
				elapsedSeconds_n = elapsedSeconds;
				addrToWrite_n = addrToWrite;
				finishTransCheck_n = 0;
				finishPhotoCheck_n = 0;
				finishTimeCheck_n = 0;
				finishMidTimeCheck_n = 0;				
				preTransCheck_n = preTransCheck;
                prePhotoCheck_n = prePhotoCheck;
                preTimeCheck_n = preTimeCheck;
				preMidTimeCheck_n = preMidTimeCheck;
			end
			flipSignal_n = 0;
            firstRead_n = 0;
			firstWrite_n = firstWrite; //
            IM_A_n = photoAddr[photoToRead];
            addrToRead_n = photoAddr[photoToRead];
            rowRead_n = 0;
            colRead_n = 0;
            rowWrite_n = 0;
            colWrite_n = 0;	
			readyToOutput_n = 0;
			outputCount_n = 0;
			readyToInput_n = 0;
			readyReadChar_n = 0;
			readCharCount_n = 0;
			outputCharCount_n = 0;
			outputTimeCount_n = 0;
			charCol_n = 0;
			charRow_n = 0;
			readyWaitCheck_n = 0;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
		end

		read_image_128_f:	begin
        	IM_WEN_n = (imageBufferCount > 8) ? 0 : 1;
        	if (imageBufferCount == 1 || imageBufferCount == 4)	begin
        		colRead_n = colRead - 2;
        		rowRead_n = rowRead + 1;
        		IM_A_n = addrToRead + 126;
        		addrToRead_n = addrToRead + 126;
        	end
        	else if (imageBufferCount < 7)	begin	// firstRead actually means not first read..
        		colRead_n = colRead + 1;
        		rowRead_n = rowRead;
        		IM_A_n = addrToRead + 1;
        		addrToRead_n = addrToRead + 1;
        	end
        	else if (imageBufferCount < 8) begin
        		if (colRead == 9'd126)	begin
        			colRead_n = 125;
                    rowRead_n = rowRead - 2;
                    IM_A_n = addrToRead - 257;
                    addrToRead_n = addrToRead - 257;
        		end
        		else if (colRead == 9'd127)     	begin
        			if (rowRead == 9'd126)	begin
        				colRead_n = 0;
                        rowRead_n = 125;
                        IM_A_n = addrToRead - 255;
                        addrToRead_n = addrToRead - 255;
        			end
        			else	begin
        				colRead_n = 0;
                    	rowRead_n = rowRead;
                    	IM_A_n = addrToRead - 127;
        	        	addrToRead_n = addrToRead - 127;
        			end
        		end
                else	begin
                	colRead_n = colRead;
                	rowRead_n = rowRead - 2;
                	IM_A_n = addrToWrite;
                	addrToRead_n = addrToRead - 256;
               	end
        	end
        	else	begin
        		colRead_n = colRead;
                rowRead_n = rowRead;
                IM_A_n = addrToWrite;
                addrToRead_n = addrToRead;
        	end

        	imageBufferCount_n = firstRead ? imageBufferCount + 1 : imageBufferCount;			
            IM_D_n = outputBuffer[0];
            CR_A_n = CR_A;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
        	for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
        	if (imageBufferCount < 9)
        		imageBuffer_n[imageBufferCount] = IM_Q;
        	// read pixel into image buffer	
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
        	elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
        	if (imageBufferCount < 9)
        		firstRead_n = 1;
        	else
        		firstRead_n = 0;
        	rowWrite_n = rowWrite;
        	colWrite_n = colWrite;
        	addrToWrite_n = addrToWrite;
        	readyToOutput_n = (imageBufferCount == 8) ? 1 : 0;
        	outputCount_n = 1;
        	firstWrite_n = 0;
        	readyToInput_n = 0;
			readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
        	finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
        	finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 1;
            preTimeCheck_n = 0;
        	preMidTimeCheck_n = 0;
        	outputBuffer_n[0] = imageBuffer[0];
        	outputBuffer_n[1] = imageBuffer[1];
        	outputBuffer_n[2] = imageBuffer[2];
        	outputBuffer_n[3] = (imageBuffer[0] + imageBuffer[1] + imageBuffer[3] + imageBuffer[4]) >> 2;
        	outputBuffer_n[4] = (imageBuffer[1] + imageBuffer[2] + imageBuffer[4] + imageBuffer[5]) >> 2;
            outputBuffer_n[5] = (imageBuffer[2] + imageBuffer[5]) >> 1;
            outputBuffer_n[6] = imageBuffer[3];
            outputBuffer_n[7] = imageBuffer[4];
        	outputBuffer_n[8] = imageBuffer[5];
            outputBuffer_n[9] = (imageBuffer[3] + imageBuffer[4] + imageBuffer[6] + imageBuffer[7]) >> 2;
            outputBuffer_n[10] = (imageBuffer[4] + imageBuffer[5] + imageBuffer[7] + imageBuffer[8]) >> 2;
            outputBuffer_n[11] = (imageBuffer[5] + imageBuffer[8]) >> 1;
        	outputBuffer_n[12] = imageBuffer[6];
            outputBuffer_n[13] = imageBuffer[7];
            outputBuffer_n[14] = imageBuffer[8];
            outputBuffer_n[15] = (imageBuffer[6] + imageBuffer[7]) >> 1;
        	outputBuffer_n[16] = (imageBuffer[7] + imageBuffer[8]) >> 1;
            outputBuffer_n[17] = imageBuffer[8];
        end

        output_image_128_f:	begin
        	if (outputCount == 3 || outputCount == 9 || outputCount == 15)	begin
        		colWrite_n = colWrite - 3;
                rowWrite_n = rowWrite + 1;
                IM_A_n = addrToWrite + 253;
                addrToWrite_n = addrToWrite + 253;
        	end
        	else if (outputCount == 6 || outputCount == 12)	begin
        		colWrite_n = colWrite - 5;	
                rowWrite_n = rowWrite + 1;
                IM_A_n = addrToWrite + 251;
                addrToWrite_n = addrToWrite + 251;
        	end
        	else if (outputCount == 18)	begin
        		if (colWrite == 253)	begin
        			colWrite_n = colWrite - 3;
                    rowWrite_n = rowWrite - 5;
                    IM_A_n = addrToWrite - 1283;
                    addrToWrite_n = addrToWrite - 1283;
        		end
        		else if (colWrite == 255)	begin
        			if (rowWrite == 253)	begin
        				colWrite_n = 0;	
                        rowWrite_n = rowWrite - 3;
        	            IM_A_n = addrToWrite - 1023;
        		        addrToWrite_n = addrToWrite - 1023;
        			end
        			else	begin
        				colWrite_n = 0;	
                        rowWrite_n = rowWrite - 1;
                        IM_A_n = addrToWrite - 511;
                        addrToWrite_n = addrToWrite - 511;
        			end
        		end
        		else	begin
        			colWrite_n = colWrite - 1;
                    rowWrite_n = rowWrite - 5;
                    IM_A_n = addrToRead;
                    addrToWrite_n = addrToWrite - 1281;
        		end
        	end
        	else if (outputCount < 18)	begin
        		colWrite_n = colWrite + 2;
                rowWrite_n = rowWrite;
                IM_A_n = addrToWrite + 2;
                addrToWrite_n = addrToWrite + 2;
        	end
        	else	begin
        		colWrite_n = colWrite;
                rowWrite_n = rowWrite;
                IM_A_n = addrToRead;
                addrToWrite_n = addrToWrite;
        	end

        	outputCount_n = outputCount + 1;
            IM_D_n = outputBuffer[outputCount];
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
        	elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
            if (outputCount < 18)
            	firstWrite_n = 1;
            else
            	firstWrite_n = 0;
        	imageBufferCount_n = 0;
        	firstRead_n = 0;
        	rowRead_n = rowRead;
        	colRead_n = colRead;
        	addrToRead_n = addrToRead;
        	readyToOutput_n = 0;
        	if (rowWrite == 255 && colWrite > 151) begin
        		IM_WEN_n = 1;
        		readyReadChar_n = 1;
        		readyToInput_n = 0;
        		CR_A_n = 24 * timeDigits[0];	// first digit of hour
        		rowWrite_n = 0;
        		colWrite_n = 0;
        		IM_A_n = fbAddr + 59544;	// first pixel of time block
				photoToRead_n = (photoToRead == photoNum) ? 1 : photoToRead + 1;					
        	end	
        	else begin
        		IM_WEN_n = (outputCount > 17) ? 1 : 0;
        		readyReadChar_n = 0;
        		readyToInput_n = (outputCount == 18) ? 1 : 0;
        		CR_A_n = CR_A;
				photoToRead_n = photoToRead;				
        	end
			//
			readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			//
        	finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
        	finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 1;
            preTimeCheck_n = 0;		
        	preMidTimeCheck_n = 0;
			outputBuffer_n[0] = imageBuffer[0];
            outputBuffer_n[1] = imageBuffer[1];
            outputBuffer_n[2] = imageBuffer[2];
            outputBuffer_n[3] = (imageBuffer[0] + imageBuffer[1] + imageBuffer[3] + imageBuffer[4]) >> 2;
            outputBuffer_n[4] = (imageBuffer[1] + imageBuffer[2] + imageBuffer[4] + imageBuffer[5]) >> 2;
            outputBuffer_n[5] = (imageBuffer[2] + imageBuffer[5]) >> 1;
            outputBuffer_n[6] = imageBuffer[3];
            outputBuffer_n[7] = imageBuffer[4];
            outputBuffer_n[8] = imageBuffer[5];
            outputBuffer_n[9] = (imageBuffer[3] + imageBuffer[4] + imageBuffer[6] + imageBuffer[7]) >> 2;
            outputBuffer_n[10] = (imageBuffer[4] + imageBuffer[5] + imageBuffer[7] + imageBuffer[8]) >> 2;
            outputBuffer_n[11] = (imageBuffer[5] + imageBuffer[8]) >> 1;
            outputBuffer_n[12] = imageBuffer[6];
            outputBuffer_n[13] = imageBuffer[7];
            outputBuffer_n[14] = imageBuffer[8];
            outputBuffer_n[15] = (imageBuffer[6] + imageBuffer[7]) >> 1;
            outputBuffer_n[16] = (imageBuffer[7] + imageBuffer[8]) >> 1;
            outputBuffer_n[17] = imageBuffer[8];
        end

		read_image_256_f:	begin
        	IM_WEN_n = (imageBufferCount > 3) ? 0 : 1;
        	if (imageBufferCount < 3)	begin	// firstRead actually means not first read..			
        		case (colRead)
        			9'd255:	begin
        				colRead_n = 0;
        				rowRead_n = rowRead + 1;
        				IM_A_n = addrToRead + 1;
        				addrToRead_n = addrToRead + 1;
        			end
        			9'd254:	begin
        				colRead_n = 1;
        				rowRead_n = rowRead + 1;
        				IM_A_n = addrToRead + 3;
        				addrToRead_n = addrToRead + 3;
        			end
        			default:	begin
        				colRead_n = colRead + 2;
        				rowRead_n = rowRead;
        				IM_A_n = addrToRead + 2;
        				addrToRead_n = addrToRead + 2;
        			end
        		endcase
        	end
        	else  begin
        		colRead_n = colRead;
        		rowRead_n = rowRead;
        		IM_A_n = addrToRead;
        		addrToRead_n = addrToRead;
        	end
			
			imageBufferCount_n = firstRead ? imageBufferCount + 1 : imageBufferCount;
            IM_D_n = imageBuffer[0];
            CR_A_n = CR_A;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
        	for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
			if (imageBufferCount < 4)
	        	imageBuffer_n[imageBufferCount] = IM_Q;		
        	// read pixel into image buffer	
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
        	if (imageBufferCount < 4)
        		firstRead_n = 1;
        	else
        		firstRead_n = 0;
        	rowWrite_n = rowWrite;
        	colWrite_n = colWrite;
        	addrToWrite_n = addrToWrite;
        	if (imageBufferCount > 2)
        		IM_A_n = addrToWrite;
        	readyToOutput_n = (imageBufferCount == 3) ? 1 : 0;
        	outputCount_n = 1;
        	firstWrite_n = 0;
        	readyToInput_n = 0;
			readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			finishTransCheck_n = 0;	
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
            finishMidTimeCheck_n = 0;				
            preTransCheck_n = 0;
            prePhotoCheck_n = 1;
            preTimeCheck_n = 0;
            preMidTimeCheck_n = 0;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
        end

        output_image_256_f:	begin
            if (outputCount < 5)	begin			
            	case (colWrite)
            		9'd255:	begin
            			colWrite_n = 0;
            			rowWrite_n = rowWrite + 1;
            			IM_A_n = addrToWrite + 1;
            			addrToWrite_n = addrToWrite + 1;
            		end
            		9'd254:	begin
            			colWrite_n = 1;
            			rowWrite_n = rowWrite + 1;
            			IM_A_n = addrToWrite + 3;
            			addrToWrite_n = addrToWrite + 3;
            		end
            		default:	begin
            			colWrite_n = colWrite + 2;
            			rowWrite_n = rowWrite;
            			IM_A_n = addrToWrite + 2;
            			addrToWrite_n = addrToWrite + 2;
            		end
            	endcase
            end
            else  begin
            	colWrite_n = colWrite;
            	rowWrite_n = rowWrite;
            	IM_A_n = addrToWrite;
        		addrToWrite_n = addrToWrite;
            end
			outputCount_n = outputCount + 1;
            IM_D_n = imageBuffer[outputCount];
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
			elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
            if (outputCount < 4)
            	firstWrite_n = 1;
            else
            	firstWrite_n = 0;
        	imageBufferCount_n = 0;
        	firstRead_n = 0;
        	rowRead_n = rowRead;
        	colRead_n = colRead;
        	addrToRead_n = addrToRead;
        	readyToOutput_n = 0;
            if (outputCount > 3)
            	IM_A_n = addrToRead;
        	if (rowWrite == 255 && colWrite > 151) begin
        		IM_WEN_n = 1;
        		readyReadChar_n = 1;
        		readyToInput_n = 0;
        		CR_A_n = 24 * timeDigits[0];	// first digit of hour
        		rowWrite_n = 0;
        		colWrite_n = 0;
        		IM_A_n = fbAddr + 59544;	// first pixel of time block
				photoToRead_n = (photoToRead == photoNum) ? 1 : photoToRead + 1;				
        	end	
        	else begin
        		IM_WEN_n = (outputCount > 3) ? 1 : 0;
        		readyReadChar_n = 0;
        		readyToInput_n = (outputCount == 4) ? 1 : 0;
        		CR_A_n = CR_A;
				photoToRead_n = photoToRead;
        	end
			//
			readCharCount_n = readCharCount;	
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
			//
			finishTransCheck_n = 0;	
		    finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
            finishMidTimeCheck_n = 0;				
            preTransCheck_n = 0;
            prePhotoCheck_n = 1;
            preTimeCheck_n = 0;
            preMidTimeCheck_n = 0;
			for (i= 0; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
		    	outputBuffer_n[i] = outputBuffer[i];
            end	
        end
		
		read_image_512_f:	begin	
        	IM_WEN_n = (imageBufferCount > 15) ? 0 : 1;
			if (!firstRead && imageBufferCount == 0)	begin
	        	colRead_n = colRead + 1;	
                rowRead_n = rowRead;
                IM_A_n = addrToRead + 1;
                addrToRead_n = addrToRead + 1;
			end
        	else if (imageBufferCount == 6)	begin
        		colRead_n = colRead - 13;
        		rowRead_n = rowRead + 1;
        		IM_A_n = addrToRead + 499;
        		addrToRead_n = addrToRead + 499;
        	end
        	else if (imageBufferCount < 14)	begin	// firstRead actually means not first read..
        		if (imageBufferCount[0] == 1'b1)	begin
        			colRead_n = colRead + 1;
        			rowRead_n = rowRead;
        			IM_A_n = addrToRead + 1;
        			addrToRead_n = addrToRead + 1;
        		end
        		else	begin
        			colRead_n = colRead + 3;
        			rowRead_n = rowRead;
        			IM_A_n = addrToRead + 3;
        			addrToRead_n = addrToRead + 3;
        		end	
        	end
        	else if (imageBufferCount < 15) begin
        		case (colRead)
                	9'd511:	begin
                		colRead_n = 0;
                		rowRead_n = rowRead + 1;
                		IM_A_n = addrToRead + 1;
                		addrToRead_n = addrToRead + 1;
                	end
                	9'd509:	begin
                		colRead_n = 2;
                		rowRead_n = rowRead + 1;
                		IM_A_n = addrToRead + 5;
                		addrToRead_n = addrToRead + 5;
                	end
                	default:	begin
                		colRead_n = colRead + 3;
                		rowRead_n = rowRead - 1;
                		IM_A_n = addrToWrite;
                		addrToRead_n = addrToRead - 509;
                	end
                endcase
        	end
        	else	begin
        		colRead_n = colRead;
                rowRead_n = rowRead;
                IM_A_n = addrToWrite;
                addrToRead_n = addrToRead;
        	end

        	imageBufferCount_n = firstRead ? imageBufferCount + 1 : imageBufferCount;			
            IM_D_n = outputBuffer[0];
            CR_A_n = CR_A;
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
        	for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
        	if (imageBufferCount < 16)
        		imageBuffer_n[imageBufferCount] = IM_Q;
        	// read pixel into image buffer	
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
        	elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
        	if (imageBufferCount < 16)
        		firstRead_n = 1;
        	else
        		firstRead_n = 0;
        	rowWrite_n = rowWrite;
        	colWrite_n = colWrite;
        	addrToWrite_n = addrToWrite;
        	readyToOutput_n = (imageBufferCount == 15) ? 1 : 0;
        	outputCount_n = 1;
        	firstWrite_n = 0;
        	readyToInput_n = 0;
			readyReadChar_n = readyReadChar;
            readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
            outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
        	finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
        	finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 1;
            preTimeCheck_n = 0;
        	preMidTimeCheck_n = 0;
        	outputBuffer_n[0] = (imageBuffer[0] + imageBuffer[1] + imageBuffer[8] + imageBuffer[9]) >> 2;
        	outputBuffer_n[1] = (imageBuffer[2] + imageBuffer[3] + imageBuffer[10] + imageBuffer[11]) >> 2;	
        	outputBuffer_n[2] = (imageBuffer[4] + imageBuffer[5] + imageBuffer[12] + imageBuffer[13]) >> 2;
        	outputBuffer_n[3] = (imageBuffer[6] + imageBuffer[7] + imageBuffer[14] + imageBuffer[15]) >> 2;
			for (i= 4; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
        end

        output_image_512_f:	begin
            if (outputCount < 5)	begin			
            	case (colWrite)
            		9'd255:	begin
            			colWrite_n = 0;
            			rowWrite_n = rowWrite + 1;
            			IM_A_n = addrToWrite + 1;
            			addrToWrite_n = addrToWrite + 1;
            		end
            		9'd254:	begin
            			colWrite_n = 1;
            			rowWrite_n = rowWrite + 1;
            			IM_A_n = addrToWrite + 3;
            			addrToWrite_n = addrToWrite + 3;
            		end
            		default:	begin
            			colWrite_n = colWrite + 2;
            			rowWrite_n = rowWrite;
            			IM_A_n = addrToWrite + 2;
            			addrToWrite_n = addrToWrite + 2;
            		end
            	endcase
            end
            else  begin
            	colWrite_n = colWrite;
            	rowWrite_n = rowWrite;
            	IM_A_n = addrToWrite;
        		addrToWrite_n = addrToWrite;
            end
        	outputCount_n = outputCount + 1;
            IM_D_n = outputBuffer[outputCount];
            fbAddr_n = fbAddr;
            photoNum_n = photoNum;
            photoToRead_n = photoToRead;
            for (i= 1; i < 5; i = i + 1)  begin
            	photoAddr_n[i] = photoAddr[i];
            	photoSize_n[i] = photoSize[i];
            end
            for (i= 0; i < 24; i = i + 1)  begin
            	charImage_n[i] = charImage[i];
            end
            for (i= 0; i < `IMAGE_BUFFER_LENGTH; i = i + 1)  begin
            	imageBuffer_n[i] = imageBuffer[i];
            end
            sysTime_n = sysTime;
            elapsedCycles_n = elapsedCycles + 1;
        	elapsedSeconds_n = elapsedSeconds;
			flipSignal_n = flipSignal;
            if (outputCount < 4)
            	firstWrite_n = 1;
            else
            	firstWrite_n = 0;
        	imageBufferCount_n = 0;
        	firstRead_n = 0;
        	rowRead_n = rowRead;
        	colRead_n = colRead;
        	addrToRead_n = addrToRead;
        	readyToOutput_n = 0;
            if (outputCount > 3)
            	IM_A_n = addrToRead;
        	if (rowWrite == 255 && colWrite > 151) begin
        		IM_WEN_n = 1;
        		readyReadChar_n = 1;
        		readyToInput_n = 0;
        		CR_A_n = 24 * timeDigits[0];	// first digit of hour
        		rowWrite_n = 0;
        		colWrite_n = 0;
        		IM_A_n = fbAddr + 59544;	// first pixel of time block
				photoToRead_n = (photoToRead == photoNum) ? 1 : photoToRead + 1;					
        	end	
        	else begin
        		IM_WEN_n = (outputCount > 3) ? 1 : 0;
        		readyReadChar_n = 0;
        		readyToInput_n = (outputCount == 4) ? 1 : 0;
        		CR_A_n = CR_A;
				photoToRead_n = photoToRead;				
        	end
			//
			readCharCount_n = readCharCount;
            outputCharCount_n = outputCharCount;
			outputTimeCount_n = outputTimeCount;
            charCol_n = charCol;
            charRow_n = charRow;
            readyWaitCheck_n = readyWaitCheck;
        	finishTransCheck_n = 0;
            finishPhotoCheck_n = 0;
            finishTimeCheck_n = 0;
        	finishMidTimeCheck_n = 0;
            preTransCheck_n = 0;
            prePhotoCheck_n = 1;
            preTimeCheck_n = 0;		
        	preMidTimeCheck_n = 0;
        	outputBuffer_n[0] = (imageBuffer[0] + imageBuffer[1] + imageBuffer[8] + imageBuffer[9]) >> 2;
            outputBuffer_n[1] = (imageBuffer[2] + imageBuffer[3] + imageBuffer[10] + imageBuffer[11]) >> 2;	
            outputBuffer_n[2] = (imageBuffer[4] + imageBuffer[5] + imageBuffer[12] + imageBuffer[13]) >> 2;
            outputBuffer_n[3] = (imageBuffer[6] + imageBuffer[7] + imageBuffer[14] + imageBuffer[15]) >> 2;
			for (i= 4; i < `OUTPUT_BUFFER_LENGTH; i = i + 1)  begin
            	outputBuffer_n[i] = outputBuffer[i];
            end	
        end



	endcase
end



endmodule







