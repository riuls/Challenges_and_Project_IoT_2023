#include "Timer.h"
#include "SenseNet.h"
#define LIST_SIZE 128

/**
 * Implementation of the SenseNet application with TOSSIM debug. 
 * SenseNet includes 8 nodes connected through a Radio interface, 
 * the first five are sensor and periodically transmit random data, 
 * while the other two are gateways which receive and forward the data to the last node which acts as a network server: 
 * it transmits the data to a Node-Red and an MQTT server and it sends an ACK to the correspondent gateway. 
 * The Network Server node also eliminates dup-ACKS. 
 * The sensor nodes retransmit the data if an ACK is not received in a 1ms window from the sending.
 *
 * @author Mario Cela
 * @author Riaz Luis Ahmed
 * @date   July 25 2023
 */

module SenseNetC @safe() {

    uses {
        interface Boot;

        interface SplitControl as AMControl;
        interface Packet;
        interface AMSend;
        interface Receive;

        // Common timer instance
        interface Timer<TMilli> as Timer0;
        interface Timer<TMilli> as Timer1;
    }

} implementation {

    // Time delay in milli seconds
    uint16_t time_delays[8] = {40, 60, 45, 50, 55, 30, 30, 75};

    message_t packet;

    // Variables to store the message to send
    message_t queued_packet;
    uint16_t queue_addr;

    list_msg list_of_messages[LIST_SIZE];

    bool data_msg_sent = FALSE;
    bool ack_sent = FALSE;

    bool locked;



    // TODO: comments
    void initialize_message_list() {
        uint16_t i = 0;

        for (i = 0; i < LIST_SIZE; i++) {
            list_of_messages[i].sense_msg = NULL;
            list_of_messages[i].ack_received = FALSE;
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
            if (type == 0 && !data_msg_sent) {
                data_msg_sent = TRUE;
                call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
                queued_packet = *packet;
                queue_addr = address;
            } else if (type == 1 && !ack_sent) {
                data_msg_sent = TRUE;
                call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
                queued_packet = *packet;
                queue_addr = address;
            }

        return TRUE;

        }
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

        initialize_message_list();
        
        // When the device is booted, the radio is started
        call AMControl.start();

    }


    //*************** AMControl interface *****************//
    event void AMControl.startDone(error_t err) {
        
        // If the radio is correctly turned on, Timer1 starts
        if(err == SUCCESS) {

            dbg("radio", "[RADIO] Radio successfully started for node %u.\n", TOS_NODE_ID);

            switch(TOS_NODE_ID)
                {
                case 1: call Timer1.startPeriodic(1000);;
                             break;
                case 2: call Timer1.startPeriodic(2000);;
                             break;
                case 3: call Timer1.startPeriodic(3000);;
                              break;
                case 4: call Timer1.startPeriodic(4000);;
                             break;
                case 5: call Timer1.startPeriodic(5000);;
                              break;

                default: default_statement;
                }

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
    * Implement here the logic to trigger the Sensor Node to send the data packet to the gateways, generate_send function 
    is called with prototype 
    generate_send(GATEWAY_ADDRESS, &packet, 1);
    */
    event void Timer1.fired() {
    
        // a pointer to packet (message_t variable) is declared and assigned to rrm  
        radio_route_msg_t* payload = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
        
        dbg("timer1", "[TIMER1] Timer fired out.\n");
        
        
       
        // generate_send(AM_BROADCAST_ADDR, &globalpacket, 1);
    
    }


    //***************** Receive interface *****************//
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    /*
    * If Network Server Parse the receive packet, implement functions and call generate_send with the ACK message packet and the ADDRESS of the destination sensor.
      If Gateway parse ACK message and forward to the destination sensor.
      If Sensor Node don't do anything
    */

    }

}