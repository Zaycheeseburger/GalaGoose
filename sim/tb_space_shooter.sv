`timescale 1ns / 1ps

module tb_space_shooter;
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

    always #5 CLK100MHZ = ~CLK100MHZ; // 100 MHz

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

    integer fail_cnt = 0;

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
            $display("[trigger_wave_clear] entry: state=%d phase=%d wave=%d",
                     dut.u_engine.game_state, dut.u_engine.phase, dut.u_engine.wave_num);
            force dut.u_engine.en_active = 16'd0;
            force dut.u_vga_sync.h_cnt = 10'd799;
            force dut.u_vga_sync.v_cnt = 10'd479;
            @(negedge dut.clk_25m);
            release dut.u_vga_sync.h_cnt;
            release dut.u_vga_sync.v_cnt;
            @(posedge dut.clk_25m);
            $display("[trigger_wave_clear] after tick: state=%d phase=%d game_tick=%b",
                     dut.u_engine.game_state, dut.u_engine.phase, dut.game_tick);
            wait (dut.u_engine.phase == 4'd11); // PH_INIT_WAVE
            $display("[trigger_wave_clear] reached PH_INIT_WAVE");
            release dut.u_engine.en_active;
            wait (dut.u_engine.phase == 4'd0);  // PH_IDLE
            repeat (10) @(posedge dut.clk_25m);
        end
    endtask

    task send_uart_byte;
        input [7:0] b;
        integer i;
        begin
            UART_TXD_IN = 1'b0; // Start bit
            #(8680);
            for (i = 0; i < 8; i = i + 1) begin
                UART_TXD_IN = b[i];
                #(8680);
            end
            UART_TXD_IN = 1'b1; // Stop bit
            #(8680);
        end
    endtask

    function integer count_pb;
        input [31:0] mask;
        integer k;
        begin
            count_pb = 0;
            for (k = 0; k < 32; k = k + 1)
                count_pb = count_pb + mask[k];
        end
    endfunction

    function integer count_eb;
        input [23:0] mask;
        integer k;
        begin
            count_eb = 0;
            for (k = 0; k < 24; k = k + 1)
                count_eb = count_eb + mask[k];
        end
    endfunction

    integer pb_c, eb_c;
    integer k_pb_chk;
    reg [9:0] prev_px, prev_py;

    initial begin
        // Watchdog timeout (100ms sim time)
        #100000000;
        $display("TIMEOUT FAILURE!");
        $finish;
    end

    initial begin
        CPU_RESETN = 1'b0;
        #1000;
        CPU_RESETN = 1'b1;
        wait(dut.rst_n == 1'b1);
        $display("[TB] Step 0: Reset released.");
        wait_frames(2);

        // 1. Verify non-X VGA & Audio outputs
        $display("[TB] Step 1: Checking non-X outputs...");
        if (^VGA_R === 1'bx || ^VGA_G === 1'bx || ^VGA_B === 1'bx ||
            VGA_HS === 1'bx || VGA_VS === 1'bx || AUD_PWM === 1'bx) begin
            $display("ERROR: X detected on VGA/Audio!");
            fail_cnt = fail_cnt + 1;
        end

        // 2. Title Screen & Menu Selection (< NORMAL > -> < HARD > -> < NORMAL >)
        $display("[TB] Step 2: Testing Title Screen...");
        if (dut.u_engine.game_state !== 3'd0) begin
            $display("ERROR: Expected GS_TITLE(0), got %d", dut.u_engine.game_state);
            fail_cnt = fail_cnt + 1;
        end
        BTNR = 1'b1; wait_frames(2); BTNR = 1'b0; wait_frames(1);
        if (dut.u_engine.menu_hard_sel !== 1'b1) begin
            $display("ERROR: Menu hard select toggle failed!");
            fail_cnt = fail_cnt + 1;
        end
        BTNL = 1'b1; wait_frames(2); BTNL = 1'b0; wait_frames(1);

        // 3. Start Game -> Intro -> Play
        $display("[TB] Step 3: Starting game...");
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(2);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(2); // skip wave intro
        if (dut.u_engine.game_state !== 3'd2) begin
            $display("ERROR: Expected GS_PLAY(2), got %d", dut.u_engine.game_state);
            fail_cnt = fail_cnt + 1;
        end
        force dut.u_engine.player_invuln = 8'd255;
        force dut.u_engine.player_lives = 3'd3;

        // 4. Test Form 1 Single Shot + UART Input
        $display("[TB] Step 4: Testing Form 1 and UART...");
        prev_px = dut.u_engine.player_x;
        send_uart_byte(8'b100_1_0100); // fire + left
        wait_frames(2);
        if (!dut.uart_link_ok || dut.u_engine.player_x >= prev_px) begin
            $display("ERROR: UART control failed! link=%b px=%d prev=%d",
                     dut.uart_link_ok, dut.u_engine.player_x, prev_px);
            fail_cnt = fail_cnt + 1;
        end
        pb_c = count_pb(dut.u_engine.pb_active);
        if (pb_c < 1) begin
            $display("ERROR: Form 1 failed to spawn bullet!");
            fail_cnt = fail_cnt + 1;
        end
        send_uart_byte(8'h80); // release UART fire + left buttons

        // 4.1 Test ASCII Keyboard Control via UART ('w'=Up, 'd'=Right, 's'=Left, 'a'=Down, Enter=Fire)
        $display("[TB] Step 4.1: Testing ASCII Keyboard via UART...");
        SW[5] = 1'b1; // Enable Keyboard mode
        wait_frames(2);
        prev_py = dut.u_engine.player_y;
        send_uart_byte(8'h77); // 'w' -> Up
        wait_frames(3);
        if (dut.u_engine.player_y >= prev_py) begin
            $display("ERROR: ASCII Keyboard 'w' (Up) failed! py=%d prev=%d", dut.u_engine.player_y, prev_py);
            fail_cnt = fail_cnt + 1;
        end
        prev_px = dut.u_engine.player_x;
        send_uart_byte(8'h64); // 'd' -> Right
        wait_frames(3);
        if (dut.u_engine.player_x <= prev_px) begin
            $display("ERROR: ASCII Keyboard 'd' (Right) failed! px=%d prev=%d", dut.u_engine.player_x, prev_px);
            fail_cnt = fail_cnt + 1;
        end
        prev_px = dut.u_engine.player_x;
        send_uart_byte(8'h73); // 's' -> Left (Prompt layout)
        wait_frames(3);
        if (dut.u_engine.player_x >= prev_px) begin
            $display("ERROR: ASCII Keyboard 's' (Left) failed! px=%d prev=%d", dut.u_engine.player_x, prev_px);
            fail_cnt = fail_cnt + 1;
        end
        prev_py = dut.u_engine.player_y;
        send_uart_byte(8'h61); // 'a' -> Down (Prompt layout)
        wait_frames(3);
        if (dut.u_engine.player_y <= prev_py) begin
            $display("ERROR: ASCII Keyboard 'a' (Down) failed! py=%d prev=%d", dut.u_engine.player_y, prev_py);
            fail_cnt = fail_cnt + 1;
        end
        SW[5] = 1'b0;
        force dut.uart_w_timer = 24'd0; force dut.uart_a_timer = 24'd0;
        force dut.uart_s_timer = 24'd0; force dut.uart_d_timer = 24'd0; force dut.uart_enter_timer = 24'd0;
        @(posedge dut.clk_25m);
        release dut.uart_w_timer; release dut.uart_a_timer;
        release dut.uart_s_timer; release dut.uart_d_timer; release dut.uart_enter_timer;

        // 4b. Test ADXL362 Gyro/Tilt Orientation (VGA connector at TOP)
        $display("[TB] Step 4b: Testing ADXL362 Gyro...");
        SW[2] = 1'b1;
        prev_px = dut.u_engine.player_x;
        prev_py = dut.u_engine.player_y;
        force dut.accel_x = -8'sd30; // Tilt VGA edge down -> move UP
        force dut.accel_y =  8'sd30; // Tilt Left edge down -> move LEFT
        wait_frames(3);
        release dut.accel_x;
        release dut.accel_y;
        SW[2] = 1'b0;
        if (dut.u_engine.player_y >= prev_py || dut.u_engine.player_x >= prev_px) begin
            $display("ERROR: ADXL362 VGA-top orientation failed! px=%d(prev %d) py=%d(prev %d)",
                     dut.u_engine.player_x, prev_px, dut.u_engine.player_y, prev_py);
            fail_cnt = fail_cnt + 1;
        end

        // 5. Test Form 2 (Blue Goose: 2 bullets) via Wave 1 clear milestone evolution
        $display("[TB] Step 5: Wave 1 Clear -> Form 2...");
        trigger_wave_clear();
        wait_frames(1);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(15); // skip intro & wait fire_cd
        if (dut.u_engine.player_form !== 2'd1) begin
            $display("ERROR: Expected Form 2 (Blue=1), got %d", dut.u_engine.player_form);
            fail_cnt = fail_cnt + 1;
        end
        force dut.u_engine.pb_active = 32'd0;
        @(posedge dut.clk_25m);
        release dut.u_engine.pb_active;
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0;
        pb_c = count_pb(dut.u_engine.pb_active);
        if (pb_c < 2) begin
            $display("ERROR: Form 2 expected >=2 bullets, got %d", pb_c);
            fail_cnt = fail_cnt + 1;
        end

        // 6. Test Form 3 (Rainbow Goose: 9-way 180-deg forward fan) via Wave 2 clear milestone evolution
        trigger_wave_clear();
        wait_frames(1);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(15); // skip intro & wait fire_cd
        if (dut.u_engine.player_form !== 2'd2) begin
            $display("ERROR: Expected Form 3 (Rainbow=2), got %d", dut.u_engine.player_form);
            fail_cnt = fail_cnt + 1;
        end
        force dut.u_engine.pb_active = 32'd0;
        @(posedge dut.clk_25m);
        release dut.u_engine.pb_active;
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0;
        pb_c = count_pb(dut.u_engine.pb_active);
        if (pb_c != 9) begin
            $display("ERROR: Form 3 expected 9 forward fan bullets, got %d", pb_c);
            fail_cnt = fail_cnt + 1;
        end
        for (k_pb_chk = 0; k_pb_chk < 32; k_pb_chk = k_pb_chk + 1) begin
            if (dut.u_engine.pb_active[k_pb_chk] && $signed(dut.u_engine.pb_vy[k_pb_chk]) > 0) begin
                $display("ERROR: Form 3 fired backward bullet vy=%0d!", $signed(dut.u_engine.pb_vy[k_pb_chk]));
                fail_cnt = fail_cnt + 1;
            end
        end

        // 6b. Test Timed Evolution Expiration -> Revert to previous state
        $display("[TB] Step 6b: Testing timed evolution revert...");
        force dut.u_engine.evo_sec_rem = 4'd1;
        force dut.u_engine.evo_frame_div = 6'd0;
        wait_frames(1);
        release dut.u_engine.evo_sec_rem;
        release dut.u_engine.evo_frame_div;
        wait_frames(1);
        if (dut.u_engine.evo_sec_rem !== 4'd0 || dut.u_engine.player_form !== 2'd0) begin
            $display("ERROR: Timed evolution failed to revert! sec=%d form=%d",
                     dut.u_engine.evo_sec_rem, dut.u_engine.player_form);
            fail_cnt = fail_cnt + 1;
        end

        // 7. Test Wave Progression -> Harder Boss AJV Multi-Directional Barrage -> Enraged AJV2 -> Victory -> Restart
        trigger_wave_clear(); // clears Wave 3 -> spawns Boss AJV (Wave 4)
        wait_frames(1);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(2); // skip boss intro
        if (dut.u_engine.wave_num !== 3'd4 || !dut.u_engine.boss_active) begin
            $display("ERROR: Boss AJV wave failed to activate! wave=%d boss=%b",
                     dut.u_engine.wave_num, dut.u_engine.boss_active);
            fail_cnt = fail_cnt + 1;
        end
        if (dut.boss_enraged !== 1'b0) begin
            $display("ERROR: Boss should start in Phase 1 (not enraged)! got boss_enraged=%b", dut.boss_enraged);
            fail_cnt = fail_cnt + 1;
        end
        force dut.u_engine.player_invuln = 8'd90;
        wait_frames(35); // wait for Boss AJV first salvo (timer starts at 30)
        eb_c = count_eb(dut.u_engine.eb_active);
        if (eb_c < 4) begin
            $display("ERROR: Boss AJV Phase 1 barrage expected >=4 bullets, got %d", eb_c);
            fail_cnt = fail_cnt + 1;
        end

        // Test Phase 2 Enrage: Boss HP drops below 50% -> ajv2 enraged sprite & rapid 7-bullet salvo
        force dut.u_engine.boss_hp = 7'd35; // < (90 >> 1)
        force dut.u_engine.boss_fire_timer = 8'd0; // trigger immediate fire salvo in phase 2
        wait_frames(2);
        release dut.u_engine.boss_fire_timer;
        if (dut.boss_enraged !== 1'b1) begin
            $display("ERROR: Expected Boss AJV to be enraged (Phase 2), got boss_enraged=%b", dut.boss_enraged);
            fail_cnt = fail_cnt + 1;
        end
        wait_frames(5);
        release dut.u_engine.player_invuln;
        eb_c = count_eb(dut.u_engine.eb_active);
        if (eb_c < 7) begin
            $display("ERROR: Boss AJV2 Enraged barrage expected >=7 bullets, got %d", eb_c);
            fail_cnt = fail_cnt + 1;
        end

        // Defeat Boss -> Victory -> Restart
        force dut.u_engine.boss_hp = 7'd1;
        force dut.u_engine.boss_active = 1'b0;
        force dut.u_engine.en_active = 16'd0;
        wait_frames(1);
        release dut.u_engine.boss_hp;
        release dut.u_engine.boss_active;
        release dut.u_engine.en_active;
        wait_frames(1);
        if (dut.u_engine.game_state !== 3'd4) begin
            $display("ERROR: Expected GS_VICTORY(4), got %d", dut.u_engine.game_state);
            fail_cnt = fail_cnt + 1;
        end

        // Restart to Title
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(2);
        if (dut.u_engine.game_state !== 3'd0) begin
            $display("ERROR: Restart to Title failed! state=%d", dut.u_engine.game_state);
            fail_cnt = fail_cnt + 1;
        end

        // 8. Test Pause -> SW[14] Give Up (GS_GAMEOVER) -> SW[14] OFF Return to Title (GS_TITLE)
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(2);
        BTNC = 1'b1; wait_frames(2); BTNC = 1'b0; wait_frames(2); // skip intro -> GS_PLAY
        SW[15] = 1'b1; wait_frames(2);
        if (dut.u_engine.game_state !== 3'd3) begin
            $display("ERROR: Expected GS_PAUSED(3), got %d", dut.u_engine.game_state);
            fail_cnt = fail_cnt + 1;
        end
        SW[14] = 1'b1; wait_frames(2);
        if (dut.u_engine.game_state !== 3'd5) begin
            $display("ERROR: Pause Give Up SW[14] failed! Expected GS_GAMEOVER(5), got %d", dut.u_engine.game_state);
            fail_cnt = fail_cnt + 1;
        end
        SW[14] = 1'b0; SW[15] = 1'b0; wait_frames(2);
        if (dut.u_engine.game_state !== 3'd0) begin
            $display("ERROR: Give Up return to Title failed! Expected GS_TITLE(0), got %d", dut.u_engine.game_state);
            fail_cnt = fail_cnt + 1;
        end

        if (fail_cnt == 0)
            $display("RESULT : PASS");
        else
            $display("RESULT : FAIL (%0d errors)", fail_cnt);
        $finish;
    end
endmodule
