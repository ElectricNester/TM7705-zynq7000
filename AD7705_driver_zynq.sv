// AD7705 SPI Driver Module for Zynq 7000
// Simplified version - HEX output only
`timescale 1ns / 1ps

module AD7705_driver_zynq(
    input wire clk_200M,        // 200MHz clock
    input wire sysrst,          // Active low system reset
    output reg [15:0] ad_data_hex = 16'd0,  // Output ADC data in HEX
    
    // AD7705 interface
    input wire AD_DRDY_n,
    input wire AD_dout,
    output reg AD_CS = 1'b1,    // Chip select (active low)
    output wire AD_clk,         // SPI clock
    output reg AD_din = 1'b0,   // SPI data in
    
    // Debug outputs
    output reg [3:0] state_debug = 4'd0,  // Current state for debug
    output reg spi_active = 1'b0         // SPI activity indicator
);

// Clock divider for SPI (200MHz -> 500kHz для TM7705)
reg [7:0] spi_div_cnt = 8'd0;
reg spi_clk = 1'b0;
reg spi_clk_en = 1'b0;

always @(posedge clk_200M) begin
    if (spi_div_cnt >= 8'd199) begin  // 200MHz/200 = 1MHz, 50% duty cycle
        spi_div_cnt <= 8'd0;
        spi_clk <= ~spi_clk;
        spi_clk_en <= 1'b1;
    end else begin
        spi_div_cnt <= spi_div_cnt + 8'd1;
        spi_clk_en <= 1'b0;
    end
end

// Generate SPI clock output
assign AD_clk = spi_clk & spi_active;

// State definitions
typedef enum logic [3:0] {
    S_IDLE           = 4'd0,
    S_RESET1         = 4'd1,    // Сброс 1: 32 такта с DIN=1
    S_DELAY1         = 4'd2,    // Задержка после сброса
    S_WRITE_CLKREG   = 4'd3,    // Запись clock register
    S_DELAY2         = 4'd4,    // Задержка после clock register
    S_WRITE_SETREG   = 4'd5,    // Запись setup register
    S_DELAY3         = 4'd6,    // Задержка после setup register
    S_WAIT_CALIB     = 4'd7,    // Ожидание калибровки
    S_CHECK_DRDY     = 4'd8,    // Проверка DRDY
    S_READ_DATA      = 4'd9,    // Чтение данных
    S_WAIT_NEXT      = 4'd10    // Ожидание следующего чтения
} state_t;

// Internal registers
reg [3:0] current_state = S_IDLE;
reg [4:0] bit_cnt = 5'd0;
reg [15:0] rx_data = 16'd0;
reg [31:0] delay_cnt = 32'd0;
reg [4:0] reset_cnt = 5'd0;

// Configuration constants for 4.9152MHz crystal (TM7705)
parameter CLK_REG_CMD  = 8'h20;  // Write clock register, CH1
parameter CLK_REG_VAL  = 8'h0F;  // CLKDIS=0, CLKDIV=1 (for 4.9152MHz), FS=11 (500Hz)
parameter SETUP_REG_CMD = 8'h10;  // Write setup register, CH1
parameter SETUP_REG_VAL = 8'h06;  // Normal mode, Gain=1, Unipolar, Buffer ON
parameter READ_DATA_CMD = 8'h38;  // Read data register, CH1

// Main FSM
always @(posedge clk_200M or negedge sysrst) begin
    if (!sysrst) begin
        current_state <= S_IDLE;
        AD_CS <= 1'b1;
        AD_din <= 1'b0;
        ad_data_hex <= 16'd0;
        bit_cnt <= 5'd0;
        rx_data <= 16'd0;
        delay_cnt <= 32'd0;
        reset_cnt <= 5'd0;
        spi_active <= 1'b0;
        state_debug <= 4'd0;
    end else begin
        state_debug <= current_state;
        
        case (current_state)
            S_IDLE: begin
                AD_CS <= 1'b1;
                AD_din <= 1'b0;
                spi_active <= 1'b0;
                
                // 1ms delay после сброса
                if (delay_cnt < 32'd200_000) begin
                    delay_cnt <= delay_cnt + 1;
                end else begin
                    delay_cnt <= 0;
                    current_state <= S_RESET1;
                end
            end
            
            S_RESET1: begin
                AD_CS <= 1'b0;
                spi_active <= 1'b1;
                
                // Generate 32 SCLK cycles with DIN=1
                if (spi_clk_en) begin
                    if (reset_cnt < 31) begin
                        AD_din <= 1'b1;
                        reset_cnt <= reset_cnt + 1;
                    end else begin
                        reset_cnt <= 0;
                        AD_din <= 1'b0;
                        current_state <= S_DELAY1;
                    end
                end
            end
            
            S_DELAY1: begin
                AD_CS <= 1'b1;
                AD_din <= 1'b0;
                spi_active <= 1'b0;
                
                if (delay_cnt < 32'd200_000) begin  // 1ms
                    delay_cnt <= delay_cnt + 1;
                end else begin
                    delay_cnt <= 0;
                    current_state <= S_WRITE_CLKREG;
                end
            end
            
            S_WRITE_CLKREG: begin
                AD_CS <= 1'b0;
                spi_active <= 1'b1;
                
                if (bit_cnt < 16) begin  // Send 2 bytes: command + data
                    if (spi_clk_en) begin
                        if (bit_cnt < 8) begin
                            AD_din <= CLK_REG_CMD[7 - (bit_cnt % 8)];
                        end else begin
                            AD_din <= CLK_REG_VAL[7 - (bit_cnt % 8)];
                        end
                        
                        bit_cnt <= bit_cnt + 1;
                    end
                end else begin
                    bit_cnt <= 0;
                    AD_din <= 1'b0;
                    delay_cnt <= 0;
                    current_state <= S_DELAY2;
                end
            end
            
            S_DELAY2: begin
                AD_CS <= 1'b1;
                AD_din <= 1'b0;
                spi_active <= 1'b0;
                
                if (delay_cnt < 32'd4_000_000) begin  // 20ms
                    delay_cnt <= delay_cnt + 1;
                end else begin
                    delay_cnt <= 0;
                    current_state <= S_WRITE_SETREG;
                end
            end
            
            S_WRITE_SETREG: begin
                AD_CS <= 1'b0;
                spi_active <= 1'b1;
                
                if (bit_cnt < 16) begin
                    if (spi_clk_en) begin
                        if (bit_cnt < 8) begin
                            AD_din <= SETUP_REG_CMD[7 - (bit_cnt % 8)];
                        end else begin
                            AD_din <= SETUP_REG_VAL[7 - (bit_cnt % 8)];
                        end
                        
                        bit_cnt <= bit_cnt + 1;
                    end
                end else begin
                    bit_cnt <= 0;
                    AD_din <= 1'b0;
                    delay_cnt <= 0;
                    current_state <= S_DELAY3;
                end
            end
            
            S_DELAY3: begin
                AD_CS <= 1'b1;
                AD_din <= 1'b0;
                spi_active <= 1'b0;
                
                if (delay_cnt < 32'd4_000_000) begin  // 20ms
                    delay_cnt <= delay_cnt + 1;
                end else begin
                    delay_cnt <= 0;
                    current_state <= S_WAIT_CALIB;
                end
            end
            
            S_WAIT_CALIB: begin
                // Wait for calibration (для 500Hz фильтра ~12ms)
                if (delay_cnt < 32'd2_400_000) begin  // 12ms
                    delay_cnt <= delay_cnt + 1;
                end else begin
                    delay_cnt <= 0;
                    current_state <= S_CHECK_DRDY;
                end
            end
            
            S_CHECK_DRDY: begin
                if (AD_DRDY_n == 1'b0) begin
                    current_state <= S_READ_DATA;
                end else begin
                    if (delay_cnt < 32'd20_000_000) begin  // 100ms таймаут
                        delay_cnt <= delay_cnt + 1;
                    end else begin
                        delay_cnt <= 0;
                        current_state <= S_READ_DATA;
                    end
                end
            end
            
            S_READ_DATA: begin
                AD_CS <= 1'b0;
                spi_active <= 1'b1;
                
                if (bit_cnt < 24) begin  // Send read command + read 16 bits
                    if (spi_clk_en) begin
                        if (bit_cnt < 8) begin
                            AD_din <= READ_DATA_CMD[7 - (bit_cnt % 8)];
                        end else begin
                            AD_din <= 1'b0;  // Dummy data for read
                        end
                        
                        if (bit_cnt >= 8) begin
                            rx_data <= {rx_data[14:0], AD_dout};
                        end
                        
                        bit_cnt <= bit_cnt + 1;
                    end
                end else begin
                    ad_data_hex <= rx_data;
                    bit_cnt <= 0;
                    AD_din <= 1'b0;
                    AD_CS <= 1'b1;
                    spi_active <= 1'b0;
                    rx_data <= 16'd0;
                    delay_cnt <= 0;
                    current_state <= S_WAIT_NEXT;
                end
            end
            
            S_WAIT_NEXT: begin
                if (delay_cnt < 32'd1_400_000) begin  // 7ms
                    delay_cnt <= delay_cnt + 1;
                end else begin
                    delay_cnt <= 0;
                    current_state <= S_CHECK_DRDY;
                end
            end
            
            default: begin
                current_state <= S_IDLE;
            end
        endcase
    end
end

endmodule