// tp_uart_rx.sv — 8N1 serial receiver.
//
// The bit period is DIV core clocks, so the baud rate tracks whatever
// clock the board runs at: baud = clk_hz / DIV. With the default DIV of
// 434 that is 115,207 baud at 50 MHz, which every serial terminal treats
// as 115200. Run the tile at 25 MHz and you get 57,600 instead — the
// relationship is fixed in silicon and there is no divisor register to
// get wrong, which on a part with no way to recover from a bad setting
// is the safer trade.
//
// Two flops of synchroniser on the pin, then sample each bit at its
// centre. No parity, one stop bit, no flow control.
`default_nettype none

module tp_uart_rx #(
    parameter int DIV  = 434,
    parameter int DIVW = 9            // $clog2(DIV) + 1
) (
    input  wire  logic       clk,
    input  wire  logic       rst,
    input  wire  logic       rx_pin,
    output logic [7:0]       data,     // valid only in the `valid` cycle
    output logic             valid     // one clock when a byte has landed
);

    localparam logic [1:0] S_IDLE  = 2'd0;
    localparam logic [1:0] S_START = 2'd1;
    localparam logic [1:0] S_DATA  = 2'd2;
    localparam logic [1:0] S_STOP  = 2'd3;

    logic            sync0, sync1;
    logic [1:0]      state;
    logic [DIVW-1:0] cnt;
    logic [2:0]      bit_idx;
    logic [7:0]      shift;

    // No separate output register: `shift` holds the finished byte through
    // the whole stop bit, which is exactly when `valid` pulses, and the
    // consumer only looks at it in that cycle. Saves eight flip-flops,
    // which on a 1x1 tile is worth having.
    assign data = shift;

    always_ff @(posedge clk) begin
        if (rst) begin
            sync0   <= 1'b1;
            sync1   <= 1'b1;
            state   <= S_IDLE;
            cnt     <= '0;
            bit_idx <= 3'd0;
            shift   <= 8'd0;
            valid   <= 1'b0;
        end else begin
            sync0 <= rx_pin;
            sync1 <= sync0;
            valid <= 1'b0;

            unique case (state)

                S_IDLE: begin
                    // a start bit is the line going low
                    if (!sync1) begin
                        state <= S_START;
                        cnt   <= '0;
                    end
                end

                S_START: begin
                    // wait half a bit and confirm the start is still low,
                    // which rejects a glitch
                    if (cnt == (DIVW'(DIV/2) - 1'b1)) begin
                        if (!sync1) begin
                            state   <= S_DATA;
                            cnt     <= '0;
                            bit_idx <= 3'd0;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    if (cnt == (DIVW'(DIV) - 1'b1)) begin
                        cnt   <= '0;
                        // least significant bit first, as 8N1 sends it
                        shift <= {sync1, shift[7:1]};
                        if (bit_idx == 3'd7) state   <= S_STOP;
                        else                 bit_idx <= bit_idx + 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    if (cnt == (DIVW'(DIV) - 1'b1)) begin
                        // a framing error (stop bit low) drops the byte
                        if (sync1) valid <= 1'b1;
                        state <= S_IDLE;
                        cnt   <= '0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule : tp_uart_rx
