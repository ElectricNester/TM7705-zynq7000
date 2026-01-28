// AD7705/TM7705 SPI Driver - Simplified Version
// Полностью игнорируем DRDY, просто читаем циклически
`timescale 1ns / 1ps

module ad7705_diagnostic(
    input wire clk_200M,
    input wire sysrst,
    output reg [15:0] adc_data_hex = 16'd0,
    
    input wire AD_DRDY_n,  // Не используется
    input wire AD_dout,
    output reg AD_CS = 1'b1,
    output wire AD_clk,
    output reg AD_din = 1'b0,
    
    output reg [3:0] state = 4'd0,
    output reg [7:0] debug_counter = 8'd0
);

// Синхронизация входа данных
reg [2:0] dout_sync = 3'b111;

always @(posedge clk_200M) begin
    dout_sync <= {dout_sync[1:0], AD_dout};
end

wire miso_data = dout_sync[2];

// SPI clock - 100kHz (200MHz / 100kHz = 2000 тактов)
reg [11:0] spi_div_cnt = 12'd0;
reg spi_clk = 1'b0;
wire spi_clk_posedge;
wire spi_clk_negedge;

always @(posedge clk_200M) begin
    if (spi_div_cnt >= 12'd1999) begin
        spi_div_cnt <= 12'd0;
        spi_clk <= ~spi_clk;
    end else begin
        spi_div_cnt <= spi_div_cnt + 12'd1;
    end
end

assign spi_clk_posedge = (spi_div_cnt == 12'd0) && (spi_clk == 1'b1);
assign spi_clk_negedge = (spi_div_cnt == 12'd999) && (spi_clk == 1'b0);

// FSM
reg [3:0] diag_state = 4'd0;
reg [4:0] bit_counter = 5'd0;
reg [15:0] shift_reg = 16'd0;
reg [31:0] delay_counter = 32'd0;
reg spi_active = 1'b0;
reg [7:0] tx_shift_reg = 8'd0;

// Константы (упрощенные)
localparam CMD_WRITE_CLK    = 8'h20; // Clock Register, CH1
localparam DATA_CLK_REG     = 8'h0C; // 50Hz (CLKDIV=0, FS=10) - золотая середина

localparam CMD_WRITE_SETUP  = 8'h10; // Setup Register, CH1
localparam DATA_SETUP_REG   = 8'h02; // Normal mode, Gain=1, Bipolar, Buffer ON

localparam CMD_READ_DATA    = 8'h38; // Read Data Register, CH1

// SPI Clock output
assign AD_clk = spi_active ? spi_clk : 1'b0;

// Главный FSM
always @(posedge clk_200M or negedge sysrst) begin
    if (!sysrst) begin
        diag_state <= 4'd0;
        AD_CS <= 1'b1;
        AD_din <= 1'b0;
        adc_data_hex <= 16'd0;
        bit_counter <= 5'd0;
        shift_reg <= 16'd0;
        delay_counter <= 32'd0;
        spi_active <= 1'b0;
        state <= 4'd0;
        debug_counter <= 8'd0;
        tx_shift_reg <= 8'd0;
    end else begin
        state <= diag_state;
        
        case (diag_state)
            // STATE 0: Инициализация
            4'd0: begin
                AD_CS <= 1'b1;
                AD_din <= 1'b0;
                spi_active <= 1'b0;
                
                if (delay_counter < 32'd200_000) begin // 1ms
                    delay_counter <= delay_counter + 1;
                end else begin
                    delay_counter <= 32'd0;
                    diag_state <= 4'd1;
                    bit_counter <= 5'd0;
                end
            end
            
            // STATE 1: Software Reset (32 бита '1')
            4'd1: begin
                AD_CS <= 1'b0;
                spi_active <= 1'b1;
                
                if (spi_clk_negedge) begin
                    if (bit_counter < 5'd31) begin
                        AD_din <= 1'b1;
                        bit_counter <= bit_counter + 1;
                    end else begin
                        bit_counter <= 5'd0;
                        AD_din <= 1'b0;
                        AD_CS <= 1'b1;
                        spi_active <= 1'b0;
                        delay_counter <= 32'd0;
                        diag_state <= 4'd2;
                    end
                end
            end
            
            // STATE 2: Задержка после сброса
            4'd2: begin
                if (delay_counter < 32'd2_000_000) begin // 10ms
                    delay_counter <= delay_counter + 1;
                end else begin
                    delay_counter <= 32'd0;
                    diag_state <= 4'd3;
                    bit_counter <= 5'd0;
                    tx_shift_reg <= CMD_WRITE_CLK;
                end
            end
            
            // STATE 3: Запись Clock Register
            4'd3: begin
                AD_CS <= 1'b0;
                spi_active <= 1'b1;
                
                if (spi_clk_negedge) begin
                    if (bit_counter < 4'd16) begin
                        if (bit_counter < 4'd8) begin
                            AD_din <= tx_shift_reg[7];
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                        end else begin
                            if (bit_counter == 4'd8) begin
                                tx_shift_reg <= DATA_CLK_REG;
                            end
                            AD_din <= tx_shift_reg[7];
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                        end
                        bit_counter <= bit_counter + 1;
                    end else begin
                        bit_counter <= 5'd0;
                        AD_din <= 1'b0;
                        AD_CS <= 1'b1;
                        spi_active <= 1'b0;
                        delay_counter <= 32'd0;
                        diag_state <= 4'd4;
                    end
                end
            end
            
            // STATE 4: Задержка
            4'd4: begin
                if (delay_counter < 32'd2_000_000) begin // 10ms
                    delay_counter <= delay_counter + 1;
                end else begin
                    delay_counter <= 32'd0;
                    diag_state <= 4'd5;
                    bit_counter <= 5'd0;
                    tx_shift_reg <= CMD_WRITE_SETUP;
                end
            end
            
            // STATE 5: Запись Setup Register
            4'd5: begin
                AD_CS <= 1'b0;
                spi_active <= 1'b1;
                
                if (spi_clk_negedge) begin
                    if (bit_counter < 4'd16) begin
                        if (bit_counter < 4'd8) begin
                            AD_din <= tx_shift_reg[7];
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                        end else begin
                            if (bit_counter == 4'd8) begin
                                tx_shift_reg <= DATA_SETUP_REG;
                            end
                            AD_din <= tx_shift_reg[7];
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                        end
                        bit_counter <= bit_counter + 1;
                    end else begin
                        bit_counter <= 5'd0;
                        AD_din <= 1'b0;
                        AD_CS <= 1'b1;
                        spi_active <= 1'b0;
                        delay_counter <= 32'd0;
                        diag_state <= 4'd6;
                    end
                end
            end
            
            // STATE 6: Задержка для установки фильтра
            4'd6: begin
                if (delay_counter < 32'd10_000_000) begin // 50ms
                    delay_counter <= delay_counter + 1;
                end else begin
                    delay_counter <= 32'd0;
                    diag_state <= 4'd7;
                    bit_counter <= 5'd0;
                    tx_shift_reg <= CMD_READ_DATA;
                end
            end
            
            // STATE 7: Чтение данных АЦП (игнорируем DRDY)
            4'd7: begin
                AD_CS <= 1'b0;
                spi_active <= 1'b1;
                
                if (spi_clk_negedge) begin
                    if (bit_counter < 4'd8) begin
                        AD_din <= tx_shift_reg[7];
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                        bit_counter <= bit_counter + 1;
                    end else if (bit_counter < 5'd24) begin
                        AD_din <= 1'b0;
                        bit_counter <= bit_counter + 1;
                    end else begin
                        AD_CS <= 1'b1;
                        spi_active <= 1'b0;
                        adc_data_hex <= shift_reg;
                        bit_counter <= 5'd0;
                        delay_counter <= 32'd0;
                        diag_state <= 4'd8;
                    end
                end
                
                if (spi_clk_posedge && bit_counter >= 4'd8 && bit_counter < 5'd24) begin
                    shift_reg <= {shift_reg[14:0], miso_data};
                end
            end
            
            // STATE 8: Задержка между чтениями
            4'd8: begin
                if (delay_counter < 32'd10_000_000) begin // 50ms
                    delay_counter <= delay_counter + 1;
                end else begin
                    delay_counter <= 32'd0;
                    diag_state <= 4'd7;
                    bit_counter <= 5'd0;
                    tx_shift_reg <= CMD_READ_DATA;
                    shift_reg <= 16'd0;
                end
            end
            
            default: begin
                diag_state <= 4'd0;
            end
        endcase
        
        debug_counter <= {3'b000, bit_counter};
    end
end

endmodule