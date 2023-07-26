#include "Timer.h"
#include "SenseNet.h"

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
        interface Random;

        // Common timer instance
        interface Timer<TMilli> as Timer0;
        interface Timer<TMilli> as Timer1;
    }

} implementation {

    // Time delay in milli seconds
    uint16_t time_delays[8] = {40, 60, 45, 50, 55, 30, 30, 75};

    message_t packet;

    list_msg* list_of_messages = NULL;
    uint16_t msg_count = 0;

    // Variable for storing sender gateway address
    uint16_t sender_gateway;


    bool data_msg_sent = FALSE;
    bool ack_sent = FALSE;

    bool locked;



    // TODO: comments
    void initialize_sensor_message_list() {
        
        list_msg temp[SENSOR_LIST_SIZE] = NULL;
        
        uint16_t i = 0;

        for (i = 0; i < SENSOR_LIST_SIZE; i++) {
            temp[i].sense_msg = NULL;
            temp[i].ack_received = FALSE;
        }

        list_of_messages = temp;

        msg_count = 0;
    }

    // TODO: comments
    void initialize_server_message_list() {

        list_msg temp[SERVER_LIST_SIZE] = NULL;
        
        uint16_t i = 0;

        for (i = 0; i < SERVER_LIST_SIZE; i++) {
            temp[i].sense_msg = NULL;
            temp[i].ack_received = FALSE;
        }

        list_of_messages = temp;

        msg_count = 0;
    }

    /*
    * TODO: comments
    * 
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
    bool generate_send (message_t* packet, uint8_t type){

        if (call Timer0.isRunning()) {
            return FALSE;
        } else {
            if (type == 0 && !data_msg_sent) {
                data_msg_sent = TRUE;
                call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
                queued_packet = *packet;
            } else if (type == 1 && !ack_sent) {
                ack_sent = TRUE;
                call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
                queued_packet = *packet;                
            }
        }
                            
        return TRUE;

    }

    /* 
    * TODO: comments
    * 
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
    bool actual_send (uint16_t* address, message_t* packet) {
        uint16_t address1, address2;

        if (locked) {

            return FALSE;
        
        } else {

            sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));

            if (TOS_NODE_ID > 1 && TOS_NODE_ID <= 4) {

                address1 = 6;
                address2 = 7;
                payload_p->destination = address1;
                
                if (call AMSend.send(address1, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    //dbg("radio_send", "[RADIO_SEND] Sending message of type node %u from %u to %u passing by gateways 1 and 2.\n", rrm->type, rrm->sender, rrm->destination, address); 
                    locked = TRUE;
                } else {
                    // Generate error message
                }

                payload_p->destination = address2;
                
                if (call AMSend.send(address2, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    //dbg("radio_send", "[RADIO_SEND] Sending message of type node %u from %u to %u passing by gateways 1 and 2.\n", rrm->type, rrm->sender, rrm->destination, address); 
                    locked = TRUE;
                } else {
                    // Generate error message
                }

            } else if (TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {
                
                payload_p->destination = SERVER_NODE;
                
                if (payload_p->type == 0) {

                    address1 = SERVER_NODE;
                    
                    if (call AMSend.send(call AMSend.send(address1, packet, sizeof(radio_route_msg_t)) == SUCCESS)) {
                        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                        //dbg("radio_send", "[RADIO_SEND] Sending message of type node %u from %u to %u passing by gateways %u.\n", rrm->type, rrm->sender, rrm->destination, address); 
                        locked = TRUE;
                    } else {
                        // Generate error message                   
                    }

                } else {

                    address1 = payload_p->destination;
                    
                    if (call AMSend.send(call AMSend.send(address1, packet, sizeof(radio_route_msg_t)) == SUCCESS)) {
                        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                        //dbg("radio_send", "[RADIO_SEND] Sending message of type node %u from %u to %u passing by gateways %u.\n", rrm->type, rrm->sender, rrm->destination, address); 
                        locked = TRUE;
                    } else {
                        // Generate error message                   
                    }                    
                }

            } else if (TOS_NODE_ID == 1) {

                address1 = 6;
                payload_p->destination = address1;
                
                if (call AMSend.send(address1, packet, sizeof(sense_msg_t)) == SUCCESS && call AMSend.send(address2, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                    //dbg("radio_send", "[RADIO_SEND] Sending message of type node %u from %u to %u passing by gateways 1 and 2.\n", rrm->type, rrm->sender, rrm->destination, address); 
                    locked = TRUE;
                } else {
                    // Generate error message
                }    

            } else if (TOS_NODE_ID == 5) {

                address1 = 7;
                payload_p->destination = address2;
                
                if (call AMSend.send(address1, packet, sizeof(sense_msg_t)) == SUCCESS && call AMSend.send(address2, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                    //dbg("radio_send", "[RADIO_SEND] Sending message of type node %u from %u to %u passing by gateways 1 and 2.\n", rrm->type, rrm->sender, rrm->destination, address); 
                    locked = TRUE;
                } else {
                    // Generate error message
                }

            } else {

                address1 = payload_p->sender;
                
                if (call AMSend.send(address1, packet, sizeof(sense_msg_t)) == SUCCESS && call AMSend.send(address2, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                    //dbg("radio_send", "[RADIO_SEND] Sending message of type node %u from %u to %u passing by gateways 1 and 2.\n", rrm->type, rrm->sender, rrm->destination, address); 
                    locked = TRUE;
                } else {
                    // Generate error message
                }  

            }

        }

        return TRUE;

    }




    //***************** Boot interface ********************//
    event void Boot.booted() {

        dbg("boot", "[BOOT] Application booted for node %u.\n", TOS_NODE_ID);

        if (TOS_NODE_ID >= 1 && TOS_NODE_ID <= SENSOR_NODES) {
            initialize_sensor_message_list();
        } else if (TOS_NODE_ID == SERVER_NODE) {
            initialize_server_message_list();
        }
        
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
        // An array is defined to contain both addresses of the gateways, in order to be able to send multiple packets
        uint16_t addr[DIM_GATEWAYS]; 
        // a pointer to packet (message_t variable) is declared and assigned to rrm  
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&packet, sizeof(sense_msg_t));
        
        dbg("timer1", "[TIMER1] Timer fired out.\n");
        payload_p->type = 0;
        payload_p->msg_id = msg_count;
        msg_count++;
        payload_p->data = call Random.rand16(); // Generate random integer
        payload_p->sender = TOS_NODE_ID;
        generate_send(addr, &packet, 0);
    }


    //***************** Receive interface *****************//
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    /*
    * If Network Server Parse the receive packet, implement functions and call generate_send with the ACK message packet and the ADDRESS of the destination sensor.
      If Gateway parse ACK message and forward to the destination sensor.
      If Sensor Node don't do anything
    */  
        uint16_t gateway_addr;
        if (len != sizeof(radio_route_msg_t)) {
            return bufPtr;
        } else {

            // Variable that contains the payload of the received message
            sense_msg_t* mess = (sense_msg_t*) payload;

            dbg("radio_rec", "[RADIO_REC] Received a message of type %u.\n", mess->type);

            if (new_mess == NULL) {
                dbgerror("radio_rec", "[RADIO_REC] ERROR ALLOCATING MEMORY FOR NEW MESSAGE.\n");
                return bufPtr;
            }

        if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5){
            if(mess->type == 0){

            }else if(mess->type == 1){

            }
        }else if(TOS_NODE_ID == 6 || TOS_NODE_ID == 7){
            if(mess->type == 0){
            }else if(mess->type == 1){

            }           
        }else if(TOS_NODE_ID == 8){
            if(mess->type == 0){
                // Functions implementation

                // DUP ACK suppression and ACK sending
                
            }else if(mess->type == 1)
                //generate error message
        }
    }
    }
    }
}
