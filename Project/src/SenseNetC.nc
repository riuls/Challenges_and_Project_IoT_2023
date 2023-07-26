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
        interface Timer<TMilli> as Timer2;
    }

} implementation {

    // Time delay in milli seconds
    uint16_t time_delays[8] = {40, 60, 45, 50, 55, 30, 30, 75};

    message_t packet;

    list_msg* list_of_messages = NULL;
    uint16_t msg_count = 0;

    // Variable for storing sender gateway address
    uint16_t sender_gateway;

    // Variable for storing radio interface occupation status
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
    * It allows to send only one packet at a time (one packet at a time is sent in the channel)
    * @Input:
    *       address: packet destination address
    *       packet: full packet to be sent (Not only Payload)
    *       type: payload message type
    *
    * MANDATORY: DO NOT MODIFY THIS FUNCTION
    */
    bool generate_send (message_t* packet){

        if (call Timer0.isRunning()) {
            return FALSE;
        } else {
            call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
            queued_packet = *packet;
        }
                            
        return TRUE;

    }

    /* 
    * TODO: comments
    * 
    * actual_send checks if another message is being sent and in case it is not then it calls
    * AMSend.send to send the new message received as pointer packet. Variable locked is used
    * for the check: if it is TRUE it means that a message is being sent (radio interface is occupied) and FALSE value is 
    * returned, if it is FALSE then no message is being sent and a TRUE value is returned. Multiple
    * messages are sent in case the node is a gateway, othherwise only one message is sent.
    * @Input: 
    *       address: packet destination address
    *       packet: packet to be sent (not only payload)
    * @Output: 
    *       boolean variable: it is TRUE when message could be sent, FALSE otherwise
    */
    bool actual_send (message_t* packet) {
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

    // TODO: comments
    uint16_t index_of_message(uint16_t id) {
        
        uint16_t i = 0;

        for (i = 0; i < SENSOR_LIST_SIZE; i++) {
            
            if (!list_of_messages[i].overwritable) {
                
                if (list_of_messages[i].sense_msg.msg_id == id) {
                    return i;
                }

            }

        }

        return -1;
    }

    // TODO: comments
    bool is_dup(uint16_t id) {

        uint16_t i;

        for (i = msg_count - 1; i >= 0; i--) {
            if (list_of_messages[i].sense_msg.msg_id == id) {
                return TRUE;
            }
        }

        for (i = msg_count; i < SERVER_LIST_SIZE; i++) {
            if (list_of_messages[i].sense_msg.msg_id == id) {
                return TRUE;
            }
        }

        return FALSE;

    }

    // TODO: comments
    void add_message_to_server_list(sense_msg_t* msg) {
        
        list_msg temp;
        
        temp.sense_msg.type = msg->type;
        temp.sense_msg.msg_id = msg->msg_id;
        temp.sense_msg.data = msg->data;
        temp.sense_msg.sender = msg->sender;
        temp.sense_msg.destination = msg->destination;

        list_of_messages[msg_count].sense_msg = temp;

        if (msg_count + 1 < SERVER_LIST_SIZE) {
            msg_count++;
        } else {
            msg_count = 0;
        }

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

                default: call Timer1.startPeriodic(1000);;
                             break
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
        actual_send (&queued_packet);
    }

    /*
    * Implement here the logic to trigger the Sensor Node to send the data packet to the gateways.
    */
    // This code is called whenever timer 1 fires. It toggles LED0.
    event void Timer1.fired() {
        // This code is executed when the timer expires.
        uint16_t addr[DIM_GATEWAYS]; 
        // a pointer to packet (message_t variable) is declared and assigned to rrm  
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&packet, sizeof(sense_msg_t));
        
        dbg("timer1", "[TIMER1] Timer fired out.\n");
        payload_p->type = 0;
        payload_p->msg_id = msg_count;
        msg_count++;
        payload_p->data = call Random.rand16(); // Generate random integer
        payload_p->sender = TOS_NODE_ID;
        generate_send(&packet);
        call Timer2.startOneShot(5000);
    }

        /*
    * Implementation of the logic to trigger the retransmission of the data packet to the gateways in case of 
    no ACK received in a 1ms window.
    */
    event void Timer2.fired() {
        // This code is executed when the timer expires.
        uint16_t addr[DIM_GATEWAYS]; 
        // a pointer to packet (message_t variable) is declared and assigned to rrm  
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&packet, sizeof(sense_msg_t));
        
        dbg("Timer2", "[Timer2] Timer fired out.\n");
        payload_p->type = 0;
        // TODO Message id of the message for which Timer2 has fired must be retrieved from array of sent messages

        msg_count++;
        payload_p->data = call Random.rand16(); // Generate random integer
        payload_p->sender = TOS_NODE_ID;
        generate_send(&packet);
        call Timer2.startOneShot(5000);
    }


    //***************** Receive interface *****************//
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    /*
    * If Network Server Parse the receive packet, implement functions and call generate_send with the ACK message packet and the ADDRESS of the destination sensor.
      If Gateway parse ACK message and forward to the destination sensor.
      If Sensor Node don't do anything

      TODO: commemts
    */  
        uint16_t gateway_addr;

        if (len != sizeof(radio_route_msg_t)) {
            return bufPtr;
        } else {

            // Variable that contains the payload of the received message
            sense_msg_t* mess = (sense_msg_t*) payload;
            
            // Variable that contains the message that will be sent from the current node
            sense_msg_t* new_mess = (sense_msg_t*) call Packet.getPayload(&packet, sizeof(sense_msg_t));

            dbg("radio_rec", "[RADIO_REC] Received a message of type %u at node %u.\n", mess->type, TOS_NODE_ID);

            if (new_mess == NULL) {
                dbgerror("radio_rec", "[RADIO_REC] ERROR ALLOCATING MEMORY FOR NEW MESSAGE.\n");
                return bufPtr;
            }

            if (TOS_NODE_ID >= 1 && TOS_NODE_ID <= SENSOR_NODES) {
                
                if (mess->type == 1) {

                    uint16_t index = 0;
                    
                    index = index_of_message(mess->msg_id);

                    if (index < 0) {
                        return NULL;
                    }

                    list_of_messages[index].overwritable = TRUE;

                } else {

                    // generate error since a sensor node is receiving a data message

                }

            } else if (TOS_NODE_ID > SENSOR_NODES && TOS_NODE_ID <= SENSOR_NODES + GATEWAY_NODES) {

                new_mess->type = mess->type;
                new_mess->msg_id = mess->msg_id;
                new_mess->data = mess->data;
                new_mess->sender = mess->sender;
                new_mess->destination = mess->destination;
                
                generate_send(&packet);
        
            } else if (TOS_NODE_ID == SERVER_NODE) {
                
                if (!is_dup(mess->msg_id)) {

                    add_message_to_server_list(mess);

                    new_mess->type = 1;
                    new_mess->msg_id = mess->msg_id;
                    new_mess->data = 0;
                    new_mess->sender = mess->destination;
                    new_mess->destination = mess->sender;

                    generate_send(&packet);

                }

            }
        }
    }
}
}
