`timescale 1ns / 1ps

module clk_gen #(
    parameter integer POR_CYCLES = 20'd500000
)(
    input  wire clk_100m,
    input  wire cpu_resetn,
    output wire clk_25m,
    output reg  rst_n
);
    wire mmcm_locked;

`ifdef SIMULATION
    // Fast 100 MHz -> 25 MHz divider for behavioral simulation
    reg [1:0] div_cnt = 2'd0;
    reg       clk_25m_sim = 1'b0;
    always @(posedge clk_100m) begin
        div_cnt <= div_cnt + 2'd1;
        if (div_cnt == 2'd1 || div_cnt == 2'd3)
            clk_25m_sim <= ~clk_25m_sim;
    end
    assign clk_25m     = clk_25m_sim;
    assign mmcm_locked = 1'b1;
`else
    wire clkfb_out;
    wire clkfb_buf;
    wire clk25_unbuf;
    wire clk100_ibuf;

    IBUF u_ibuf_clk (
        .I(clk_100m),
        .O(clk100_ibuf)
    );

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(10.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE_F(40.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKOUT0(clk25_unbuf),
        .CLKFBOUT(clkfb_out),
        .LOCKED(mmcm_locked),
        .CLKIN1(clk100_ibuf),
        .PWRDWN(1'b0),
        .RST(1'b0),
        .CLKFBIN(clkfb_buf)
    );

    BUFG u_bufg_fb (
        .I(clkfb_out),
        .O(clkfb_buf)
    );

    BUFG u_bufg_25m (
        .I(clk25_unbuf),
        .O(clk_25m)
    );
`endif

    // Synchronize external active-low reset and hold rst_n low briefly after lock
    reg [1:0]  rst_sync = 2'b00;
    reg [19:0] por_cnt  = 20'd0;

    always @(posedge clk_25m) begin
        rst_sync <= {rst_sync[0], (cpu_resetn & mmcm_locked)};
        if (!rst_sync[1]) begin
            por_cnt <= 20'd0;
            rst_n   <= 1'b0;
        end else if (por_cnt < POR_CYCLES) begin
            por_cnt <= por_cnt + 20'd1;
            rst_n   <= 1'b0;
        end else begin
            rst_n   <= 1'b1;
        end
    end
endmodule
