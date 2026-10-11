`timescale 1ns/1ps

module regfile (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       wr_en,     // one-cycle pulse: a write frame completed
    input  wire [6:0] wr_addr,
    input  wire [7:0] wr_data,
    input  wire [6:0] rd_addr,
    output reg  [7:0] rd_data
);
    localparam [7:0] ID_VAL = 8'hA5;

    reg [7:0] mem [0:15];        // index 0 (ID) and 2 (STATUS) are not used
    reg [7:0] status_cnt;        // counts completed write frames
    integer i;

    // Write side
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) mem[i] <= 8'h00;
            status_cnt <= 8'h00;
        end else if (wr_en) begin
            status_cnt <= status_cnt + 8'd1;   // counts every completed write
            // only 0x01 and 0x03..0x0F are writable
            if (wr_addr <= 7'h0F && wr_addr != 7'h00 && wr_addr != 7'h02)
                mem[wr_addr[3:0]] <= wr_data;
        end
    end

    // Read side (combinational)
    always @(*) begin
        case (rd_addr)
            7'h00:   rd_data = ID_VAL;
            7'h02:   rd_data = status_cnt;
            default: rd_data = (rd_addr <= 7'h0F) ? mem[rd_addr[3:0]] : 8'h00;
        endcase
    end
endmodule