`timescale 1ns / 1ps

module audio_synth (
    input  wire       clk,         // 25 MHz
    input  wire       rst_n,
    input  wire       mute,
    input  wire [2:0] game_state,  // 0=TITLE,1=INTRO,2=PLAY,3=PAUSE,4=VICTORY,5=GAMEOVER
    input  wire [2:0] wave_num,    // 1..3 normal, 4=boss
    input  wire       sfx_valid,
    input  wire [2:0] sfx_id,      // 1=sh1,2=sh2,3=sh3,4=exp,5=evo,6=hurt,7=warn
    output reg        aud_pwm,
    output wire       aud_sd
);
    assign aud_sd = ~mute;

    // -----------------------------------------------------------------------
    // BGM ROM (512 x 16-bit)
    // -----------------------------------------------------------------------
    reg  [8:0]  bgm_addr;
    wire [15:0] bgm_word;
    sync_rom #(
        .ADDR_WIDTH(9),
        .DATA_WIDTH(16),
        .DEPTH(512),
        .INIT_FILE("bgm_rom.mem")
    ) u_bgm_rom (
        .clk(clk),
        .addr(bgm_addr),
        .dout(bgm_word)
    );

    // Note phase increment LUT (freq * 2^24 / 25e6)
    function [11:0] note_to_inc;
        input [5:0] n;
        begin
            case (n)
                6'd1:  note_to_inc = 12'd88;   // C3
                6'd2:  note_to_inc = 12'd93;
                6'd3:  note_to_inc = 12'd99;   // D3
                6'd4:  note_to_inc = 12'd104;
                6'd5:  note_to_inc = 12'd111;  // E3
                6'd6:  note_to_inc = 12'd117;  // F3
                6'd7:  note_to_inc = 12'd124;
                6'd8:  note_to_inc = 12'd132;  // G3
                6'd9:  note_to_inc = 12'd139;
                6'd10: note_to_inc = 12'd148;  // A3
                6'd11: note_to_inc = 12'd156;
                6'd12: note_to_inc = 12'd166;  // B3
                6'd13: note_to_inc = 12'd176;  // C4
                6'd14: note_to_inc = 12'd186;
                6'd15: note_to_inc = 12'd197;  // D4
                6'd16: note_to_inc = 12'd209;
                6'd17: note_to_inc = 12'd221;  // E4
                6'd18: note_to_inc = 12'd234;  // F4
                6'd19: note_to_inc = 12'd248;
                6'd20: note_to_inc = 12'd263;  // G4
                6'd21: note_to_inc = 12'd279;
                6'd22: note_to_inc = 12'd295;  // A4
                6'd23: note_to_inc = 12'd313;
                6'd24: note_to_inc = 12'd331;  // B4
                6'd25: note_to_inc = 12'd351;  // C5
                6'd26: note_to_inc = 12'd372;
                6'd27: note_to_inc = 12'd394;  // D5
                6'd28: note_to_inc = 12'd417;
                6'd29: note_to_inc = 12'd442;  // E5
                6'd30: note_to_inc = 12'd469;  // F5
                6'd31: note_to_inc = 12'd496;
                6'd32: note_to_inc = 12'd526;  // G5
                6'd33: note_to_inc = 12'd557;
                6'd34: note_to_inc = 12'd590;  // A5
                6'd35: note_to_inc = 12'd626;
                6'd36: note_to_inc = 12'd663;  // B5
                6'd37: note_to_inc = 12'd702;  // C6
                default: note_to_inc = 12'd0;
            endcase
        end
    endfunction

    // Step tempo (~135 BPM eighth notes -> ~140 ms = 3,500,000 cycles @ 25 MHz)
    localparam [21:0] STEP_CYCLES = 22'd3250000;
    reg [21:0] step_timer;
    reg [6:0]  step_idx;
    reg [2:0]  prev_track;
    reg        stinger_done;

    reg [1:0] cur_track;
    always @(*) begin
        if (game_state == 3'd4)
            cur_track = 2'd3; // Victory
        else if (game_state == 3'd5)
            cur_track = 2'd3; // Game over
        else if ((game_state == 3'd2 || game_state == 3'd1) && wave_num == 3'd4)
            cur_track = 2'd2; // Boss AJV
        else if (game_state == 3'd2)
            cur_track = 2'd1; // Action
        else
            cur_track = 2'd0; // Title
    end

    // LFSR for noise percussion & explosion SFX
    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (!rst_n)
            lfsr <= 16'hACE1;
        else
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // Sequencer
    always @(posedge clk) begin
        if (!rst_n) begin
            step_timer   <= 22'd0;
            step_idx     <= 7'd0;
            prev_track   <= 3'd7;
            bgm_addr     <= 9'd0;
            stinger_done <= 1'b0;
        end else begin
            if (game_state == 3'd3) begin
                // Paused: hold sequencer
            end else if ({game_state == 3'd5, cur_track} != prev_track) begin
                prev_track   <= {game_state == 3'd5, cur_track};
                step_idx     <= 7'd0;
                step_timer   <= 22'd0;
                stinger_done <= 1'b0;
            end else if (step_timer >= STEP_CYCLES) begin
                step_timer <= 22'd0;
                if (game_state == 3'd4 || game_state == 3'd5) begin
                    if (step_idx < 7'd63)
                        step_idx <= step_idx + 7'd1;
                    else
                        stinger_done <= 1'b1;
                end else begin
                    step_idx <= step_idx + 7'd1;
                end
            end else begin
                step_timer <= step_timer + 22'd1;
            end

            // Compute ROM address
            if (game_state == 3'd4)
                bgm_addr <= 9'd384 + {3'd0, step_idx[5:0]};
            else if (game_state == 3'd5)
                bgm_addr <= 9'd448 + {3'd0, step_idx[5:0]};
            else
                bgm_addr <= {cur_track, step_idx};
        end
    end

    wire [5:0] lead_note = stinger_done ? 6'd0 : bgm_word[15:10];
    wire [5:0] bass_note = stinger_done ? 6'd0 : bgm_word[9:4];
    wire [3:0] drum_mask = stinger_done ? 4'd0 : bgm_word[3:0];

    reg [23:0] lead_phase, bass_phase;
    always @(posedge clk) begin
        if (!rst_n || game_state == 3'd3) begin
            lead_phase <= 24'd0;
            bass_phase <= 24'd0;
        end else begin
            lead_phase <= lead_phase + {12'd0, note_to_inc(lead_note)};
            bass_phase <= bass_phase + {12'd0, note_to_inc(bass_note)};
        end
    end

    wire lead_on = (lead_note != 6'd0) && (step_timer < (STEP_CYCLES - 22'd400000));
    wire bass_on = (bass_note != 6'd0);
    // 25% duty pulse for lead, 50% square for bass
    wire [4:0] lead_amp = (lead_on && (lead_phase[23:22] == 2'b00)) ? 5'd24 : 5'd0;
    wire [4:0] bass_amp = (bass_on && bass_phase[23]) ? 5'd18 : 5'd0;
    wire [4:0] drum_amp = (drum_mask[0] && step_timer < 22'd350000 && lfsr[0]) ? 5'd14 :
                          (drum_mask[1] && step_timer < 22'd500000 && lfsr[2]) ? 5'd12 :
                          (drum_mask[2] && step_timer < 22'd180000 && lfsr[4]) ? 5'd7  : 5'd0;

    // -----------------------------------------------------------------------
    // Priority SFX Generator
    // -----------------------------------------------------------------------
    reg [2:0]  sfx_cur;
    reg [22:0] sfx_timer;
    reg [23:0] sfx_phase;
    reg [12:0] sfx_inc;

    always @(posedge clk) begin
        if (!rst_n) begin
            sfx_cur   <= 3'd0;
            sfx_timer <= 23'd0;
            sfx_phase <= 24'd0;
            sfx_inc   <= 13'd0;
        end else begin
            if (sfx_valid && (sfx_id >= sfx_cur || sfx_cur == 3'd0)) begin
                sfx_cur   <= sfx_id;
                sfx_timer <= 23'd0;
                sfx_phase <= 24'd0;
                case (sfx_id)
                    3'd1: sfx_inc <= 13'd720;  // Laser high
                    3'd2: sfx_inc <= 13'd880;  // Twin plasma
                    3'd3: sfx_inc <= 13'd520;  // Nova chime
                    3'd4: sfx_inc <= 13'd160;  // Explosion punch
                    3'd5: sfx_inc <= 13'd351;  // Evo arpeggio start
                    3'd6: sfx_inc <= 13'd220;  // Hurt buzz
                    default: sfx_inc <= 13'd400;
                endcase
            end else if (sfx_cur != 3'd0) begin
                sfx_timer <= sfx_timer + 23'd1;
                sfx_phase <= sfx_phase + {11'd0, sfx_inc};
                // Pitch envelopes every ~32k cycles
                if (sfx_timer[15:0] == 16'd0) begin
                    case (sfx_cur)
                        3'd1, 3'd2: if (sfx_inc > 13'd180) sfx_inc <= sfx_inc - 13'd18;
                        3'd3:       sfx_inc <= sfx_inc + 13'd24;
                        3'd4:       if (sfx_inc > 13'd45)  sfx_inc <= sfx_inc - 13'd4;
                        3'd5:       sfx_inc <= sfx_inc + 13'd22;
                        3'd6:       if (sfx_inc > 13'd70)  sfx_inc <= sfx_inc - 13'd6;
                        3'd7:       sfx_inc <= (sfx_timer[18]) ? 13'd520 : 13'd390;
                        default: ;
                    endcase
                end
                // End durations
                if ((sfx_cur <= 3'd3 && sfx_timer >= 23'd1800000) ||
                    (sfx_cur == 3'd4 && sfx_timer >= 23'd3500000) ||
                    (sfx_cur == 3'd5 && sfx_timer >= 23'd6500000) ||
                    (sfx_cur >= 3'd6 && sfx_timer >= 23'd4500000)) begin
                    sfx_cur <= 3'd0;
                end
            end
        end
    end

    reg [5:0] sfx_amp;
    always @(*) begin
        if (sfx_cur == 3'd0) begin
            sfx_amp = 6'd0;
        end else if (sfx_cur == 3'd4) begin
            sfx_amp = (lfsr[1] ? 6'd42 : 6'd0) + (sfx_phase[23] ? 6'd16 : 6'd0);
        end else if (sfx_cur == 3'd6) begin
            sfx_amp = (sfx_phase[23] ^ lfsr[0]) ? 6'd44 : 6'd0;
        end else begin
            sfx_amp = sfx_phase[23] ? 6'd44 : 6'd0;
        end
    end

    // -----------------------------------------------------------------------
    // 8-bit PWM DAC @ 97.6 kHz
    // -----------------------------------------------------------------------
    wire [7:0] mix_sample = (game_state == 3'd3 || mute) ? 8'd0 :
                            ({2'd0, lead_amp} + {2'd0, bass_amp} + {2'd0, drum_amp} + {1'd0, sfx_amp});
    reg [7:0] pwm_cnt;
    always @(posedge clk) begin
        if (!rst_n) begin
            pwm_cnt <= 8'd0;
            aud_pwm <= 1'b0;
        end else begin
            pwm_cnt <= pwm_cnt + 8'd1;
            aud_pwm <= (pwm_cnt < mix_sample) && !mute;
        end
    end
endmodule
