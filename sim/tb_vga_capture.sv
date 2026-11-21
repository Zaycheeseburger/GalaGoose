`timescale 1ns / 1ps

module tb_vga_capture;
    reg         CLK100MHZ = 1'b0;
    reg         CPU_RESETN = 1'b0;
    reg         BTNC = 1'b0, BTNU = 1'b0, BTNL = 1'b0, BTNR = 1'b0, BTND = 1'b0;
    reg  [15:0] SW = 16'd0;
    wire [15:0] LED;
    wire        LED16_R, LED16_G, LED16_B, LED17_R, LED17_G, LED17_B;
    wire [7:0]  AN;
    wire        CA, CB, CC, CD, CE, CF, CG, DP;
    wire [3:0]  VGA_R, VGA_G, VGA_B;
    wire        VGA_HS, VGA_VS;
    wire        AUD_PWM, AUD_SD;
    reg         ACL_MISO = 1'b0;
    wire        ACL_MOSI, ACL_SCLK, ACL_CSN;
    reg         UART_TXD_IN = 1'b1;

    always #5 CLK100MHZ = ~CLK100MHZ;

    space_shooter_top #(
        .POR_CYCLES(10),
        .DEBOUNCE_MAX(4)
    ) dut (
        .CLK100MHZ(CLK100MHZ),
        .CPU_RESETN(CPU_RESETN),
        .BTNC(BTNC), .BTNU(BTNU), .BTNL(BTNL), .BTNR(BTNR), .BTND(BTND),
        .SW(SW),
        .LED(LED),
        .LED16_R(LED16_R), .LED16_G(LED16_G), .LED16_B(LED16_B),
        .LED17_R(LED17_R), .LED17_G(LED17_G), .LED17_B(LED17_B),
        .AN(AN), .CA(CA), .CB(CB), .CC(CC), .CD(CD), .CE(CE), .CF(CF), .CG(CG), .DP(DP),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .AUD_PWM(AUD_PWM), .AUD_SD(AUD_SD),
        .ACL_MISO(ACL_MISO), .ACL_MOSI(ACL_MOSI), .ACL_SCLK(ACL_SCLK), .ACL_CSN(ACL_CSN),
        .PS2_CLK(1'b1), .PS2_DATA(1'b1),
        .UART_TXD_IN(UART_TXD_IN)
    );

    task wait_frames;
        input integer n;
        integer f;
        begin
            for (f = 0; f < n; f = f + 1) begin
                repeat (12) @(posedge dut.clk_25m);
                force dut.u_vga_sync.h_cnt = 10'd799;
                force dut.u_vga_sync.v_cnt = 10'd479;
                @(negedge dut.clk_25m);
                release dut.u_vga_sync.h_cnt;
                release dut.u_vga_sync.v_cnt;
                @(posedge dut.game_tick);
                wait (dut.u_engine.phase != 4'd0);
                wait (dut.u_engine.phase == 4'd0);
                repeat (10) @(posedge dut.clk_25m);
            end
        end
    endtask

    task trigger_wave_clear;
        begin
            force dut.u_engine.en_active = 16'd0;
            force dut.u_vga_sync.h_cnt = 10'd799;
            force dut.u_vga_sync.v_cnt = 10'd479;
            @(negedge dut.clk_25m);
            release dut.u_vga_sync.h_cnt;
            release dut.u_vga_sync.v_cnt;
            wait (dut.u_engine.phase == 4'd11); // PH_INIT_WAVE
            release dut.u_engine.en_active;
            wait (dut.u_engine.phase == 4'd0);  // PH_IDLE
            repeat (10) @(posedge dut.clk_25m);
        end
    endtask

    // Capture exactly 640x480 active pixels synchronized by renderer output pipeline (s4_act)
    // Using VGA_VS falling edge to start frame, then tracking active scanlines by timing
    task capture_ppm;
        input [256*8-1:0] filename;
        integer fd, px_cnt;
        begin
            fd = $fopen(filename, "w");
            $fwrite(fd, "P3\n640 480\n15\n");
            // Wait for exact frame start after vsync pulse, then capture 307,200 active pixels
            @(negedge VGA_VS);
            px_cnt = 0;
            while (px_cnt < 640 * 480) begin
                @(posedge dut.clk_25m);
                if (dut.u_renderer.s4_act) begin
                    #1; // sample newly latched VGA_R/G/B output flip-flops
                    $fwrite(fd, "%0d %0d %0d\n", VGA_R, VGA_G, VGA_B);
                    px_cnt = px_cnt + 1;
                end
            end
            $fclose(fd);
            $display("Captured %s (%0d pixels)", filename, px_cnt);
        end
    endtask

    initial begin
        CPU_RESETN = 1'b0;
        #1000;
        CPU_RESETN = 1'b1;
        wait(dut.rst_n == 1'b1);
        wait_frames(3);

        // 0. Title Screen
        capture_ppm("frame_0_title.ppm");

        // 1. Launch Wave 1 -> wait for enemies to enter formation -> fire & capture
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(2);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0;
        wait_frames(45);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0;
        wait_frames(4);
        capture_ppm("frame_1_wave1.ppm");

        // 2. Wave 2 (all 4 face enemies: pf, ppuen, ppeem, pping) + Form 2 Blue Goose
        trigger_wave_clear(); // clears Wave 1 -> Wave 2, Form 2
        wait_frames(1);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; // skip intro
        wait_frames(75);
        BTNC = 1'b1; wait_frames(3); BTNC = 1'b0;
        wait_frames(5);
        capture_ppm("frame_2_blue_wave2.ppm");

        // 3. Form 3 Rainbow Goose 8-way Nova shot!
        force dut.u_engine.player_form = 2'd2;
        force dut.u_engine.player_y = 10'd300;
        wait_frames(2);
        release dut.u_engine.player_y;
        wait_frames(15);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0;
        wait_frames(8);
        capture_ppm("frame_3_rainbow_8way.ppm");
        release dut.u_engine.player_form;

        // 4. Wave 4 Boss AJV!
        trigger_wave_clear(); // Wave 2 -> Wave 3
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0;
        trigger_wave_clear(); // Wave 3 -> Wave 4 (Boss AJV)
        wait_frames(1);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; // skip boss intro
        wait_frames(60);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0;
        wait_frames(6);
        capture_ppm("frame_4_boss_ajv.ppm");

        // 5. Victory Screen
        force dut.u_engine.boss_hp = 7'd1;
        force dut.u_engine.boss_active = 1'b0;
        force dut.u_engine.en_active = 16'd0;
        wait_frames(2);
        release dut.u_engine.boss_hp;
        release dut.u_engine.boss_active;
        release dut.u_engine.en_active;
        wait_frames(2);
        capture_ppm("frame_5_victory.ppm");

        $display("VGA CAPTURE COMPLETE");
        $finish;
    end
endmodule
