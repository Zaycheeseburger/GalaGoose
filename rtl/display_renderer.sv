`timescale 1ns / 1ps

module display_renderer (
    input  wire        clk,
    input  wire        rst_n,

    // Raw VGA timing
    input  wire [9:0]  h_cnt,
    input  wire [9:0]  v_cnt,
    input  wire        raw_hsync,
    input  wire        raw_vsync,
    input  wire        raw_active,

    // Game State
    input  wire [2:0]  game_state,
    input  wire [2:0]  wave_num,
    input  wire [7:0]  frame_cnt,
    input  wire [3:0]  shake_amt,
    input  wire        sw_debug,

    // Player
    input  wire [9:0]  player_x,
    input  wire [9:0]  player_y,
    input  wire        player_left_face,
    input  wire [1:0]  player_form,
    input  wire [7:0]  player_invuln,
    input  wire        barrier_active,
    input  wire [7:0]  mic_volume,
    input  wire [7:0]  mic_threshold,
    input  wire [8:0]  barrier_cooldown,

    // Enemies (16)
    input  wire [15:0] en_active,
    input  wire [9:0]  en_x     [0:15],
    input  wire [9:0]  en_y     [0:15],
    input  wire [1:0]  en_type  [0:15],
    input  wire [3:0]  en_flash [0:15],

    // Boss AJV
    input  wire        boss_active,
    input  wire        boss_enraged,
    input  wire [9:0]  boss_x,
    input  wire [9:0]  boss_y,
    input  wire [3:0]  boss_flash,

    // Player Bullets (32)
    input  wire [31:0] pb_active,
    input  wire [9:0]  pb_x    [0:31],
    input  wire [9:0]  pb_y    [0:31],
    input  wire [1:0]  pb_kind [0:31],

    // Enemy Bullets (24)
    input  wire [23:0] eb_active,
    input  wire [23:0] eb_reflected,
    input  wire [9:0]  eb_x [0:23],
    input  wire [9:0]  eb_y [0:23],

    // Orbs (4)
    input  wire [3:0]  orb_active,
    input  wire [9:0]  orb_x    [0:3],
    input  wire [9:0]  orb_y    [0:3],
    input  wire [1:0]  orb_type [0:3],

    // Explosions (8)
    input  wire [7:0]  exp_active,
    input  wire [9:0]  exp_x     [0:7],
    input  wire [9:0]  exp_y     [0:7],
    input  wire [3:0]  exp_timer [0:7],

    // HUD BRAM Write Port from Game Engine
    input  wire        hud_we,
    input  wire [12:0] hud_waddr,
    input  wire [11:0] hud_wdata,

    // Final VGA Pins
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         vga_hs,
    output reg         vga_vs
);
    // -----------------------------------------------------------------------
    // Stage -1: Screen Shake + HUD Tile BRAM Read Address
    // -----------------------------------------------------------------------
    wire [12:0] hud_raddr = {v_cnt[8:3], h_cnt[9:3]};
    wire [11:0] hud_tile_dout;

    hud_tile_ram u_hud_ram (
        .clk(clk),
        .addr_a(hud_raddr),
        .dout_a(hud_tile_dout),
        .we_b(hud_we),
        .addr_b(hud_waddr),
        .din_b(hud_wdata)
    );

    reg [9:0] s0_x, s0_y, s0_px, s0_py;
    reg       s0_hs, s0_vs, s0_act;

    wire signed [4:0] shk_dx = (shake_amt != 4'd0 && v_cnt >= 10'd24) ?
                               (frame_cnt[0] ? $signed({1'b0, shake_amt[2:0]}) : -$signed({1'b0, shake_amt[2:0]})) :
                               5'sd0;
    wire signed [4:0] shk_dy = (shake_amt != 4'd0 && v_cnt >= 10'd24) ?
                               (frame_cnt[1] ? $signed({1'b0, shake_amt[2:0]}) : -$signed({1'b0, shake_amt[2:0]})) :
                               5'sd0;
    wire signed [11:0] cand_px = $signed({2'b00, h_cnt}) + shk_dx;
    wire signed [11:0] cand_py = $signed({2'b00, v_cnt}) + shk_dy;

    always @(posedge clk) begin
        if (!rst_n) begin
            s0_x <= 10'd0; s0_y <= 10'd0; s0_px <= 10'd0; s0_py <= 10'd0;
            s0_hs <= 1'b1; s0_vs <= 1'b1; s0_act <= 1'b0;
        end else begin
            s0_x   <= h_cnt;
            s0_y   <= v_cnt;
            s0_px  <= (cand_px < 12'sd0) ? 10'd0 : ((cand_px > 12'sd639) ? 10'd639 : cand_px[9:0]);
            s0_py  <= (cand_py < 12'sd0) ? 10'd0 : ((cand_py > 12'sd479) ? 10'd479 : cand_py[9:0]);
            s0_hs  <= raw_hsync;
            s0_vs  <= raw_vsync;
            s0_act <= raw_active;
        end
    end

    // -----------------------------------------------------------------------
    // Stage 0: Hitbox Matching, Address Generation & Starfield
    // Separate always @(*) blocks with unique loop indices!
    // -----------------------------------------------------------------------
    // 0a. Player Goose (32x32)
    wire show_player = (game_state != 3'd5) && (game_state != 3'd0) && (!player_invuln[2]);
    wire player_hit0 = show_player &&
                       (s0_px >= player_x) && (s0_px < player_x + 10'd32) &&
                       (s0_py >= player_y) && (s0_py < player_y + 10'd32);
    wire [4:0] pl_lx_raw = s0_px[4:0] - player_x[4:0];
    wire [4:0] pl_lx = player_left_face ? (5'd31 - pl_lx_raw) : pl_lx_raw;
    wire [4:0] pl_ly = s0_py[4:0] - player_y[4:0];
    wire [10:0] goose_addr0 = {frame_cnt[3], pl_ly, pl_lx};

    // 0a-2. Energy Barrier (Voice Shouted Barrier - Last Boss only)
    wire show_barrier = barrier_active && (game_state == 3'd2);
    wire [9:0] bar_cx = player_x + 10'd16;
    wire [9:0] bar_cy = player_y + 10'd16;
    wire [9:0] bar_dx = (s0_px > bar_cx) ? (s0_px - bar_cx) : (bar_cx - s0_px);
    wire [9:0] bar_dy = (s0_py > bar_cy) ? (s0_py - bar_cy) : (bar_cy - s0_py);
    wire [9:0] bar_max = (bar_dx > bar_dy) ? bar_dx : bar_dy;
    wire [9:0] bar_min = (bar_dx > bar_dy) ? bar_dy : bar_dx;
    wire [9:0] bar_dist = bar_max + (bar_min >> 1);
    wire barrier_ring0 = show_barrier && (bar_dist >= 10'd24 && bar_dist <= 10'd30);
    wire barrier_fill0 = show_barrier && (bar_dist < 10'd24) && ((bar_dx[1:0] ^ bar_dy[1:0]) == frame_cnt[3:2]);

    // 0b. Enemies (16 x 32x32)
    reg        en_hit0;
    reg [11:0] en_addr0;
    reg        en_flash0;
    integer    k_en;
    always @(*) begin
        en_hit0   = 1'b0;
        en_addr0  = 12'd0;
        en_flash0 = 1'b0;
        for (k_en = 0; k_en < 16; k_en = k_en + 1) begin
            if (!en_hit0 && en_active[k_en] &&
                (s0_px >= en_x[k_en]) && (s0_px < en_x[k_en] + 10'd32) &&
                (s0_py >= en_y[k_en]) && (s0_py < en_y[k_en] + 10'd32)) begin
                en_hit0   = 1'b1;
                en_flash0 = (en_flash[k_en] > 4'd0);
                en_addr0  = {en_type[k_en], (s0_py[4:0] - en_y[k_en][4:0]), (s0_px[4:0] - en_x[k_en][4:0])};
            end
        end
    end

    // 0c. Boss AJV (80x80)
    wire boss_hit0 = boss_active &&
                     (s0_px >= boss_x) && (s0_px < boss_x + 10'd80) &&
                     (s0_py >= boss_y) && (s0_py < boss_y + 10'd80);
    wire [6:0] boss_lx = s0_px - boss_x;
    wire [6:0] boss_ly = s0_py - boss_y;
    // y*80 = (y<<6) + (y<<4)
    wire [13:0] boss_base  = boss_enraged ? 14'd6400 : 14'd0;
    wire [13:0] boss_addr0 = boss_base + ({7'd0, boss_ly} << 6) + ({7'd0, boss_ly} << 4) + {7'd0, boss_lx};
    wire boss_flash0 = (boss_flash > 4'd0);

    // 0d. FX Port A: Explosions (32x32) > Orbs (16x16)
    reg        exp_hit0;
    reg        orb_hit0;
    reg [12:0] fx_addr_a0;
    integer    k_exp;
    integer    k_orb;
    always @(*) begin
        exp_hit0   = 1'b0;
        orb_hit0   = 1'b0;
        fx_addr_a0 = 13'd0;
        for (k_exp = 0; k_exp < 8; k_exp = k_exp + 1) begin
            if (!exp_hit0 && exp_active[k_exp] &&
                (s0_px >= exp_x[k_exp]) && (s0_px < exp_x[k_exp] + 10'd32) &&
                (s0_py >= exp_y[k_exp]) && (s0_py < exp_y[k_exp] + 10'd32)) begin
                exp_hit0   = 1'b1;
                fx_addr_a0 = {1'b0, exp_timer[k_exp][3:2], (s0_py[4:0] - exp_y[k_exp][4:0]), (s0_px[4:0] - exp_x[k_exp][4:0])};
            end
        end
        if (!exp_hit0) begin
            for (k_orb = 0; k_orb < 4; k_orb = k_orb + 1) begin
                if (!orb_hit0 && orb_active[k_orb] &&
                    (s0_px >= orb_x[k_orb]) && (s0_px < orb_x[k_orb] + 10'd16) &&
                    (s0_py >= orb_y[k_orb]) && (s0_py < orb_y[k_orb] + 10'd16)) begin
                    orb_hit0   = 1'b1;
                    fx_addr_a0 = 13'd4096 + {3'd0, orb_type[k_orb], (s0_py[3:0] - orb_y[k_orb][3:0]), (s0_px[3:0] - orb_x[k_orb][3:0])};
                end
            end
        end
    end

    // 0e. FX Port B: Player Bullets (16x16) > Enemy Bullets (16x16)
    reg        pb_hit0;
    reg        eb_hit0;
    reg        eb_refl0;
    reg [12:0] fx_addr_b0;
    integer    k_pb;
    integer    k_eb;
    always @(*) begin
        pb_hit0    = 1'b0;
        eb_hit0    = 1'b0;
        eb_refl0   = 1'b0;
        fx_addr_b0 = 13'd0;
        for (k_pb = 0; k_pb < 32; k_pb = k_pb + 1) begin
            if (!pb_hit0 && pb_active[k_pb] &&
                (s0_px >= pb_x[k_pb]) && (s0_px < pb_x[k_pb] + 10'd16) &&
                (s0_py >= pb_y[k_pb]) && (s0_py < pb_y[k_pb] + 10'd16)) begin
                pb_hit0    = 1'b1;
                fx_addr_b0 = 13'd4864 + {3'd0, pb_kind[k_pb], (s0_py[3:0] - pb_y[k_pb][3:0]), (s0_px[3:0] - pb_x[k_pb][3:0])};
            end
        end
        if (!pb_hit0) begin
            for (k_eb = 0; k_eb < 24; k_eb = k_eb + 1) begin
                if (!eb_hit0 && eb_active[k_eb] &&
                    (s0_px >= eb_x[k_eb]) && (s0_px < eb_x[k_eb] + 10'd16) &&
                    (s0_py >= eb_y[k_eb]) && (s0_py < eb_y[k_eb] + 10'd16)) begin
                    eb_hit0    = 1'b1;
                    eb_refl0   = eb_reflected[k_eb];
                    fx_addr_b0 = 13'd5632 + {5'd0, (s0_py[3:0] - eb_y[k_eb][3:0]), (s0_px[3:0] - eb_x[k_eb][3:0])};
                end
            end
        end
    end

    // 0f. Title Logo (256x64 @ x=192..447, y=64..127)
    wire logo_hit0 = (game_state == 3'd0) &&
                     (s0_x >= 10'd192) && (s0_x < 10'd448) &&
                     (s0_y >= 10'd64)  && (s0_y < 10'd128);
    wire [7:0] logo_lx = s0_x[7:0] - 8'd192;
    wire [5:0] logo_ly = s0_y[5:0];
    wire [13:0] logo_addr0 = {logo_ly, logo_lx};

    // 0g. Voice Barrier GUI Widget (Icon, Real-time Volume Gauge & Threshold Marker)
    // Displayed strictly during Last Boss stage (wave 4, boss active)
    wire show_voice_gui = (game_state == 3'd2) && (wave_num == 3'd4) && boss_active;

    // Shield Icon (x = 202..213, y = 35..46) -> 12x12 px procedural crest
    wire [9:0] si_x_rel = s0_x - 10'd202;
    wire [9:0] si_y_rel = s0_y - 10'd35;
    wire si_box = show_voice_gui && (s0_x >= 10'd202) && (s0_x <= 10'd213) && (s0_y >= 10'd35) && (s0_y <= 10'd46);
    wire si_in_shape = (si_y_rel <= 10'd6) ? 1'b1 :
                       ((si_x_rel >= (si_y_rel - 10'd6)) && (si_x_rel <= (10'd11 - (si_y_rel - 10'd6))));
    wire si_border = (si_y_rel == 10'd0) || (si_x_rel == 10'd0) || (si_x_rel == 10'd11) ||
                     (si_y_rel > 10'd6 && ((si_x_rel == (si_y_rel - 10'd6)) || (si_x_rel == (10'd11 - (si_y_rel - 10'd6)))));
    wire si_crest  = (si_x_rel == 10'd5 || si_x_rel == 10'd6) || (si_y_rel == 10'd4 && si_x_rel >= 10'd3 && si_x_rel <= 10'd8);
    wire si_hit    = si_box && si_in_shape;

    // Gauge Dimensions (x = 220..419, y = 37..45) -> 200x9 px outer
    wire gauge_box    = show_voice_gui && (s0_x >= 10'd220) && (s0_x <= 10'd419) && (s0_y >= 10'd37) && (s0_y <= 10'd45);
    wire gauge_border = gauge_box && (s0_x == 10'd220 || s0_x == 10'd419 || s0_y == 10'd37 || s0_y == 10'd45);
    wire gauge_inner  = gauge_box && !gauge_border; // x = 221..418 (198 px width), y = 38..44 (7 px height)

    // Voice Volume Level mapping (0..255 -> 0..198)
    wire [15:0] vol_mult   = mic_volume * 8'd198;
    wire [7:0]  vol_w      = vol_mult[15:8];
    wire [9:0]  inner_x_10 = s0_x - 10'd221;
    wire [7:0]  inner_x    = inner_x_10[7:0];

    // Threshold Marker (mic_threshold -> x coord)
    wire [15:0] thresh_mult = mic_threshold * 8'd198;
    wire [9:0]  x_thresh    = 10'd221 + {2'b00, thresh_mult[15:8]};
    wire thresh_line_hit    = show_voice_gui && (s0_x == x_thresh) && (s0_y >= 10'd36) && (s0_y <= 10'd46);
    // Top arrow notch (y = 35..36), bottom arrow notch (y = 46..47)
    wire thresh_notch_hit   = show_voice_gui && (
        ((s0_y == 10'd35) && (s0_x >= x_thresh - 10'd2) && (s0_x <= x_thresh + 10'd2)) ||
        ((s0_y == 10'd36) && (s0_x >= x_thresh - 10'd1) && (s0_x <= x_thresh + 10'd1)) ||
        ((s0_y == 10'd46) && (s0_x >= x_thresh - 10'd1) && (s0_x <= x_thresh + 10'd1)) ||
        ((s0_y == 10'd47) && (s0_x >= x_thresh - 10'd2) && (s0_x <= x_thresh + 10'd2))
    );
    wire thresh_marker_hit  = thresh_line_hit || thresh_notch_hit;

    // Cooldown fill (480 down to 0 -> 0 to 198)
    wire [15:0] cd_elapsed = (barrier_cooldown > 9'd480) ? 16'd0 : {7'd0, (9'd480 - barrier_cooldown)};
    wire [15:0] cd_mult    = cd_elapsed * 8'd106;
    wire [7:0]  cd_w       = cd_mult[15:8];
    wire [9:0]  stripe_pos = s0_x + {frame_cnt, 1'b0};

    // Color computation in Stage 0
    reg        widget_hit0;
    reg [11:0] widget_rgb0;

    always @(*) begin
        widget_hit0 = 1'b0;
        widget_rgb0 = 12'h000;

        if (show_voice_gui) begin
            // 1. Threshold Marker (highest priority within widget)
            if (thresh_marker_hit) begin
                widget_hit0 = 1'b1;
                if (mic_volume >= mic_threshold)
                    widget_rgb0 = frame_cnt[1] ? 12'hFFF : 12'h0FF; // Flashing bright when shout threshold reached!
                else
                    widget_rgb0 = 12'hF22; // Neon red indicator notch
            end
            // 2. Shield Icon
            else if (si_hit) begin
                widget_hit0 = 1'b1;
                if (si_border) begin
                    widget_rgb0 = barrier_active ? 12'h0FF :
                                  (barrier_cooldown == 9'd0 ? 12'hDDD : 12'h668);
                end else if (si_crest) begin
                    widget_rgb0 = barrier_active ? 12'hFFF :
                                  (barrier_cooldown == 9'd0 ? 12'hFFF : 12'h88A);
                end else begin
                    if (barrier_active)
                        widget_rgb0 = frame_cnt[2] ? 12'h0BF : 12'h07C;
                    else if (barrier_cooldown == 9'd0)
                        widget_rgb0 = (mic_volume >= mic_threshold) ? 12'h5FF : 12'h1B4;
                    else
                        widget_rgb0 = 12'h223;
                end
            end
            // 3. Gauge Border
            else if (gauge_border) begin
                widget_hit0 = 1'b1;
                if (barrier_active)
                    widget_rgb0 = 12'h0FF;
                else if (barrier_cooldown == 9'd0)
                    widget_rgb0 = (mic_volume >= mic_threshold) ? 12'h0FF : 12'h88A;
                else
                    widget_rgb0 = 12'h445;
            end
            // 4. Gauge Interior
            else if (gauge_inner) begin
                widget_hit0 = 1'b1;
                if (barrier_active) begin
                    // Animated plasma energy stripes while barrier is active
                    widget_rgb0 = (stripe_pos[3:2] == 2'd0) ? 12'hFFF : 12'h0CF;
                end else if (barrier_cooldown > 9'd0) begin
                    // Recharging cooldown progress fill
                    if (inner_x < cd_w)
                        widget_rgb0 = (inner_x >= cd_w - 8'd3) ? 12'h79C : 12'h346;
                    else
                        widget_rgb0 = 12'h112; // Empty track
                end else begin
                    // Real-time voice energy volume meter
                    if (inner_x < vol_w) begin
                        if (inner_x < 8'd75)
                            widget_rgb0 = 12'h2E5; // Green (low)
                        else if (inner_x < 8'd125)
                            widget_rgb0 = 12'hBE2; // Lime
                        else if (inner_x < 8'd165)
                            widget_rgb0 = 12'hFE2; // Yellow
                        else
                            widget_rgb0 = 12'hF32; // Red (loud)
                    end else begin
                        widget_rgb0 = 12'h112; // Empty dark background
                    end
                end
            end
        end
    end

    // 0h. Procedural 3-Layer Parallax Starfield
    wire [9:0] sy_fast = s0_y - {1'b0, frame_cnt, 1'b0};
    wire [9:0] sy_mid  = s0_y - {2'b00, frame_cnt};
    wire [9:0] sy_slow = s0_y - {3'b000, frame_cnt[7:1]};
    wire [11:0] h_fast = ({s0_x[7:0], 4'd0} ^ {2'd0, sy_fast}) * 12'h02D + {sy_fast[5:0], s0_x[5:0]};
    wire [11:0] h_mid  = ({s0_x[8:1], 4'd0} ^ {2'd0, sy_mid})  * 12'h035 + {sy_mid[6:1],  s0_x[6:1]};
    wire star_fast = (h_fast == 12'h5A3) && ((s0_x[2:0] ^ sy_fast[2:0]) == 3'd3);
    wire star_mid  = (h_mid[9:0] == 10'h2D7) && (s0_x[0] == 1'b0);
    wire star_slow = ((s0_x[5:0] == 6'd17) && (sy_slow[5:0] == 6'd41)) ||
                     ((s0_x[6:0] == 7'd91) && (sy_slow[6:0] == 7'd23));
    reg [11:0] star_rgb0;
    always @(*) begin
        if (s0_y < 10'd20)
            star_rgb0 = 12'h002; // Darker top HUD bar backdrop
        else if (star_fast)
            star_rgb0 = 12'hFFF;
        else if (star_mid)
            star_rgb0 = frame_cnt[3] ? 12'h4BF : 12'h28C;
        else if (star_slow)
            star_rgb0 = 12'h447;
        else
            star_rgb0 = 12'h001; // Deep space navy
    end

    // Debug Hitbox Border Overlay (SW[4])
    wire dbg_box0 = sw_debug && (
        (player_hit0 && (pl_lx == 0 || pl_lx == 31 || pl_ly == 0 || pl_ly == 31)) ||
        (boss_hit0   && (boss_lx == 0 || boss_lx == 79 || boss_ly == 0 || boss_ly == 79))
    );

    // Stage 0 -> Stage 1 Registers (drive BRAM read addresses)
    reg [9:0]  s1_y;
    reg        s1_hs, s1_vs, s1_act;
    reg [2:0]  s1_font_lx;
    reg [3:0]  s1_hud_col;
    reg        s1_goose_hit, s1_en_hit, s1_en_flash, s1_boss_hit, s1_boss_flash;
    reg        s1_exp_hit, s1_orb_hit, s1_pb_hit, s1_eb_hit, s1_logo_hit, s1_dbg;
    reg        s1_bar_ring, s1_bar_fill, s1_eb_refl;
    reg        s1_widget_hit;
    reg [11:0] s1_widget_rgb;
    reg [4:0]  s1_goose_ly;
    reg [11:0] s1_star_rgb;

    reg [10:0] rom_goose_addr;
    reg [11:0] rom_en_addr;
    reg [13:0] rom_boss_addr;
    reg [12:0] rom_fx_addr_a, rom_fx_addr_b;
    reg [13:0] rom_logo_addr;
    reg [9:0]  rom_font_addr;

    always @(posedge clk) begin
        if (!rst_n) begin
            s1_y <= 10'd0; s1_hs <= 1'b1; s1_vs <= 1'b1; s1_act <= 1'b0;
            s1_font_lx <= 3'd0; s1_hud_col <= 4'd0;
            s1_goose_hit <= 1'b0; s1_en_hit <= 1'b0; s1_en_flash <= 1'b0;
            s1_boss_hit <= 1'b0; s1_boss_flash <= 1'b0;
            s1_exp_hit <= 1'b0; s1_orb_hit <= 1'b0; s1_pb_hit <= 1'b0; s1_eb_hit <= 1'b0;
            s1_bar_ring <= 1'b0; s1_bar_fill <= 1'b0; s1_eb_refl <= 1'b0;
            s1_widget_hit <= 1'b0; s1_widget_rgb <= 12'h000;
            s1_logo_hit <= 1'b0; s1_dbg <= 1'b0;
            s1_goose_ly <= 5'd0; s1_star_rgb <= 12'h001;
            rom_goose_addr <= 11'd0; rom_en_addr <= 12'd0; rom_boss_addr <= 14'd0;
            rom_fx_addr_a <= 13'd0; rom_fx_addr_b <= 13'd0; rom_logo_addr <= 14'd0;
            rom_font_addr <= 10'd0;
        end else begin
            s1_y          <= s0_y;
            s1_hs         <= s0_hs;
            s1_vs         <= s0_vs;
            s1_act        <= s0_act;
            s1_font_lx    <= s0_x[2:0];
            s1_hud_col    <= hud_tile_dout[11:8];
            rom_font_addr <= {hud_tile_dout[6:0], s0_y[2:0]};

            s1_goose_hit   <= player_hit0;
            s1_goose_ly    <= pl_ly;
            rom_goose_addr <= goose_addr0;

            s1_en_hit     <= en_hit0;
            s1_en_flash   <= en_flash0;
            rom_en_addr   <= en_addr0;

            s1_boss_hit   <= boss_hit0;
            s1_boss_flash <= boss_flash0;
            rom_boss_addr <= boss_addr0;

            s1_exp_hit    <= exp_hit0;
            s1_orb_hit    <= orb_hit0;
            rom_fx_addr_a <= fx_addr_a0;

            s1_pb_hit     <= pb_hit0;
            s1_eb_hit     <= eb_hit0;
            s1_eb_refl    <= eb_refl0;
            rom_fx_addr_b <= fx_addr_b0;

            s1_bar_ring   <= barrier_ring0;
            s1_bar_fill   <= barrier_fill0;
            s1_widget_hit <= widget_hit0;
            s1_widget_rgb <= widget_rgb0;

            s1_logo_hit   <= logo_hit0;
            rom_logo_addr <= logo_addr0;

            s1_star_rgb   <= star_rgb0;
            s1_dbg        <= dbg_box0;
        end
    end

    // -----------------------------------------------------------------------
    // Stage 1: Synchronous BRAM Reads (1 cycle latency -> valid in Stage 2)
    // -----------------------------------------------------------------------
    wire [7:0] goose_px, enemy_px, boss_px, fx_px_a, fx_px_b, logo_px, font_byte;

    sync_rom #(.ADDR_WIDTH(11), .DATA_WIDTH(8), .DEPTH(2048),  .INIT_FILE("goose_rom.mem")) u_rom_goose (
        .clk(clk), .addr(rom_goose_addr), .dout(goose_px)
    );
    sync_rom #(.ADDR_WIDTH(12), .DATA_WIDTH(8), .DEPTH(4096),  .INIT_FILE("enemy_rom.mem")) u_rom_enemy (
        .clk(clk), .addr(rom_en_addr), .dout(enemy_px)
    );
    sync_rom #(.ADDR_WIDTH(14), .DATA_WIDTH(8), .DEPTH(12800), .INIT_FILE("boss_rom.mem")) u_rom_boss (
        .clk(clk), .addr(rom_boss_addr), .dout(boss_px)
    );
    sync_dp_rom #(.ADDR_WIDTH(13), .DATA_WIDTH(8), .DEPTH(6144), .INIT_FILE("fx_rom.mem")) u_rom_fx (
        .clk(clk), .addr_a(rom_fx_addr_a), .dout_a(fx_px_a), .addr_b(rom_fx_addr_b), .dout_b(fx_px_b)
    );
    sync_rom #(.ADDR_WIDTH(14), .DATA_WIDTH(8), .DEPTH(16384), .INIT_FILE("logo_rom.mem")) u_rom_logo (
        .clk(clk), .addr(rom_logo_addr), .dout(logo_px)
    );
    sync_rom #(.ADDR_WIDTH(10), .DATA_WIDTH(8), .DEPTH(1024),  .INIT_FILE("font_rom.mem")) u_rom_font (
        .clk(clk), .addr(rom_font_addr), .dout(font_byte)
    );

    reg [9:0]  s2_y;
    reg        s2_hs, s2_vs, s2_act;
    reg [2:0]  s2_font_lx;
    reg [3:0]  s2_hud_col;
    reg        s2_goose_hit, s2_en_hit, s2_en_flash, s2_boss_hit, s2_boss_flash;
    reg        s2_exp_hit, s2_orb_hit, s2_pb_hit, s2_eb_hit, s2_logo_hit, s2_dbg;
    reg        s2_bar_ring, s2_bar_fill, s2_eb_refl;
    reg        s2_widget_hit;
    reg [11:0] s2_widget_rgb;
    reg [4:0]  s2_goose_ly;
    reg [11:0] s2_star_rgb;

    always @(posedge clk) begin
        if (!rst_n) begin
            s2_y <= 10'd0; s2_hs <= 1'b1; s2_vs <= 1'b1; s2_act <= 1'b0;
            s2_font_lx <= 3'd0; s2_hud_col <= 4'd0;
            s2_goose_hit <= 1'b0; s2_en_hit <= 1'b0; s2_en_flash <= 1'b0;
            s2_boss_hit <= 1'b0; s2_boss_flash <= 1'b0;
            s2_exp_hit <= 1'b0; s2_orb_hit <= 1'b0; s2_pb_hit <= 1'b0; s2_eb_hit <= 1'b0;
            s2_bar_ring <= 1'b0; s2_bar_fill <= 1'b0; s2_eb_refl <= 1'b0;
            s2_widget_hit <= 1'b0; s2_widget_rgb <= 12'h000;
            s2_logo_hit <= 1'b0; s2_dbg <= 1'b0;
            s2_goose_ly <= 5'd0; s2_star_rgb <= 12'h001;
        end else begin
            s2_y          <= s1_y;
            s2_hs         <= s1_hs;
            s2_vs         <= s1_vs;
            s2_act        <= s1_act;
            s2_font_lx    <= s1_font_lx;
            s2_hud_col    <= s1_hud_col;
            s2_goose_hit  <= s1_goose_hit;
            s2_goose_ly   <= s1_goose_ly;
            s2_en_hit     <= s1_en_hit;
            s2_en_flash   <= s1_en_flash;
            s2_boss_hit   <= s1_boss_hit;
            s2_boss_flash <= s1_boss_flash;
            s2_exp_hit    <= s1_exp_hit;
            s2_orb_hit    <= s1_orb_hit;
            s2_pb_hit     <= s1_pb_hit;
            s2_eb_hit     <= s1_eb_hit;
            s2_eb_refl    <= s1_eb_refl;
            s2_bar_ring   <= s1_bar_ring;
            s2_bar_fill   <= s1_bar_fill;
            s2_widget_hit <= s1_widget_hit;
            s2_widget_rgb <= s1_widget_rgb;
            s2_logo_hit   <= s1_logo_hit;
            s2_star_rgb   <= s1_star_rgb;
            s2_dbg        <= s1_dbg;
        end
    end

    // -----------------------------------------------------------------------
    // Stage 2: Layer Priority Mux & Goose Evolution Recoloring -> Stage 3
    // -----------------------------------------------------------------------
    wire font_bit = font_byte[3'd7 - s2_font_lx];
    reg [11:0] hud_rgb;
    always @(*) begin
        case (s2_hud_col)
            4'd0: hud_rgb = 12'hFFF; // White
            4'd1: hud_rgb = 12'h0FF; // Cyan
            4'd2: hud_rgb = 12'hFF3; // Yellow
            4'd3: hud_rgb = 12'hF33; // Red
            4'd4: hud_rgb = 12'h3F6; // Green
            4'd5: hud_rgb = 12'hF4E; // Magenta
            4'd6: hud_rgb = 12'hF92; // Orange
            default: hud_rgb = 12'hFFF;
        endcase
    end

    // Goose evolution palette remap (Form 1: White, Form 2: Blue, Form 3: Rainbow)
    reg [7:0] goose_px_evo;
    wire [2:0] rainbow_band = s2_goose_ly[3:1] + frame_cnt[4:2];
    always @(*) begin
        goose_px_evo = goose_px;
        if (player_form == 2'd1) begin
            if (goose_px == 8'd2)      goose_px_evo = 8'd8;
            else if (goose_px == 8'd3) goose_px_evo = 8'd9;
        end else if (player_form == 2'd2) begin
            if (goose_px == 8'd2 || goose_px == 8'd3)
                goose_px_evo = 8'd16 + {5'd0, rainbow_band};
        end
    end

    reg [7:0]  mux_pal_idx;
    reg        mux_use_ovr;
    reg [11:0] mux_ovr_rgb;

    always @(*) begin
        mux_pal_idx = 8'd0;
        mux_use_ovr = 1'b0;
        mux_ovr_rgb = 12'h000;

        if (font_bit) begin
            mux_use_ovr = 1'b1;
            mux_ovr_rgb = hud_rgb;
        end else if (s2_widget_hit) begin
            mux_use_ovr = 1'b1;
            mux_ovr_rgb = s2_widget_rgb;
        end else if (s2_y == 10'd20) begin
            mux_use_ovr = 1'b1;
            mux_ovr_rgb = 12'h25A;
        end else if (s2_bar_ring) begin
            mux_use_ovr = 1'b1;
            mux_ovr_rgb = frame_cnt[2] ? 12'h0FF : 12'hFFF; // Bright animated cyan/white plasma barrier ring!
        end else if (s2_logo_hit && logo_px != 8'd0) begin
            mux_pal_idx = logo_px;
        end else if (s2_exp_hit && fx_px_a != 8'd0) begin
            mux_pal_idx = fx_px_a;
        end else if ((s2_pb_hit || s2_eb_hit) && fx_px_b != 8'd0) begin
            if (s2_eb_hit && s2_eb_refl) begin
                mux_use_ovr = 1'b1;
                mux_ovr_rgb = frame_cnt[1] ? 12'h0FF : 12'hFFF; // Bright reflected cyan laser!
            end else begin
                mux_pal_idx = fx_px_b;
            end
        end else if (s2_orb_hit && fx_px_a != 8'd0) begin
            mux_pal_idx = fx_px_a;
        end else if (s2_goose_hit && goose_px_evo != 8'd0) begin
            mux_pal_idx = goose_px_evo;
        end else if (s2_bar_fill) begin
            mux_use_ovr = 1'b1;
            mux_ovr_rgb = frame_cnt[1] ? 12'h2AF : 12'h06C; // Vivid electric blue forcefield inside barrier
        end else if (s2_en_hit && enemy_px != 8'd0) begin
            if (s2_en_flash) begin
                mux_use_ovr = 1'b1;
                mux_ovr_rgb = 12'hFFF;
            end else begin
                mux_pal_idx = enemy_px;
            end
        end else if (s2_boss_hit && boss_px != 8'd0) begin
            if (s2_boss_flash) begin
                mux_use_ovr = 1'b1;
                mux_ovr_rgb = 12'hFFF;
            end else begin
                mux_pal_idx = boss_px;
            end
        end else if (s2_dbg) begin
            mux_use_ovr = 1'b1;
            mux_ovr_rgb = 12'h0F0;
        end else begin
            mux_use_ovr = 1'b1;
            mux_ovr_rgb = s2_star_rgb;
        end
    end

    reg [7:0]  s3_pal_idx;
    reg        s3_use_ovr;
    reg [11:0] s3_ovr_rgb;
    reg        s3_hs, s3_vs, s3_act;

    always @(posedge clk) begin
        if (!rst_n) begin
            s3_pal_idx <= 8'd0; s3_use_ovr <= 1'b1; s3_ovr_rgb <= 12'h000;
            s3_hs <= 1'b1; s3_vs <= 1'b1; s3_act <= 1'b0;
        end else begin
            s3_pal_idx <= mux_pal_idx;
            s3_use_ovr <= mux_use_ovr;
            s3_ovr_rgb <= mux_ovr_rgb;
            s3_hs      <= s2_hs;
            s3_vs      <= s2_vs;
            s3_act     <= s2_act;
        end
    end

    // -----------------------------------------------------------------------
    // Stage 3: Palette LUT Lookup (256 x 12-bit) -> Stage 4 -> VGA Output FF
    // -----------------------------------------------------------------------
    wire [11:0] pal_rgb;
    sync_rom #(.ADDR_WIDTH(8), .DATA_WIDTH(12), .DEPTH(256), .INIT_FILE("pal_rom.mem")) u_rom_pal (
        .clk(clk), .addr(s3_pal_idx), .dout(pal_rgb)
    );

    reg        s4_use_ovr;
    reg [11:0] s4_ovr_rgb;
    reg        s4_hs, s4_vs, s4_act;

    always @(posedge clk) begin
        if (!rst_n) begin
            s4_use_ovr <= 1'b1; s4_ovr_rgb <= 12'h000;
            s4_hs <= 1'b1; s4_vs <= 1'b1; s4_act <= 1'b0;
        end else begin
            s4_use_ovr <= s3_use_ovr;
            s4_ovr_rgb <= s3_ovr_rgb;
            s4_hs      <= s3_hs;
            s4_vs      <= s3_vs;
            s4_act     <= s3_act;
        end
    end

    wire [11:0] final_rgb = s4_use_ovr ? s4_ovr_rgb : pal_rgb;

    always @(posedge clk) begin
        if (!rst_n) begin
            vga_r <= 4'd0; vga_g <= 4'd0; vga_b <= 4'd0;
            vga_hs <= 1'b1; vga_vs <= 1'b1;
        end else begin
            {vga_r, vga_g, vga_b} <= s4_act ? final_rgb : 12'h000;
            vga_hs <= s4_hs;
            vga_vs <= s4_vs;
        end
    end
endmodule
