`timescale 1ns/1ps
module tb_regfile;
    reg        clk = 0, rst_n = 0, wr_en = 0;
    reg  [6:0] wr_addr = 0, rd_addr = 0;
    reg  [7:0] wr_data = 0;
    wire [7:0] rd_data;
    integer    errors = 0;
    integer    wr_count = 0;

    regfile dut (.clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_addr(wr_addr),
                 .wr_data(wr_data), .rd_addr(rd_addr), .rd_data(rd_data));

    always #5 clk = ~clk;   // 100 MHz

    task do_write(input [6:0] a, input [7:0] d);
    begin
        @(negedge clk); wr_en = 1; wr_addr = a; wr_data = d;
        @(negedge clk); wr_en = 0;
        wr_count = wr_count + 1;
    end
    endtask

    task check_read(input [6:0] a, input [7:0] expected);
    begin
        rd_addr = a; #1;
        if (rd_data !== expected) begin
            $display("FAIL: addr 0x%02h expected 0x%02h got 0x%02h", a, expected, rd_data);
            errors = errors + 1;
        end else
            $display("PASS: addr 0x%02h = 0x%02h", a, rd_data);
    end
    endtask

    initial begin
        #20 rst_n = 1;
        check_read(7'h00, 8'hA5);                 // T1: ID after reset
        do_write(7'h01, 8'h5A); check_read(7'h01, 8'h5A);   // T2: RW register
        do_write(7'h0F, 8'hC3); check_read(7'h0F, 8'hC3);
        do_write(7'h00, 8'hFF); check_read(7'h00, 8'hA5);   // T3: RO write ignored
        do_write(7'h20, 8'hAB); check_read(7'h20, 8'h00);   // T4: unmapped
        check_read(7'h02, wr_count[7:0]);          // T5: STATUS counts writes

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule