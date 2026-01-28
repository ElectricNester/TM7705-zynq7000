`timescale 1ns / 1ps

module AD7705_driver_zynq_tb();
    
    // Test signals
    reg clk_p = 0;
    reg clk_n = 1;
    reg sysrst = 0;
    reg AD_DRDY_n = 1;
    reg AD_dout = 0;
    
    // Outputs
    wire [15:0] ad_data_out;
    wire AD_CS;
    wire AD_clk;
    wire AD_din;
    
    // Instantiate DUT
    AD7705_driver_zynq dut (
        .clk_p(clk_p),
        .clk_n(clk_n),
        .sysrst(sysrst),
        .ad_data_out(ad_data_out),
        .AD_DRDY_n(AD_DRDY_n),
        .AD_dout(AD_dout),
        .AD_CS(AD_CS),
        .AD_clk(AD_clk),
        .AD_din(AD_din)
    );
    
    // Generate differential clock (200MHz) - period 5ns
    always #2.5 begin
        clk_p = ~clk_p;
        clk_n = ~clk_n;
    end
    
    // Simulate AD7705 data output
    reg [15:0] sim_data = 16'hABCD;
    reg [4:0] bit_cnt = 0;
    
    always @(negedge AD_clk) begin
        if (dut.spi_enable && dut.current_state == dut.S_READ_DATA) begin
            if (bit_cnt >= 8 && bit_cnt < 24) begin
                AD_dout <= sim_data[23 - bit_cnt];  // MSB first
                bit_cnt <= bit_cnt + 1;
            end else if (bit_cnt == 24) begin
                bit_cnt <= 0;
                sim_data <= sim_data + 16'h111;  // Change data
            end else begin
                bit_cnt <= bit_cnt + 1;
            end
        end else begin
            bit_cnt <= 0;
        end
    end
    
    // Simulate DRDY signal
    reg [31:0] drdy_counter = 0;
    
    // Generate DRDY pulse every ~10ms (for 100Hz)
    always @(posedge dut.clk_50M) begin
        if (sysrst) begin
            drdy_counter <= drdy_counter + 1;
            
            if (drdy_counter >= 32'd500_000) begin  // 10ms at 50MHz
                AD_DRDY_n <= 0;
                #1000;  // Hold low for 1us
                AD_DRDY_n <= 1;
                drdy_counter <= 0;
            end
        end
    end
    
    // Main test sequence
    initial begin
        // Initialize
        $display("========================================");
        $display("AD7705 Driver Test for Zynq 7000");
        $display("Clock: 200 MHz differential LVDS");
        $display("Time: %t", $time);
        $display("========================================");
        
        // Apply reset
        sysrst = 0;
        #100;
        sysrst = 1;
        $display("[%t] Reset released", $time);
        
        // Wait for initialization and calibration
        #100_000_000;  // 100ms
        
        // Monitor for data readings
        repeat (20) begin
            wait(AD_DRDY_n == 0);
            $display("[%t] DRDY active - Data: 0x%04X", $time, ad_data_out);
            #5_000_000;  // Wait 5ms
        end
        
        $display("========================================");
        $display("Test Complete");
        $display("========================================");
        $finish;
    end
    
    // Monitor signals
    initial begin
        $monitor("Time: %t, State: %d, Data: 0x%04X, SCLK: %b, MOSI: %b, MISO: %b",
                $time, dut.current_state, ad_data_out, AD_clk, AD_din, AD_dout);
    end
    
    // VCD dump for debugging
    initial begin
        $dumpfile("ad7705_zynq_200mhz.vcd");
        $dumpvars(0, AD7705_driver_zynq_tb);
    end
    
endmodule