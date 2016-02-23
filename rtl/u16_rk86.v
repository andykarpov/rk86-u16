// ====================================================================
//                Radio-86RK FPGA REPLICA
//
//            Copyright (C) 2011 Dmitry Tselikov
//
// This core is distributed under modified BSD license. 
// For complete licensing information see LICENSE.TXT.
// -------------------------------------------------------------------- 
//
// An open implementation of Radio-86RK home computer
//
// Author: Dmitry Tselikov   http://bashkiria-2m.narod.ru/
// 
// Minor changes for adaptation to SDRAM: Ivan Gorodetsky, 2014
// 
// Port to Reverse-U16: Andy Karpov, 2016
//
// Design File: u16_rk86.v
//
// Top level design file.

module u16_rk86(
	input			CLK_50MHZ,
	
	inout		[15:0] SDRAM_DQ,				//	SDRAM Data bus 16 Bits
	output	[11:0] SDRAM_A,				//	SDRAM Address bus 12 Bits
	output			SDRAM_DQML,				//	SDRAM Low-byte Data Mask 
	output			SDRAM_DQMH,				//	SDRAM High-byte Data Mask
	output			SDRAM_NWE,				//	SDRAM Write Enable
	output			SDRAM_NCAS,				//	SDRAM Column Address Strobe
	output			SDRAM_NRAS,				//	SDRAM Row Address Strobe
	output	[1:0] SDRAM_BA,				//	SDRAM Bank Address 0
	output			SDRAM_CLK,				//	SDRAM Clock

	inout			PS2_KBD_CLK,
	inout			PS2_KBD_DAT,

	input				SD_SO,					//	SD Card Data 				(MISO)
	output			SD_NCS,					//	SD Card Data 3 			(CSn)
	output			SD_SI,					//	SD Card Command Signal	(MOSI)
	output			SD_CLK,					//	SD Card Clock				(SCK)

	output			DN,
	output			DP,
	
	output			HDMI_D0,
	output			HDMI_D1,
	output			HDMI_D1N,
	output			HDMI_D2,
	output			HDMI_CLK

);

// CLOCK
wire clk50mhz;
wire clk250mhz;
wire clock_locked;
clk clock(
	.inclk0		(CLK_50MHZ),
	.c0		(clk250mhz),
	.c1		(clk50mhz),
	.locked		(clock_locked));

wire VGA_HS;
wire VGA_VS;
wire[4:0] VGA_R;
wire[5:0] VGA_G;
wire[4:0] VGA_B;
wire BEEP;

assign DP = BEEP;
assign DN = BEEP;

////////////////////   RESET   ////////////////////
reg[3:0] reset_cnt;
reg reset_n;
wire reset = ~reset_n;
reg[3:0] KEY = {4'b1111}; // missed hw buttons on reverse-u16, all keys are pulled up

always @(posedge clk50mhz) begin
	if (KEY[0] && k_reset==1'b0 && reset_cnt==4'd14)
		reset_n <= 1'b1;
	else begin
		reset_n <= 1'b0;
		reset_cnt <= reset_cnt+4'd1;
	end
end

////////////////////   STEP & GO   ////////////////////
reg		stepkey;
reg		onestep;

always @(posedge clk50mhz) begin
	stepkey <= KEY[1];
	onestep <= stepkey & ~KEY[1];
end

////////////////////   MEM   ////////////////////

wire sram_msb = 0;
wire[7:0] rom_o;

assign SDRAM_CLK=clk50mhz;				//	SDRAM Clock
wire[15:0] dramout;
wire DRAM_CS_N;
SDRAM_Controller ramd(
	.clk50mhz(clk50mhz),				//  Clock 50MHz
	.reset(reset),					//  System reset
	.DRAM_DQ(SDRAM_DQ),				//	SDRAM Data bus 16 Bits
	.DRAM_ADDR(SDRAM_A),			//	SDRAM Address bus 12 Bits
	.DRAM_LDQM(SDRAM_DQML),				//	SDRAM Low-byte Data Mask 
	.DRAM_UDQM(SDRAM_DQMH),				//	SDRAM High-byte Data Mask
	.DRAM_WE_N(SDRAM_NWE),				//	SDRAM Write Enable
	.DRAM_CAS_N(SDRAM_NCAS),				//	SDRAM Column Address Strobe
	.DRAM_RAS_N(SDRAM_NRAS),				//	SDRAM Row Address Strobe
	.DRAM_CS_N(DRAM_CS_N),				//	SDRAM Chip Select
	.DRAM_BA_0(SDRAM_BA[0]),				//	SDRAM Bank Address 0
	.DRAM_BA_1(SDRAM_BA[1]),				//	SDRAM Bank Address 1
	.iaddr(vid_rd ? {3'b000,vid_addr[14:0]} : {3'b000,addrbus[14:0]}),
	.idata(cpu_o),
	.rd(vid_rd ? 1'b1 : cpu_rd&(!addrbus[15])),
	.we_n(vid_rd? 1'b1 : cpu_wr_n|addrbus[15]),
	.odata(dramout)
);
wire[7:0] mem_o = dramout[7:0];

biossd rom(.address({addrbus[11]|startup,addrbus[10:0]}), .clock(clk50mhz), .q(rom_o));

////////////////////   CPU   ////////////////////
wire[15:0] addrbus;
wire[7:0] cpu_o;
wire cpu_sync;
wire cpu_rd;
wire cpu_wr_n;
wire cpu_int;
wire cpu_inta_n;
wire inte;
reg[7:0] cpu_i;
reg startup;

always @(*)
	casex (addrbus[15:13])
	3'b0xx: cpu_i = startup ? rom_o : mem_o;
	3'b100: cpu_i = ppa1_o;
	3'b101: cpu_i = sd_o;
	3'b110: cpu_i = crt_o;
	3'b111: cpu_i = rom_o;
	endcase

wire ppa1_we_n = addrbus[15:13]!=3'b100|cpu_wr_n;
wire ppa2_we_n = addrbus[15:13]!=3'b101|cpu_wr_n;
wire crt_we_n  = addrbus[15:13]!=3'b110|cpu_wr_n;
wire crt_rd_n  = addrbus[15:13]!=3'b110|~cpu_rd;
wire dma_we_n  = addrbus[15:13]!=3'b111|cpu_wr_n;

reg[4:0] cpu_cnt;
reg cpu_ce2;
reg[10:0] hldareg;
wire cpu_ce = cpu_ce2;
always @(posedge clk50mhz) begin
	if(reset) begin cpu_cnt<=0; cpu_ce2<=0; hldareg=11'd0; end
	else
   if((hldareg[10:9]==2'b01)&&((cpu_rd==1)||(cpu_wr_n==0))) begin cpu_cnt<=0; cpu_ce2<=1; end
	else
	if(cpu_cnt<27) begin cpu_cnt <= cpu_cnt + 5'd1; cpu_ce2<=0; end
	else begin cpu_cnt<=0; cpu_ce2<=~hlda; end
	hldareg<={hldareg[9:0],hlda};
	startup <= reset|(startup&~addrbus[15]);
end

k580wm80a CPU(.clk(clk50mhz), .ce(cpu_ce), .reset(reset),
	.idata(cpu_i), .addr(addrbus), .sync(cpu_sync), .rd(cpu_rd), .wr_n(cpu_wr_n),
	.intr(cpu_int), .inta_n(cpu_inta_n), .odata(cpu_o), .inte_o(inte));

////////////////////   VIDEO   ////////////////////
wire[7:0] crt_o;
wire[3:0] vid_line;
wire[6:0] vid_char;
wire[15:0] vid_addr;
wire[3:0] dma_dack;
wire[7:0] dma_o;
wire[1:0] vid_lattr;
wire[1:0] vid_gattr;
wire vid_cce,vid_drq,vid_irq,hlda;
wire vid_lten,vid_vsp,vid_rvv,vid_hilight;
wire dma_owe_n,dma_ord_n,dma_oiowe_n,dma_oiord_n;
wire vid_hr, vid_vr;

wire vid_rd = ~dma_oiord_n;
wire[10:0] vga_counter_x;
wire[10:0] vga_counter_y;
wire vga_blank;

k580wt57 dma(.clk(clk50mhz), .ce(vid_cce), .reset(reset),
	.iaddr(addrbus[3:0]), .idata(cpu_o), .drq({1'b0,vid_drq,2'b00}), .iwe_n(dma_we_n), .ird_n(1'b1),
	.hlda(hlda), .hrq(hlda), .dack(dma_dack), .odata(dma_o), .oaddr(vid_addr),
	.owe_n(dma_owe_n), .ord_n(dma_ord_n), .oiowe_n(dma_oiowe_n), .oiord_n(dma_oiord_n) );

k580wg75 crt(.clk(clk50mhz), .ce(vid_cce),
	.iaddr(addrbus[0]), .idata(cpu_o), .iwe_n(crt_we_n), .ird_n(crt_rd_n),
	.vrtc(vid_vr), .hrtc(vid_hr), .dack(dma_dack[2]), .ichar(mem_o), .drq(vid_drq), .irq(vid_irq),
	.odata(crt_o), .line(vid_line), .ochar(vid_char), .lten(vid_lten), .vsp(vid_vsp),
	.rvv(vid_rvv), .hilight(vid_hilight), .lattr(vid_lattr), .gattr(vid_gattr) );
	
rk_video vid(.clk(clk50mhz), 
	.hr(VGA_HS), .vr(VGA_VS), 
	.r(VGA_R), .g(VGA_G), .b(VGA_B),
	.hr_wg75(vid_hr), .vr_wg75(vid_vr), .cce(vid_cce),
	.line(vid_line), .ichar(vid_char),
	.vsp(vid_vsp), .lten(vid_lten), .rvv(vid_rvv),
	.counter_x(vga_counter_x), .counter_y(vga_counter_y), .blank(vga_blank)
);

////////////////////   KBD   ////////////////////
wire[7:0] kbd_o;
wire[2:0] kbd_shift;
wire k_reset;

rk_kbd kbd(.clk(clk50mhz), .reset(reset), .ps2_clk(PS2_KBD_CLK), .ps2_dat(PS2_KBD_DAT),
	.addr(~ppa1_a), .odata(kbd_o), .shift(kbd_shift), .k_reset(k_reset));

////////////////////   SYS PPA   ////////////////////
wire[7:0] ppa1_o;
wire[7:0] ppa1_a;
wire[7:0] ppa1_b;
wire[7:0] ppa1_c;

k580ww55 ppa1(.clk(clk50mhz), .reset(reset), .addr(addrbus[1:0]), .we_n(ppa1_we_n),
	.idata(cpu_o), .odata(ppa1_o), .ipa(ppa1_a), .opa(ppa1_a),
	.ipb(~kbd_o), .opb(ppa1_b), .ipc({~kbd_shift,tapein,ppa1_c[3:0]}), .opc(ppa1_c));

////////////////////   SOUND   ////////////////////
reg tapein;

soundcodec sound(
	.clk(clk50mhz),
	.pulse(ppa1_c[0]^inte),
	.reset_n(reset_n),
	.o_pwm(BEEP)
);

////////////////////   SD CARD   ////////////////////
reg sdcs;
reg sdclk;
reg sdcmd;
reg[6:0] sddata;
wire[7:0] sd_o = {sddata, SD_SO};

assign SD_NCS = ~sdcs;
assign SD_SI = sdcmd;
assign SD_CLK = sdclk;

always @(posedge clk50mhz or posedge reset) begin
	if (reset) begin
		sdcs <= 1'b0;
		sdclk <= 1'b0;
		sdcmd <= 1'h1;
	end else begin
		if (addrbus[0]==1'b0 && ~ppa2_we_n) sdcs <= cpu_o[0];
		if (addrbus[0]==1'b1 && ~ppa2_we_n) begin
			if (sdclk) sddata <= {sddata[5:0],SD_SO};
			sdcmd <= cpu_o[7];
			sdclk <= 1'b0;
		end
		if (cpu_rd) sdclk <= 1'b1;
	end
end

/////////////////////   HDMI /////////////////////////

    hdmi tmds(
	.I_CLK		(clk250mhz),
	.I_CLK_PIXEL	(clk50mhz),
	.I_R		({VGA_R,3'b000}),
	.I_G		({VGA_G[5:0],2'b00}),
	.I_B		({VGA_B,3'b000}),
	.I_HSYNC		(VGA_HS),
	.I_VSYNC		(VGA_VS),
	.I_BLANK	   (vga_blank),
	.O_TMDS_D0  (HDMI_D0),
	.O_TMDS_D1  (HDMI_D1),
	.O_TMDS_D2  (HDMI_D2),
	.O_TMDS_CLK (HDMI_CLK)
    );
    
    assign HDMI_D1N = 1'b0;

endmodule
