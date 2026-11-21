`timescale 1ns / 1ps

module game_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        game_tick,

    // Inputs (debounced)
    input  wire        btn_up,
    input  wire        btn_down,
    input  wire        btn_left,
    input  wire        btn_right,
    input  wire        btn_fire,
    input  wire        btn_fire_rise,
    input  wire        btn_left_rise,
    input  wire        btn_right_rise,

    input  wire        sw_autofire,
    input  wire        sw_tilt,
    input  wire        sw_hard,
    input  wire        sw_giveup,
    input  wire        sw_pause,
    input  wire        sw_kbd,
    input  wire        sw_kbd_swap,

    input  wire signed [7:0] accel_x,
    input  wire signed [7:0] accel_y,

    input  wire [4:0]  uart_btn_mask, // {fire, right, left, down, up}
    input  wire        uart_link_ok,

    input  wire [4:0]  kbd_btn_mask,  // {fire, right, left, down, up}
    input  wire        kbd_link_ok,

    // Voice Barrier Mic Input
    input  wire [7:0]  mic_volume,
    input  wire [7:0]  mic_threshold,
    input  wire        shout_trigger,

    // Display State Outputs
    output wire        barrier_active,
    output reg  [8:0]  barrier_cooldown,
    output wire [23:0] eb_reflected,
    output wire        boss_enraged,
    output reg  [2:0]  game_state,    // 0=TITLE,1=INTRO,2=PLAY,3=PAUSE,4=WIN,5=LOSE
    output reg  [2:0]  wave_num,      // 1..4
    output reg         hard_mode,
    output reg  [7:0]  frame_cnt,
    output reg  [3:0]  shake_amt,

    // Player Outputs
    output reg  [9:0]  player_x,
    output reg  [9:0]  player_y,
    output reg         player_left_face,
    output reg  [1:0]  player_form,   // 0=White, 1=Blue, 2=Rainbow
    output reg  [2:0]  player_lives,
    output reg  [7:0]  player_invuln,

    // Enemies (16)
    output reg  [15:0] en_active,
    output reg  [9:0]  en_x     [0:15],
    output reg  [9:0]  en_y     [0:15],
    output reg  [1:0]  en_type  [0:15],
    output reg  [3:0]  en_flash [0:15],

    // Boss AJV (80x80)
    output reg         boss_active,
    output reg  [9:0]  boss_x,
    output reg  [9:0]  boss_y,
    output reg  [6:0]  boss_hp,
    output reg  [6:0]  boss_max_hp,
    output reg  [3:0]  boss_flash,

    // Player Bullets (32)
    output reg  [31:0] pb_active,
    output reg  [9:0]  pb_x    [0:31],
    output reg  [9:0]  pb_y    [0:31],
    output reg  [1:0]  pb_kind [0:31],

    // Enemy Bullets (24)
    output reg  [23:0] eb_active,
    output reg  [9:0]  eb_x [0:23],
    output reg  [9:0]  eb_y [0:23],

    // Power-up Orbs (4)
    output reg  [3:0]  orb_active,
    output reg  [9:0]  orb_x    [0:3],
    output reg  [9:0]  orb_y    [0:3],
    output reg  [1:0]  orb_type [0:3],

    // Explosions (8)
    output reg  [7:0]  exp_active,
    output reg  [9:0]  exp_x     [0:7],
    output reg  [9:0]  exp_y     [0:7],
    output reg  [3:0]  exp_timer [0:7],

    // HUD BRAM Write Port
    output reg         hud_we,
    output reg  [12:0] hud_waddr,
    output reg  [11:0] hud_wdata,

    // Telemetry & Audio
    output wire [31:0] seg7_digits,
    output wire [7:0]  seg7_dp_mask,
    output reg  [15:0] led_bar,
    output reg  [3:0]  evt_flash_timer,
    output reg  [1:0]  evt_flash_kind, // 0=none, 1=evo/win(green), 2=hurt(red), 3=boss(yellow)
    output reg         sfx_valid,
    output reg  [2:0]  sfx_id
);
    // Game States
    localparam [2:0] GS_TITLE      = 3'd0,
                     GS_WAVE_INTRO = 3'd1,
                     GS_PLAY       = 3'd2,
                     GS_PAUSED     = 3'd3,
                     GS_VICTORY    = 3'd4,
                     GS_GAMEOVER   = 3'd5;

    // Internal Sub-FSM Phases (time-multiplexed 1 entity/pair per cycle)
    localparam [3:0] PH_IDLE       = 4'd0,
                     PH_PLAYER     = 4'd1,
                     PH_SPAWN_PB   = 4'd2,
                     PH_UPD_PB     = 4'd3,
                     PH_COL_PB     = 4'd4,
                     PH_UPD_EN     = 4'd5,
                     PH_UPD_BOSS   = 4'd6,
                     PH_UPD_EB     = 4'd7,
                     PH_UPD_ORB    = 4'd8,
                     PH_UPD_EXP    = 4'd9,
                     PH_WAVE_CHK   = 4'd10,
                     PH_INIT_WAVE  = 4'd11,
                     PH_HUD_X      = 4'd12,
                     PH_BOSS_FIRE  = 4'd13;

    reg [3:0]  phase;
    reg [5:0]  idx_a;
    reg [5:0]  idx_b;
    reg [3:0]  spawn_sub;
    reg [3:0]  spawn_total;
    reg [6:0]  hud_tx;
    reg [5:0]  hud_ty;

    // Score BCD (6 digits) & High Score BCD
    reg [3:0]  sc_d [0:5];
    reg [3:0]  hi_d [0:5];
    reg [23:0] score_add_val; // 6-digit BCD increment

    // Internal entity kinematic arrays
    reg [9:0]  en_home_x [0:15];
    reg [9:0]  en_home_y [0:15];
    reg [2:0]  en_hp     [0:15];
    reg [1:0]  en_mode   [0:15]; // 0=enter,1=form,2=dive,3=return

    reg signed [5:0] pb_vx [0:31];
    reg signed [5:0] pb_vy [0:31];
    reg signed [5:0] eb_vx [0:23];
    reg signed [5:0] eb_vy [0:23];
    reg [23:0]       eb_reflected_reg;

    // Voice Barrier Control (Last Boss only)
    reg [7:0]  barrier_timer;
    reg        shout_latched;

    assign barrier_active      = (barrier_timer > 8'd0);
    assign eb_reflected        = eb_reflected_reg;
    wire   voice_above_thresh  = (mic_volume >= mic_threshold) && (mic_threshold > 8'd0);

    reg [7:0]  fire_cd;
    reg [7:0]  intro_timer;
    reg [7:0]  dive_timer;
    reg [7:0]  boss_fire_timer;
    reg        boss_dir_right;
    reg [1:0]  boss_atk_mode;
    reg [7:0]  boss_rand_seed;
    reg [2:0]  boss_spin_idx;
    reg [3:0]  boss_salvo_total;
    reg [4:0]  wave_kills;
    reg [8:0]  boss_orb_timer;
    reg [7:0]  evo_banner_timer;
    reg [1:0]  evo_banner_type; // 1=blue, 2=rainbow, 3=life
    reg [3:0]  evo_sec_rem;     // Temporary evolution countdown (seconds)
    reg [5:0]  evo_frame_div;   // 59..0 sub-second frame counter
    reg [1:0]  evo_prev_form;   // Form restored when evolution expires
    reg signed [7:0] form_sway;
    reg        form_sway_dir;
    wire [9:0] cur_en_target_x = $signed({1'b0, en_home_x[idx_a[3:0]]}) + $signed(form_sway);
    reg        menu_hard_sel;
    reg        prev_uart_fire;
    reg        prev_sw_giveup;
    reg        surrendered_via_sw;
    reg        pend_fire_rise;
    reg        pend_left_rise;
    reg        pend_right_rise;
    reg [2:0]  pending_wave;

    // LFSR RNG
    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (!rst_n)
            lfsr <= 16'hD4E7;
        else
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // 7-Segment Mapping: AN7=Wave(b for boss), AN6=Form(1..3 with DP), AN5..0=Score
    wire [3:0] seg_wave = (wave_num == 3'd4) ? 4'hB : {1'b0, wave_num};
    wire [3:0] seg_form = {2'b00, player_form} + 4'd1;
    assign seg7_digits  = {seg_wave, seg_form, sc_d[5], sc_d[4], sc_d[3], sc_d[2], sc_d[1], sc_d[0]};
    assign seg7_dp_mask = 8'b0100_0000; // dot after Form digit

    // -----------------------------------------------------------------------
    // Helper Functions (Pure Combinational, No Loops Sharing Globals)
    // -----------------------------------------------------------------------
    function [9:0] abs_diff;
        input [9:0] a;
        input [9:0] b;
        begin
            abs_diff = (a >= b) ? (a - b) : (b - a);
        end
    endfunction

    // Octagon distance: max(|dx|,|dy|) + (min(|dx|,|dy|) >> 1)
    function [10:0] oct_dist;
        input [9:0] ax;
        input [9:0] ay;
        input [9:0] bx;
        input [9:0] by;
        reg [9:0] dx, dy, mx, mn;
        begin
            dx = abs_diff(ax, bx);
            dy = abs_diff(ay, by);
            mx = (dx >= dy) ? dx : dy;
            mn = (dx >= dy) ? dy : dx;
            oct_dist = {1'b0, mx} + {2'b00, mn[9:1]};
        end
    endfunction

    // 6-digit BCD adder: adds up to 4-digit BCD value (0..9999)
    task automatic add_bcd_score;
        input [3:0] d3, d2, d1, d0;
        reg [4:0] s0, s1, s2, s3, s4, s5;
        reg c0, c1, c2, c3, c4;
        begin
            s0 = {1'b0, sc_d[0]} + {1'b0, d0};
            if (s0 >= 5'd10) begin sc_d[0] <= s0[3:0] - 4'd10; c0 = 1'b1; end
            else             begin sc_d[0] <= s0[3:0];         c0 = 1'b0; end

            s1 = {1'b0, sc_d[1]} + {1'b0, d1} + {4'd0, c0};
            if (s1 >= 5'd10) begin sc_d[1] <= s1[3:0] - 4'd10; c1 = 1'b1; end
            else             begin sc_d[1] <= s1[3:0];         c1 = 1'b0; end

            s2 = {1'b0, sc_d[2]} + {1'b0, d2} + {4'd0, c1};
            if (s2 >= 5'd10) begin sc_d[2] <= s2[3:0] - 4'd10; c2 = 1'b1; end
            else             begin sc_d[2] <= s2[3:0];         c2 = 1'b0; end

            s3 = {1'b0, sc_d[3]} + {1'b0, d3} + {4'd0, c2};
            if (s3 >= 5'd10) begin sc_d[3] <= s3[3:0] - 4'd10; c3 = 1'b1; end
            else             begin sc_d[3] <= s3[3:0];         c3 = 1'b0; end

            s4 = {1'b0, sc_d[4]} + {4'd0, c3};
            if (s4 >= 5'd10) begin sc_d[4] <= s4[3:0] - 4'd10; c4 = 1'b1; end
            else             begin sc_d[4] <= s4[3:0];         c4 = 1'b0; end

            s5 = {1'b0, sc_d[5]} + {4'd0, c4};
            if (s5 >= 5'd10) sc_d[5] <= 4'd9;
            else             sc_d[5] <= s5[3:0];
        end
    endtask

    task automatic spawn_explosion;
        input [9:0] ex;
        input [9:0] ey;
        integer k_exp;
        reg placed;
        begin
            placed = 1'b0;
            for (k_exp = 0; k_exp < 8; k_exp = k_exp + 1) begin
                if (!placed && !exp_active[k_exp]) begin
                    exp_active[k_exp] <= 1'b1;
                    exp_x[k_exp]      <= ex;
                    exp_y[k_exp]      <= ey;
                    exp_timer[k_exp]  <= 4'd0;
                    placed            = 1'b1;
                end
            end
        end
    endtask

    task automatic spawn_enemy_bullet;
        input [9:0] sx;
        input [9:0] sy;
        input signed [5:0] vx;
        input signed [5:0] vy;
        integer k_eb;
        reg placed;
        begin
            placed = 1'b0;
            for (k_eb = 0; k_eb < 24; k_eb = k_eb + 1) begin
                if (!placed && !eb_active[k_eb]) begin
                    eb_active[k_eb]        <= 1'b1;
                    eb_reflected_reg[k_eb] <= 1'b0;
                    eb_x[k_eb]             <= sx;
                    eb_y[k_eb]             <= sy;
                    eb_vx[k_eb]            <= vx;
                    eb_vy[k_eb]            <= vy;
                    placed                 = 1'b1;
                end
            end
        end
    endtask

    task automatic spawn_orb;
        input [9:0] ox;
        input [9:0] oy;
        input [1:0] otype;
        integer k_or;
        reg placed;
        begin
            placed = 1'b0;
            for (k_or = 0; k_or < 4; k_or = k_or + 1) begin
                if (!placed && !orb_active[k_or]) begin
                    orb_active[k_or] <= 1'b1;
                    orb_x[k_or]      <= ox;
                    orb_y[k_or]      <= oy;
                    orb_type[k_or]   <= otype;
                    placed           = 1'b1;
                end
            end
        end
    endtask

    task automatic trigger_player_hit;
        begin
            if (player_invuln == 8'd0) begin
                spawn_explosion(player_x, player_y);
                shake_amt       <= 4'd10;
                evt_flash_timer <= 4'd15;
                evt_flash_kind  <= 2'd2;
                sfx_valid       <= 1'b1;
                sfx_id          <= 3'd6;
                if (player_lives > 3'd0)
                    player_lives <= player_lives - 3'd1;
                player_invuln <= 8'd120; // 2s invulnerability
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Combinational HUD Character Generator for (hud_tx, hud_ty)
    // Color IDs (4-bit): 0=White, 1=Cyan, 2=Yellow, 3=Red, 4=Green, 5=Magenta, 6=Orange
    // -----------------------------------------------------------------------
    reg [7:0] hud_char;
    reg [3:0] hud_col;

    // Helper to pick character from a string-like table via index
    function [7:0] digit_ascii;
        input [3:0] d;
        begin
            digit_ascii = 8'h30 + {4'd0, d};
        end
    endfunction

    always @(*) begin
        hud_char = 8'h20;
        hud_col  = 4'd0;

        // Row 1: Top Status Bar (always visible except Title top cleanly shows High Score)
        if (hud_ty == 6'd1) begin
            hud_col = 4'd1; // Cyan labels
            case (hud_tx)
                7'd2:  begin hud_char = "S"; end
                7'd3:  begin hud_char = "C"; end
                7'd4:  begin hud_char = "O"; end
                7'd5:  begin hud_char = "R"; end
                7'd6:  begin hud_char = "E"; end
                7'd7:  begin hud_char = ":"; end
                7'd8:  begin hud_char = digit_ascii(sc_d[5]); hud_col = 4'd0; end
                7'd9:  begin hud_char = digit_ascii(sc_d[4]); hud_col = 4'd0; end
                7'd10: begin hud_char = digit_ascii(sc_d[3]); hud_col = 4'd0; end
                7'd11: begin hud_char = digit_ascii(sc_d[2]); hud_col = 4'd0; end
                7'd12: begin hud_char = digit_ascii(sc_d[1]); hud_col = 4'd0; end
                7'd13: begin hud_char = digit_ascii(sc_d[0]); hud_col = 4'd0; end

                7'd17: begin hud_char = "H"; end
                7'd18: begin hud_char = "I"; end
                7'd19: begin hud_char = ":"; end
                7'd20: begin hud_char = digit_ascii(hi_d[5]); hud_col = 4'd2; end
                7'd21: begin hud_char = digit_ascii(hi_d[4]); hud_col = 4'd2; end
                7'd22: begin hud_char = digit_ascii(hi_d[3]); hud_col = 4'd2; end
                7'd23: begin hud_char = digit_ascii(hi_d[2]); hud_col = 4'd2; end
                7'd24: begin hud_char = digit_ascii(hi_d[1]); hud_col = 4'd2; end
                7'd25: begin hud_char = digit_ascii(hi_d[0]); hud_col = 4'd2; end

                7'd29: begin hud_char = "W"; end
                7'd30: begin hud_char = "A"; end
                7'd31: begin hud_char = "V"; end
                7'd32: begin hud_char = "E"; end
                7'd33: begin hud_char = ":"; end
                7'd34: begin hud_char = (wave_num == 3'd4) ? "B" : digit_ascii({1'b0, wave_num}); hud_col = (wave_num == 3'd4) ? 4'd3 : 4'd2; end
                7'd35: begin hud_char = "/"; hud_col = 4'd0; end
                7'd36: begin hud_char = "4"; hud_col = 4'd0; end

                7'd40: begin hud_char = "F"; end
                7'd41: begin hud_char = "O"; end
                7'd42: begin hud_char = "R"; end
                7'd43: begin hud_char = "M"; end
                7'd44: begin hud_char = ":"; end
                7'd45: begin hud_char = (player_form == 2'd0) ? "W" : ((player_form == 2'd1) ? "B" : "R"); hud_col = (player_form == 2'd0) ? 4'd0 : ((player_form == 2'd1) ? 4'd1 : 4'd5); end
                7'd46: begin hud_char = (player_form == 2'd0) ? "H" : ((player_form == 2'd1) ? "L" : "A"); hud_col = (player_form == 2'd0) ? 4'd0 : ((player_form == 2'd1) ? 4'd1 : 4'd2); end
                7'd47: begin hud_char = (player_form == 2'd0) ? "I" : ((player_form == 2'd1) ? "U" : "I"); hud_col = (player_form == 2'd0) ? 4'd0 : ((player_form == 2'd1) ? 4'd1 : 4'd4); end
                7'd48: begin hud_char = (player_form == 2'd0) ? "T" : ((player_form == 2'd1) ? "E" : "N"); hud_col = (player_form == 2'd0) ? 4'd0 : ((player_form == 2'd1) ? 4'd1 : 4'd1); end
                7'd49: begin hud_char = (player_form == 2'd0) ? "E" : ((player_form == 2'd1) ? " " : "B"); hud_col = (player_form == 2'd0) ? 4'd0 : ((player_form == 2'd1) ? 4'd1 : 4'd3); end
                7'd50: begin hud_char = (player_form == 2'd2) ? "O" : " "; hud_col = 4'd6; end
                7'd51: begin hud_char = (player_form == 2'd2) ? "W" : " "; hud_col = 4'd5; end
                7'd52: begin hud_char = (evo_sec_rem > 4'd0) ? digit_ascii(evo_sec_rem) : " "; hud_col = (evo_sec_rem <= 4'd3) ? 4'd3 : 4'd2; end
                7'd53: begin hud_char = (evo_sec_rem > 4'd0) ? "S" : " "; hud_col = (evo_sec_rem <= 4'd3) ? 4'd3 : 4'd2; end

                7'd55: begin hud_char = "H"; end
                7'd56: begin hud_char = "P"; end
                7'd57: begin hud_char = ":"; end
                7'd58: begin hud_char = (player_lives >= 3'd1) ? 8'h01 : " "; hud_col = 4'd3; end
                7'd59: begin hud_char = (player_lives >= 3'd2) ? 8'h01 : " "; hud_col = 4'd3; end
                7'd60: begin hud_char = (player_lives >= 3'd3) ? 8'h01 : " "; hud_col = 4'd3; end
                7'd61: begin hud_char = (player_lives >= 3'd4) ? 8'h01 : " "; hud_col = 4'd3; end
                7'd62: begin hud_char = (player_lives >= 3'd5) ? 8'h01 : " "; hud_col = 4'd3; end

                7'd66: begin hud_char = hard_mode ? "H" : "N"; hud_col = hard_mode ? 4'd3 : 4'd4; end
                7'd67: begin hud_char = hard_mode ? "A" : "O"; hud_col = hard_mode ? 4'd3 : 4'd4; end
                7'd68: begin hud_char = hard_mode ? "R" : "R"; hud_col = hard_mode ? 4'd3 : 4'd4; end
                7'd69: begin hud_char = hard_mode ? "D" : "M"; hud_col = hard_mode ? 4'd3 : 4'd4; end

                7'd72: begin hud_char = (sw_kbd | kbd_link_ok) ? "K" : (uart_link_ok ? "U" : (sw_tilt ? "A" : "B")); hud_col = (sw_kbd | kbd_link_ok) ? 4'd5 : (uart_link_ok ? 4'd4 : 4'd2); end
                7'd73: begin hud_char = (sw_kbd | kbd_link_ok) ? "B" : (uart_link_ok ? "S" : (sw_tilt ? "C" : "T")); hud_col = (sw_kbd | kbd_link_ok) ? 4'd5 : (uart_link_ok ? 4'd4 : 4'd2); end
                7'd74: begin hud_char = (sw_kbd | kbd_link_ok) ? "D" : (uart_link_ok ? "B" : (sw_tilt ? "L" : "N")); hud_col = (sw_kbd | kbd_link_ok) ? 4'd5 : (uart_link_ok ? 4'd4 : 4'd2); end
                default: ;
            endcase
        end

        // Row 3: Boss HP Bar or Evolution Banner
        if (hud_ty == 6'd3) begin
            if (game_state == GS_PLAY && wave_num == 3'd4 && boss_active) begin
                if (hud_tx == 7'd20) begin hud_char = "B"; hud_col = 4'd3; end
                if (hud_tx == 7'd21) begin hud_char = "O"; hud_col = 4'd3; end
                if (hud_tx == 7'd22) begin hud_char = "S"; hud_col = 4'd3; end
                if (hud_tx == 7'd23) begin hud_char = "S"; hud_col = 4'd3; end
                if (hud_tx == 7'd25) begin hud_char = "A"; hud_col = 4'd2; end
                if (hud_tx == 7'd26) begin hud_char = "J"; hud_col = 4'd2; end
                if (hud_tx == 7'd27) begin hud_char = "V"; hud_col = 4'd2; end
                if (hud_tx == 7'd29) begin hud_char = "["; hud_col = 4'd0; end
                if (hud_tx == 7'd60) begin hud_char = "]"; hud_col = 4'd0; end
                if (hud_tx >= 7'd30 && hud_tx <= 7'd59) begin
                    // 30-block HP bar: 90 HP (x3) normal, 120 HP (x4) hard
                    if ({1'b0, (hud_tx - 7'd30)} * (hard_mode ? 7'd4 : 7'd3) < boss_hp) begin
                        hud_char = 8'h03;
                        hud_col  = (boss_hp <= (boss_max_hp >> 1)) ? 4'd3 : 4'd6;
                    end else begin
                        hud_char = "-";
                        hud_col  = 4'd0;
                    end
                end
            end else if (evo_banner_timer > 8'd0 && game_state == GS_PLAY) begin
                // Show EVOLUTION notice!
                if (evo_banner_type == 2'd1) begin
                    hud_col = 4'd1;
                    case (hud_tx)
                        7'd27: hud_char="E"; 7'd28: hud_char="V"; 7'd29: hud_char="O"; 7'd30: hud_char="L";
                        7'd31: hud_char="V"; 7'd32: hud_char="E"; 7'd33: hud_char="D"; 7'd34: hud_char=":";
                        7'd36: hud_char="B"; 7'd37: hud_char="L"; 7'd38: hud_char="U"; 7'd39: hud_char="E";
                        7'd41: hud_char="G"; 7'd42: hud_char="O"; 7'd43: hud_char="O"; 7'd44: hud_char="S"; 7'd45: hud_char="E";
                        7'd47: hud_char="("; 7'd48: hud_char="2"; 7'd49: hud_char="-"; 7'd50: hud_char="S";
                        7'd51: hud_char="H"; 7'd52: hud_char="O"; 7'd53: hud_char="T"; 7'd54: hud_char=")";
                        default: ;
                    endcase
                end else if (evo_banner_type == 2'd2) begin
                    hud_col = 4'd5;
                    case (hud_tx)
                        7'd25: hud_char="E"; 7'd26: hud_char="V"; 7'd27: hud_char="O"; 7'd28: hud_char="L";
                        7'd29: hud_char="V"; 7'd30: hud_char="E"; 7'd31: hud_char="D"; 7'd32: hud_char=":";
                        7'd34: hud_char="R"; 7'd35: hud_char="A"; 7'd36: hud_char="I"; 7'd37: hud_char="N";
                        7'd38: hud_char="B"; 7'd39: hud_char="O"; 7'd40: hud_char="W";
                        7'd42: hud_char="("; 7'd43: hud_char="1"; 7'd44: hud_char="8"; 7'd45: hud_char="0";
                        7'd46: hud_char="-"; 7'd47: hud_char="D"; 7'd48: hud_char="E"; 7'd49: hud_char="G";
                        7'd50: hud_char=" "; 7'd51: hud_char="F"; 7'd52: hud_char="A"; 7'd53: hud_char="N";
                        7'd54: hud_char=")";
                        default: ;
                    endcase
                end else begin
                    hud_col = 4'd4;
                    case (hud_tx)
                        7'd32: hud_char="+"; 7'd33: hud_char="1"; 7'd35: hud_char="E"; 7'd36: hud_char="X";
                        7'd37: hud_char="T"; 7'd38: hud_char="R"; 7'd39: hud_char="A";
                        7'd41: hud_char="L"; 7'd42: hud_char="I"; 7'd43: hud_char="F"; 7'd44: hud_char="E";
                        7'd45: hud_char="!";
                        default: ;
                    endcase
                end
            end else if (evo_sec_rem > 4'd0 && game_state == GS_PLAY) begin
                hud_col = (evo_sec_rem <= 4'd3) ? 4'd3 : 4'd1;
                case (hud_tx)
                    7'd33: hud_char="E"; 7'd34: hud_char="V"; 7'd35: hud_char="O";
                    7'd37: hud_char="T"; 7'd38: hud_char="I"; 7'd39: hud_char="M"; 7'd40: hud_char="E"; 7'd41: hud_char=":";
                    7'd43: hud_char=digit_ascii(evo_sec_rem);
                    7'd44: hud_char="S";
                    default: ;
                endcase
            end
        end

        // Row 4: Voice Barrier Graphical UI is rendered directly in display_renderer.sv

        // Center Overlays for Non-Play States
        if (game_state == GS_TITLE) begin
            if (hud_ty == 6'd20) begin
                hud_col = 4'd2;
                case (hud_tx)
                    7'd26: hud_char="S"; 7'd27: hud_char="P"; 7'd28: hud_char="A"; 7'd29: hud_char="C"; 7'd30: hud_char="E";
                    7'd32: hud_char="G"; 7'd33: hud_char="O"; 7'd34: hud_char="O"; 7'd35: hud_char="S"; 7'd36: hud_char="E";
                    7'd38: hud_char="G"; 7'd39: hud_char="A"; 7'd40: hud_char="L"; 7'd41: hud_char="A"; 7'd42: hud_char="G"; 7'd43: hud_char="A";
                    7'd45: hud_char="E"; 7'd46: hud_char="D"; 7'd47: hud_char="I"; 7'd48: hud_char="T"; 7'd49: hud_char="I"; 7'd50: hud_char="O"; 7'd51: hud_char="N";
                    default: ;
                endcase
            end else if (hud_ty == 6'd25) begin
                hud_col = menu_hard_sel ? 4'd3 : 4'd4;
                case (hud_tx)
                    7'd30: hud_char="M"; 7'd31: hud_char="O"; 7'd32: hud_char="D"; 7'd33: hud_char="E"; 7'd34: hud_char=":";
                    7'd36: hud_char="<";
                    7'd38: hud_char = menu_hard_sel ? "H" : "N";
                    7'd39: hud_char = menu_hard_sel ? "A" : "O";
                    7'd40: hud_char = menu_hard_sel ? "R" : "R";
                    7'd41: hud_char = menu_hard_sel ? "D" : "M";
                    7'd42: hud_char = menu_hard_sel ? " " : "A";
                    7'd43: hud_char = menu_hard_sel ? " " : "L";
                    7'd45: hud_char=">";
                    default: ;
                endcase
            end else if (hud_ty == 6'd29 && !frame_cnt[4]) begin
                hud_col = 4'd0;
                case (hud_tx)
                    7'd29: hud_char="P"; 7'd30: hud_char="R"; 7'd31: hud_char="E"; 7'd32: hud_char="S"; 7'd33: hud_char="S";
                    7'd35: hud_char="B"; 7'd36: hud_char="T"; 7'd37: hud_char="N"; 7'd38: hud_char="C";
                    7'd40: hud_char="T"; 7'd41: hud_char="O";
                    7'd43: hud_char="L"; 7'd44: hud_char="A"; 7'd45: hud_char="U"; 7'd46: hud_char="N"; 7'd47: hud_char="C"; 7'd48: hud_char="H";
                    default: ;
                endcase
            end else if (hud_ty == 6'd35) begin
                hud_col = 4'd1;
                case (hud_tx)
                    7'd18: hud_char="E"; 7'd19: hud_char="V"; 7'd20: hud_char="O"; 7'd21: hud_char=":";
                    7'd23: hud_char="F"; 7'd24: hud_char="1"; 7'd25: hud_char=":"; 7'd26: hud_char="W"; 7'd27: hud_char="H"; 7'd28: hud_char="I"; 7'd29: hud_char="T"; 7'd30: hud_char="E"; 7'd31: hud_char="("; 7'd32: hud_char="1"; 7'd33: hud_char=")";
                    7'd35: hud_char="-"; 7'd36: hud_char=">";
                    7'd38: hud_char="F"; 7'd39: hud_char="2"; 7'd40: hud_char=":"; 7'd41: hud_char="B"; 7'd42: hud_char="L"; 7'd43: hud_char="U"; 7'd44: hud_char="E"; 7'd45: hud_char="("; 7'd46: hud_char="2"; 7'd47: hud_char=")";
                    7'd49: hud_char="-"; 7'd50: hud_char=">";
                    7'd52: hud_char="F"; 7'd53: hud_char="3"; 7'd54: hud_char=":"; 7'd55: hud_char="R"; 7'd56: hud_char="A"; 7'd57: hud_char="I"; 7'd58: hud_char="N"; 7'd59: hud_char="B"; 7'd60: hud_char="O"; 7'd61: hud_char="W"; 7'd62: hud_char="("; 7'd63: hud_char="1"; 7'd64: hud_char="8"; 7'd65: hud_char="0"; 7'd66: hud_char=")";
                    default: ;
                endcase
            end else if (hud_ty == 6'd40) begin
                hud_col = 4'd0;
                case (hud_tx)
                    7'd18: hud_char="B"; 7'd19: hud_char="T"; 7'd20: hud_char="N"; 7'd21: hud_char="L"; 7'd22: hud_char="/"; 7'd23: hud_char="R"; 7'd24: hud_char="/"; 7'd25: hud_char="U"; 7'd26: hud_char="/"; 7'd27: hud_char="D"; 7'd28: hud_char=":"; 7'd29: hud_char="M"; 7'd30: hud_char="O"; 7'd31: hud_char="V"; 7'd32: hud_char="E";
                    7'd35: hud_char="B"; 7'd36: hud_char="T"; 7'd37: hud_char="N"; 7'd38: hud_char="C"; 7'd39: hud_char=":"; 7'd40: hud_char="F"; 7'd41: hud_char="I"; 7'd42: hud_char="R"; 7'd43: hud_char="E";
                    7'd46: hud_char="S"; 7'd47: hud_char="W"; 7'd48: hud_char="1"; 7'd49: hud_char=":"; 7'd50: hud_char="A"; 7'd51: hud_char="U"; 7'd52: hud_char="T"; 7'd53: hud_char="O";
                    7'd56: hud_char="S"; 7'd57: hud_char="W"; 7'd58: hud_char="2"; 7'd59: hud_char=":"; 7'd60: hud_char="T"; 7'd61: hud_char="I"; 7'd62: hud_char="L"; 7'd63: hud_char="T";
                    default: ;
                endcase
            end else if (hud_ty == 6'd44) begin
                hud_col = 4'd6;
                case (hud_tx)
                    7'd19: hud_char="S"; 7'd20: hud_char="W"; 7'd21: hud_char="0"; 7'd22: hud_char=":"; 7'd23: hud_char="M"; 7'd24: hud_char="U"; 7'd25: hud_char="T"; 7'd26: hud_char="E";
                    7'd28: hud_char="S"; 7'd29: hud_char="W"; 7'd30: hud_char="3"; 7'd31: hud_char=":"; 7'd32: hud_char="H"; 7'd33: hud_char="A"; 7'd34: hud_char="R"; 7'd35: hud_char="D";
                    7'd37: hud_char="S"; 7'd38: hud_char="W"; 7'd39: hud_char="1"; 7'd40: hud_char="4"; 7'd41: hud_char=":"; 7'd42: hud_char="Q"; 7'd43: hud_char="U"; 7'd44: hud_char="I"; 7'd45: hud_char="T";
                    7'd47: hud_char="S"; 7'd48: hud_char="W"; 7'd49: hud_char="1"; 7'd50: hud_char="5"; 7'd51: hud_char=":"; 7'd52: hud_char="P"; 7'd53: hud_char="A"; 7'd54: hud_char="U"; 7'd55: hud_char="S"; 7'd56: hud_char="E";
                    default: ;
                endcase
            end
        end else if (game_state == GS_WAVE_INTRO) begin
            if (hud_ty == 6'd28) begin
                if (wave_num == 3'd4) begin
                    hud_col = frame_cnt[3] ? 4'd3 : 4'd2;
                    case (hud_tx)
                        7'd29: hud_char="W"; 7'd30: hud_char="A"; 7'd31: hud_char="R"; 7'd32: hud_char="N"; 7'd33: hud_char="I"; 7'd34: hud_char="N"; 7'd35: hud_char="G"; 7'd36: hud_char=":";
                        7'd38: hud_char="B"; 7'd39: hud_char="O"; 7'd40: hud_char="S"; 7'd41: hud_char="S";
                        7'd43: hud_char="A"; 7'd44: hud_char="J"; 7'd45: hud_char="V"; 7'd46: hud_char="!";
                        default: ;
                    endcase
                end else begin
                    hud_col = 4'd2;
                    case (hud_tx)
                        7'd34: hud_char="W"; 7'd35: hud_char="A"; 7'd36: hud_char="V"; 7'd37: hud_char="E";
                        7'd39: hud_char=digit_ascii({1'b0, wave_num});
                        7'd41: hud_char="R"; 7'd42: hud_char="E"; 7'd43: hud_char="A"; 7'd44: hud_char="D"; 7'd45: hud_char="Y";
                        default: ;
                    endcase
                end
            end else if (evo_sec_rem > 4'd0 && game_state == GS_PLAY) begin
                hud_col = (evo_sec_rem <= 4'd3) ? 4'd3 : 4'd1;
                case (hud_tx)
                    7'd33: hud_char="E"; 7'd34: hud_char="V"; 7'd35: hud_char="O";
                    7'd37: hud_char="T"; 7'd38: hud_char="I"; 7'd39: hud_char="M"; 7'd40: hud_char="E"; 7'd41: hud_char=":";
                    7'd43: hud_char=digit_ascii(evo_sec_rem);
                    7'd44: hud_char="S";
                    default: ;
                endcase
            end
        end else if (game_state == GS_PAUSED) begin
            if (hud_ty == 6'd25) begin
                hud_col = 4'd2;
                case (hud_tx)
                    7'd31: hud_char="="; 7'd32: hud_char="="; 7'd34: hud_char="P"; 7'd35: hud_char="A"; 7'd36: hud_char="U"; 7'd37: hud_char="S"; 7'd38: hud_char="E"; 7'd39: hud_char="D"; 7'd41: hud_char="="; 7'd42: hud_char="=";
                    default: ;
                endcase
            end else if (hud_ty == 6'd29) begin
                hud_col = 4'd4;
                case (hud_tx)
                    7'd29: hud_char="S"; 7'd30: hud_char="W"; 7'd31: hud_char="1"; 7'd32: hud_char="5"; 7'd34: hud_char="O"; 7'd35: hud_char="F"; 7'd36: hud_char="F"; 7'd37: hud_char=":";
                    7'd39: hud_char="R"; 7'd40: hud_char="E"; 7'd41: hud_char="S"; 7'd42: hud_char="U"; 7'd43: hud_char="M"; 7'd44: hud_char="E";
                    default: ;
                endcase
            end else if (hud_ty == 6'd32) begin
                hud_col = 4'd3;
                case (hud_tx)
                    7'd28: hud_char="S"; 7'd29: hud_char="W"; 7'd30: hud_char="1"; 7'd31: hud_char="4"; 7'd33: hud_char="O"; 7'd34: hud_char="N"; 7'd35: hud_char=":";
                    7'd37: hud_char="G"; 7'd38: hud_char="I"; 7'd39: hud_char="V"; 7'd40: hud_char="E";
                    7'd42: hud_char="U"; 7'd43: hud_char="P";
                    default: ;
                endcase
            end
        end else if (game_state == GS_VICTORY || game_state == GS_GAMEOVER) begin
            if (hud_ty == 6'd25) begin
                hud_col = (game_state == GS_VICTORY) ? 4'd4 : 4'd3;
                if (game_state == GS_VICTORY) begin
                    case (hud_tx)
                        7'd27: hud_char="V"; 7'd28: hud_char="I"; 7'd29: hud_char="C"; 7'd30: hud_char="T"; 7'd31: hud_char="O"; 7'd32: hud_char="R"; 7'd33: hud_char="Y"; 7'd34: hud_char="!";
                        7'd36: hud_char="A"; 7'd37: hud_char="J"; 7'd38: hud_char="V";
                        7'd40: hud_char="D"; 7'd41: hud_char="E"; 7'd42: hud_char="F"; 7'd43: hud_char="E"; 7'd44: hud_char="A"; 7'd45: hud_char="T"; 7'd46: hud_char="E"; 7'd47: hud_char="D"; 7'd48: hud_char="!";
                        default: ;
                    endcase
                end else begin
                    case (hud_tx)
                        7'd34: hud_char="G"; 7'd35: hud_char="A"; 7'd36: hud_char="M"; 7'd37: hud_char="E";
                        7'd39: hud_char="O"; 7'd40: hud_char="V"; 7'd41: hud_char="E"; 7'd42: hud_char="R";
                        default: ;
                    endcase
                end
            end else if (hud_ty == 6'd29) begin
                hud_col = 4'd2;
                case (hud_tx)
                    7'd31: hud_char="F"; 7'd32: hud_char="I"; 7'd33: hud_char="N"; 7'd34: hud_char="A"; 7'd35: hud_char="L"; 7'd36: hud_char=":";
                    7'd38: hud_char=digit_ascii(sc_d[5]);
                    7'd39: hud_char=digit_ascii(sc_d[4]);
                    7'd40: hud_char=digit_ascii(sc_d[3]);
                    7'd41: hud_char=digit_ascii(sc_d[2]);
                    7'd42: hud_char=digit_ascii(sc_d[1]);
                    7'd43: hud_char=digit_ascii(sc_d[0]);
                    default: ;
                endcase
            end else if (hud_ty == 6'd33 && !frame_cnt[4]) begin
                hud_col = 4'd0;
                if (game_state == GS_GAMEOVER) begin
                    case (hud_tx)
                        7'd26: hud_char="B"; 7'd27: hud_char="T"; 7'd28: hud_char="N"; 7'd29: hud_char="C";
                        7'd31: hud_char="O"; 7'd32: hud_char="R";
                        7'd34: hud_char="S"; 7'd35: hud_char="W"; 7'd36: hud_char="1"; 7'd37: hud_char="4";
                        7'd39: hud_char="O"; 7'd40: hud_char="F"; 7'd41: hud_char="F"; 7'd42: hud_char=":";
                        7'd44: hud_char="M"; 7'd45: hud_char="E"; 7'd46: hud_char="N"; 7'd47: hud_char="U";
                        default: ;
                    endcase
                end else begin
                    case (hud_tx)
                        7'd29: hud_char="P"; 7'd30: hud_char="R"; 7'd31: hud_char="E"; 7'd32: hud_char="S"; 7'd33: hud_char="S";
                        7'd35: hud_char="B"; 7'd36: hud_char="T"; 7'd37: hud_char="N"; 7'd38: hud_char="C";
                        7'd40: hud_char="T"; 7'd41: hud_char="O";
                        7'd43: hud_char="R"; 7'd44: hud_char="E"; 7'd45: hud_char="T"; 7'd46: hud_char="R"; 7'd47: hud_char="Y";
                        default: ;
                    endcase
                end
            end
        end
    end

    // Boss Enrage state (<= 50% HP)
    assign boss_enraged = boss_active && (boss_hp <= (boss_max_hp >> 1));

    // Keyboard mapping (Standard WASD + Arrow Keys):
    // kbd_btn_mask: {fire (Enter/Space), right (D), left (A), down (S), up (W)}
    wire kbd_up     = kbd_btn_mask[0];
    wire kbd_down   = kbd_btn_mask[1];
    wire kbd_left   = kbd_btn_mask[2];
    wire kbd_right  = kbd_btn_mask[3];
    wire kbd_fire   = kbd_btn_mask[4];
    wire kbd_active = sw_kbd | kbd_link_ok;
    wire _unused_kbd_swap = sw_kbd_swap;

    reg prev_kbd_fire, prev_kbd_left, prev_kbd_right;

    // In keyboard mode, board push buttons and tilt sensor (ADXL362) are disabled to ensure keyboard-only control
    wire allow_btns = ~kbd_active;
    wire allow_tilt = sw_tilt & ~kbd_active;

    // Combined Inputs (ADXL362 on Nexys A7 PCB is mounted 90-deg rotated; VGA connector at TOP)
    wire eff_up    = (allow_btns & btn_up)    | (kbd_active & kbd_up)    | uart_btn_mask[0] | (allow_tilt && (accel_x < -8'sd14));
    wire eff_down  = (allow_btns & btn_down)  | (kbd_active & kbd_down)  | uart_btn_mask[1] | (allow_tilt && (accel_x >  8'sd14));
    wire eff_left  = (allow_btns & btn_left)  | (kbd_active & kbd_left)  | uart_btn_mask[2] | (allow_tilt && (accel_y >  8'sd14));
    wire eff_right = (allow_btns & btn_right) | (kbd_active & kbd_right) | uart_btn_mask[3] | (allow_tilt && (accel_y < -8'sd14));
    wire eff_fire  = (allow_btns & btn_fire)  | (kbd_active & kbd_fire)  | uart_btn_mask[4] | sw_autofire;
    wire uart_fire_rise  = uart_btn_mask[4] & ~prev_uart_fire;
    wire kbd_fire_rise   = (kbd_active & kbd_fire) & ~prev_kbd_fire;
    wire sw_giveup_rise  = sw_giveup & ~prev_sw_giveup;
    wire sw_giveup_fall  = ~sw_giveup & prev_sw_giveup;
    wire any_left_pulse  = (allow_btns & (btn_left_rise  | pend_left_rise))  | ((kbd_active & kbd_left) & ~prev_kbd_left);
    wire any_right_pulse = (allow_btns & (btn_right_rise | pend_right_rise)) | ((kbd_active & kbd_right) & ~prev_kbd_right);
    wire any_start_pulse = (allow_btns & (btn_fire_rise  | pend_fire_rise))  | uart_fire_rise | kbd_fire_rise;

    // -----------------------------------------------------------------------
    // Main Sequential Game Engine
    // -----------------------------------------------------------------------
    integer k_rst;
    integer k_f;
    always @(posedge clk) begin
        if (!rst_n) begin
            game_state       <= GS_TITLE;
            wave_num         <= 3'd1;
            hard_mode        <= 1'b0;
            menu_hard_sel    <= 1'b0;
            frame_cnt        <= 8'd0;
            shake_amt        <= 4'd0;
            player_x         <= 10'd304;
            player_y         <= 10'd410;
            player_left_face <= 1'b0;
            player_form      <= 2'd0;
            player_lives     <= 3'd3;
            player_invuln    <= 8'd0;
            en_active        <= 16'd0;
            boss_active      <= 1'b0;
            boss_x           <= 10'd280;
            boss_y           <= 10'd60;
            boss_hp          <= 7'd90;
            boss_max_hp      <= 7'd90;
            boss_flash       <= 4'd0;
            pb_active        <= 32'd0;
            eb_active        <= 24'd0;
            eb_reflected_reg <= 24'd0;
            barrier_timer    <= 8'd0;
            barrier_cooldown <= 9'd0;
            shout_latched    <= 1'b0;
            orb_active       <= 4'd0;
            exp_active       <= 8'd0;
            phase            <= PH_IDLE;
            idx_a            <= 6'd0;
            idx_b            <= 6'd0;
            spawn_sub        <= 4'd0;
            spawn_total      <= 4'd0;
            hud_tx           <= 7'd0;
            hud_ty           <= 6'd0;
            hud_we           <= 1'b0;
            hud_waddr        <= 13'd0;
            hud_wdata        <= 12'h020;
            fire_cd          <= 8'd0;
            intro_timer      <= 8'd0;
            dive_timer       <= 8'd60;
            boss_fire_timer  <= 8'd35;
            boss_orb_timer   <= 9'd180;
            boss_dir_right   <= 1'b1;
            boss_atk_mode    <= 2'd0;
            boss_rand_seed   <= 8'd0;
            boss_spin_idx    <= 3'd0;
            boss_salvo_total <= 4'd5;
            wave_kills       <= 5'd0;
            evo_banner_timer <= 8'd0;
            evo_banner_type  <= 2'd0;
            evo_sec_rem      <= 4'd0;
            evo_frame_div    <= 6'd0;
            evo_prev_form    <= 2'd0;
            form_sway        <= 8'sd0;
            form_sway_dir    <= 1'b1;
            prev_uart_fire     <= 1'b0;
            prev_sw_giveup     <= 1'b0;
            surrendered_via_sw <= 1'b0;
            pend_fire_rise     <= 1'b0;
            pend_left_rise   <= 1'b0;
            pend_right_rise  <= 1'b0;
            pending_wave     <= 3'd1;
            led_bar          <= 16'd0;
            evt_flash_timer  <= 4'd0;
            evt_flash_kind   <= 2'd0;
            sfx_valid        <= 1'b0;
            sfx_id           <= 3'd0;
            for (k_rst = 0; k_rst < 6; k_rst = k_rst + 1) begin
                sc_d[k_rst] <= 4'd0;
                hi_d[k_rst] <= 4'd0;
            end
            for (k_rst = 0; k_rst < 16; k_rst = k_rst + 1) begin
                en_x[k_rst] <= 10'd0; en_y[k_rst] <= 10'd0;
                en_home_x[k_rst] <= 10'd0; en_home_y[k_rst] <= 10'd0;
                en_type[k_rst] <= 2'd0; en_hp[k_rst] <= 3'd1;
                en_mode[k_rst] <= 2'd0; en_flash[k_rst] <= 4'd0;
            end
            for (k_rst = 0; k_rst < 24; k_rst = k_rst + 1) begin
                eb_x[k_rst] <= 10'd0; eb_y[k_rst] <= 10'd0;
                eb_vx[k_rst] <= 6'sd0; eb_vy[k_rst] <= 6'sd0;
            end
            for (k_rst = 0; k_rst < 32; k_rst = k_rst + 1) begin
                pb_x[k_rst] <= 10'd0; pb_y[k_rst] <= 10'd0;
                pb_vx[k_rst] <= 6'sd0; pb_vy[k_rst] <= 6'sd0;
                pb_kind[k_rst] <= 2'd0;
            end
            for (k_rst = 0; k_rst < 4; k_rst = k_rst + 1) begin
                orb_x[k_rst] <= 10'd0; orb_y[k_rst] <= 10'd0; orb_type[k_rst] <= 2'd0;
            end
            for (k_rst = 0; k_rst < 8; k_rst = k_rst + 1) begin
                exp_x[k_rst] <= 10'd0; exp_y[k_rst] <= 10'd0; exp_timer[k_rst] <= 4'd0;
            end
        end else begin
            hud_we    <= 1'b0;
            sfx_valid <= 1'b0;
            if (shout_trigger || voice_above_thresh)
                shout_latched <= 1'b1;

            hard_mode <= (game_state == GS_TITLE) ? (menu_hard_sel | sw_hard) : (hard_mode | sw_hard);
            if (allow_btns && btn_fire_rise)  pend_fire_rise  <= 1'b1;
            if (allow_btns && btn_left_rise)  pend_left_rise  <= 1'b1;
            if (allow_btns && btn_right_rise) pend_right_rise <= 1'b1;

            // Update LED bar cleanly
            if (game_state == GS_PLAY && wave_num == 3'd4 && boss_active) begin
                // 16-LED Boss HP bar (scaled for 90 normal / 120 hard)
                for (k_f = 0; k_f < 16; k_f = k_f + 1)
                    led_bar[k_f] <= ({3'd0, k_f[3:0]} * (hard_mode ? 7'd7 : 7'd6) < boss_hp);
            end else if (game_state == GS_PLAY) begin
                led_bar <= en_active;
            end else begin
                led_bar <= {frame_cnt[3:0], 12'd0} | (16'h0001 << player_form);
            end

            case (phase)
                PH_IDLE: begin
                    if (game_tick) begin
                        prev_uart_fire  <= uart_btn_mask[4];
                        prev_kbd_fire   <= (kbd_active & kbd_fire);
                        prev_kbd_left   <= (kbd_active & kbd_left);
                        prev_kbd_right  <= (kbd_active & kbd_right);
                        prev_sw_giveup  <= sw_giveup;
                        pend_fire_rise  <= 1'b0;
                        pend_left_rise  <= 1'b0;
                        pend_right_rise <= 1'b0;
                        frame_cnt       <= frame_cnt + 8'd1;
                        if (shake_amt > 4'd0)       shake_amt <= shake_amt - 4'd1;
                        if (evt_flash_timer > 4'd0) evt_flash_timer <= evt_flash_timer - 4'd1;
                        if (evo_banner_timer > 8'd0) evo_banner_timer <= evo_banner_timer - 8'd1;

                        if (game_state == GS_TITLE) begin
                            if (any_left_pulse || any_right_pulse)
                                menu_hard_sel <= ~menu_hard_sel;
                            if (any_start_pulse) begin
                                for (k_f = 0; k_f < 6; k_f = k_f + 1) sc_d[k_f] <= 4'd0;
                                player_x         <= 10'd304;
                                player_y         <= 10'd410;
                                player_left_face <= 1'b0;
                                player_form      <= 2'd0;
                                evo_prev_form    <= 2'd0;
                                evo_sec_rem      <= 4'd0;
                                evo_frame_div    <= 6'd0;
                                evo_banner_timer <= 8'd0;
                                player_lives     <= 3'd3;
                                player_invuln    <= 8'd60;
                                pb_active        <= 32'd0;
                                eb_active        <= 24'd0;
                                eb_reflected_reg <= 24'd0;
                                barrier_timer    <= 8'd0;
                                barrier_cooldown <= 9'd0;
                                orb_active       <= 4'd0;
                                exp_active       <= 8'd0;
                                boss_active        <= 1'b0;
                                surrendered_via_sw <= 1'b0;
                                hard_mode          <= menu_hard_sel | sw_hard;
                                wave_num           <= 3'd1;
                                pending_wave       <= 3'd1;
                                game_state         <= GS_WAVE_INTRO;
                                intro_timer        <= 8'd75;
                                phase              <= PH_INIT_WAVE;
                                idx_a              <= 6'd0;
                            end else begin
                                hud_tx <= 7'd0; hud_ty <= 6'd0;
                                phase  <= PH_HUD_X;
                            end
                        end else if (game_state == GS_VICTORY || game_state == GS_GAMEOVER) begin
                            if (any_start_pulse || (game_state == GS_GAMEOVER && surrendered_via_sw && sw_giveup_fall)) begin
                                surrendered_via_sw <= 1'b0;
                                game_state         <= GS_TITLE;
                            end
                            hud_tx <= 7'd0; hud_ty <= 6'd0;
                            phase  <= PH_HUD_X;
                        end else if (game_state == GS_PAUSED) begin
                            if (sw_giveup_rise) begin
                                if ({sc_d[5], sc_d[4], sc_d[3], sc_d[2], sc_d[1], sc_d[0]} >
                                    {hi_d[5], hi_d[4], hi_d[3], hi_d[2], hi_d[1], hi_d[0]}) begin
                                    for (k_f = 0; k_f < 6; k_f = k_f + 1) hi_d[k_f] <= sc_d[k_f];
                                end
                                player_lives       <= 3'd0;
                                pb_active          <= 32'd0;
                                eb_active          <= 24'd0;
                                surrendered_via_sw <= 1'b1;
                                evt_flash_timer    <= 4'd15;
                                evt_flash_kind     <= 2'd2;
                                sfx_valid          <= 1'b1;
                                sfx_id             <= 3'd6;
                                game_state         <= GS_GAMEOVER;
                            end else if (!sw_pause) begin
                                game_state <= GS_PLAY;
                            end
                            hud_tx <= 7'd0; hud_ty <= 6'd0;
                            phase  <= PH_HUD_X;
                        end else if (game_state == GS_WAVE_INTRO) begin
                            if (intro_timer > 8'd0 && !any_start_pulse)
                                intro_timer <= intro_timer - 8'd1;
                            else
                                game_state <= GS_PLAY;
                            // Glide enemies smoothly while intro plays
                            idx_a <= 5'd0;
                            phase <= PH_UPD_EN;
                        end else if (game_state == GS_PLAY) begin
                            if (sw_pause) begin
                                game_state <= GS_PAUSED;
                                hud_tx <= 7'd0; hud_ty <= 6'd0;
                                phase  <= PH_HUD_X;
                            end else begin
                                phase <= PH_PLAYER;
                            end
                        end
                    end
                end

                // -----------------------------------------------------------
                // Initialize Wave Formation (1 enemy per cycle: 0..15)
                // -----------------------------------------------------------
                PH_INIT_WAVE: begin
                    if (idx_a < 5'd16) begin
                        if (pending_wave == 3'd4) begin
                            // Wave 4: Harder Boss AJV + 2 escort guards
                            if (idx_a == 6'd0) begin
                                boss_active     <= 1'b1;
                                boss_x          <= 10'd280;
                                boss_y          <= 10'd48;
                                boss_max_hp     <= hard_mode ? 7'd120 : 7'd90;
                                boss_hp         <= hard_mode ? 7'd120 : 7'd90;
                                boss_flash      <= 4'd0;
                                boss_dir_right  <= 1'b1;
                                boss_fire_timer <= 8'd30;
                                boss_orb_timer  <= 9'd180;
                                boss_spin_idx   <= 3'd0;
                                evt_flash_timer <= 4'd15;
                                evt_flash_kind  <= 2'd3;
                                sfx_valid       <= 1'b1;
                                sfx_id          <= 3'd7;
                            end
                            if (idx_a == 6'd1 || idx_a == 6'd2) begin
                                en_active[idx_a[3:0]] <= 1'b1;
                                en_home_x[idx_a[3:0]] <= (idx_a == 6'd1) ? 10'd72 : 10'd536;
                                en_home_y[idx_a[3:0]] <= 10'd108;
                                en_x[idx_a[3:0]]      <= (idx_a == 6'd1) ? 10'd72 : 10'd536;
                                en_y[idx_a[3:0]]      <= 10'd20;
                                en_type[idx_a[3:0]]   <= (idx_a == 6'd1) ? 2'd2 : 2'd3;
                                en_hp[idx_a[3:0]]     <= hard_mode ? 3'd4 : 3'd3;
                                en_mode[idx_a[3:0]]   <= 2'd0;
                                en_flash[idx_a[3:0]]  <= 4'd0;
                            end else begin
                                en_active[idx_a[3:0]] <= 1'b0;
                            end
                        end else begin
                            // 4 columns x 4 rows (or 12 enemies in Wave 1)
                            if (pending_wave == 3'd1 && idx_a[3:2] == 2'd3) begin
                                en_active[idx_a[3:0]] <= 1'b0;
                            end else begin
                                en_active[idx_a[3:0]] <= 1'b1;
                                en_home_x[idx_a[3:0]] <= 10'd120 + {6'd0, idx_a[1:0]} * 10'd112;
                                en_home_y[idx_a[3:0]] <= 10'd64  + {6'd0, idx_a[3:2]} * 10'd44;
                                en_x[idx_a[3:0]]      <= 10'd120 + {6'd0, idx_a[1:0]} * 10'd112;
                                en_y[idx_a[3:0]]      <= 10'd16; // Enter from top
                                en_mode[idx_a[3:0]]   <= 2'd0;
                                en_flash[idx_a[3:0]]  <= 4'd0;
                                if (pending_wave == 3'd1) begin
                                    en_type[idx_a[3:0]] <= idx_a[0] ? 2'd1 : 2'd0; // pf & ppuen
                                    en_hp[idx_a[3:0]]   <= 3'd1;
                                end else if (pending_wave == 3'd2) begin
                                    en_type[idx_a[3:0]] <= idx_a[3:2]; // all 4 types across rows
                                    en_hp[idx_a[3:0]]   <= (idx_a[3:2] >= 2'd2) ? 3'd2 : 3'd1;
                                end else begin
                                    en_type[idx_a[3:0]] <= idx_a[3:2] ^ {1'b0, idx_a[0]};
                                    en_hp[idx_a[3:0]]   <= hard_mode ? 3'd3 : 3'd2;
                                end
                            end
                        end
                        idx_a <= idx_a + 5'd1;
                    end else begin
                        wave_kills    <= 5'd0;
                        form_sway     <= 8'sd0;
                        form_sway_dir <= 1'b1;
                        dive_timer    <= 8'd60;
                        hud_tx        <= 7'd0;
                        hud_ty        <= 6'd0;
                        phase         <= PH_HUD_X;
                    end
                end

                // -----------------------------------------------------------
                // Player Input, Movement & Fire Trigger
                // -----------------------------------------------------------
                PH_PLAYER: begin
                    if (player_invuln > 8'd0) player_invuln <= player_invuln - 8'd1;
                    if (fire_cd > 8'd0)       fire_cd       <= fire_cd - 8'd1;

                    // Barrier active & cooldown timers (sequential: cooldown counts down AFTER barrier ends)
                    if (barrier_timer > 8'd0) begin
                        barrier_timer <= barrier_timer - 8'd1;
                    end else if (barrier_cooldown > 9'd0) begin
                        barrier_cooldown <= barrier_cooldown - 9'd1;
                    end

                    // Voice Barrier Activation (strictly usable ONLY in Last Boss state)
                    if (wave_num == 3'd4 && boss_active && (game_state == GS_PLAY)) begin
                        if (voice_above_thresh || shout_trigger || shout_latched) begin
                            shout_latched <= 1'b0;
                            if (barrier_cooldown == 9'd0 && barrier_timer == 8'd0) begin
                                barrier_timer    <= 8'd180; // 3.0 seconds active barrier
                                barrier_cooldown <= 9'd480; // 8.0 seconds cooldown AFTER barrier expires
                                sfx_valid        <= 1'b1;
                                sfx_id           <= 3'd3;   // Nova shield power SFX
                                shake_amt        <= 4'd2;
                            end
                        end
                    end else begin
                        shout_latched <= 1'b0;
                    end

                    // Timed Evolution countdown (reverts to evo_prev_form when expired)
                    if (evo_sec_rem > 4'd0) begin
                        if (evo_frame_div > 6'd0) begin
                            evo_frame_div <= evo_frame_div - 6'd1;
                        end else begin
                            evo_frame_div <= 6'd59;
                            if (evo_sec_rem == 4'd1) begin
                                evo_sec_rem  <= 4'd0;
                                player_form  <= evo_prev_form;
                            end else begin
                                evo_sec_rem <= evo_sec_rem - 4'd1;
                            end
                        end
                    end

                    // Global formation sway
                    if (frame_cnt[1:0] == 2'd0) begin
                        if (form_sway_dir) begin
                            if (form_sway >= 8'sd56) form_sway_dir <= 1'b0;
                            else                     form_sway     <= form_sway + 8'sd1;
                        end else begin
                            if (form_sway <= -8'sd56) form_sway_dir <= 1'b1;
                            else                      form_sway     <= form_sway - 8'sd1;
                        end
                    end

                    // 4-way movement clamped in playfield
                    if (eff_left && player_x > 10'd16) begin
                        player_x         <= player_x - 10'd3;
                        player_left_face <= 1'b1;
                    end else if (eff_right && player_x < 10'd592) begin
                        player_x         <= player_x + 10'd3;
                        player_left_face <= 1'b0;
                    end

                    if (eff_up && player_y > 10'd72)
                        player_y <= player_y - 10'd3;
                    else if (eff_down && player_y < 10'd440)
                        player_y <= player_y + 10'd3;

                    // Check fire
                    if (eff_fire && fire_cd == 8'd0) begin
                        spawn_sub   <= 4'd0;
                        idx_a       <= 5'd0;
                        sfx_valid   <= 1'b1;
                        if (player_form == 2'd0) begin
                            spawn_total <= 4'd1;
                            fire_cd     <= 8'd12;
                            sfx_id      <= 3'd1;
                        end else if (player_form == 2'd1) begin
                            spawn_total <= 4'd2;
                            fire_cd     <= 8'd10;
                            sfx_id      <= 3'd2;
                        end else begin
                            spawn_total <= 4'd9;
                            fire_cd     <= 8'd14;
                            sfx_id      <= 3'd3;
                        end
                        phase <= PH_SPAWN_PB;
                    end else begin
                        idx_a <= 6'd0;
                        phase <= PH_UPD_PB;
                    end
                end

                // -----------------------------------------------------------
                // Spawn Player Bullets (1 per cycle, 1/2/9 bullets by form)
                // -----------------------------------------------------------
                PH_SPAWN_PB: begin
                    if (spawn_sub < spawn_total && idx_a < 6'd32) begin
                        if (!pb_active[idx_a[4:0]]) begin
                            pb_active[idx_a[4:0]] <= 1'b1;
                            pb_kind[idx_a[4:0]]   <= player_form;
                            if (player_form == 2'd0) begin
                                pb_x[idx_a[4:0]]  <= player_x + 10'd8;
                                pb_y[idx_a[4:0]]  <= player_y - 10'd6;
                                pb_vx[idx_a[4:0]] <= 6'sd0;
                                pb_vy[idx_a[4:0]] <= -6'sd7;
                            end else if (player_form == 2'd1) begin
                                pb_x[idx_a[4:0]]  <= (spawn_sub == 4'd0) ? player_x : (player_x + 10'd16);
                                pb_y[idx_a[4:0]]  <= player_y - 10'd4;
                                pb_vx[idx_a[4:0]] <= 6'sd0;
                                pb_vy[idx_a[4:0]] <= -6'sd8;
                            end else begin
                                // 180-degree forward fan (9 dense rays, every 22.5 deg, vy <= 0)
                                pb_x[idx_a[4:0]] <= player_x + 10'd8;
                                pb_y[idx_a[4:0]] <= player_y - 10'd2;
                                case (spawn_sub)
                                    4'd0: begin pb_vx[idx_a[4:0]] <= -6'sd8; pb_vy[idx_a[4:0]] <=  6'sd0; end
                                    4'd1: begin pb_vx[idx_a[4:0]] <= -6'sd7; pb_vy[idx_a[4:0]] <= -6'sd3; end
                                    4'd2: begin pb_vx[idx_a[4:0]] <= -6'sd6; pb_vy[idx_a[4:0]] <= -6'sd6; end
                                    4'd3: begin pb_vx[idx_a[4:0]] <= -6'sd3; pb_vy[idx_a[4:0]] <= -6'sd7; end
                                    4'd4: begin pb_vx[idx_a[4:0]] <=  6'sd0; pb_vy[idx_a[4:0]] <= -6'sd8; end
                                    4'd5: begin pb_vx[idx_a[4:0]] <=  6'sd3; pb_vy[idx_a[4:0]] <= -6'sd7; end
                                    4'd6: begin pb_vx[idx_a[4:0]] <=  6'sd6; pb_vy[idx_a[4:0]] <= -6'sd6; end
                                    4'd7: begin pb_vx[idx_a[4:0]] <=  6'sd7; pb_vy[idx_a[4:0]] <= -6'sd3; end
                                    default: begin pb_vx[idx_a[4:0]] <= 6'sd8; pb_vy[idx_a[4:0]] <= 6'sd0; end
                                endcase
                            end
                            spawn_sub <= spawn_sub + 4'd1;
                            idx_a     <= idx_a + 6'd1;
                        end else begin
                            idx_a <= idx_a + 6'd1;
                        end
                    end else begin
                        idx_a <= 6'd0;
                        phase <= PH_UPD_PB;
                    end
                end

                // -----------------------------------------------------------
                // Move Player Bullets (1 per cycle)
                // -----------------------------------------------------------
                PH_UPD_PB: begin
                    if (idx_a < 6'd32) begin
                        if (pb_active[idx_a[4:0]]) begin
                            if ($signed({1'b0, pb_x[idx_a[4:0]]}) + $signed(pb_vx[idx_a[4:0]]) < 11'sd4 ||
                                $signed({1'b0, pb_x[idx_a[4:0]]}) + $signed(pb_vx[idx_a[4:0]]) > 11'sd628 ||
                                $signed({1'b0, pb_y[idx_a[4:0]]}) + $signed(pb_vy[idx_a[4:0]]) < 11'sd20 ||
                                $signed({1'b0, pb_y[idx_a[4:0]]}) + $signed(pb_vy[idx_a[4:0]]) > 11'sd468) begin
                                pb_active[idx_a[4:0]] <= 1'b0;
                            end else begin
                                pb_x[idx_a[4:0]] <= $signed({1'b0, pb_x[idx_a[4:0]]}) + $signed(pb_vx[idx_a[4:0]]);
                                pb_y[idx_a[4:0]] <= $signed({1'b0, pb_y[idx_a[4:0]]}) + $signed(pb_vy[idx_a[4:0]]);
                            end
                        end
                        idx_a <= idx_a + 6'd1;
                    end else begin
                        idx_a <= 6'd0;
                        idx_b <= 6'd0;
                        phase <= PH_COL_PB;
                    end
                end

                // -----------------------------------------------------------
                // Player Bullet vs Enemy / Boss Collision (1 pair per cycle)
                // -----------------------------------------------------------
                PH_COL_PB: begin
                    if (idx_a < 6'd32) begin
                        if (!pb_active[idx_a[4:0]]) begin
                            idx_a <= idx_a + 6'd1;
                            idx_b <= 6'd0;
                        end else if (idx_b < 6'd16) begin
                            if (en_active[idx_b[3:0]]) begin
                                if (oct_dist(pb_x[idx_a[4:0]] + 10'd8, pb_y[idx_a[4:0]] + 10'd8,
                                             en_x[idx_b[3:0]] + 10'd16, en_y[idx_b[3:0]] + 10'd16) < 11'd20) begin
                                    pb_active[idx_a[4:0]] <= 1'b0;
                                    if (en_hp[idx_b[3:0]] <= 3'd1) begin
                                        en_active[idx_b[3:0]] <= 1'b0;
                                        spawn_explosion(en_x[idx_b[3:0]], en_y[idx_b[3:0]]);
                                        sfx_valid <= 1'b1;
                                        sfx_id    <= 3'd4;
                                        shake_amt <= 4'd3;
                                        wave_kills <= wave_kills + 5'd1;
                                        if (en_type[idx_b[3:0]] >= 2'd2)
                                            add_bcd_score(4'd0, 4'd2, 4'd0, 4'd0); // +200
                                        else
                                            add_bcd_score(4'd0, 4'd1, 4'd0, 4'd0); // +100

                                        // Power-up Evo Orb drops!
                                        if (wave_num == 3'd1 && wave_kills == 5'd2 && player_form == 2'd0) begin
                                            spawn_orb(en_x[idx_b[3:0]] + 10'd8, en_y[idx_b[3:0]] + 10'd8, 2'd0);
                                        end else if (wave_num == 3'd2 && wave_kills == 5'd2 && player_form <= 2'd1) begin
                                            spawn_orb(en_x[idx_b[3:0]] + 10'd8, en_y[idx_b[3:0]] + 10'd8, 2'd1);
                                        end else if (lfsr[2:0] == 3'd0) begin
                                            if (player_form == 2'd0)
                                                spawn_orb(en_x[idx_b[3:0]] + 10'd8, en_y[idx_b[3:0]] + 10'd8, 2'd0);
                                            else if (player_form == 2'd1)
                                                spawn_orb(en_x[idx_b[3:0]] + 10'd8, en_y[idx_b[3:0]] + 10'd8, 2'd1);
                                            else
                                                spawn_orb(en_x[idx_b[3:0]] + 10'd8, en_y[idx_b[3:0]] + 10'd8, 2'd2);
                                        end
                                    end else begin
                                        en_hp[idx_b[3:0]]    <= en_hp[idx_b[3:0]] - 3'd1;
                                        en_flash[idx_b[3:0]] <= 4'd6;
                                    end
                                    idx_a <= idx_a + 6'd1;
                                    idx_b <= 6'd0;
                                end else begin
                                    idx_b <= idx_b + 6'd1;
                                end
                            end else begin
                                idx_b <= idx_b + 6'd1;
                            end
                        end else begin
                            // Check Boss AJV (idx_b == 16)
                            if (boss_active &&
                                abs_diff(pb_x[idx_a[4:0]] + 10'd8, boss_x + 10'd40) < 10'd36 &&
                                abs_diff(pb_y[idx_a[4:0]] + 10'd8, boss_y + 10'd40) < 10'd36) begin
                                pb_active[idx_a[4:0]] <= 1'b0;
                                boss_flash            <= 4'd4;
                                add_bcd_score(4'd0, 4'd0, 4'd5, 4'd0); // +50
                                if (boss_hp <= 7'd1) begin
                                    boss_hp     <= 7'd0;
                                    boss_active <= 1'b0;
                                    spawn_explosion(boss_x + 10'd12, boss_y + 10'd12);
                                    spawn_explosion(boss_x + 10'd36, boss_y + 10'd28);
                                    spawn_explosion(boss_x + 10'd24, boss_y + 10'd40);
                                    add_bcd_score(4'd2, 4'd0, 4'd0, 4'd0); // +2000
                                    shake_amt <= 4'd15;
                                    sfx_valid <= 1'b1;
                                    sfx_id    <= 3'd4;
                                end else begin
                                    boss_hp <= boss_hp - 7'd1;
                                    // Drop Heart item at Phase 2 milestone & 25% HP remaining
                                    if (boss_hp == (boss_max_hp >> 1) + 7'd1 || boss_hp == 7'd24)
                                        spawn_orb(boss_x + 10'd32, boss_y + 10'd64, 2'd2);
                                end
                            end
                            idx_a <= idx_a + 6'd1;
                            idx_b <= 6'd0;
                        end
                    end else begin
                        idx_a <= 6'd0;
                        phase <= PH_UPD_EN;
                    end
                end

                // -----------------------------------------------------------
                // Update Enemies (1 per cycle)
                // -----------------------------------------------------------
                PH_UPD_EN: begin
                    if (idx_a == 5'd0 && game_state == GS_PLAY) begin
                        if (dive_timer > 8'd0) dive_timer <= dive_timer - 8'd1;
                        else dive_timer <= (wave_num == 3'd1) ? 8'd90 : ((wave_num == 3'd2) ? 8'd65 : 8'd45);
                    end

                    if (idx_a < 5'd16) begin
                        if (en_active[idx_a[3:0]]) begin
                            if (en_flash[idx_a[3:0]] > 4'd0)
                                en_flash[idx_a[3:0]] <= en_flash[idx_a[3:0]] - 4'd1;

                            if (en_mode[idx_a[3:0]] == 2'd0 || en_mode[idx_a[3:0]] == 2'd3) begin
                                // Entering / Returning to formation slot
                                if (en_x[idx_a[3:0]] < cur_en_target_x)      en_x[idx_a[3:0]] <= en_x[idx_a[3:0]] + 10'd2;
                                else if (en_x[idx_a[3:0]] > cur_en_target_x) en_x[idx_a[3:0]] <= en_x[idx_a[3:0]] - 10'd2;

                                if (en_y[idx_a[3:0]] < en_home_y[idx_a[3:0]])
                                    en_y[idx_a[3:0]] <= en_y[idx_a[3:0]] + 10'd2;
                                else if (en_y[idx_a[3:0]] > en_home_y[idx_a[3:0]])
                                    en_y[idx_a[3:0]] <= en_y[idx_a[3:0]] - 10'd2;
                                else if (abs_diff(en_x[idx_a[3:0]], cur_en_target_x) <= 10'd3)
                                    en_mode[idx_a[3:0]] <= 2'd1;
                            end else if (en_mode[idx_a[3:0]] == 2'd1) begin
                                // Formation sway
                                en_x[idx_a[3:0]] <= $signed({1'b0, en_home_x[idx_a[3:0]]}) + $signed(form_sway);
                                en_y[idx_a[3:0]] <= en_home_y[idx_a[3:0]];
                                if (game_state == GS_PLAY && dive_timer == 8'd0 && idx_a[3:0] == lfsr[3:0]) begin
                                    en_mode[idx_a[3:0]] <= 2'd2;
                                end else if (game_state == GS_PLAY && lfsr[9:0] == {idx_a[3:0], 6'd7} && (wave_num >= 3'd2 || hard_mode)) begin
                                    spawn_enemy_bullet(en_x[idx_a[3:0]] + 10'd8, en_y[idx_a[3:0]] + 10'd24, 6'sd0, hard_mode ? 6'sd4 : 6'sd3);
                                end
                            end else begin
                                // Diving toward player!
                                en_y[idx_a[3:0]] <= en_y[idx_a[3:0]] + (hard_mode ? 10'd4 : 10'd3);
                                if (en_x[idx_a[3:0]] + 10'd2 < player_x)
                                    en_x[idx_a[3:0]] <= en_x[idx_a[3:0]] + 10'd2;
                                else if (en_x[idx_a[3:0]] > player_x + 10'd2)
                                    en_x[idx_a[3:0]] <= en_x[idx_a[3:0]] - 10'd2;

                                if (en_y[idx_a[3:0]] == 10'd180 || en_y[idx_a[3:0]] == 10'd280) begin
                                    spawn_enemy_bullet(en_x[idx_a[3:0]] + 10'd8, en_y[idx_a[3:0]] + 10'd20,
                                                       (player_x > en_x[idx_a[3:0]]) ? 6'sd1 : -6'sd1, 6'sd4);
                                end
                                if (en_y[idx_a[3:0]] > 10'd456) begin
                                    en_y[idx_a[3:0]]    <= 10'd24;
                                    en_mode[idx_a[3:0]] <= 2'd3;
                                end
                            end

                            // Enemy vs Player body collision (absorbed if barrier active)
                            if (game_state == GS_PLAY && !barrier_active &&
                                oct_dist(en_x[idx_a[3:0]] + 10'd16, en_y[idx_a[3:0]] + 10'd16,
                                         player_x + 10'd16, player_y + 10'd16) < 11'd24) begin
                                trigger_player_hit();
                            end
                        end
                        idx_a <= idx_a + 5'd1;
                    end else begin
                        if (game_state == GS_WAVE_INTRO) begin
                            hud_tx <= 7'd0; hud_ty <= 6'd0;
                            phase  <= PH_HUD_X;
                        end else begin
                            phase <= PH_UPD_BOSS;
                        end
                    end
                end

                // -----------------------------------------------------------
                // Update Boss AJV (Faster weave, random feints, multi-dir barrages)
                // -----------------------------------------------------------
                PH_UPD_BOSS: begin
                    if (boss_active) begin
                        if (boss_flash > 4'd0) boss_flash <= boss_flash - 4'd1;
                        // Move horizontally (faster in phase 2, plus random mid-arena feints)
                        if ((boss_hp <= (boss_max_hp >> 1)) ? (lfsr[7:0] == 8'hA5) : (lfsr[8:0] == 9'h155)) begin
                            boss_dir_right <= ~boss_dir_right;
                        end else if (boss_dir_right) begin
                            if (boss_x >= 10'd516) boss_dir_right <= 1'b0;
                            else boss_x <= boss_x + ((boss_hp <= (boss_max_hp >> 1)) ? 10'd4 : 10'd3);
                        end else begin
                            if (boss_x <= 10'd44) boss_dir_right <= 1'b1;
                            else boss_x <= boss_x - ((boss_hp <= (boss_max_hp >> 1)) ? 10'd4 : 10'd3);
                        end
                        // Deeper vertical swoop when enraged
                        if (boss_hp <= (boss_max_hp >> 1))
                            boss_y <= 10'd48 + {5'd0, frame_cnt[5] ? (5'd31 - frame_cnt[4:0]) : frame_cnt[4:0]};
                        else
                            boss_y <= 10'd54 + {6'd0, frame_cnt[4] ? (4'd15 - frame_cnt[3:0]) : frame_cnt[3:0]};

                        // Periodically drop Evo Orbs & Extra Hearts during boss fight
                        if (orb_active == 4'd0) begin
                            if (boss_orb_timer > 9'd0) begin
                                boss_orb_timer <= boss_orb_timer - 9'd1;
                            end else begin
                                if (player_form == 2'd0) begin
                                    // White Goose: drop Blue Orb to start evolution (next in 4.0s)
                                    boss_orb_timer <= 9'd240;
                                    spawn_orb(boss_x + 10'd32, boss_y + 10'd68, 2'd0);
                                end else if (player_form == 2'd1) begin
                                    // Blue Goose: drop Rainbow Orb within 3.0s (guaranteed well inside 9s window!)
                                    boss_orb_timer <= 9'd180;
                                    spawn_orb(boss_x + 10'd32, boss_y + 10'd68, 2'd1);
                                end else begin
                                    // Rainbow Goose: drop Heart item to sustain max form (5.0s)
                                    boss_orb_timer <= 9'd300;
                                    spawn_orb(boss_x + 10'd32, boss_y + 10'd68, 2'd2);
                                end
                            end
                        end

                        // Boss vs Player collision (shield protects goose)
                        if (!barrier_active &&
                            abs_diff(boss_x + 10'd40, player_x + 10'd16) < 10'd48 &&
                            abs_diff(boss_y + 10'd40, player_y + 10'd16) < 10'd48) begin
                            trigger_player_hit();
                        end

                        // Trigger randomized multi-directional fire salvo
                        if (boss_fire_timer > 8'd0) begin
                            boss_fire_timer <= boss_fire_timer - 8'd1;
                            idx_a <= 6'd0;
                            phase <= PH_UPD_EB;
                        end else begin
                            if (boss_hp <= (boss_max_hp >> 1)) begin
                                // Enraged AJV2: rapid relentless barrage!
                                boss_fire_timer  <= hard_mode ? 8'd14 : 8'd18;
                                boss_salvo_total <= 4'd7;
                            end else begin
                                // Normal AJV (calmer phase 1): fires slower with fewer bullets!
                                boss_fire_timer  <= hard_mode ? 8'd45 : 8'd60;
                                boss_salvo_total <= 4'd4;
                            end
                            boss_atk_mode    <= lfsr[1:0];
                            boss_rand_seed   <= lfsr[13:6];
                            boss_spin_idx    <= boss_spin_idx + 3'd1;
                            spawn_sub        <= 4'd0;
                            idx_a            <= 6'd0;
                            phase            <= PH_BOSS_FIRE;
                        end
                    end else begin
                        idx_a <= 6'd0;
                        phase <= PH_UPD_EB;
                    end
                end

                // -----------------------------------------------------------
                // Spawn Boss AJV Randomized Multi-Directional Salvo (1 per cycle)
                // -----------------------------------------------------------
                PH_BOSS_FIRE: begin
                    if (spawn_sub < boss_salvo_total && idx_a < 6'd24) begin
                        if (!eb_active[idx_a[4:0]]) begin
                            eb_active[idx_a[4:0]]        <= 1'b1;
                            eb_reflected_reg[idx_a[4:0]] <= 1'b0;
                            eb_x[idx_a[4:0]]             <= boss_x + 10'd32;
                            eb_y[idx_a[4:0]]      <= boss_y + 10'd56;
                            case (boss_atk_mode)
                                2'd0: begin
                                    // Random Chaos Multi-Directional Scatter (16 angles via LFSR + spawn_sub)
                                    case (lfsr[3:0] ^ boss_rand_seed[3:0] ^ spawn_sub)
                                        4'd0:  begin eb_vx[idx_a[4:0]] <= -6'sd6; eb_vy[idx_a[4:0]] <=  6'sd2; end
                                        4'd1:  begin eb_vx[idx_a[4:0]] <= -6'sd5; eb_vy[idx_a[4:0]] <=  6'sd3; end
                                        4'd2:  begin eb_vx[idx_a[4:0]] <= -6'sd4; eb_vy[idx_a[4:0]] <=  6'sd5; end
                                        4'd3:  begin eb_vx[idx_a[4:0]] <= -6'sd2; eb_vy[idx_a[4:0]] <=  6'sd6; end
                                        4'd4:  begin eb_vx[idx_a[4:0]] <=  6'sd0; eb_vy[idx_a[4:0]] <=  6'sd6; end
                                        4'd5:  begin eb_vx[idx_a[4:0]] <=  6'sd2; eb_vy[idx_a[4:0]] <=  6'sd6; end
                                        4'd6:  begin eb_vx[idx_a[4:0]] <=  6'sd4; eb_vy[idx_a[4:0]] <=  6'sd5; end
                                        4'd7:  begin eb_vx[idx_a[4:0]] <=  6'sd5; eb_vy[idx_a[4:0]] <=  6'sd3; end
                                        4'd8:  begin eb_vx[idx_a[4:0]] <=  6'sd6; eb_vy[idx_a[4:0]] <=  6'sd2; end
                                        4'd9:  begin eb_vx[idx_a[4:0]] <= -6'sd5; eb_vy[idx_a[4:0]] <=  6'sd1; end
                                        4'd10: begin eb_vx[idx_a[4:0]] <=  6'sd5; eb_vy[idx_a[4:0]] <=  6'sd1; end
                                        4'd11: begin eb_vx[idx_a[4:0]] <= -6'sd3; eb_vy[idx_a[4:0]] <=  6'sd5; end
                                        4'd12: begin eb_vx[idx_a[4:0]] <=  6'sd3; eb_vy[idx_a[4:0]] <=  6'sd5; end
                                        4'd13: begin eb_vx[idx_a[4:0]] <= -6'sd1; eb_vy[idx_a[4:0]] <=  6'sd5; end
                                        4'd14: begin eb_vx[idx_a[4:0]] <=  6'sd1; eb_vy[idx_a[4:0]] <=  6'sd5; end
                                        default: begin eb_vx[idx_a[4:0]] <= (boss_rand_seed[4] ? 6'sd4 : -6'sd4); eb_vy[idx_a[4:0]] <= 6'sd4; end
                                    endcase
                                end
                                2'd1: begin
                                    // Shifted Wide Spread Fan (with random jitter)
                                    case (spawn_sub[2:0])
                                        3'd0: begin eb_vx[idx_a[4:0]] <= -6'sd5; eb_vy[idx_a[4:0]] <= 6'sd3; end
                                        3'd1: begin eb_vx[idx_a[4:0]] <= -6'sd3 + (boss_rand_seed[0] ? 6'sd1 : -6'sd1); eb_vy[idx_a[4:0]] <= 6'sd5; end
                                        3'd2: begin eb_vx[idx_a[4:0]] <=  6'sd0 + (boss_rand_seed[1] ? 6'sd1 : -6'sd1); eb_vy[idx_a[4:0]] <= 6'sd6; end
                                        3'd3: begin eb_vx[idx_a[4:0]] <=  6'sd3 + (boss_rand_seed[2] ? 6'sd1 : -6'sd1); eb_vy[idx_a[4:0]] <= 6'sd5; end
                                        3'd4: begin eb_vx[idx_a[4:0]] <=  6'sd5; eb_vy[idx_a[4:0]] <= 6'sd3; end
                                        3'd5: begin eb_vx[idx_a[4:0]] <= -6'sd6; eb_vy[idx_a[4:0]] <= 6'sd2; end
                                        default: begin eb_vx[idx_a[4:0]] <= 6'sd6; eb_vy[idx_a[4:0]] <= 6'sd2; end
                                    endcase
                                end
                                2'd2: begin
                                    // Aimed Player Volley + Diagonal Flank Barrage
                                    if (spawn_sub == 4'd0 || spawn_sub == 4'd1) begin
                                        eb_vx[idx_a[4:0]] <= (player_x > boss_x + 10'd48) ? 6'sd3 :
                                                             ((player_x + 10'd16 < boss_x + 10'd32) ? -6'sd3 : 6'sd0);
                                        eb_vy[idx_a[4:0]] <= (spawn_sub == 4'd0) ? 6'sd6 : 6'sd5;
                                    end else if (spawn_sub == 4'd2) begin
                                        eb_x[idx_a[4:0]]  <= boss_x + 10'd12;
                                        eb_vx[idx_a[4:0]] <= -6'sd4; eb_vy[idx_a[4:0]] <= 6'sd4;
                                    end else if (spawn_sub == 4'd3) begin
                                        eb_x[idx_a[4:0]]  <= boss_x + 10'd60;
                                        eb_vx[idx_a[4:0]] <=  6'sd4; eb_vy[idx_a[4:0]] <= 6'sd4;
                                    end else if (spawn_sub == 4'd4) begin
                                        eb_vx[idx_a[4:0]] <= (boss_rand_seed[3] ? 6'sd2 : -6'sd2);
                                        eb_vy[idx_a[4:0]] <= 6'sd6;
                                    end else if (spawn_sub == 4'd5) begin
                                        eb_vx[idx_a[4:0]] <= -6'sd5; eb_vy[idx_a[4:0]] <= 6'sd2;
                                    end else begin
                                        eb_vx[idx_a[4:0]] <=  6'sd5; eb_vy[idx_a[4:0]] <= 6'sd2;
                                    end
                                end
                                default: begin
                                    // Rotating Spiral Pinwheel (random start + rotating offset)
                                    case (boss_spin_idx + spawn_sub[2:0] + boss_rand_seed[2:0])
                                        3'd0: begin eb_vx[idx_a[4:0]] <= -6'sd6; eb_vy[idx_a[4:0]] <= 6'sd1; end
                                        3'd1: begin eb_vx[idx_a[4:0]] <= -6'sd4; eb_vy[idx_a[4:0]] <= 6'sd4; end
                                        3'd2: begin eb_vx[idx_a[4:0]] <= -6'sd2; eb_vy[idx_a[4:0]] <= 6'sd6; end
                                        3'd3: begin eb_vx[idx_a[4:0]] <=  6'sd0; eb_vy[idx_a[4:0]] <= 6'sd6; end
                                        3'd4: begin eb_vx[idx_a[4:0]] <=  6'sd2; eb_vy[idx_a[4:0]] <= 6'sd6; end
                                        3'd5: begin eb_vx[idx_a[4:0]] <=  6'sd4; eb_vy[idx_a[4:0]] <= 6'sd4; end
                                        3'd6: begin eb_vx[idx_a[4:0]] <=  6'sd6; eb_vy[idx_a[4:0]] <= 6'sd1; end
                                        default: begin eb_vx[idx_a[4:0]] <= (boss_rand_seed[5] ? 6'sd3 : -6'sd3); eb_vy[idx_a[4:0]] <= 6'sd5; end
                                    endcase
                                end
                            endcase
                            spawn_sub <= spawn_sub + 4'd1;
                            idx_a     <= idx_a + 6'd1;
                        end else begin
                            idx_a <= idx_a + 6'd1;
                        end
                    end else begin
                        idx_a <= 6'd0;
                        phase <= PH_UPD_EB;
                    end
                end

                // -----------------------------------------------------------
                // Update Enemy Bullets (1 per cycle, 24 slots)
                // -----------------------------------------------------------
                PH_UPD_EB: begin
                    if (idx_a < 6'd24) begin
                        if (eb_active[idx_a[4:0]]) begin
                            if ($signed({1'b0, eb_x[idx_a[4:0]]}) + $signed(eb_vx[idx_a[4:0]]) < 11'sd4 ||
                                $signed({1'b0, eb_x[idx_a[4:0]]}) + $signed(eb_vx[idx_a[4:0]]) > 11'sd624 ||
                                $signed({1'b0, eb_y[idx_a[4:0]]}) + $signed(eb_vy[idx_a[4:0]]) < 11'sd4 ||
                                $signed({1'b0, eb_y[idx_a[4:0]]}) + $signed(eb_vy[idx_a[4:0]]) > 11'sd468) begin
                                eb_active[idx_a[4:0]]        <= 1'b0;
                                eb_reflected_reg[idx_a[4:0]] <= 1'b0;
                            end else begin
                                eb_x[idx_a[4:0]] <= $signed({1'b0, eb_x[idx_a[4:0]]}) + $signed(eb_vx[idx_a[4:0]]);
                                eb_y[idx_a[4:0]] <= $signed({1'b0, eb_y[idx_a[4:0]]}) + $signed(eb_vy[idx_a[4:0]]);

                                if (eb_reflected_reg[idx_a[4:0]]) begin
                                    // Reflected bullet hits Boss AJV!
                                    if (boss_active &&
                                        abs_diff(eb_x[idx_a[4:0]] + 10'd8, boss_x + 10'd40) < 10'd36 &&
                                        abs_diff(eb_y[idx_a[4:0]] + 10'd8, boss_y + 10'd40) < 10'd36) begin
                                        eb_active[idx_a[4:0]]        <= 1'b0;
                                        eb_reflected_reg[idx_a[4:0]] <= 1'b0;
                                        boss_flash                   <= 4'd4;
                                        add_bcd_score(4'd0, 4'd1, 4'd0, 4'd0); // +100
                                        if (boss_hp <= 7'd2) begin
                                            boss_hp     <= 7'd0;
                                            boss_active <= 1'b0;
                                            spawn_explosion(boss_x + 10'd12, boss_y + 10'd12);
                                            spawn_explosion(boss_x + 10'd36, boss_y + 10'd28);
                                            spawn_explosion(boss_x + 10'd24, boss_y + 10'd40);
                                            add_bcd_score(4'd2, 4'd0, 4'd0, 4'd0); // +2000
                                            shake_amt <= 4'd15;
                                            sfx_valid <= 1'b1;
                                            sfx_id    <= 3'd4;
                                        end else begin
                                            boss_hp   <= boss_hp - 7'd2; // Reflected bullet deals heavy 2 HP damage!
                                            sfx_valid <= 1'b1;
                                            sfx_id    <= 3'd1;
                                            if (boss_hp == (boss_max_hp >> 1) + 7'd2 || boss_hp == (boss_max_hp >> 1) + 7'd1 || boss_hp == 7'd24)
                                                spawn_orb(boss_x + 10'd32, boss_y + 10'd64, 2'd2);
                                        end
                                    end
                                end else begin
                                    // Normal enemy bullet
                                    // Voice Barrier protection check (pure defense, absorb bullets)
                                    if (barrier_active &&
                                        oct_dist(eb_x[idx_a[4:0]] + 10'd8, eb_y[idx_a[4:0]] + 10'd8,
                                                 player_x + 10'd16, player_y + 10'd16) < 11'd32) begin
                                        // PURE DEFENSE: Absorb and neutralize enemy bullet
                                        eb_active[idx_a[4:0]]        <= 1'b0;
                                        eb_reflected_reg[idx_a[4:0]] <= 1'b0;
                                        sfx_valid                    <= 1'b1;
                                        sfx_id                       <= 3'd1; // Deflection sound
                                    end else if (oct_dist(eb_x[idx_a[4:0]] + 10'd8, eb_y[idx_a[4:0]] + 10'd8,
                                                         player_x + 10'd16, player_y + 10'd16) < 11'd13) begin
                                        eb_active[idx_a[4:0]]        <= 1'b0;
                                        eb_reflected_reg[idx_a[4:0]] <= 1'b0;
                                        trigger_player_hit();
                                    end
                                end
                            end
                        end
                        idx_a <= idx_a + 6'd1;
                    end else begin
                        idx_a <= 6'd0;
                        phase <= PH_UPD_ORB;
                    end
                end

                // -----------------------------------------------------------
                // Update Power-Up Orbs (1 per cycle)
                // -----------------------------------------------------------
                PH_UPD_ORB: begin
                    if (idx_a < 6'd4) begin
                        if (orb_active[idx_a[1:0]]) begin
                            if (orb_y[idx_a[1:0]] >= 10'd464) begin
                                orb_active[idx_a[1:0]] <= 1'b0;
                            end else begin
                                orb_y[idx_a[1:0]] <= orb_y[idx_a[1:0]] + 10'd2;
                                if (oct_dist(orb_x[idx_a[1:0]] + 10'd8, orb_y[idx_a[1:0]] + 10'd8,
                                             player_x + 10'd16, player_y + 10'd16) < 11'd24) begin
                                    orb_active[idx_a[1:0]] <= 1'b0;
                                    sfx_valid       <= 1'b1;
                                    sfx_id          <= 3'd5;
                                    evt_flash_timer <= 4'd15;
                                    evt_flash_kind  <= 2'd1;
                                    if (orb_type[idx_a[1:0]] == 2'd0) begin
                                        if (evo_sec_rem == 4'd0)
                                            evo_prev_form <= player_form;
                                        if (player_form < 2'd1)
                                            player_form <= 2'd1;
                                        evo_sec_rem      <= 4'd9;
                                        evo_frame_div    <= 6'd59;
                                        evo_banner_type  <= 2'd1;
                                        evo_banner_timer <= 8'd90;
                                        add_bcd_score(4'd0, 4'd3, 4'd0, 4'd0);
                                        if (wave_num == 3'd4 && boss_active)
                                            boss_orb_timer <= 9'd150; // In boss fight, spawn Rainbow Orb in 2.5s!
                                    end else if (orb_type[idx_a[1:0]] == 2'd1) begin
                                        if (evo_sec_rem == 4'd0)
                                            evo_prev_form <= player_form;
                                        player_form      <= 2'd2;
                                        evo_sec_rem      <= 4'd9;
                                        evo_frame_div    <= 6'd59;
                                        evo_banner_type  <= 2'd2;
                                        evo_banner_timer <= 8'd90;
                                        add_bcd_score(4'd0, 4'd5, 4'd0, 4'd0);
                                    end else begin
                                        if (player_lives < 3'd5) player_lives <= player_lives + 3'd1;
                                        evo_banner_type  <= 2'd3;
                                        evo_banner_timer <= 8'd90;
                                        add_bcd_score(4'd0, 4'd2, 4'd0, 4'd0);
                                    end
                                end
                            end
                        end
                        idx_a <= idx_a + 6'd1;
                    end else begin
                        idx_a <= 6'd0;
                        phase <= PH_UPD_EXP;
                    end
                end

                // -----------------------------------------------------------
                // Update Explosions (1 per cycle)
                // -----------------------------------------------------------
                PH_UPD_EXP: begin
                    if (idx_a < 6'd8) begin
                        if (exp_active[idx_a[2:0]]) begin
                            if (exp_timer[idx_a[2:0]] == 4'd15)
                                exp_active[idx_a[2:0]] <= 1'b0;
                            else
                                exp_timer[idx_a[2:0]] <= exp_timer[idx_a[2:0]] + 4'd1;
                        end
                        idx_a <= idx_a + 6'd1;
                    end else begin
                        phase <= PH_WAVE_CHK;
                    end
                end

                // -----------------------------------------------------------
                // Wave Clear / Win / Lose Check
                // -----------------------------------------------------------
                PH_WAVE_CHK: begin
                    // Update High Score (lexicographical BCD check)
                    if ({sc_d[5], sc_d[4], sc_d[3], sc_d[2], sc_d[1], sc_d[0]} >
                        {hi_d[5], hi_d[4], hi_d[3], hi_d[2], hi_d[1], hi_d[0]}) begin
                        for (k_f = 0; k_f < 6; k_f = k_f + 1) hi_d[k_f] <= sc_d[k_f];
                    end

                    if (player_lives == 3'd0) begin
                        game_state <= GS_GAMEOVER;
                        hud_tx <= 7'd0; hud_ty <= 6'd0;
                        phase  <= PH_HUD_X;
                    end else if ((wave_num < 3'd4 && en_active == 16'd0) ||
                                 (wave_num == 3'd4 && !boss_active && en_active == 16'd0)) begin
                        eb_active <= 24'd0;
                        if (wave_num == 3'd4) begin
                            game_state      <= GS_VICTORY;
                            evt_flash_timer <= 4'd15;
                            evt_flash_kind  <= 2'd1;
                            sfx_valid       <= 1'b1;
                            sfx_id          <= 3'd5;
                            hud_tx          <= 7'd0; hud_ty <= 6'd0;
                            phase           <= PH_HUD_X;
                        end else begin
                            // Wave milestone temporary evolution boost (9s, reverts to prior form)
                            if (wave_num == 3'd1 && player_form == 2'd0) begin
                                if (evo_sec_rem == 4'd0) evo_prev_form <= player_form;
                                player_form      <= 2'd1;
                                evo_sec_rem      <= 4'd9;
                                evo_frame_div    <= 6'd59;
                                evo_banner_type  <= 2'd1;
                                evo_banner_timer <= 8'd90;
                            end else if (wave_num == 3'd2 && player_form < 2'd2) begin
                                if (evo_sec_rem == 4'd0) evo_prev_form <= player_form;
                                player_form      <= 2'd2;
                                evo_sec_rem      <= 4'd9;
                                evo_frame_div    <= 6'd59;
                                evo_banner_type  <= 2'd2;
                                evo_banner_timer <= 8'd90;
                            end
                            wave_num     <= wave_num + 3'd1;
                            pending_wave <= wave_num + 3'd1;
                            game_state   <= GS_WAVE_INTRO;
                            intro_timer  <= 8'd75;
                            idx_a        <= 6'd0;
                            phase        <= PH_INIT_WAVE;
                        end
                    end else begin
                        hud_tx <= 7'd0; hud_ty <= 6'd0;
                        phase  <= PH_HUD_X;
                    end
                end

                // -----------------------------------------------------------
                // Sequential 80x60 HUD Tilemap Refresh (1 tile per cycle)
                // -----------------------------------------------------------
                PH_HUD_X: begin
                    hud_we    <= 1'b1;
                    hud_waddr <= {hud_ty, hud_tx};
                    hud_wdata <= {hud_col, hud_char};
                    if (hud_tx == 7'd79) begin
                        hud_tx <= 7'd0;
                        if (hud_ty == 6'd59) begin
                            hud_ty <= 6'd0;
                            phase  <= PH_IDLE;
                        end else begin
                            hud_ty <= hud_ty + 6'd1;
                        end
                    end else begin
                        hud_tx <= hud_tx + 7'd1;
                    end
                end

                default: phase <= PH_IDLE;
            endcase
        end
    end
endmodule
