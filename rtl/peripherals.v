`timescale 1ns / 1ps

module debounce_bank #(
    parameter integer WIDTH = 5,
    parameter integer DEBOUNCE_MAX = 125000  // 5ms @ 25 MHz
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] raw_in,
    output reg  [WIDTH-1:0] debounced,
    output reg  [WIDTH-1:0] rise_pulse
);
    reg [WIDTH-1:0] sync0;
    reg [WIDTH-1:0] sync1;
    reg [17:0]      cnt [0:WIDTH-1];

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            sync0      <= {WIDTH{1'b0}};
            sync1      <= {WIDTH{1'b0}};
            debounced  <= {WIDTH{1'b0}};
            rise_pulse <= {WIDTH{1'b0}};
            for (i = 0; i < WIDTH; i = i + 1)
                cnt[i] <= 18'd0;
        end else begin
            sync0 <= raw_in;
            sync1 <= sync0;
            rise_pulse <= {WIDTH{1'b0}};
            for (i = 0; i < WIDTH; i = i + 1) begin
                if (sync1[i] == debounced[i]) begin
                    cnt[i] <= 18'd0;
                end else if (cnt[i] >= DEBOUNCE_MAX) begin
                    debounced[i]  <= sync1[i];
                    rise_pulse[i] <= sync1[i];
                    cnt[i]        <= 18'd0;
                end else begin
                    cnt[i] <= cnt[i] + 18'd1;
                end
            end
        end
    end
endmodule


module seg7_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] digits,   // 8 nibbles: [31:28]=AN7 ... [3:0]=AN0
    input  wire [7:0]  dp_mask,  // 1 = turn on decimal point
    output reg  [7:0]  an,
    output reg         ca,
    output reg         cb,
    output reg         cc,
    output reg         cd,
    output reg         ce,
    output reg         cf,
    output reg         cg,
    output reg         dp
);
    // Refresh ~1.5 kHz per digit @ 25 MHz -> 16-bit counter, top 3 bits select digit
    reg [15:0] scan_cnt;
    always @(posedge clk) begin
        if (!rst_n)
            scan_cnt <= 16'd0;
        else
            scan_cnt <= scan_cnt + 16'd1;
    end

    wire [2:0] dig_sel = scan_cnt[15:13];
    reg  [3:0] cur_nib;
    reg  [6:0] seg_pat;

    always @(*) begin
        case (dig_sel)
            3'd0: cur_nib = digits[3:0];
            3'd1: cur_nib = digits[7:4];
            3'd2: cur_nib = digits[11:8];
            3'd3: cur_nib = digits[15:12];
            3'd4: cur_nib = digits[19:16];
            3'd5: cur_nib = digits[23:20];
            3'd6: cur_nib = digits[27:24];
            default: cur_nib = digits[31:28];
        endcase

        // Active-low {ca,cb,cc,cd,ce,cf,cg}
        case (cur_nib)
            4'h0: seg_pat = 7'b0000001;
            4'h1: seg_pat = 7'b1001111;
            4'h2: seg_pat = 7'b0010010;
            4'h3: seg_pat = 7'b0000110;
            4'h4: seg_pat = 7'b1001100;
            4'h5: seg_pat = 7'b0100100;
            4'h6: seg_pat = 7'b0100000;
            4'h7: seg_pat = 7'b0001111;
            4'h8: seg_pat = 7'b0000000;
            4'h9: seg_pat = 7'b0000100;
            4'hA: seg_pat = 7'b0001000; // 'A'
            4'hB: seg_pat = 7'b1100000; // 'b' (Boss)
            4'hC: seg_pat = 7'b0110001; // 'C'
            4'hD: seg_pat = 7'b1000010; // 'd'
            4'hE: seg_pat = 7'b0110000; // 'E'
            default: seg_pat = 7'b1111111; // 4'hF = blank
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            an <= 8'hFF;
            {ca, cb, cc, cd, ce, cf, cg, dp} <= 8'hFF;
        end else begin
            an <= ~(8'b00000001 << dig_sel);
            {ca, cb, cc, cd, ce, cf, cg} <= seg_pat;
            dp <= ~dp_mask[dig_sel];
        end
    end
endmodule


module adxl362_spi (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       acl_miso,
    output reg        acl_mosi,
    output reg        acl_sclk,
    output reg        acl_csn,
    output reg signed [7:0] accel_x,
    output reg signed [7:0] accel_y
);
    // Simple SPI Mode-0 polling FSM (~1.56 MHz SCLK from 25 MHz clk)
    localparam [2:0] ST_BOOT   = 3'd0,
                     ST_CFG_TX = 3'd1,
                     ST_RD_TX  = 3'd2,
                     ST_IDLE   = 3'd3;

    reg [2:0]  state;
    reg [15:0] wait_cnt;
    reg [4:0]  bit_cnt;
    reg [23:0] tx_shift;
    reg [7:0]  rx_shift;
    reg [3:0]  clk_div;
    reg        read_y;  // 0 = read X (0x08), 1 = read Y (0x09)

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= ST_BOOT;
            wait_cnt <= 16'd0;
            bit_cnt  <= 5'd0;
            tx_shift <= 24'd0;
            rx_shift <= 8'd0;
            clk_div  <= 4'd0;
            acl_csn  <= 1'b1;
            acl_sclk <= 1'b0;
            acl_mosi <= 1'b0;
            accel_x  <= 8'sd0;
            accel_y  <= 8'sd0;
            read_y   <= 1'b0;
        end else begin
            case (state)
                ST_BOOT: begin
                    acl_csn  <= 1'b1;
                    acl_sclk <= 1'b0;
                    if (wait_cnt >= 16'd50000) begin
                        // Write POWER_CTL (0x2D) = 0x02 (Measure mode)
                        tx_shift <= {8'h0A, 8'h2D, 8'h02};
                        bit_cnt  <= 5'd23;
                        clk_div  <= 4'd0;
                        acl_csn  <= 1'b0;
                        acl_mosi <= 1'b0;
                        state    <= ST_CFG_TX;
                    end else begin
                        wait_cnt <= wait_cnt + 16'd1;
                    end
                end

                ST_CFG_TX, ST_RD_TX: begin
                    clk_div <= clk_div + 4'd1;
                    if (clk_div == 4'd0) begin
                        acl_sclk <= 1'b0;
                        acl_mosi <= tx_shift[23];
                    end else if (clk_div == 4'd8) begin
                        acl_sclk <= 1'b1;
                        rx_shift <= {rx_shift[6:0], acl_miso};
                    end else if (clk_div == 4'd15) begin
                        acl_sclk <= 1'b0;
                        tx_shift <= {tx_shift[22:0], 1'b0};
                        if (bit_cnt == 5'd0) begin
                            acl_csn <= 1'b1;
                            if (state == ST_RD_TX) begin
                                if (!read_y)
                                    accel_x <= rx_shift;
                                else
                                    accel_y <= rx_shift;
                                read_y <= ~read_y;
                            end
                            wait_cnt <= 16'd0;
                            state    <= ST_IDLE;
                        end else begin
                            bit_cnt <= bit_cnt - 5'd1;
                        end
                    end
                end

                ST_IDLE: begin
                    acl_csn  <= 1'b1;
                    acl_sclk <= 1'b0;
                    if (wait_cnt >= 16'd10000) begin
                        tx_shift <= {8'h0B, (read_y ? 8'h09 : 8'h08), 8'h00};
                        bit_cnt  <= 5'd23;
                        clk_div  <= 4'd0;
                        acl_csn  <= 1'b0;
                        state    <= ST_RD_TX;
                    end else begin
                        wait_cnt <= wait_cnt + 16'd1;
                    end
                end

                default: state <= ST_BOOT;
            endcase
        end
    end
endmodule


module uart_rx #(
    parameter integer CLKS_PER_BIT = 217  // 25 MHz / 115200 = 217
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);
    reg [1:0] rx_sync;
    reg [1:0] state;
    reg [8:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shift;

    localparam [1:0] U_IDLE = 2'd0, U_START = 2'd1, U_DATA = 2'd2, U_STOP = 2'd3;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_sync  <= 2'b11;
            state    <= U_IDLE;
            clk_cnt  <= 9'd0;
            bit_idx  <= 3'd0;
            shift    <= 8'd0;
            rx_data  <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_sync  <= {rx_sync[0], rx};
            rx_valid <= 1'b0;
            case (state)
                U_IDLE: begin
                    if (!rx_sync[1]) begin
                        clk_cnt <= 9'd0;
                        state   <= U_START;
                    end
                end
                U_START: begin
                    if (clk_cnt == (CLKS_PER_BIT >> 1)) begin
                        if (!rx_sync[1]) begin
                            clk_cnt <= 9'd0;
                            bit_idx <= 3'd0;
                            state   <= U_DATA;
                        end else begin
                            state <= U_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 9'd1;
                    end
                end
                U_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt        <= 9'd0;
                        shift[bit_idx] <= rx_sync[1];
                        if (bit_idx == 3'd7)
                            state <= U_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else begin
                        clk_cnt <= clk_cnt + 9'd1;
                    end
                end
                U_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_data  <= shift;
                        rx_valid <= 1'b1;
                        state    <= U_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 9'd1;
                    end
                end
            endcase
        end
    end
endmodule

// ---------------------------------------------------------------------------
// 5. PS/2 Keyboard Controller for Digilent Nexys A7 USB Host (J5)
// Decodes W (0x1D), A (0x1C), S (0x1B), D (0x23), Enter (0x5A), Space (0x29)
// and extended Arrow keys (0xE0 + 0x75/0x72/0x6B/0x74).
// Handles make codes and break codes (0xF0 prefix) with glitch filter.
// ---------------------------------------------------------------------------
module ps2_keyboard (
    input  wire       clk,        // 25 MHz
    input  wire       rst_n,
    input  wire       ps2_clk,    // From FPGA pin F4
    input  wire       ps2_data,   // From FPGA pin B2
    output reg  [4:0] kbd_btn,    // {fire, right, left, down, up}
    output reg        kbd_link_ok,// High when keyboard has recently sent data
    output reg  [7:0] last_scan_code // Debug/Telemetry: last valid scan code received
);
    // 3-stage synchronizers
    reg [2:0] clk_sync;
    reg [2:0] data_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_sync  <= 3'b111;
            data_sync <= 3'b111;
        end else begin
            clk_sync  <= {clk_sync[1:0], ps2_clk};
            data_sync <= {data_sync[1:0], ps2_data};
        end
    end

    // Digital debounce filter for ps2_clk (stable for 8 cycles = 320 ns @ 25 MHz)
    reg [3:0] filter_cnt;
    reg       ps2_clk_f;
    reg       prev_clk_f;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filter_cnt <= 4'd0;
            ps2_clk_f  <= 1'b1;
            prev_clk_f <= 1'b1;
        end else begin
            prev_clk_f <= ps2_clk_f;
            if (clk_sync[2] == ps2_clk_f) begin
                filter_cnt <= 4'd0;
            end else begin
                filter_cnt <= filter_cnt + 4'd1;
                if (filter_cnt == 4'd7) begin
                    ps2_clk_f  <= clk_sync[2];
                    filter_cnt <= 4'd0;
                end
            end
        end
    end

    wire ps2_fall = (prev_clk_f && !ps2_clk_f);

    // 11-bit frame receiver: Start(0), D0..D7, Parity, Stop(1)
    reg [7:0]  rx_shift;
    reg [3:0]  bit_cnt;
    reg [19:0] timeout_cnt; // Watchdog to reset frame if line stalls

    reg [7:0]  rx_byte;
    reg        rx_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift    <= 8'd0;
            bit_cnt     <= 4'd0;
            timeout_cnt <= 20'd0;
            rx_byte     <= 8'd0;
            rx_valid    <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            if (ps2_fall) begin
                timeout_cnt <= 20'd0;
                case (bit_cnt)
                    4'd0: begin
                        // Start bit must be 0
                        if (data_sync[2] == 1'b0)
                            bit_cnt <= 4'd1;
                    end
                    4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7: begin
                        // Shift in D0..D6 (LSB first)
                        rx_shift <= {data_sync[2], rx_shift[7:1]};
                        bit_cnt  <= bit_cnt + 4'd1;
                    end
                    4'd8: begin
                        // Shift in D7 (MSB)
                        rx_shift <= {data_sync[2], rx_shift[7:1]};
                        bit_cnt  <= 4'd9;
                    end
                    4'd9: begin
                        // Parity bit (relaxed for compatibility)
                        bit_cnt <= 4'd10;
                    end
                    4'd10: begin
                        // Stop bit must be 1
                        if (data_sync[2] == 1'b1) begin
                            rx_byte  <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                        bit_cnt <= 4'd0;
                    end
                    default: bit_cnt <= 4'd0;
                endcase
            end else if (bit_cnt != 4'd0) begin
                timeout_cnt <= timeout_cnt + 20'd1;
                if (timeout_cnt >= 20'd125000) begin // 5 ms timeout
                    bit_cnt     <= 4'd0;
                    timeout_cnt <= 20'd0;
                end
            end
        end
    end

    // PS/2 Set 2 Scan Code Decoder
    reg is_break;
    reg is_ext;
    reg [24:0] link_timer;

    reg key_w, key_a, key_s, key_d, key_fire;
    reg key_up_arr, key_down_arr, key_left_arr, key_right_arr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_break       <= 1'b0;
            is_ext         <= 1'b0;
            link_timer     <= 25'd0;
            key_w          <= 1'b0;
            key_a          <= 1'b0;
            key_s          <= 1'b0;
            key_d          <= 1'b0;
            key_fire       <= 1'b0;
            key_up_arr     <= 1'b0;
            key_down_arr   <= 1'b0;
            key_left_arr   <= 1'b0;
            key_right_arr  <= 1'b0;
            kbd_btn        <= 5'd0;
            kbd_link_ok    <= 1'b0;
            last_scan_code <= 8'd0;
        end else begin
            if (link_timer > 25'd0) begin
                link_timer  <= link_timer - 25'd1;
                kbd_link_ok <= 1'b1;
            end else begin
                kbd_link_ok <= 1'b0;
            end

            if (rx_valid) begin
                link_timer     <= 25'd25000000; // 1 second link status
                last_scan_code <= rx_byte;
                if (rx_byte == 8'hE0) begin
                    is_ext <= 1'b1;
                end else if (rx_byte == 8'hF0) begin
                    is_break <= 1'b1;
                end else begin
                    if (is_ext) begin
                        case (rx_byte)
                            8'h75: key_up_arr    <= ~is_break; // Up arrow
                            8'h72: key_down_arr  <= ~is_break; // Down arrow
                            8'h6B: key_left_arr  <= ~is_break; // Left arrow
                            8'h74: key_right_arr <= ~is_break; // Right arrow
                            8'h5A: key_fire      <= ~is_break; // Numpad Enter
                            default: ;
                        endcase
                    end else begin
                        case (rx_byte)
                            8'h1D: key_w         <= ~is_break; // W
                            8'h1C: key_a         <= ~is_break; // A
                            8'h1B: key_s         <= ~is_break; // S
                            8'h23: key_d         <= ~is_break; // D
                            8'h5A: key_fire      <= ~is_break; // Enter
                            8'h29: key_fire      <= ~is_break; // Space
                            default: ;
                        endcase
                    end
                    is_break <= 1'b0;
                    is_ext   <= 1'b0;
                end
            end

            // Standard WASD & Arrow Key Mapping:
            // W / Up Arrow    -> Up    (bit 0)
            // S / Down Arrow  -> Down  (bit 1)
            // A / Left Arrow  -> Left  (bit 2)
            // D / Right Arrow -> Right (bit 3)
            // Enter / Space   -> Fire  (bit 4)
            kbd_btn[0] <= key_w | key_up_arr;
            kbd_btn[1] <= key_s | key_down_arr;
            kbd_btn[2] <= key_a | key_left_arr;
            kbd_btn[3] <= key_d | key_right_arr;
            kbd_btn[4] <= key_fire;
        end
    end
endmodule


// ===========================================================================
// Nexys A7 On-Board MEMS Microphone Driver (ADMP421 PDM) & Envelope Meter
// ===========================================================================
module pdm_microphone (
    input  wire        clk,            // 25 MHz system clock
    input  wire        rst_n,          // Active-low reset
    input  wire        m_data,         // Digital MEMS mic PDM data in (Pin H5)
    input  wire [7:0]  threshold,      // Volume trigger threshold (e.g. 80..95)
    output reg         m_clk,          // Mic clock out: ~2.5 MHz (Pin J5)
    output wire        m_lrsel,        // Channel select: 1'b0 = Left (Pin F5)
    output reg  [7:0]  volume_level,   // Smoothed volume envelope (0..255)
    output reg         shout_trigger   // 1-cycle pulse when shout detected
);
    assign m_lrsel = 1'b0; // Always Left channel on Nexys A7

    // -------------------------------------------------------------------------
    // 1. Clock Generation: 25 MHz / 10 = 2.50 MHz (50% duty cycle)
    // -------------------------------------------------------------------------
    reg [3:0] clk_div;
    wire m_clk_rise = (clk_div == 4'd4);
    wire m_clk_fall = (clk_div == 4'd9);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div <= 4'd0;
            m_clk   <= 1'b0;
        end else begin
            if (clk_div == 4'd9)
                clk_div <= 4'd0;
            else
                clk_div <= clk_div + 4'd1;

            if (m_clk_rise)
                m_clk <= 1'b1;
            else if (m_clk_fall)
                m_clk <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Synchronize M_DATA to 25 MHz clock domain
    // Sample on M_CLK rising edge (valid on rising edge for L/R = GND)
    // -------------------------------------------------------------------------
    reg m_data_s0, m_data_s1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_data_s0 <= 1'b0;
            m_data_s1 <= 1'b0;
        end else begin
            m_data_s0 <= m_data;
            m_data_s1 <= m_data_s0;
        end
    end

    // -------------------------------------------------------------------------
    // 3. PDM Demodulation Window (128 samples = 51.2 us)
    // Count '1' bits over 128 clocks. Silence is ~64 ones.
    // -------------------------------------------------------------------------
    reg [6:0] sample_cnt;
    reg [7:0] ones_cnt;
    reg [7:0] cur_amp;
    reg       window_done;

    wire [7:0] dev_diff = (ones_cnt >= 8'd64) ? (ones_cnt - 8'd64) : (8'd64 - ones_cnt);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_cnt  <= 7'd0;
            ones_cnt    <= 8'd0;
            cur_amp     <= 8'd0;
            window_done <= 1'b0;
        end else begin
            window_done <= 1'b0;
            if (m_clk_rise) begin
                if (sample_cnt == 7'd127) begin
                    sample_cnt  <= 7'd0;
                    window_done <= 1'b1;
                    cur_amp     <= (dev_diff >= 8'd63) ? 8'd255 : { dev_diff[5:0], 2'b00 };
                    ones_cnt    <= m_data_s1 ? 8'd1 : 8'd0;
                end else begin
                    sample_cnt <= sample_cnt + 7'd1;
                    ones_cnt   <= ones_cnt + (m_data_s1 ? 8'd1 : 8'd0);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Envelope Detector (Fast Attack, Smooth Decay)
    // -------------------------------------------------------------------------
    reg [5:0] decay_cnt;
    reg [7:0] env_reg;
    reg [7:0] prev_env;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decay_cnt     <= 6'd0;
            env_reg       <= 8'd0;
            prev_env      <= 8'd0;
            volume_level  <= 8'd0;
            shout_trigger <= 1'b0;
        end else begin
            shout_trigger <= 1'b0;
            if (window_done) begin
                if (cur_amp > env_reg) begin
                    env_reg <= cur_amp;
                end else begin
                    if (decay_cnt == 6'd63) begin
                        decay_cnt <= 6'd0;
                        if (env_reg > 8'd2)
                            env_reg <= env_reg - 8'd2;
                        else
                            env_reg <= 8'd0;
                    end else begin
                        decay_cnt <= decay_cnt + 6'd1;
                    end
                end

                volume_level <= env_reg;

                if (env_reg >= threshold) begin
                    shout_trigger <= 1'b1;
                end
                prev_env <= env_reg;
            end
        end
    end
endmodule

