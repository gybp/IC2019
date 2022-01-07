
module  CONV(
	input		clk,
	input		reset,
	output		reg busy,	
	input		ready,	
			
	output		reg [11:0]iaddr,
	input		[19:0]idata,	
	
	output	 	cwr,
	output	 	[11:0]caddr_wr,
	output	 	[19:0]cdata_wr,
	
	output	 	crd,
	output	 	[11:0]caddr_rd,
	input	 	[19:0]cdata_rd,
	
	output	  	[2:0]csel
	);

	//output reg

	reg reg_crd;
	//reg [19:0]reg_cdata_rd;
	reg [11:0]reg_caddr_rd;

	reg reg_cwr;
	reg [19:0]reg_cdata_wr;
	reg [11:0]reg_caddr_wr;
	
	reg [2:0]reg_csel;

	assign cwr = reg_cwr;
	assign caddr_wr = reg_caddr_wr;
	assign cdata_wr = reg_cdata_wr;

	assign crd = reg_crd;
	assign caddr_rd = reg_caddr_rd;
	//assign cdata_rd = reg_cdata_rd;

	assign csel = reg_csel;

	//sys start sig
	wire flag_padding;
	reg [6:0] row_count;
	reg [6:0] col_count;

	reg [1:0] state;
	reg [3:0] csel_state;
	reg [3:0] next_csel_state;

	reg ena_conv;
	reg ena_max;
	reg ena_flatten;

	reg clk2;
	wire [19:0]idata_conv;
	wire [19:0]odata_conv;
	wire [19:0]odata_max;
	wire [19:0]odata_flatten;

	wire valid_conv;

	reg [11:0]index_caddr_rd;

	convolution convolution(.clk(clk), .reset(reset), .ena(ena_conv), .idata(idata_conv), .odata(odata_conv), .valid(valid_conv));
	maxpolling maxpolling(.clk(clk), .reset(reset), .ena(ena_max), .idata(cdata_rd), .odata(odata_max));
	flatten flatten(.clk(clk), .reset(reset), .ena(ena_flatten), .idata(cdata_rd), .odata(odata_flatten));

	//freq divider
	always @(posedge clk or posedge reset) begin
		if(reset)begin
			clk2 <= 0;
		end
		else begin
			clk2 <= ~clk2;
		end
	end

	//sys start signal
	always @(posedge clk or posedge reset) begin
		if(reset)begin
			busy <= 1'b0;
		end
		else begin
			if(ready)begin
				busy <= 1'b1;	
			end
			else begin
				if(state == 2'b10 & caddr_wr == 2047)begin
					busy <= 0;
				end
			end	
		end
	end

	//state transition
	always @(posedge clk or posedge reset) begin
		if(reset)begin
			ena_conv <= 0;
			ena_max <= 0;
			ena_flatten <= 0;
			state <= 2'b00;
		end
		else begin
			case(state)
				2'b00:begin
					ena_conv <= 1;
					if(caddr_wr == 4095 & csel_state == 4'b1)begin
						state <= state + 1'b1;
						ena_conv <= 0;
						ena_max <= 1;
					end
				end
				2'b01:begin
					if(caddr_wr == 1023 & csel_state == 4'd9)begin
						state <= state + 1'b1;
						ena_max <= 0;
						ena_flatten <= 1;
					end
				end
				2'b10:begin
					if(caddr_wr == 2047)begin
						state <= state + 1'b1;
						ena_flatten <= 0;
					end
				end
				default: state<=state;
			endcase
		end
	end

	//pixel counter
	always @(posedge clk2 or posedge reset) begin
		if(reset)begin
			row_count <= 0;
			col_count <= 0;
		end
		else begin
			if(row_count == 7'd65)begin
				row_count <= 0;
				col_count <= col_count + 1;
			end
			else begin
				row_count <= row_count + 1;
			end
		end
	end

	//input data selector for zero padding
	always @(posedge clk2 or posedge reset) begin
		if(reset)begin
			iaddr <= 12'd0;
		end
		else begin
			if(flag_padding)begin
				iaddr <= iaddr;
			end
			else begin
				iaddr <= iaddr + 1;
			end
		end			
	end
	assign idata_conv = (flag_padding)? 20'd0:idata;
	assign flag_padding = (col_count == 7'd0 | col_count == 7'd65 | row_count == 7'd0 | row_count == 7'd65)?1:0;

	//caddr_wr adder
	always @(posedge clk or posedge reset ) begin
		if(reset)begin
			reg_caddr_wr <= 0;
		end
		else begin
			case(state)
				2'd0:begin
					if(cwr)begin
						if(clk2==0)begin
							reg_caddr_wr <= reg_caddr_wr + 1;
						end
					end
					else begin
						reg_caddr_wr <= reg_caddr_wr;
					end
					if(reg_caddr_wr == 12'd4095)begin
						if(clk2==0)begin
							reg_caddr_wr <= 0;
						end
					end
				end
				2'd1:begin
					if(cwr)begin
						if(clk2==0)begin
							reg_caddr_wr <= reg_caddr_wr + 1;
						end
					end
					else begin
						reg_caddr_wr <= reg_caddr_wr;
					end
					if(reg_caddr_wr == 12'd1023 & csel_state == 4'd9)begin
						if(clk2==0)begin
							reg_caddr_wr <= 0;
						end
					end
				end
				2'd2:begin
					if(cwr)begin
							reg_caddr_wr <= reg_caddr_wr + 1;
					end
					else begin
						reg_caddr_wr <= reg_caddr_wr;
					end
				end

			endcase
		end
	end

	//assign cdata_wr for diff state
	always @(*) begin
		case(state)
			2'd0:begin
				reg_cdata_wr = odata_conv;
			end
			2'd1:begin
				reg_cdata_wr = odata_max;
			end
			2'd2:begin
				reg_cdata_wr = odata_flatten;
			end
		endcase
	end

	//state mechine
	always @(posedge clk or posedge reset) begin
		if(reset)begin
			csel_state = 0;
		end
		else begin
			csel_state <= next_csel_state;
		end
	end
	always @(*) begin
		if(reset)begin
			next_csel_state <= 0;
			reg_csel = 0;
			reg_caddr_rd = 0;
			index_caddr_rd = 0;
			reg_crd = 0;
			reg_cwr = 0;
		end
		else begin
			case(state)
				2'd0:begin
					if(ena_conv)begin
						case(csel_state)
							4'd0:begin
								reg_csel = 1;
								next_csel_state = csel_state + 1;
								reg_cwr = valid_conv;
							end
							4'd1:begin
								reg_csel = 2;
								next_csel_state = 0;
								reg_cwr = valid_conv;
							end
						endcase				
					end
				end
				2'd1:begin
					if(ena_max)begin
						case(csel_state)
							4'd0:begin
								reg_csel = 1;
								next_csel_state = csel_state + 1;
								reg_caddr_rd = index_caddr_rd;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd1:begin
								reg_csel = 2;
								next_csel_state = csel_state + 1;
								reg_caddr_rd = index_caddr_rd;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd2:begin
								reg_csel = 1;
								next_csel_state = csel_state + 1;
								reg_caddr_rd = index_caddr_rd + 1;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd3:begin
								reg_csel = 2;
								next_csel_state = csel_state + 1;
								reg_caddr_rd = index_caddr_rd + 1;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd4:begin
								reg_csel = 1;
								next_csel_state = csel_state + 1;
								reg_caddr_rd = index_caddr_rd + 64;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd5:begin
								reg_csel = 2;
								next_csel_state = csel_state + 1;
								reg_caddr_rd = index_caddr_rd + 64;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd6:begin
								reg_csel = 1;
								next_csel_state = csel_state + 1;
								reg_caddr_rd = index_caddr_rd + 65;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd7:begin
								reg_csel = 2;
								next_csel_state = csel_state + 1;
								reg_caddr_rd = index_caddr_rd + 65;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd8:begin
								reg_csel = 3;
								next_csel_state = csel_state + 1;
								reg_crd = 0;
								reg_cwr = 1;
							end
							4'd9:begin
								reg_csel = 4;
								next_csel_state = 0;
								reg_crd = 0;
								reg_cwr = 1;
								if(index_caddr_rd % 64 == 62)begin
									index_caddr_rd = index_caddr_rd + 66;
								end
								else begin
									index_caddr_rd = index_caddr_rd + 2;
								end
							end
						endcase				
					end
				end
				2'd2:begin
					if(ena_flatten)begin
						case(csel_state)
							4'd0:begin
								if(caddr_rd == 12'd4095)begin
									reg_caddr_rd = 0;
								end
								reg_csel = 3;
								next_csel_state = csel_state + 1;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd1:begin
								reg_csel = 4;
								next_csel_state = csel_state + 1;
								reg_crd = 1;
								reg_cwr = 0;
							end
							4'd2:begin
								reg_caddr_rd = reg_caddr_rd + 1;
								reg_csel = 5;
								next_csel_state = csel_state + 1;
								reg_crd = 0;
								reg_cwr = 1;
							end
							4'd3:begin
								reg_csel = 5;
								next_csel_state = 0;
								reg_crd = 0;
								reg_cwr = 1;
							end
						endcase				
						
					end
				end
			endcase
		end
	end
	
endmodule
	

module convolution(input clk, input reset, input ena, input [19:0]idata, output [19:0]odata, output valid);
	parameter [19:0] bias0 = 20'h01310;
	parameter [19:0] k0_00 = 20'h0A89E;
	parameter [19:0] k0_01 = 20'h092D5;
	parameter [19:0] k0_02 = 20'h06D43;
	parameter [19:0] k0_10 = 20'h01004;
	parameter [19:0] k0_11 = 20'hF8F71;
	parameter [19:0] k0_12 = 20'hF6E54;
	parameter [19:0] k0_20 = 20'hFA6D7;
	parameter [19:0] k0_21 = 20'hFC834;
	parameter [19:0] k0_22 = 20'hFAC19;

	parameter [19:0] bias1 = 20'hF7295;
	parameter [19:0] k1_00 = 20'hFDB55;
	parameter [19:0] k1_01 = 20'h02992;
	parameter [19:0] k1_02 = 20'hFC994;
	parameter [19:0] k1_10 = 20'h050FD;
	parameter [19:0] k1_11 = 20'h02F20;
	parameter [19:0] k1_12 = 20'h0202D;
	parameter [19:0] k1_20 = 20'h03BD7;
	parameter [19:0] k1_21 = 20'hFD369;
	parameter [19:0] k1_22 = 20'h05E68;

	reg [19:0] kernel0[8:0];
	reg [19:0] kernel1[8:0];

	reg [19:0] b0;
	reg [19:0] b1;
	reg [19:0] linebuffer0[65:0];
	reg [19:0] linebuffer1[65:0];
	reg [19:0] linebuffer2[65:0];
	reg flag_linebuffer_full;

	reg [39:0] product0[8:0];
	reg [39:0] product1[8:0];
	reg [39:0] add0;
	reg [39:0] add1;
	reg [19:0] round0;
	reg [19:0] round1;
	reg [19:0] relu0;
	reg [19:0] relu1;
	integer i;
	reg [7:0]counter;
	reg clk2;

	initial begin
		b0 = bias0;
		b1 = bias1;
		kernel0[0] = k0_00;
		kernel0[1] = k0_01;
		kernel0[2] = k0_02;
		kernel0[3] = k0_10;
		kernel0[4] = k0_11;
		kernel0[5] = k0_12;
		kernel0[6] = k0_20;
		kernel0[7] = k0_21;
		kernel0[8] = k0_22;
		kernel1[0] = k1_00;
		kernel1[1] = k1_01;
		kernel1[2] = k1_02;
		kernel1[3] = k1_10;
		kernel1[4] = k1_11;
		kernel1[5] = k1_12;
		kernel1[6] = k1_20;
		kernel1[7] = k1_21;
		kernel1[8] = k1_22;
	end

	//clk divider
	always @(posedge clk or posedge reset) begin
		if(reset)begin
			clk2 <= 0;
		end
		else begin
			clk2 <= ~clk2;
		end
	end

	// line buffer shift
	always @(posedge clk2 or posedge reset) begin
		if(reset)begin
			for(i = 0; i < 64; i = i + 1)begin
				linebuffer0[i] <= 0;
				linebuffer1[i] <= 0;
			end
			linebuffer2[0]<=0;
			linebuffer2[1]<=0;
			linebuffer2[2]<=0;
		end	
		else begin
			if(ena)begin
				linebuffer0[0] <= idata;
				linebuffer1[0] <= linebuffer0[65];
				linebuffer2[0] <= linebuffer1[65];
				linebuffer2[1] <= linebuffer2[0];
				linebuffer2[2] <= linebuffer2[1];
				for( i = 0; i < 65; i = i + 1)begin
					linebuffer0[i + 1] <= linebuffer0[i];
					linebuffer1[i + 1] <= linebuffer1[i];
				end
			end
			else begin
				
			end
		end
	end

	//66+66+3 for fullfill line buffer, another 4 for first valid answer 66+66+3+4 = 139, 139-1(count from 0) = 138
	always @(posedge clk2 or posedge reset) begin
		if(reset)begin
			counter <= 0;
			flag_linebuffer_full <= 0;
		end
		else begin
			if(ena)begin
				if(flag_linebuffer_full)begin
					if(counter < 8'd65)begin
						counter <= counter + 1;
					end
					else begin
						counter <= 0;
					end
				end
				else begin
					if(counter < 8'd138)begin
						counter <= counter + 1;
					end
					else begin
						counter <= 0;
						flag_linebuffer_full <= 1;
					end
				end
			end
			else begin
				counter <= 0;
				flag_linebuffer_full <= 0;
			end
		end
	end
	assign valid = flag_linebuffer_full && (counter < 8'd64)? 1:0;

	//conv op
	always@(posedge clk2 or posedge reset)begin
		if(reset)begin
			add0 <= 0;
			add1 <= 0;
			round0 <= 0;
			round1 <= 0;
			relu0 <= 0;
			relu1 <= 0;
			for(i = 0; i < 9; i = i + 1)begin
				product0[i] <= 0;
				product1[i] <= 0;
			end
		end
		else begin
			if(ena)begin
				product0[0] <= $signed(kernel0[0]) * $signed(linebuffer2[2]);
				product0[1] <= $signed(kernel0[1]) * $signed(linebuffer2[1]);
				product0[2] <= $signed(kernel0[2]) * $signed(linebuffer2[0]);
				product0[3] <= $signed(kernel0[3]) * $signed(linebuffer1[2]);
				product0[4] <= $signed(kernel0[4]) * $signed(linebuffer1[1]);
				product0[5] <= $signed(kernel0[5]) * $signed(linebuffer1[0]);
				product0[6] <= $signed(kernel0[6]) * $signed(linebuffer0[2]);
				product0[7] <= $signed(kernel0[7]) * $signed(linebuffer0[1]);
				product0[8] <= $signed(kernel0[8]) * $signed(linebuffer0[0]);

				product1[0] <= $signed(kernel1[0]) * $signed(linebuffer2[2]);
				product1[1] <= $signed(kernel1[1]) * $signed(linebuffer2[1]);
				product1[2] <= $signed(kernel1[2]) * $signed(linebuffer2[0]);
				product1[3] <= $signed(kernel1[3]) * $signed(linebuffer1[2]);
				product1[4] <= $signed(kernel1[4]) * $signed(linebuffer1[1]);
				product1[5] <= $signed(kernel1[5]) * $signed(linebuffer1[0]);
				product1[6] <= $signed(kernel1[6]) * $signed(linebuffer0[2]);
				product1[7] <= $signed(kernel1[7]) * $signed(linebuffer0[1]);
				product1[8] <= $signed(kernel1[8]) * $signed(linebuffer0[0]);

				add0 <= $signed(product0[0]) + $signed(product0[1]) + $signed(product0[2]) + 
					$signed(product0[3]) + $signed(product0[4]) + $signed(product0[5]) + 
					$signed(product0[6]) + $signed(product0[7]) + $signed(product0[8]) + {{4{b0[19]}}, b0, 16'h0000}; 
				add1 <= $signed(product1[0]) + $signed(product1[1]) + $signed(product1[2]) + 
					$signed(product1[3]) + $signed(product1[4]) + $signed(product1[5]) + 
					$signed(product1[6]) + $signed(product1[7]) + $signed(product1[8]) + {{4{b1[19]}}, b1, 16'h0000}; 
				round0 <= (add0[15:0]>16'h8000)?add0[35:16]+1:add0[35:16];
				round1 <= (add1[15:0]>16'h8000)?add1[35:16]+1:add1[35:16];
				relu0 <= ($signed(round0)>0)? round0:0;
				relu1 <= ($signed(round1)>0)? round1:0;
			end		
			else begin
			end
		end
	end
	//odata
	assign odata = (clk2)?relu0:relu1;

endmodule

module maxpolling(input clk, input reset, input ena, input [19:0]idata, output [19:0]odata);
	reg [19:0]ans0;
	reg [19:0]ans1;
	reg clk2;
	reg [2:0]counter;

	always @(posedge clk or posedge reset) begin
		if(reset)begin
			clk2 <= 0;
		end
		else begin
			clk2 <= ~clk2;
		end
	end

	always @(posedge clk2 or posedge reset) begin
		if(reset)begin
			counter <= 0;
		end
		else begin
			if(ena)begin
				if(counter == 3'd5)begin
					counter <= 1;				
				end
				else begin
					counter <= counter + 1;
				end
			end
			else begin
				counter <= 0;
			end
		end
	end

	
	always @(posedge clk or posedge reset) begin
		if(reset)begin
			ans0 <= 0;
			ans1 <= 0;
		end
		else begin
			if(ena)begin
				if(counter < 3'd5)begin
					if(clk2)begin
						ans0 <= (ans0>idata)? ans0:idata;
					end
					else begin
						ans1 <= (ans1>idata)? ans1:idata;
					end
				end
				else begin
					if(clk2 == 0)begin
						ans0 <= 0;
						ans1 <= 0;
					end
				end
			end
			else begin
				ans0 <= 0;
				ans1 <= 0;
			end
		end
	end
	assign odata = (clk2)?ans0:ans1;
endmodule

module flatten(input clk, input reset, input ena, input [19:0]idata, output [19:0]odata);
	reg clk2;
	reg [19:0]ans0;
	reg [19:0]ans1;
	always @(posedge clk or posedge reset) begin
		if(reset)begin
			clk2 <= 0;
		end	
		else begin
			clk2 <= ~clk2;
		end
	end
	
	
	always @(posedge clk or posedge reset) begin
		if(reset)begin
			ans0 <= 0;
			ans1 <= 0;
		end
		else begin
			if(ena)begin
				if(clk2)begin
					ans0 <= idata;
				end
				else begin
					ans1 <= idata;
				end
			end
			else begin
				ans0 <= 0;
				ans1 <= 0;
			end
		end
	end
	assign odata = (clk2)?ans0:ans1;

endmodule