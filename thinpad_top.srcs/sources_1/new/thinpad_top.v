`default_nettype none

module thinpad_top(
    input wire clk_50M,           //50MHz 时钟输入
    input wire clk_11M0592,       //11.0592MHz 时钟输入

    input wire clock_btn,         //BTN5手动时钟按钮�?关，带消抖电路，按下时为1
    input wire reset_btn,         //BTN6手动复位按钮�?关，带消抖电路，按下时为1

    input  wire[3:0]  touch_btn,  //BTN1~BTN4，按钮开关，按下时为1
    input  wire[31:0] dip_sw,     //32位拨码开关，拨到“ON”时�?1
    output wire[15:0] leds,       //16位LED，输出时1点亮
    output wire[7:0]  dpy0,       //数码管低位信号，包括小数点，输出1点亮
    output wire[7:0]  dpy1,       //数码管高位信号，包括小数点，输出1点亮

    //CPLD串口控制器信�?
    output wire uart_rdn,         //读串口信号，低有�?
    output wire uart_wrn,         //写串口信号，低有�?
    input wire uart_dataready,    //串口数据准备�?
    input wire uart_tbre,         //发�?�数据标�?
    input wire uart_tsre,         //数据发�?�完毕标�?

    //BaseRAM信号
    inout wire[31:0] base_ram_data,  //BaseRAM数据，低8位与CPLD串口控制器共�?
    output wire[19:0] base_ram_addr, //BaseRAM地址
    output wire[3:0] base_ram_be_n,  //BaseRAM字节使能，低有效。如果不使用字节使能，请保持�?0
    output wire base_ram_ce_n,       //BaseRAM片�?�，低有�?
    output wire base_ram_oe_n,       //BaseRAM读使能，低有�?
    output wire base_ram_we_n,       //BaseRAM写使能，低有�?

    //ExtRAM信号
    inout wire[31:0] ext_ram_data,  //ExtRAM数据
    output wire[19:0] ext_ram_addr, //ExtRAM地址
    output wire[3:0] ext_ram_be_n,  //ExtRAM字节使能，低有效。如果不使用字节使能，请保持�?0
    output wire ext_ram_ce_n,       //ExtRAM片�?�，低有�?
    output wire ext_ram_oe_n,       //ExtRAM读使能，低有�?
    output wire ext_ram_we_n,       //ExtRAM写使能，低有�?

    //直连串口信号
    output wire txd,  //直连串口发�?�端
    input  wire rxd,  //直连串口接收�?

    //Flash存储器信号，参�?? JS28F640 芯片手册
    output wire [22:0]flash_a,      //Flash地址，a0仅在8bit模式有效�?16bit模式无意�?
    inout  wire [15:0]flash_d,      //Flash数据
    output wire flash_rp_n,         //Flash复位信号，低有效
    output wire flash_vpen,         //Flash写保护信号，低电平时不能擦除、烧�?
    output wire flash_ce_n,         //Flash片�?�信号，低有�?
    output wire flash_oe_n,         //Flash读使能信号，低有�?
    output wire flash_we_n,         //Flash写使能信号，低有�?
    output wire flash_byte_n,       //Flash 8bit模式选择，低有效。在使用flash�?16位模式时请设�?1

    //USB 控制器信号，参�?? SL811 芯片手册
    output wire sl811_a0,
    //inout  wire[7:0] sl811_d,     //USB数据线与网络控制器的dm9k_sd[7:0]共享
    output wire sl811_wr_n,
    output wire sl811_rd_n,
    output wire sl811_cs_n,
    output wire sl811_rst_n,
    output wire sl811_dack_n,
    input  wire sl811_intrq,
    input  wire sl811_drq_n,

    //网络控制器信号，参�?? DM9000A 芯片手册
    output wire dm9k_cmd,
    inout  wire[15:0] dm9k_sd,
    output wire dm9k_iow_n,
    output wire dm9k_ior_n,
    output wire dm9k_cs_n,
    output wire dm9k_pwrst_n,
    input  wire dm9k_int,

    //图像输出信号
    output wire[2:0] video_red,    //红色像素�?3�?
    output wire[2:0] video_green,  //绿色像素�?3�?
    output wire[1:0] video_blue,   //蓝色像素�?2�?
    output wire video_hsync,       //行同步（水平同步）信�?
    output wire video_vsync,       //场同步（垂直同步）信�?
    output wire video_clk,         //像素时钟输出
    output wire video_de           //行数据有效信号，用于区分消隐�?
);

// 不使用内存、串口时，禁用其使能信号
assign ext_ram_ce_n = 1'b1;
assign ext_ram_oe_n = 1'b1;
assign ext_ram_we_n = 1'b1;

reg reset_uart = 1'b1;
reg[7:0] recv = 8'b0;
wire uart_finish;
wire[7:0] uart_in;
wire[7:0] uart_out;
reg[3:0] state = 4'h0;
reg we = 1'b0;
reg ce = 1'b1;
assign uart_in = recv;

reg ram_ce = 1'b0;
reg ram_oe = 1'b0;
reg ram_we = 1'b0;
reg ram_is_write = 1'b0;
assign base_ram_ce_n = !ram_ce;
assign base_ram_oe_n = !ram_oe;
assign base_ram_we_n = !ram_we;
assign base_ram_data = ram_is_write ? {24'h0, recv} : 32'hz;
reg[19:0] addr;
assign base_ram_addr = addr;
reg[3:0] counter = 4'h0;
SEG7_LUT seg7(dpy1,counter);

always @(posedge clk_11M0592, posedge reset_btn) begin
    if(reset_btn == 1'b1) begin
        state <= 4'h0; 
        addr <= dip_sw[19:0];
        counter <= 0;
    end else
    case(state)
        4'h0: begin
            ram_ce <= 1'b0;
            ram_is_write <= 1'b0;
            ce <= 1'b1;
            we <= 1'b0;
            reset_uart <= 1'b1;
            state <= 4'h1;
        end
        4'h1: begin
            reset_uart <= 1'b0;
            if(uart_finish == 1'b1) begin
                recv <= uart_out;
                ce <= 1'b0;
                state <= 4'h2;
            end
        end
        4'h2: begin
            ram_ce <= 1'b1;
            ram_we <= 1'b0;
            ram_oe <= 1'b0;
            ram_is_write <= 1'b1;
            state <= 4'h3;
        end
        4'h3: begin
            ram_we <= 1'b1;
            state <= 4'h4;
            counter <= counter + 1;
        end
        4'h4: begin
            ram_is_write <= 1'b0;
            addr <= addr + 1;
            ram_we <= 1'b0;
            ram_ce <= 1'b0;
            if(counter == 10) begin
                state <= 4'h5;
                addr <= dip_sw[19:0];
            end
            else
                state <= 4'h0;
        end
        4'h5: begin
            // read from sram
            ram_ce <= 1'b1;
            ram_we <= 1'b0;
            ram_oe <= 1'b0;
            ram_is_write <= 1'b0;
            ce <= 1'b0;
            we <= 1'b0;
            state <= 4'h6;
        end
        4'h6: begin
            ram_oe <= 1'b1;
            state <= 4'h7;
        end
        4'h7: begin
            recv <= base_ram_data[7:0];
            state <= 4'h8;
        end
        4'h8: begin
            ce <= 1'b1;
            we <= 1'b1;
            ram_ce <= 1'b0;
            ram_oe <= 1'b0;
            state <= 4'h9;
            reset_uart <= 1'b1;
        end
        4'h9: begin
            reset_uart <= 1'b0;
            if(uart_finish == 1'b1) begin
                state <= 4'ha;
                counter <= counter - 1;
                addr <= addr + 1;
            end
        end
        4'ha: begin
            if(counter != 0) begin
                state <= 4'h5;
            end else
                state <= 4'hb;
        end
    endcase
end

uart_controller uart_ctrl(
      .clk(clk_11M0592),
      .rst(reset_uart),
      .ce(ce),
      .we(we),
      .data_bus_i(base_ram_data[7:0]),
      .data_bus_o(base_ram_data[7:0]),
      .tbre_i(uart_tbre),
      .tsre_i(uart_tsre),
      .data_ready_i(uart_dataready),
      .rdn_o(uart_rdn),
      .wrn_o(uart_wrn),
      .data_o(uart_out),
      .data_i(uart_in),
      .uart_finish(uart_finish)
);


endmodule
