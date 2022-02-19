`timescale 1ns / 1ps
//
//
module hcsr04_capture_tb();

// Test vars
    logic        clk;
    logic        rst;
    logic        echo;
    logic        trigger;
    logic [21:0] echo_time;

    localparam T_CLK       = 10;
    //
    localparam TRIG_TIME   = 10*1000; // trigger duration in ns
    localparam T_BURST     = 8*25000; // period of 40kHz burst in ns   

// DUT instantiation
    hcsr04_capture 
    #(.T_CLK(T_CLK))
    DUT
    (
    .i_clk       (clk),
    .i_rst       (rst),
    //  
    .i_echo      (echo),
    .o_trigger   (trigger),
    //  
    .o_dbg_led   (),
    .o_echo_time (echo_time)
    );

// Clock generation
    initial clk = 0;
    always#(T_CLK/2) clk = ~clk;

// Test task to simulate sensor behavior
    task sensorDetect;
        input int echoTime; // echo pulse width in us
        begin
            // reset DUT
            @(posedge clk) rst <= 1;
            @(posedge clk) rst <= 0;
            @(posedge clk);

            // look for trigger
            for(int i=0; i<3; i++) begin
                @(posedge clk) begin
                    if(trigger) break;
                    else if(i==2) begin
                        $display("No trigger detected!");
                        $display("Test failed!");
                        $stop;
                    end
                end
            end

            // wait for trigger to complete
            // -> assert should fail if trigger < 10ms
            #(TRIG_TIME); 

            // simulate the sensor sending ultrasonic burst
            #(T_BURST)

            // set echo for specified duration
            @(posedge clk) echo <= 1;
            #(echoTime);
            @(posedge clk) echo <= 0;

            //
            repeat(2) @(posedge clk);
        end
    endtask

//  
    initial begin
        $display("Test begin!");
        echo = 0;
        rst = 1;
        #100;
        sensorDetect(90_000);
        sensorDetect(150_000);
        sensorDetect(250_000);
        sensorDetect(350_000);
    end
    
// Check that trigger is always 10us
    property trig_time_p;
        @(posedge clk) trigger |-> ##(10000/10) ~trigger;
    endproperty
    trig_time_chk: assert property(trig_time_p);

// Check that trigger is asserted after echo is reset
    property trig_rst_p;
        @(posedge clk) $fell(echo)&&(!rst) |=> ##2 trigger;
    endproperty
    trig_rst_chk: assert property(trig_rst_p);

// Check that if max time is reached, a new trigger pulse is sent
    property trig_set_p;
        @(posedge clk) $fell(trigger) |=> ##[0:(38000000+T_BURST)] trigger;
    endproperty
    trig_set_chk: assert property(trig_set_p);

// Check that after trigger is asserted, the local timer starts from 0
    property localTimer_rst_p;
        @(posedge clk) $fell(trigger) |-> (DUT.timer == 0);
    endproperty
    localTimer_rst_chk: assert property(localTimer_rst_p);

endmodule
