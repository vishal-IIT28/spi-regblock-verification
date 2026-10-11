`timescale 1ns/1ps
module tb_spi_slave;
    localparam HALF = 80;      // SCLK half period (ns): SCLK = clk/16
    reg clk = 0, rst_n = 0, sclk = 0, cs_n = 1, mosi = 0;
    wire miso;
    integer errors = 0;
    integer wr_count = 0;
    reg [15:0] rxd;

    spi_slave dut (.clk(clk), .rst_n(rst_n), .sclk(sclk),
                   .cs_n(cs_n), .mosi(mosi), .miso(miso));

    always #5 clk = ~clk;      // 100 MHz

    // Sends nbits of txd (MSB first), captures MISO into rxd
    task spi_xfer(input [15:0] txd, input integer nbits);
        integer i;
    begin
        rxd = 16'h0000;
        cs_n = 0;
        #40;
        for (i = 15; i > 15 - nbits; i = i - 1) begin
            mosi = txd[i];          // change on falling edge
            #HALF;
            rxd[i] = miso;          // sample on rising edge
            sclk = 1;
            #HALF;
            sclk = 0;
        end
        #HALF;
        cs_n = 1;
        mosi = 0;
        #100;
    end
    endtask

    task do_write(input [6:0] a, input [7:0] d);
    begin
        spi_xfer({1'b1, a, d}, 16);
        wr_count = wr_count + 1;
    end
    endtask

    task check_read(input [6:0] a, input [7:0] expected);
    begin
        spi_xfer({1'b0, a, 8'h00}, 16);
        if (rxd[7:0] !== expected) begin
            $display("FAIL: read 0x%02h expected 0x%02h got 0x%02h", a, expected, rxd[7:0]);
            errors = errors + 1;
        end else
            $display("PASS: read 0x%02h = 0x%02h", a, rxd[7:0]);
    end
    endtask

    initial begin
        #30 rst_n = 1;
        #50;
        check_read(7'h00, 8'hA5);                           // T1: ID
        do_write(7'h01, 8'h5A); check_read(7'h01, 8'h5A);   // T2: RW
        do_write(7'h0F, 8'hC3); check_read(7'h0F, 8'hC3);
        do_write(7'h00, 8'hFF); check_read(7'h00, 8'hA5);   // T3: RO ignored
        do_write(7'h20, 8'hAB); check_read(7'h20, 8'h00);   // T4: unmapped
        spi_xfer({1'b1, 7'h07, 8'hFF}, 10);                 // T6: aborted write
        check_read(7'h07, 8'h00);
        check_read(7'h02, wr_count[7:0]);                   // T5: STATUS count

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule