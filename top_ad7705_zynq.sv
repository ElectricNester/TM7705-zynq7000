`timescale 1ns / 1ps

module top_ad7705_zynq(
    input wire clk_p,
    input wire clk_n,
    input wire sysrst,
    
    input wire AD_DRDY_n,
    input wire AD_dout,
    output wire AD_CS,
    output wire AD_clk,
    output wire AD_din,
    output wire AD_RST_n,
    
    output reg [6:0] leds = 7'b0
);

wire clk_200M;
IBUFDS #(
    .DIFF_TERM("FALSE"),
    .IBUF_LOW_PWR("TRUE"),
    .IOSTANDARD("LVDS")
) IBUFDS_inst (
    .O(clk_200M),
    .I(clk_p),
    .IB(clk_n)
);

// Аппаратный сброс - держим неактивным
assign AD_RST_n = 1'b1;

// Diagnostic module
wire [15:0] adc_data_hex;
wire [3:0] diag_state;
wire [7:0] debug_cnt;

ad7705_diagnostic diag_inst (
    .clk_200M(clk_200M),
    .sysrst(sysrst),
    .adc_data_hex(adc_data_hex),
    .AD_DRDY_n(AD_DRDY_n),
    .AD_dout(AD_dout),
    .AD_CS(AD_CS),
    .AD_clk(AD_clk),
    .AD_din(AD_din),
    .state(diag_state),
    .debug_counter(debug_cnt)
);

// LED индикация
reg [27:0] counter = 0;
reg [15:0] last_adc_value = 16'd0;

always @(posedge clk_200M or negedge sysrst) begin
    if (!sysrst) begin
        counter <= 0;
        last_adc_value <= 16'd0;
        leds <= 7'b0;
    end else begin
        if (counter < 28'd10_000_000) begin
            counter <= counter + 1;
        end else begin
            counter <= 0;
            
            // Сохраняем последнее не "плохое" значение
            if (adc_data_hex != 16'h0000 && adc_data_hex != 16'hFFFF) begin
                last_adc_value <= adc_data_hex;
            end
            
            // Показываем состояние или данные
            if (diag_state == 4'd7 || diag_state == 4'd8) begin
                // В режиме чтения показываем младшие биты данных
                leds <= last_adc_value[6:0];
            end else begin
                // В остальных случаях - состояние
                case (diag_state)
                    4'd0: leds <= 7'b0000001;
                    4'd1: leds <= 7'b0000010;
                    4'd2: leds <= 7'b0000100;
                    4'd3: leds <= 7'b0001000;
                    4'd4: leds <= 7'b0010000;
                    4'd5: leds <= 7'b0100000;
                    4'd6: leds <= 7'b1000000;
                    default: leds <= 7'b0000000;
                endcase
            end
        end
    end
end

// ILA signals - УБЕРИТЕ ILA ЕСЛИ ЕСТЬ ПРОБЛЕМЫ!
// Для начала лучше отключить ILA
wire [0:0] MISO = AD_dout;
wire [0:0] MOSI = AD_din;
wire [0:0] SCLK = AD_clk;
wire [0:0] DRDY = 1'b0;
wire [0:0] RST = sysrst;
wire [3:0] SM = diag_state;
wire [7:0] BIT_CNT = debug_cnt;
wire [15:0] ADC_DATA = adc_data_hex;
wire [0:0] CS = AD_CS;
wire [0:0] AD_RST = AD_RST_n;

ila_0 ila_ad7705_inst (
    .clk(clk_200M),
    .probe0(MISO),
    .probe1(MOSI),
    .probe2(SCLK),
    .probe3(DRDY),
    .probe4(RST),
    .probe5(SM),
    .probe6(BIT_CNT),
    .probe7(ADC_DATA),
    .probe8(CS),
    .probe9(AD_RST)
);


endmodule