`timescale 1ns / 1ps

module space_shooter_top #(
    parameter integer POR_CYCLES   = 20'd500000,
    parameter integer DEBOUNCE_MAX = 125000
)(
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,

    input  wire        BTNC,
    input  wire        BTNU,
    input  wire        BTNL,
    input  wire        BTNR,
    input  wire        BTND,

    input  wire [15:0] SW,

    output wire [15:0] LED,
    output reg         LED16_R,
    output reg         LED16_G,
    output reg         LED16_B,
    output reg         LED17_R,
    output reg         LED17_G,
    output reg         LED17_B,

    output wire [7:0]  AN,
    output wire        CA,
    output wire        CB,
    output wire        CC,
    output wire        CD,
    output wire        CE,
    output wire        CF,
    output wire        CG,
    output wire        DP,

    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,

    output wire        AUD_PWM,
    output wire        AUD_SD,

    input  wire        ACL_MISO,
    output wire        ACL_MOSI,
    output wire        ACL_SCLK,
    output wire        ACL_CSN,

    input  wire        PS2_CLK,
    input  wire        PS2_DATA,

    input  wire        UART_TXD_IN,

    // On-board MEMS Microphone (ADMP421 PDM)
    output wire        M_CLK,
    input  wire        M_DATA,
    output wire        M_LRSEL
);
    // -----------------------------------------------------------------------
    // 1. Clock & Synchronized Reset (100 MHz -> 25 MHz)
    // -----------------------------------------------------------------------
    wire clk_25m;
    wire rst_n;

    clk_gen #(.POR_CYCLES(POR_CYCLES)) u_clk_gen (
        .clk_100m(CLK100MHZ),
        .cpu_resetn(CPU_RESETN),
        .clk_25m(clk_25m),
        .rst_n(rst_n)
    );

    // -----------------------------------------------------------------------
    // 2. Debounced Buttons & Switches (5ms @ 25 MHz)
    // -----------------------------------------------------------------------
    wire [4:0] btn_deb, btn_rise;
    debounce_bank #(.WIDTH(5), .DEBOUNCE_MAX(DEBOUNCE_MAX)) u_deb_btn (
        .clk(clk_25m),
        .rst_n(rst_n),
        .raw_in({BTNC, BTNR, BTNL, BTND, BTNU}),
        .debounced(btn_deb),
        .rise_pulse(btn_rise)
    );

    wire [15:0] sw_deb, sw_rise;
    debounce_bank #(.WIDTH(16), .DEBOUNCE_MAX(DEBOUNCE_MAX)) u_deb_sw (
        .clk(clk_25m),
        .rst_n(rst_n),
        .raw_in(SW),
        .debounced(sw_deb),
        .rise_pulse(sw_rise)
    );

    wire sw_mute     = sw_deb[0];
    wire sw_autofire = sw_deb[1];
    wire sw_tilt     = sw_deb[2];
    wire sw_hard     = sw_deb[3];
    wire sw_debug    = sw_deb[4];
    wire sw_kbd      = sw_deb[5];
    wire sw_kbd_swap = sw_deb[6];
    wire sw_giveup   = sw_deb[14];
    wire sw_pause    = sw_deb[15];

    // -----------------------------------------------------------------------
    // 2b. On-Board MEMS PDM Microphone & Shout Detector
    // -----------------------------------------------------------------------
    wire [7:0] mic_volume;
    wire       shout_trigger;
    // Switch 13:12 for microphone sensitivity tuning if desired:
    // 00: 85 (Normal shout), 01: 65 (Sensitive), 10: 105 (Louder), 11: 130
    wire [7:0] mic_threshold = (sw_deb[13:12] == 2'b01) ? 8'd65  :
                               (sw_deb[13:12] == 2'b10) ? 8'd105 :
                               (sw_deb[13:12] == 2'b11) ? 8'd130 : 8'd85;

    pdm_microphone u_mic (
        .clk(clk_25m),
        .rst_n(rst_n),
        .m_data(M_DATA),
        .threshold(mic_threshold),
        .m_clk(M_CLK),
        .m_lrsel(M_LRSEL),
        .volume_level(mic_volume),
        .shout_trigger(shout_trigger)
    );

    // -----------------------------------------------------------------------
    // 3. Accelerometer (ADXL362), PS/2 Keyboard & USB-UART Controller Bridge
    // -----------------------------------------------------------------------
    wire signed [7:0] accel_x, accel_y;
    adxl362_spi u_adxl (
        .clk(clk_25m),
        .rst_n(rst_n),
        .acl_miso(ACL_MISO),
        .acl_mosi(ACL_MOSI),
        .acl_sclk(ACL_SCLK),
        .acl_csn(ACL_CSN),
        .accel_x(accel_x),
        .accel_y(accel_y)
    );

    // On-board USB Host (J5) PS/2 Keyboard Controller
    wire [4:0] ps2_kbd_btn;
    wire       ps2_kbd_link;
    wire [7:0] ps2_last_scan;
    ps2_keyboard u_ps2_kbd (
        .clk(clk_25m),
        .rst_n(rst_n),
        .ps2_clk(PS2_CLK),
        .ps2_data(PS2_DATA),
        .kbd_btn(ps2_kbd_btn),
        .kbd_link_ok(ps2_kbd_link),
        .last_scan_code(ps2_last_scan)
    );

    wire [7:0] uart_byte;
    wire       uart_valid;
    uart_rx #(.CLKS_PER_BIT(217)) u_uart_rx (
        .clk(clk_25m),
        .rst_n(rst_n),
        .rx(UART_TXD_IN),
        .rx_data(uart_byte),
        .rx_valid(uart_valid)
    );

    // UART protocol: supports both compact 1-byte packets (MSB=1) and PC ASCII keyboard (W,A,S,D,Enter)
    reg [4:0]  uart_compact_mask;
    reg [24:0] uart_compact_timer;
    reg [23:0] uart_w_timer, uart_a_timer, uart_s_timer, uart_d_timer, uart_enter_timer;

    wire uart_ascii_up    = (uart_w_timer > 24'd0);
    wire uart_ascii_down  = (uart_s_timer > 24'd0);
    wire uart_ascii_left  = (uart_a_timer > 24'd0);
    wire uart_ascii_right = (uart_d_timer > 24'd0);
    wire uart_ascii_fire  = (uart_enter_timer > 24'd0);
    wire uart_ascii_link  = (uart_w_timer > 24'd0) || (uart_s_timer > 24'd0) || (uart_a_timer > 24'd0) ||
                            (uart_d_timer > 24'd0) || (uart_enter_timer > 24'd0);
    wire [4:0] uart_ascii_mask = {uart_ascii_fire, uart_ascii_right, uart_ascii_left, uart_ascii_down, uart_ascii_up};

    wire [4:0] uart_btn_mask = uart_compact_mask;
    wire       uart_link_ok  = (uart_compact_timer > 25'd0);

    // Combined Keyboard (PS/2 on-board J5 + PC UART terminal):
    wire [4:0] kbd_btn_mask = ps2_kbd_btn | uart_ascii_mask;
    wire       kbd_link_ok  = ps2_kbd_link | uart_ascii_link;

    always @(posedge clk_25m) begin
        if (!rst_n) begin
            uart_compact_mask  <= 5'd0;
            uart_compact_timer <= 25'd0;
            uart_w_timer       <= 24'd0;
            uart_a_timer       <= 24'd0;
            uart_s_timer       <= 24'd0;
            uart_d_timer       <= 24'd0;
            uart_enter_timer   <= 24'd0;
        end else begin
            if (uart_compact_timer > 25'd0) begin
                uart_compact_timer <= uart_compact_timer - 25'd1;
                if (uart_compact_timer == 25'd1) uart_compact_mask <= 5'd0;
            end
            if (uart_w_timer > 24'd0)     uart_w_timer     <= uart_w_timer - 24'd1;
            if (uart_a_timer > 24'd0)     uart_a_timer     <= uart_a_timer - 24'd1;
            if (uart_s_timer > 24'd0)     uart_s_timer     <= uart_s_timer - 24'd1;
            if (uart_d_timer > 24'd0)     uart_d_timer     <= uart_d_timer - 24'd1;
            if (uart_enter_timer > 24'd0) uart_enter_timer <= uart_enter_timer - 24'd1;

            if (uart_valid) begin
                if (uart_byte[7]) begin
                    uart_compact_mask  <= uart_byte[4:0];
                    uart_compact_timer <= 25'd25000000; // 1.0 s timeout
                end else begin
                    case (uart_byte)
                        8'h77, 8'h57: begin
                            uart_w_timer <= 24'd5000000; // 'w', 'W' (0.2s hold)
                            uart_s_timer <= 24'd0;
                        end
                        8'h73, 8'h53: begin
                            uart_s_timer <= 24'd5000000; // 's', 'S'
                            uart_w_timer <= 24'd0;
                        end
                        8'h61, 8'h41: begin
                            uart_a_timer <= 24'd5000000; // 'a', 'A'
                            uart_d_timer <= 24'd0;
                        end
                        8'h64, 8'h44: begin
                            uart_d_timer <= 24'd5000000; // 'd', 'D'
                            uart_a_timer <= 24'd0;
                        end
                        8'h0D, 8'h0A, 8'h20: uart_enter_timer <= 24'd5000000; // Enter, newline, space
                        default: ;
                    endcase
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // 4. VGA Timing Generator
    // -----------------------------------------------------------------------
    wire [9:0] h_cnt, v_cnt;
    wire       raw_hsync, raw_vsync, raw_active, game_tick;

    vga_sync u_vga_sync (
        .clk(clk_25m),
        .rst_n(rst_n),
        .h_cnt(h_cnt),
        .v_cnt(v_cnt),
        .hsync(raw_hsync),
        .vsync(raw_vsync),
        .active(raw_active),
        .game_tick(game_tick)
    );

    // -----------------------------------------------------------------------
    // 5. Game Engine & Display Renderer Interconnect
    // -----------------------------------------------------------------------
    wire [2:0]  game_state, wave_num;
    wire        hard_mode;
    wire [7:0]  frame_cnt;
    wire [3:0]  shake_amt;

    wire [9:0]  player_x, player_y;
    wire        player_left_face;
    wire [1:0]  player_form;
    wire [2:0]  player_lives;
    wire [7:0]  player_invuln;

    wire [15:0] en_active;
    wire [9:0]  en_x     [0:15];
    wire [9:0]  en_y     [0:15];
    wire [1:0]  en_type  [0:15];
    wire [3:0]  en_flash [0:15];

    wire        boss_active, boss_enraged;
    wire [9:0]  boss_x, boss_y;
    wire [6:0]  boss_hp, boss_max_hp;
    wire [3:0]  boss_flash;

    wire [31:0] pb_active;
    wire [9:0]  pb_x    [0:31];
    wire [9:0]  pb_y    [0:31];
    wire [1:0]  pb_kind [0:31];

    wire [23:0] eb_active;
    wire [9:0]  eb_x [0:23];
    wire [9:0]  eb_y [0:23];
    wire [23:0] eb_reflected;
    wire        barrier_active;
    wire [8:0]  barrier_cooldown;

    wire [3:0]  orb_active;
    wire [9:0]  orb_x    [0:3];
    wire [9:0]  orb_y    [0:3];
    wire [1:0]  orb_type [0:3];

    wire [7:0]  exp_active;
    wire [9:0]  exp_x     [0:7];
    wire [9:0]  exp_y     [0:7];
    wire [3:0]  exp_timer [0:7];

    wire        hud_we;
    wire [12:0] hud_waddr;
    wire [11:0] hud_wdata;

    wire [31:0] seg7_digits;
    wire [7:0]  seg7_dp_mask;
    wire [15:0] engine_led_bar;
    wire [3:0]  evt_flash_timer;
    wire [1:0]  evt_flash_kind;
    wire        sfx_valid;
    wire [2:0]  sfx_id;

    game_engine u_engine (
        .clk(clk_25m),
        .rst_n(rst_n),
        .game_tick(game_tick),
        .btn_up(btn_deb[0]),
        .btn_down(btn_deb[1]),
        .btn_left(btn_deb[2]),
        .btn_right(btn_deb[3]),
        .btn_fire(btn_deb[4]),
        .btn_fire_rise(btn_rise[4]),
        .btn_left_rise(btn_rise[2]),
        .btn_right_rise(btn_rise[3]),
        .sw_autofire(sw_autofire),
        .sw_tilt(sw_tilt),
        .sw_hard(sw_hard),
        .sw_giveup(sw_giveup),
        .sw_pause(sw_pause),
        .sw_kbd(sw_kbd),
        .sw_kbd_swap(sw_kbd_swap),
        .accel_x(accel_x),
        .accel_y(accel_y),
        .uart_btn_mask(uart_btn_mask),
        .uart_link_ok(uart_link_ok),
        .kbd_btn_mask(kbd_btn_mask),
        .kbd_link_ok(kbd_link_ok),
        .mic_volume(mic_volume),
        .mic_threshold(mic_threshold),
        .shout_trigger(shout_trigger),
        .barrier_active(barrier_active),
        .barrier_cooldown(barrier_cooldown),
        .eb_reflected(eb_reflected),
        .boss_enraged(boss_enraged),
        .game_state(game_state),
        .wave_num(wave_num),
        .hard_mode(hard_mode),
        .frame_cnt(frame_cnt),
        .shake_amt(shake_amt),
        .player_x(player_x),
        .player_y(player_y),
        .player_left_face(player_left_face),
        .player_form(player_form),
        .player_lives(player_lives),
        .player_invuln(player_invuln),
        .en_active(en_active),
        .en_x(en_x),
        .en_y(en_y),
        .en_type(en_type),
        .en_flash(en_flash),
        .boss_active(boss_active),
        .boss_x(boss_x),
        .boss_y(boss_y),
        .boss_hp(boss_hp),
        .boss_max_hp(boss_max_hp),
        .boss_flash(boss_flash),
        .pb_active(pb_active),
        .pb_x(pb_x),
        .pb_y(pb_y),
        .pb_kind(pb_kind),
        .eb_active(eb_active),
        .eb_x(eb_x),
        .eb_y(eb_y),
        .orb_active(orb_active),
        .orb_x(orb_x),
        .orb_y(orb_y),
        .orb_type(orb_type),
        .exp_active(exp_active),
        .exp_x(exp_x),
        .exp_y(exp_y),
        .exp_timer(exp_timer),
        .hud_we(hud_we),
        .hud_waddr(hud_waddr),
        .hud_wdata(hud_wdata),
        .seg7_digits(seg7_digits),
        .seg7_dp_mask(seg7_dp_mask),
        .led_bar(engine_led_bar),
        .evt_flash_timer(evt_flash_timer),
        .evt_flash_kind(evt_flash_kind),
        .sfx_valid(sfx_valid),
        .sfx_id(sfx_id)
    );

    display_renderer u_renderer (
        .clk(clk_25m),
        .rst_n(rst_n),
        .h_cnt(h_cnt),
        .v_cnt(v_cnt),
        .raw_hsync(raw_hsync),
        .raw_vsync(raw_vsync),
        .raw_active(raw_active),
        .game_state(game_state),
        .wave_num(wave_num),
        .frame_cnt(frame_cnt),
        .shake_amt(shake_amt),
        .sw_debug(sw_debug),
        .player_x(player_x),
        .player_y(player_y),
        .player_left_face(player_left_face),
        .player_form(player_form),
        .player_invuln(player_invuln),
        .barrier_active(barrier_active),
        .mic_volume(mic_volume),
        .mic_threshold(mic_threshold),
        .barrier_cooldown(barrier_cooldown),
        .en_active(en_active),
        .en_x(en_x),
        .en_y(en_y),
        .en_type(en_type),
        .en_flash(en_flash),
        .boss_active(boss_active),
        .boss_enraged(boss_enraged),
        .boss_x(boss_x),
        .boss_y(boss_y),
        .boss_flash(boss_flash),
        .pb_active(pb_active),
        .pb_x(pb_x),
        .pb_y(pb_y),
        .pb_kind(pb_kind),
        .eb_active(eb_active),
        .eb_reflected(eb_reflected),
        .eb_x(eb_x),
        .eb_y(eb_y),
        .orb_active(orb_active),
        .orb_x(orb_x),
        .orb_y(orb_y),
        .orb_type(orb_type),
        .exp_active(exp_active),
        .exp_x(exp_x),
        .exp_y(exp_y),
        .exp_timer(exp_timer),
        .hud_we(hud_we),
        .hud_waddr(hud_waddr),
        .hud_wdata(hud_wdata),
        .vga_r(VGA_R),
        .vga_g(VGA_G),
        .vga_b(VGA_B),
        .vga_hs(VGA_HS),
        .vga_vs(VGA_VS)
    );

    // -----------------------------------------------------------------------
    // 6. 7-Segment Telemetry, Status LEDs & Chiptune Audio
    // -----------------------------------------------------------------------
    // In debug mode (SW[4]=ON): show "COdE  xx" where xx is the PS/2 scan code in hex.
    wire [31:0] kbd_debug_digits = {4'hC, 4'h0, 4'hD, 4'hE, 4'hF, 4'hF, ps2_last_scan[7:4], ps2_last_scan[3:0]};

    seg7_ctrl u_seg7 (
        .clk(clk_25m),
        .rst_n(rst_n),
        .digits(sw_debug ? kbd_debug_digits : seg7_digits),
        .dp_mask(sw_debug ? 8'b0000_0011 : seg7_dp_mask),
        .an(AN),
        .ca(CA), .cb(CB), .cc(CC), .cd(CD), .ce(CE), .cf(CF), .cg(CG), .dp(DP)
    );

    // Normal game: show enemy/boss HP bar. When SW[5] is ON, LED[5] also lights on keyboard link activity.
    // In Last Boss fight: LED[15:11] displays live voice microphone VU meter!
    // Debug mode (SW[4]=ON): LED[7:0]=last scan code, LED[8]=PS2_CLK, LED[9]=PS2_DATA,
    // LED[10]=kbd_link_ok, LED[15:11]={Fire, Right, Left, Down, Up}.
    wire [4:0] mic_vu = { (mic_volume >= 8'd130),
                          (mic_volume >= 8'd105),
                          (mic_volume >= 8'd85),
                          (mic_volume >= 8'd60),
                          (mic_volume >= 8'd35) };
    wire [15:0] normal_game_leds = (sw_kbd ? (engine_led_bar | {10'd0, ps2_kbd_link, 5'd0}) : engine_led_bar);
    wire [15:0] boss_mic_leds    = {mic_vu, engine_led_bar[10:0]};

    assign LED = sw_debug ? {kbd_btn_mask, ps2_kbd_link, PS2_DATA, PS2_CLK, ps2_last_scan}
                          : ((wave_num == 3'd4 && boss_active && game_state == 3'd2) ? boss_mic_leds : normal_game_leds);

    audio_synth u_audio (
        .clk(clk_25m),
        .rst_n(rst_n),
        .mute(sw_mute),
        .game_state(game_state),
        .wave_num(wave_num),
        .sfx_valid(sfx_valid),
        .sfx_id(sfx_id),
        .aud_pwm(AUD_PWM),
        .aud_sd(AUD_SD)
    );

    // -----------------------------------------------------------------------
    // 7. Gentle PWM RGB LEDs (LED16 = Evolution Form, LED17 = Game Event)
    // -----------------------------------------------------------------------
    reg [7:0] rgb_pwm_cnt;
    always @(posedge clk_25m) begin
        if (!rst_n) begin
            rgb_pwm_cnt <= 8'd0;
            {LED16_R, LED16_G, LED16_B} <= 3'b000;
            {LED17_R, LED17_G, LED17_B} <= 3'b000;
        end else begin
            rgb_pwm_cnt <= rgb_pwm_cnt + 8'd1;
            // Duty capped at 32/256 (12.5%) for comfortable eye brightness
            if (rgb_pwm_cnt < 8'd32) begin
                case (player_form)
                    2'd0: {LED16_R, LED16_G, LED16_B} <= 3'b111; // White Goose
                    2'd1: {LED16_R, LED16_G, LED16_B} <= 3'b011; // Blue/Cyan Goose
                    default: begin
                        // Gentle Rainbow cycle
                        case (frame_cnt[6:4])
                            3'd0: {LED16_R, LED16_G, LED16_B} <= 3'b100;
                            3'd1: {LED16_R, LED16_G, LED16_B} <= 3'b110;
                            3'd2: {LED16_R, LED16_G, LED16_B} <= 3'b010;
                            3'd3: {LED16_R, LED16_G, LED16_B} <= 3'b011;
                            3'd4: {LED16_R, LED16_G, LED16_B} <= 3'b001;
                            default: {LED16_R, LED16_G, LED16_B} <= 3'b101;
                        endcase
                    end
                endcase

                if (evt_flash_timer > 4'd0) begin
                    case (evt_flash_kind)
                        2'd1: {LED17_R, LED17_G, LED17_B} <= 3'b010; // Green (Evo/Win)
                        2'd2: {LED17_R, LED17_G, LED17_B} <= 3'b100; // Red (Hurt)
                        2'd3: {LED17_R, LED17_G, LED17_B} <= 3'b110; // Yellow (Boss)
                        default: {LED17_R, LED17_G, LED17_B} <= 3'b001;
                    endcase
                end else if (wave_num == 3'd4 && boss_active && game_state == 3'd2) begin
                    if (barrier_active)
                        {LED17_R, LED17_G, LED17_B} <= 3'b011; // Cyan (Barrier Active!)
                    else
                        {LED17_R, LED17_G, LED17_B} <= 3'b010; // Green (Barrier Ready to Shout!)
                end else begin
                    {LED17_R, LED17_G, LED17_B} <= (game_state == 3'd2) ? 3'b001 : 3'b000;
                end
            end else begin
                {LED16_R, LED16_G, LED16_B} <= 3'b000;
                {LED17_R, LED17_G, LED17_B} <= 3'b000;
            end
        end
    end

    // Keep unused switch bits referenced cleanly without affecting gameplay
    wire _unused_ok = &{1'b0, sw_deb[14], sw_deb[11:7], boss_max_hp, player_lives, hard_mode, sw_rise};
endmodule
