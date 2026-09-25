// tp_uart_tx.sv — 8N1 serial transmitter.
//
// Same bit period as tp_uart_rx. Pulse `start` with `data` valid while
// `busy` is low; the byte goes out start bit first, least significant
// data bit first, one stop bit.
`default_nettype none

module tp_uart_tx #(
    parameter int DIV  = 434,
    parameter int DIVW = 9
) (
    input  wire  logic       clk,
    input  wire  logic       rst,
    input  wire  logic       start,
    input  wire  logic [7:0] data,
    output logic             tx_pin,
    output logic             busy
);

    logic [DIVW-1:0] cnt;
    logic [3:0]      bit_idx;
    logic [9:0]      shift;      // {stop, data[7:0], start}

    always_ff @(posedge clk) begin
        if (rst) begin
            cnt     <= '0;
            bit_idx <= 4'd0;
            shift   <= 10'h3FF;
            tx_pin  <= 1'b1;
            busy    <= 1'b0;
        end else if (!busy) begin
            tx_pin <= 1'b1;
            if (start) begin
                shift   <= {1'b1, data, 1'b0};
                busy    <= 1'b1;
                cnt     <= '0;
                bit_idx <= 4'd0;
                tx_pin  <= 1'b0;          // start bit immediately
            end
        end else begin
            if (cnt == (DIVW'(DIV) - 1'b1)) begin
                cnt <= '0;
                if (bit_idx == 4'd9) begin
                    busy   <= 1'b0;
                    tx_pin <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 1'b1;
                    tx_pin  <= shift[bit_idx + 4'd1];
                end
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

endmodule : tp_uart_tx
