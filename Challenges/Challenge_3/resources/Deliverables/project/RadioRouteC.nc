#include "Timer.h"
#include "RadioRoute.h"

module RadioRouteC @safe() {

    uses {
        interface Boot;

        interface SplitControl as AMControl;
        interface Packet;
        interface AMSend;
        interface Receive;

        interface Timer<TMilli> as Timer0;
        interface Timer<TMilli> as Timer1;

        interface Leds;

    }

} implementation {

    message_t globalpacket;

    // Variables to store the message to send
    message_t queued_packet;
    uint16_t queue_addr;

    // Time delay in milli seconds
    uint16_t time_delays[7] = {61,173,267,371,479,583,689};

    bool route_req_sent = FALSE;
    bool route_rep_sent = FALSE;

    bool locked;

    /* 
    * The routing table is declared as a matrix of integer. 
    * For more on how it is formed, see the initialize_routing_table() function
    */
    uint16_t routing_table[6][3];

    // Variable to not send more than once the data message
    bool sent = FALSE;

    // Variables to store temporary led index and person code
    uint16_t i_start = 7;
    uint32_t pcode = 10372022;



    /* 
    * Each node will have its table initialized when the device is started.
    * In particular, all the nodes that we know do belong to the network are inserted into the table,
    * except for self references, checked with the TOS_NODE_ID.
    * Finally, both the next hop column and the cost column are set to UINT16_MAX, that means that
    * the values are not initialized.
    * @Input: no input needed
    * @Output: nothing is returned by tge function
    */
    void initialize_routing_table() {

        uint16_t i = 0;

        for (i = 0; i < TOS_NODE_ID - 1; i++) {
            routing_table[i][0] = i + 1;
            routing_table[i][1] = UINT16_MAX;
            routing_table[i][2] = UINT16_MAX;
        }
        for (i = TOS_NODE_ID - 1; i < 6; i++) {
            routing_table[i][0] = i + 2;
            routing_table[i][1] = UINT16_MAX;
            routing_table[i][2] = UINT16_MAX;
        }

    }

    /*
    * Function to be used when performing the send after the receive message event.
    * It stores the packet and address into a global variable and start the timer execution to schedule the send.
    * It allows the sending of only one message for each REQ and REP type
    * @Input:
    *       address: packet destination address
    *       packet: full packet to be sent (Not only Payload)
    *       type: payload message type
    *
    * MANDATORY: DO NOT MODIFY THIS FUNCTION
    */
    bool generate_send (uint16_t address, message_t* packet, uint8_t type){

        if (call Timer0.isRunning()) {
            return FALSE;
        } else {
            if (type == 1 && !route_req_sent ) {
                route_req_sent = TRUE;
                call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
                queued_packet = *packet;
                queue_addr = address;
            } else if (type == 2 && !route_rep_sent) {
                route_rep_sent = TRUE;
                call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
                queued_packet = *packet;
                queue_addr = address;
            } else if (type == 0) {
                call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
                queued_packet = *packet;
                queue_addr = address;   
            }
        }

        return TRUE;
    }

    /* 
    * actual_send checks if another message is being sent and in case it is not then it calls
    * AMSend.send to send the new message received as pointer packet. Variable locked is used
    * for the check: if it is TRUE it means that a message is being sent and FALSE value is 
    * returned, if it is FALSE then no message is being sent and a TRUE value is returned
    * @Input: 
    *       address: packet destination address
    *       packet: packet to be sent (not only payload)
    * @Output: 
    *       boolean variable: it is TRUE when message could be sent, FALSE otherwise
    */
    bool actual_send (uint16_t address, message_t* packet){
        
        if (locked) {

            return FALSE;
        
        }
        else {

            if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
                radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(packet, sizeof(radio_route_msg_t));
                dbg("radio_send", "[RADIO_SEND] Sending message of type %u from %u to %u passing by %u.\n", rrm->type, rrm->sender, rrm->destination, address); 
                locked = TRUE;
            }

        }

        return TRUE;

    }

    /* 
    * Since the routing table contains all the nodes of the network except for the node itself,
    * this function is used to get the row in which a desired node is put.
    * @Input:
    *       node_id: is the id of the node for which we want to obtain the corresponding row in the routing table
    * @Output:
    *       it is returned the row where it is stored information about the desired node specified in input
    */
    uint16_t get_row_index_by_node_id(uint16_t node_id) {
        
        uint16_t i = 0;

        for (i = 0; i < 6; i++) {
            if (routing_table[i][0] == node_id) {
                return i;
            }
        }

        return -1;

    }




    //***************** Boot interface ********************//
    event void Boot.booted() {

        dbg("boot", "[BOOT] Application booted for node %u.\n", TOS_NODE_ID);

        initialize_routing_table();
        dbg("init", "[INIT] Routing table initialized for node %u.\n", TOS_NODE_ID);
        
        // When the device is booted, the radio is started
        call AMControl.start();

    }


    //*************** AMControl interface *****************//
    event void AMControl.startDone(error_t err) {
        
        // If the radio is correctly turned on, Timer1 starts
        if(err == SUCCESS) {

            dbg("radio", "[RADIO] Radio successfully started for node %u.\n", TOS_NODE_ID);

            // We send first req only from node 1
            if(TOS_NODE_ID == 1)
                call Timer1.startOneShot(5000);

        } 
        // If the radio didn't turn on successfully, the start is performed again
        else {
            
            // TODO print something for the debugging
            dbg("radio", "[RADIO] Radio starting failed for node %u...restarting.\n", TOS_NODE_ID);
            call AMControl.start();
        }

    }

    event void AMControl.stopDone(error_t err) {

        dbg("radio", "[RADIO] Radio stopped for node %u.\n", TOS_NODE_ID);

    }
    

    //***************** AMSend interface ******************//
    /* This event is triggered when a message is sent 
    *  Check if the packet is sent 
    */
    event void AMSend.sendDone(message_t* bufPtr, error_t error) {

        if (error == SUCCESS) {

            dbg("radio_send", "[RADIO_SEND] Packet sent from %u at time %s.\n", TOS_NODE_ID, sim_time_string());
            locked = FALSE;

        } else {

            dbgerror("radio_send", "[RADIO_SEND] Send done error for node %u!\n", TOS_NODE_ID);

        }
    }


    //****************** Timer interface ******************//
    event void Timer0.fired() {
    /*
    * Timer triggered to perform the send.
    * MANDATORY: DO NOT MODIFY THIS FUNCTION
    */

        actual_send (queue_addr, &queued_packet);
    }

    /*
    * Implement here the logic to trigger the Node 1 to send the first REQ packet
    */
    event void Timer1.fired() {
    
        // a pointer to globalpacket (message_t variable) is declared and assigned to rrm  
        radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(&globalpacket, sizeof(radio_route_msg_t));
        
        dbg("timer1", "[TIMER1] Timer fired out.\n");
        
        if (rrm == NULL){
            return;
        }
        
        // When Timer1 fires out, the node sends a ROUTE_REQ message, requesting information about node 7
        rrm->type = 1;
        rrm->node_requested = 7;

        rrm->sender = TOS_NODE_ID;
        rrm->destination = AM_BROADCAST_ADDR;
        rrm->value = UINT16_MAX;
        rrm->cost = UINT16_MAX;
    
        // The ROUTE_REQ is sent in broadcast to the other nodes connected to the sender
        generate_send(AM_BROADCAST_ADDR, &globalpacket, 1);
    
    }


    //***************** Receive interface *****************//
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    /*
    * Parse the receive packet.
    * Implement all the functionalities.
    * Perform the packet send using the generate_send function if needed.
    * Implement the LED logic and print LED status on Debug.
    */

        uint16_t i;
        uint32_t tmp;
        uint16_t c;
        
        // Led status update
        // For every i value from 7 to 0, divide person code by 10 for i times, get the remainder and compute the module 3
        // of the value; afterwise toggle the lED corresponding to the computed module
    
        // pcode is loaded in tmp
        tmp = pcode;
        // i_start is loaded in i
        i = i_start;
        // tmp is divided by 10 for i times
        while(i > 0){
            tmp /= 10;
            i--;
        }
        // digit c is computed from tmp
        c = tmp % 10;
        // module 3 is computed from digit and reassigned to same digit
        if(c >= 3)
            c = c % 3;
            
        // toggle LED1 if digit == 1, LED2 if digit == 2 and LED0 if digit == 0 or digit ==3
        if(c == 1){
            call Leds.led1Toggle();
            dbg("leds", "Leds : LED 1 toggled at node %u \n",TOS_NODE_ID);
        }
        else if(c == 2){
            call Leds.led2Toggle();
            dbg("leds", "Leds : LED 2 toggled at node %u \n",TOS_NODE_ID);
        }
        else{
            call Leds.led0Toggle();
            dbg("leds", "Leds : LED 0 toggled at node %u \n",TOS_NODE_ID);
        }

        
        // update i_start 
        if(i_start == 0)
            i_start = 7;
        else
            i_start--;
        
        

        if (len != sizeof(radio_route_msg_t)) {
            return bufPtr;
        } else {

            // Variable that contains the payload of the received message
            radio_route_msg_t* mess = (radio_route_msg_t*) payload;
            // Variable that will contain the payload of the message that will be sent
            radio_route_msg_t* new_mess = (radio_route_msg_t*)call Packet.getPayload(&globalpacket, sizeof(radio_route_msg_t));
            // Variable used to get the row in which the desired node is located in the routing table
            uint16_t row = 0;

            dbg("radio_rec", "[RADIO_REC] Received a message of type %u.\n", mess->type);

            if (new_mess == NULL) {
                dbgerror("radio_rec", "[RADIO_REC] ERROR ALLOCATING MEMORY FOR NEW MESSAGE.\n");
                return bufPtr;
            }

            // A data message is received
            if (mess->type == 0) {

                // If the current node is node 7, that is the destination of the data message, we don't need to forward packets anymore
                if (TOS_NODE_ID == 7) {

                    // WE'RE DONE
                    dbg ("radio_rec", "[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u WITH VALUE %u. WE'RE DONE!\n", TOS_NODE_ID, mess->type, mess->value);

                } 
                // Otherwise, the message needs to be forwarded
                else {

                    // FORWARD TO THE NEXT HOP SPECIFIED IN THE ROUTING TABLE
                    row = get_row_index_by_node_id(mess->destination);

                    new_mess->type = 0;
                    new_mess->sender = TOS_NODE_ID;
                    new_mess->destination = mess->destination;
                    new_mess->value = mess->value;

                    new_mess->node_requested = UINT16_MAX;
                    new_mess->cost = UINT16_MAX;

                    // It is generated a send to the next hop specified in the routing table
                    generate_send(routing_table[row][1], &globalpacket, 0);

                }

            }
            
            // A ROUTE_REQ is received
            if (mess->type == 1) {

                row = get_row_index_by_node_id(mess->node_requested);

                // If the current node is not the requested node of the ROUTE_REQ and it has not initialized the row
                // corresponding to the requested node, we broadcast a new route request
                if (mess->node_requested != TOS_NODE_ID && routing_table[row][1] == UINT16_MAX) {

                    // BROADCAST A NEW ROUTE_REQ MESSAGE
                    new_mess->type = 1;
                    new_mess->node_requested = mess->node_requested;

                    new_mess->sender = TOS_NODE_ID;
                    new_mess->destination = UINT16_MAX;
                    new_mess->cost = UINT16_MAX;
                    new_mess->value = UINT16_MAX;

                    // The ROUTE_REQ is sent in broadcast to the other nodes connected to the sender
                    generate_send(AM_BROADCAST_ADDR, &globalpacket, 1);

                } 
                // If the current node is the requested node, we broadcast a route reply
                else if (mess->node_requested == TOS_NODE_ID) {

                    // BROADCAST A ROUTE_REPLY WITH COST SET TO 1
                    new_mess->type = 2;
                    new_mess->sender = TOS_NODE_ID;
                    new_mess->node_requested = TOS_NODE_ID;
                    new_mess->cost = 1;

                    new_mess->destination = UINT16_MAX;
                    new_mess->value = UINT16_MAX;

                    // The ROUTE_REPLY is sent in broadcast to the other nodes connected to the sender
                    generate_send(AM_BROADCAST_ADDR, &globalpacket, 2);

                } 
                // If we are not the requested node but the we have a path to reach the requested node,
                // we broacast a route reply
                else if (routing_table[row][1] != UINT16_MAX) {
                    
                    // BROADCAST A ROUTE REPLY WITH COST SET TO THE ONE IN THE ROUTING TABLE + 1
                    new_mess->type = 2;
                    new_mess->sender = TOS_NODE_ID;
                    new_mess->node_requested = mess->node_requested;
                    new_mess->cost = routing_table[row][2] + 1;

                    new_mess->destination = UINT16_MAX;
                    new_mess->value = UINT16_MAX;

                    // The ROUTE_REPLY is sent in broadcast to the other nodes connected to the sender
                    generate_send(AM_BROADCAST_ADDR, &globalpacket, 2);

                }

            }

            // A ROUTE_REPLY is received
            if (mess->type == 2) {

                row = get_row_index_by_node_id(mess->node_requested);

                // If we are the requested node, we do nothing
                if (mess->node_requested == TOS_NODE_ID) {

                    // DO NOTHING

                } 
                // If we are not the requested node, if we can update the current node's routing table, we do it.
                // Then we broadcast the new cost to the other connected nodes
                else if (routing_table[row][1] == UINT16_MAX || mess->cost < routing_table[row][2]) {

                    // UPDATE THE ROUTING TABLE
                    routing_table[row][1] = mess->sender;
                    routing_table[row][2] = mess->cost;
                    
                    // If the current node is node 1, we can start sending the data message destinated to node 7
                    if (TOS_NODE_ID == 1) {

                        // This check is performed in order to send the data message just once
                        if (sent == FALSE) {

                            sent = TRUE;
                        
                            // SEND A NEW DATA MESSAGE IF NODE 1 IS RECEIVING A ROUTE REPLY
                            new_mess->type = 0;
                            new_mess->sender = TOS_NODE_ID;
                            new_mess->destination = 7;
                            new_mess->value = 5;

                            new_mess->node_requested = UINT16_MAX;
                            new_mess->cost = UINT16_MAX;
                            
                            // It is generated a send to the next hop specified in the routing table
                            generate_send(routing_table[row][1], &globalpacket, 0);

                        }
                    
                    } 
                    // If the current node is not node 1, we broadcast the route reply
                    else {

                        // BROADCAST THE ROUTE REPLY BY INCREMENTING THE COST BY 1
                        new_mess->type = 2;
                        new_mess->sender = TOS_NODE_ID;
                        new_mess->node_requested = mess->node_requested;
                        new_mess->cost = routing_table[row][2] + 1;

                        new_mess->destination = UINT16_MAX;
                        new_mess->value = UINT16_MAX;

                        // The ROUTE_REPLY is sent in broadcast to the other nodes connected to the sender
                        generate_send(AM_BROADCAST_ADDR, &globalpacket, 2);

                    }

                }

            }
     
            return bufPtr;
        }
        
        
    }

}