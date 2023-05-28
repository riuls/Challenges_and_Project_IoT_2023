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

    // Variable to not send more than once the data message
    bool sent = FALSE;

    // Time delay in milli seconds
    uint16_t time_delays[7] = {61,173,267,371,479,583,689};

    bool route_req_sent = FALSE;
    bool route_rep_sent = FALSE;

    bool locked;

    // Variable to store temporary led index
    uint16_t cind = 0;

    /* 
    * The routing table is declared as a matrix of integer. 
    * For more on how it is formed, see the initialize_routing_table() function
    */
    uint16_t routing_table[6][3];

    /* 
    * Each node will have its table initialized when the device is started.
    * In particular, all the nodes that we know do belong to the network are inserted into the table,
    * except for self references, checked with the TOS_NODE_ID.
    * Finally, both the next hop column and the cost column are set to UINT16_MAX, that means that
    * the values are not initialized.
    */
    void initialize_routing_table() {

        uint16_t i = 0;

        for (i = 0; i < 7; i++) {
            if (i + 1 != TOS_NODE_ID) {
                routing_table[i][0] = i + 1;
                routing_table[i][1] = UINT16_MAX;
                routing_table[i][2] = UINT16_MAX;
            }
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

    //TODO comments
    bool actual_send (uint16_t address, message_t* packet){
        
        if (locked) {
            return FALSE;
        }
        else {
            if (call AMSend.send(AM_BROADCAST_ADDR, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
                radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(packet, sizeof(radio_route_msg_t));
                dbg("radio_send", "Sending message of type %u from %u to %u.\n", rrm->type, rrm->sender, rrm->destination); 
                locked = TRUE;
            }
        }
        return TRUE;

    }

    /* 
    * Since the routing table contains all the nodes of the network except for the node itself,
    * this function is used to get the row in which they are next hop and cost to reach the desired node
    * given in input (node_id)
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

        dbg("boot", "Application booted.\n");
        
        // When the device is booted, the radio is started
        call AMControl.start();

    }


    //*************** AMControl interface *****************//
    event void AMControl.startDone(error_t err) {
        
        // If the radio is correctly turned on, the routing table of the node is initialized
        if(err == SUCCESS) {

            dbg("radio_start", "Radio successfully started for node %u.\n", TOS_NODE_ID);
            
            initialize_routing_table();

            dbg("radio_start", "Routing table successfully started for node %u.\n", TOS_NODE_ID);

            // TODO after the radio is ON we should start counting in order to send the first req from 1 to 7

            // We send first req only from node 1
            if(TOS_NODE_ID == 1)
                call Timer1.startOneShot(5000);
        } 
        // If the radio didn't turn on successfully, the start is performed again
        else {
            
            // TODO print something for the debugging
            dbg("radio_start", "Radio starting failed for node %u...restarting\n", TOS_NODE_ID);
            call AMControl.start();
        }

    }

    event void AMControl.stopDone(error_t err) {
        dbg("boot", "Radio stopped!\n");
    }

    event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    /* This event is triggered when a message is sent 
    *  Check if the packet is sent 
    */ 

        if (&globalpacket == bufPtr && error == SUCCESS) {
            dbg("radio_send", "Packet sent...");
            dbg_clear("radio_send", " at time %s \n", sim_time_string());
            locked = FALSE;
        } else {
            dbgerror("radio_send", "Send done error!\n");
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
      
        uint16_t address = AM_BROADCAST_ADDR;
        uint8_t type = 1;
        radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(&globalpacket, sizeof(radio_route_msg_t));
        
        if (rrm == NULL){
            return;
        }
        
        rrm->destination = address;
        rrm->sender = TOS_NODE_ID;
        rrm->type = type;
        rrm->node_requested = 7;

        if(generate_send(address, &globalpacket, type) == TRUE)
            dbg("data", "SUCCESS: message of type %u sent from %u to %u requesting the node %u\n", rrm->type, rrm->sender, rrm->destination, rrm->node_requested);
        else
            dbg("data", "FAILURE: message of type %u NOT sent from %u to %u requesting the node %u\n", rrm->type, rrm->sender, rrm->destination, rrm->node_requested);
    
    }


    //***************** Receive interface *****************//
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    /*
    * Parse the receive packet.
    * Implement all the functionalities.
    * Perform the packet send using the generate_send function if needed.
    * Implement the LED logic and print LED status on Debug.
    */

        uint16_t i = 0;
        uint16_t tmp;
        uint32_t pcode = 10372022;
        uint16_t c;

        if (len != sizeof(radio_route_msg_t)) {
            return bufPtr;
        } else {
            radio_route_msg_t* mess = (radio_route_msg_t*) payload;
            radio_route_msg_t* new_mess = (radio_route_msg_t*)call Packet.getPayload(&globalpacket, sizeof(radio_route_msg_t));
            uint16_t row = 0;

            // It is received a data message
            if (mess->type == 0) {

                // If the current node is the destination of the message, the transmission finishes
                if (mess->destination == TOS_NODE_ID) {
                    dbg("data", "Received THAT packet\n");

                } 
                // If it is not, the message should be forwarded to the next hop specified in the routing table
                else {

                    if (new_mess == NULL) {
                        return NULL;
                    }

                    row = get_row_index_by_node_id(7);

                    new_mess->type = 0;
                    new_mess->sender = TOS_NODE_ID;
                    new_mess->destination = mess->destination;
                    new_mess->value = mess->value;

                    new_mess->destination = UINT16_MAX;
                    new_mess->value = UINT16_MAX;

                    // It is generated a send to the next hop specified in the routing table
                    generate_send(routing_table[row][1], &globalpacket, 0);

                }

            }

            // It is received a ROUTE_REQ message
            else if (mess->type == 1) {
                row = get_row_index_by_node_id(mess->node_requested);

                // If the current node is the requested node, it is generated a ROUTE_REPLY message, with the cost set to 1. 
                if (mess->node_requested == TOS_NODE_ID) {
                    
                    if (new_mess == NULL) {
                        return NULL;
                    }

                    new_mess->type = 2;
                    new_mess->sender = TOS_NODE_ID;
                    new_mess->node_requested = TOS_NODE_ID;
                    new_mess->cost = 1;

                    new_mess->destination = UINT16_MAX;
                    new_mess->value = UINT16_MAX;

                    // The message is sent in broadcast
                    generate_send(AM_BROADCAST_ADDR, &globalpacket, 2);

                } 
                // The following condition means that the requested node is not initialized in routing table of the node
                // So, it is needed to forward in broadcast the ROUTE_REQ
                else if (routing_table[row][2] == UINT16_MAX) {

                    if (new_mess == NULL) {
                        return NULL;
                    }

                    new_mess->type = 1;
                    new_mess->node_requested = mess->node_requested;

                    new_mess->sender = UINT16_MAX;
                    new_mess->destination = UINT16_MAX;
                    new_mess->value = UINT16_MAX;
                    new_mess->cost = UINT16_MAX;

                    // The message is sent in broadcast
                    generate_send(AM_BROADCAST_ADDR, &globalpacket, 1);

                } 
                // The requested node is in the routing table of the current node, so it generates a ROUTE_REPLY message
                else{
                    
                    if (new_mess == NULL) {
                        return NULL;
                    }

                    new_mess->type = 2;
                    new_mess->sender = TOS_NODE_ID;
                    new_mess->node_requested = mess->node_requested;
                    // The cost to reach the requested node is set to the cost set in the routing table +1
                    new_mess->cost = routing_table[row][2] + 1;

                    new_mess->destination = UINT16_MAX;
                    new_mess->value = UINT16_MAX;

                    // The message is sent in broadcast
                    generate_send(AM_BROADCAST_ADDR, &globalpacket, 2);


                }

            }

            // It is received a ROUTE_REPLY message
            else if (mess->type == 2) {
                row = get_row_index_by_node_id(mess->node_requested);

                // We need to modify the routing table if we are not the requested node and 
                // if in the routing table we have a cost to reach node that is higher than the one
                // we are receiving now from the reply.
                // Notice that this check also includes the case in which the node is not initialized in the routing table
                // since we used the UINT16_MAX as value for initialized variables.
                if (mess->node_requested != TOS_NODE_ID && routing_table[row][2] > mess->cost) {
                    routing_table[row][1] = mess->sender;
                    routing_table[row][2] = mess->cost;
                    
                    if (new_mess == NULL) {
                        return NULL;
                    }

                    new_mess->type = 2;
                    new_mess->sender = TOS_NODE_ID;
                    new_mess->node_requested = mess->node_requested;
                    new_mess->cost = routing_table[row][2] + 1;

                    new_mess->destination = UINT16_MAX;
                    new_mess->value = UINT16_MAX;

                    // After the update, we broadcast the new REPLY
                    generate_send(AM_BROADCAST_ADDR, &globalpacket, 2);

                }

                // If the current node is the node 1 and the data message has not been sent yet,
                // the transmission of the packet can be performed
                if (TOS_NODE_ID == 1 && sent == FALSE) {
                        
                    row = get_row_index_by_node_id(7);
                    
                    if (new_mess == NULL) {
                        return NULL;
                    }

                    // In the message that will be sent, we put again the values of the fields of the data message specified
                    // at the beginning of the execution
                    new_mess->type = 0;
                    new_mess->sender = 1;
                    new_mess->destination = 7;
                    new_mess->value = 5;

                    new_mess->node_requested = UINT16_MAX;
                    new_mess->cost = UINT16_MAX;

                    // The message is sent to the next hop specified in the routing table to reach the desired node
                    generate_send(routing_table[row][1], &globalpacket, 0);

                    // The sent flag is sent to true in order to not send again the same packet 
                    // when the node will receive other ROUTE_REPLY 
                    sent = TRUE;

                }

            }
     
            return bufPtr;
        }
        
        // Led status update

        if(cind == 0)
            cind = 7;
        
        tmp = pcode;

        // divide tmp and get cypher
        while(i < cind){
            tmp /= 10;
            i++;
        }

        c = tmp % 10;

        // compute module 3 of cypher
        c = c % 3;

        // toggle corresponding LED
        if(c == 1)
            call Leds.led0Toggle();
        else if(c == 2)
            call Leds.led1Toggle();
        else
            call Leds.led2Toggle();

        // update cind
        cind--;
    }

}