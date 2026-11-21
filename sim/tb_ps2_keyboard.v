`timescale 1ns/1ps

module tb_ps2_keyboard;
    reg clk;
    reg rst_n;
    reg ps2_clk;
    reg ps2_data;
    wire [4:0] kbd_btn;
    wire       kbd_link_ok;
    wire [7:0] last_scan_code;

    ps2_keyboard dut (
        .clk(clk),
        .rst_n(rst_n),
        .ps2_clk(ps2_clk),
        .ps2_data(ps2_data),
        .kbd_btn(kbd_btn),
        .kbd_link_ok(kbd_link_ok),
        .last_scan_code(last_scan_code)
    );

    always #20 clk = ~clk; // 25 MHz (40 ns period)

    task send_ps2_byte(input [7:0] byte_val);
        integer i;
        reg parity;
        begin
            parity = ~(^byte_val); // odd parity
            // Start bit
            ps2_data = 1'b0;
            #1000; ps2_clk = 1'b0; #20000; ps2_clk = 1'b1; #20000;
            // 8 data bits LSB first
            for (i = 0; i < 8; i = i + 1) begin
                ps2_data = byte_val[i];
                #1000; ps2_clk = 1'b0; #20000; ps2_clk = 1'b1; #20000;
            end
            // Parity bit
            ps2_data = parity;
            #1000; ps2_clk = 1'b0; #20000; ps2_clk = 1'b1; #20000;
            // Stop bit
            ps2_data = 1'b1;
            #1000; ps2_clk = 1'b0; #20000; ps2_clk = 1'b1; #20000;
            #50000; // Idle gap
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        ps2_clk = 1;
        ps2_data = 1;
        #200;
        rst_n = 1;
        #1000;

        $display("--- Test 1: Send 'W' make (0x1D) ---");
        send_ps2_byte(8'h1D);
        #1000;
        $display("last_scan_code: 0x%02h (expected 1D), kbd_btn[0] (Up): %b", last_scan_code, kbd_btn[0]);
        if (last_scan_code !== 8'h1D || kbd_btn[0] !== 1'b1) $fatal(1, "Test 1 failed!");

        $display("--- Test 2: Send 'W' break (0xF0, 0x1D) ---");
        send_ps2_byte(8'hF0);
        #1000;
        send_ps2_byte(8'h1D);
        #1000;
        $display("last_scan_code: 0x%02h, kbd_btn[0] (Up): %b", last_scan_code, kbd_btn[0]);
        if (last_scan_code !== 8'h1D || kbd_btn[0] !== 1'b0) $fatal(1, "Test 2 failed!");

        $display("--- Test 3: Send 'A' make (0x1C) ---");
        send_ps2_byte(8'h1C);
        #1000;
        $display("last_scan_code: 0x%02h (expected 1C), kbd_btn[2] (Left): %b", last_scan_code, kbd_btn[2]);
        if (last_scan_code !== 8'h1C || kbd_btn[2] !== 1'b1) $fatal(1, "Test 3 failed!");

        $display("--- Test 4: Send 'S' make (0x1B) ---");
        send_ps2_byte(8'h1B);
        #1000;
        $display("last_scan_code: 0x%02h (expected 1B), kbd_btn[1] (Down): %b", last_scan_code, kbd_btn[1]);
        if (last_scan_code !== 8'h1B || kbd_btn[1] !== 1'b1) $fatal(1, "Test 4 failed!");

        $display("--- Test 5: Send 'D' make (0x23) ---");
        send_ps2_byte(8'h23);
        #1000;
        $display("last_scan_code: 0x%02h (expected 23), kbd_btn[3] (Right): %b", last_scan_code, kbd_btn[3]);
        if (last_scan_code !== 8'h23 || kbd_btn[3] !== 1'b1) $fatal(1, "Test 5 failed!");

        $display("--- Test 6: Send 'Enter' make (0x5A) ---");
        send_ps2_byte(8'h5A);
        #1000;
        $display("last_scan_code: 0x%02h (expected 5A), kbd_btn[4] (Fire): %b", last_scan_code, kbd_btn[4]);
        if (last_scan_code !== 8'h5A || kbd_btn[4] !== 1'b1) $fatal(1, "Test 6 failed!");

        $display("ALL PS/2 TESTS PASSED SUCCESSFULLY!");
        $finish;
    end
endmodule
