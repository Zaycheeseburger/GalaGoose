`timescale 1ns / 1ps

module sync_rom #(
    parameter integer ADDR_WIDTH = 10,
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 1024,
    parameter         INIT_FILE  = ""
)(
    input  wire                    clk,
    input  wire [ADDR_WIDTH-1:0]   addr,
    output reg  [DATA_WIDTH-1:0]   dout
);
    (* rom_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        dout <= mem[addr];
    end
endmodule


module sync_dp_rom #(
    parameter integer ADDR_WIDTH = 13,
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 6144,
    parameter         INIT_FILE  = ""
)(
    input  wire                    clk,
    input  wire [ADDR_WIDTH-1:0]   addr_a,
    output reg  [DATA_WIDTH-1:0]   dout_a,
    input  wire [ADDR_WIDTH-1:0]   addr_b,
    output reg  [DATA_WIDTH-1:0]   dout_b
);
    (* rom_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        dout_a <= mem[addr_a];
        dout_b <= mem[addr_b];
    end
endmodule


module hud_tile_ram (
    input  wire        clk,
    // Port A: Display Renderer scanout
    input  wire [12:0] addr_a,
    output reg  [11:0] dout_a,
    // Port B: Game Engine HUD writer
    input  wire        we_b,
    input  wire [12:0] addr_b,
    input  wire [11:0] din_b
);
    (* ram_style = "block" *) reg [11:0] mem [0:8191];

    integer k_init;
    initial begin
        for (k_init = 0; k_init < 8192; k_init = k_init + 1)
            mem[k_init] = 12'h020; // space char, color 0
    end

    always @(posedge clk) begin
        dout_a <= mem[addr_a];
        if (we_b)
            mem[addr_b] <= din_b;
    end
endmodule
