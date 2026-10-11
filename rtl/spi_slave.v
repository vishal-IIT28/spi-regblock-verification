`timescale 1ns/1ps
module spi_slave (
    input  wire clk,
    input  wire rst_n,
    input  wire sclk,
    input  wire cs_n,
    input  wire mosi,
    output reg  miso
);
    // ---- 1) Synchronize async SPI inputs into the clk domain ----
    reg [2:0] sclk_s, cs_s, mosi_s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_s <= 3'b000;
            cs_s   <= 3'b111;
            mosi_s <= 3'b000;
        end else begin
            sclk_s <= {sclk_s[1:0], sclk};
            cs_s   <= {cs_s[1:0],   cs_n};
            mosi_s <= {mosi_s[1:0], mosi};
        end
    end

    wire sclk_rise = (sclk_s[2:1] == 2'b01);   // synchronized edge detect
    wire sclk_fall = (sclk_s[2:1] == 2'b10);
    wire cs_active = ~cs_s[1];
    wire mosi_in   = mosi_s[1];

    // ---- 2) Frame state ----
    reg [4:0] bit_cnt;       // rising edges received this frame (0..16)
    reg [7:0] rx, tx;        // receive / transmit shift registers
    reg [6:0] addr_l;        // latched address
    reg       rw_l;          // latched R/W bit (1 = write)
    reg       wr_en_r;       // one-cycle write pulse to regfile
    reg [7:0] wr_data_r;
    wire [7:0] rd_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 5'd0; rx <= 8'h00; tx <= 8'h00;
            addr_l <= 7'h00; rw_l <= 1'b0;
            wr_en_r <= 1'b0; wr_data_r <= 8'h00; miso <= 1'b0;
        end else begin
            wr_en_r <= 1'b0;                      // default: no write
            if (!cs_active) begin                 // frame ended or aborted
                bit_cnt <= 5'd0;
                miso    <= 1'b0;
            end else if (sclk_rise) begin         // sample on rising edge
                if (bit_cnt < 5'd16) begin
                    rx      <= {rx[6:0], mosi_in};
                    bit_cnt <= bit_cnt + 5'd1;
                    if (bit_cnt == 5'd7) begin    // 8th edge: RW + ADDR complete
                        rw_l   <= rx[6];
                        addr_l <= {rx[5:0], mosi_in};
                    end
                    if (bit_cnt == 5'd15 && rw_l) begin   // 16th edge of a write
                        wr_en_r   <= 1'b1;
                        wr_data_r <= {rx[6:0], mosi_in};
                    end
                end
            end else if (sclk_fall) begin         // change MISO on falling edge
                if (!rw_l && bit_cnt == 5'd8) begin
                    miso <= rd_data[7];
                    tx   <= {rd_data[6:0], 1'b0};
                end else if (!rw_l && bit_cnt > 5'd8 && bit_cnt <= 5'd15) begin
                    miso <= tx[7];
                    tx   <= {tx[6:0], 1'b0};
                end else begin
                    miso <= 1'b0;
                end
            end
        end
    end

    // ---- 3) Register file ----
    regfile u_regfile (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en_r), .wr_addr(addr_l), .wr_data(wr_data_r),
        .rd_addr(addr_l), .rd_data(rd_data)
    );
endmodule