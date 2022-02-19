// module: hcsr04_capture.sv
//
// The HC-SR04 ultrasonic sensor transmits an ultrasonic burst 
// when a pulse is detected on the trigger pin. It then waits for 
// the reflected ultrasonic burst; when detected, the sensor
// sets the echo pin to high for a period proportional to the distance.
// 
// Sensor Details:
//  - range 2cm - 400cm OR 1" - 13ft
//  - trigger pulse width: 10us
//
// This module sets the trigger pin whenever a reading is not in
// progress and updates the distance output accordingly.
//
//
module hcsr04_capture
    #(parameter T_CLK = 10) // input clock period; ns
    (
    input  logic        i_clk,      // input clock
    input  logic        i_rst,      // sync active-high reset
    //        
    input  logic        i_echo,     // sensor echo input
    output logic        o_trigger,  // sensor trigger output
    //
    output logic [3:0]  o_dbg_led,  // debug LEDs
    //
    output logic [21:0] o_echo_time // detected echo period; 0 if nothing present
    );

// DEBUG LEDS
    always_comb begin
        o_dbg_led[0] = (o_echo_time > 0)             && (o_echo_time < 22'd950_000);
        o_dbg_led[1] = (o_echo_time > 22'd950_000)   && (o_echo_time < 22'd1_900_000);
        o_dbg_led[2] = (o_echo_time > 22'd1_900_000) && (o_echo_time < 22'd2_850_000);
        o_dbg_led[3] = (timer == MAX_COUNTS-1);
    end

// CONSTANTS

    // Timeout Duration
    // -> If no obstacle: echo will be high for 38 ms  
    localparam MAX_TIME    = 38000*1000;           // max time in ns 
    localparam MAX_COUNTS  = MAX_TIME / T_CLK -1;  // max time in clock periods

    // Trigger Duration
    localparam TRIG_TIME   = 10*1000;              // trigger duration in ns
    localparam TRIG_COUNTS = TRIG_TIME / T_CLK -1; // trigger duration in clock periods

    // Ultrasonic Sensor Burst Duration
    localparam T_BURST      = 8*25000;          // 8 periods of 40kHz ns; ultrasonic burst
    localparam BURST_COUNTS = T_BURST/T_CLK -1; // burst duration in clock periods


// INTERNAL LOGIC DECLARATIONS
    
    // Output Next State Logic
    logic        nxt_trigger;
    logic [21:0] nxt_echo_time;

    // FSM
    logic [2:0] STATE, NEXT_STATE;
    localparam  STATE_TRIG       = 0, // Set the trigger pin
                STATE_TRIG_DELAY = 1, // Wait for TRIG_COUNTS periods
                STATE_WAIT_ECHO  = 2, // Wait for sensor to assert echo
                STATE_ECHO       = 3; // Sample echo pin and set nxt_echo_time

    // Timer
    logic [$clog2(MAX_COUNTS)-1:0] timer, nxt_timer;

    // Echo
    logic echo_q0;      // synchronizer first FF
    logic echo_q1;      // synchronizer second FF; most recent safe to use
    logic echo_q2;      // one cycle delay on echo_q1
    logic echo_negedge; // asserted on echo negative edge
    logic echo_posedge; // asserted on echo rising edge


// SYNCHRONIZER AND EDGE DETECTOR FOR ECHO SIGNAL
    always_ff@(posedge i_clk) begin
        if(i_rst) {echo_q0, echo_q1, echo_q2} <= 3'b0;
        else      {echo_q0, echo_q1, echo_q2} <= {i_echo, echo_q0, echo_q1};
    end
    assign echo_negedge = echo_q2 & !echo_q1;
    assign echo_posedge = !echo_q2 & echo_q1;


// FSM SYNCHRONOUS LOGIC
    always_ff@(posedge i_clk) begin
        if(i_rst) begin
            o_trigger   <= 0;
            o_echo_time <= 0;
            timer       <= 0;
            STATE       <= STATE_TRIG;
        end 
        else begin
            o_trigger   <= nxt_trigger;
            o_echo_time <= nxt_echo_time;
            timer       <= nxt_timer;
            STATE       <= NEXT_STATE;
        end
    end


// FSM NEXT STATE COMBINATORIAL LOGIC
    always_comb begin
        // default values
        nxt_trigger   = o_trigger;
        nxt_echo_time = o_echo_time;
        nxt_timer     = timer;
        NEXT_STATE    = STATE;

        // next state logic
        case(STATE)

            // Set the sensor trigger pin
            STATE_TRIG: begin
                nxt_trigger = 1;
                nxt_timer   = 0;
                NEXT_STATE   = STATE_TRIG_DELAY;
            end

            // Wait for TRIG_COUNTS periods, then reset trigger
            STATE_TRIG_DELAY: begin
                if(timer < TRIG_COUNTS) begin
                    nxt_timer = timer+1;
                end
                else begin
                    nxt_timer   = 0;
                    nxt_trigger = 0; 
                    NEXT_STATE  = STATE_WAIT_ECHO;
                end
            end

            // Wait for echo to be asserted
            STATE_WAIT_ECHO: 
                if(echo_posedge) begin
                    NEXT_STATE = STATE_ECHO;
                    nxt_timer  = timer + 1;
                end
            end

            // Capture echo time; go back to STATE_TRIG at max counts
            STATE_ECHO: begin

                // count echo time
                if(timer < MAX_COUNTS) begin
                    nxt_timer = timer+1;

                    if(echo_negedge) begin // echo dropped, send new pulse
                        nxt_echo_time = timer;
                        nxt_timer     = 0;
                        NEXT_STATE    = STATE_TRIG;
                    end
                end

                // echo timed out!
                else begin
                    nxt_echo_time = MAX_COUNTS-1;
                    nxt_timer     = 0;
                    NEXT_STATE    = STATE_TRIG;
                end
            end
        endcase
    end

endmodule
