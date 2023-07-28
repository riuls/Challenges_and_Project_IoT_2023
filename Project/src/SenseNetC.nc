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
    message_t queued_packet;

    // TODO: comments
    last_message_received* last_sensor_messages = NULL;

    // Variable for storing radio interface occupation status
    bool locked;

    // Variable for storing ACK reception status
    ack_status_t ack_rec_status;

    uint16_t msg_count = 0;


    // TODO: comments
    void initialize_ack_rec_status() {

        ack_rec_status.ack_received = FALSE;
    
    }

    // TODO: comments
    void initialize_server_message_list() {

        last_message_received temp[SENSOR_NODES];
        
        uint16_t i = 0;

        for (i = 0; i < SENSOR_NODES; i++) {
            temp[i].msg_id = -1;
            temp[i].retransmitted = FALSE;
        }

        last_sensor_messages = temp;

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

            gateway_1 = SENSOR_NODES + GATEWAY_NODES -1;
            gateway_2 = SENSOR_NODES + GATEWAY_NODES;

            if (TOS_NODE_ID == 2 || TOS_NODE_ID == 4) {

                payload_p->destination = gateway_1;

                if (call AMSend.send(gateway_1, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    dbg("radio_send", "[RADIO_SEND] Sending message of type %u with id %u from %u to %u passing by gateway 1 (Node %u).\n", payload_p->type, payload_p->msg_id, payload_p->sender, SERVER_NODE, payload_p->destination); 
                    locked = TRUE;
                } else  {
                    // Generate error message
                    dbg("radio_send", "[RADIO_SEND] Error sending message of type %u with id %u from %u to %u passing by gateway 1 (Node %u).\n", payload_p->type, payload_p->msg_id, payload_p->sender, SERVER_NODE, payload_p->destination);
                }

                payload_p->destination = gateway_2;

                if (call AMSend.send(gateway_2, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    dbg("radio_send", "[RADIO_SEND] Sending message of type %u with id %u from %u to %u passing by gateway 2 (Node %u).\n", payload_p->type, payload_p->msg_id, payload_p->sender, SERVER_NODE, payload_p->destination); 
                    locked = TRUE;
                } else  {
                    // Generate error message
                    dbg("radio_send", "[RADIO_SEND] Error sending message of type %u with id %u from %u to %u passing by gateway 2 (Node %u).\n", payload_p->type, payload_p->msg_id, payload_p->sender, SERVER_NODE, payload_p->destination);
                }

            } else if (TOS_NODE_ID == 1) {

                payload_p->destination = gateway_1;
                
                if (call AMSend.send(gateway_1, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                    dbg("radio_send", "[RADIO_SEND] Sending message of type %u with id %u from %u to %u passing by gateway 1 (Node %u).\n", payload_p->type, payload_p->msg_id, payload_p->sender, SERVER_NODE, payload_p->destination);
                    locked = TRUE;
                } else {
                    dbg("radio_send", "[RADIO_SEND] Error sending message of type %u with id %u from %u to %u passing by gateway 1 (Node %u).\n", payload_p->type, payload_p->msg_id, payload_p->sender, payload_p->destination);
                }    

            } else if (TOS_NODE_ID == 3 || TOS_NODE_ID == 5) {

                payload_p->destination = gateway_2;
                
                if (call AMSend.send(gateway_2, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                    dbg("radio_send", "[RADIO_SEND] Sending message of type %u with id %u from %u to %u passing by gateway 2 (Node %u).\n", payload_p->type, payload_p->msg_id, payload_p->sender, SERVER_NODE, payload_p->destination); 
                    locked = TRUE;
                } else {
                    dbg("radio_send", "[RADIO_SEND] Error sending message of type %u with id %u from %u to %u passing by gateway 2 (Node %u).\n", payload_p->type, payload_p->msg_id, payload_p->sender, SERVER_NODE, payload_p->destination);
                }

            } else if (TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {
                                
                if (payload_p->type == 0) {
                    
                    if (call AMSend.send(SERVER_NODE, packet, sizeof(sense_msg_t)) == SUCCESS) {
                        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                        dbg("radio_send", "[RADIO_SEND] Sending message of type %u with id %u from %u to %u.\n", payload_p->type, payload_p->msg_id, TOS_NODE_ID, SERVER_NODE);
                        locked = TRUE;
                    } else {
                        dbg("radio_send", "[RADIO_SEND] Error sending message of type %u with id %u from %u to %u.\n", payload_p->type, payload_p->msg_id, TOS_NODE_ID, SERVER_NODE);                   
                    }

                } else {
                    
                    if (call AMSend.send(payload_p->destination, packet, sizeof(sense_msg_t)) == SUCCESS) {
                        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                        dbg("radio_send", "[RADIO_SEND] Sending message of type %u with id %u from %u to %u.\n", payload_p->type, payload_p->msg_id, payload_p->sender, payload_p->destination);
                        locked = TRUE;
                    } else {
                        dbg("radio_send", "[RADIO_SEND] Error sending message of type %u with id %u from %u to %u.\n", payload_p->type, payload_p->msg_id, payload_p->sender, payload_p->destination);                   
                    }

                }

            } else if (TOS_NODE_ID == SERVER_NODE) {
                
                if (call AMSend.send(payload_p->sender, packet, sizeof(sense_msg_t)) == SUCCESS) {
                    sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));
                dbg("radio_send", "[RADIO_SEND] Sending message of type %u with id %u from Server (Node %u) to %u passing by gateway %u (Node %u).\n", payload_p->type, payload_p->msg_id, SERVER_NODE, payload_p->destination, payload_p->sender - SENSOR_NODES, payload_p->sender);
                    locked = TRUE;
                } else {
                    dbg("radio_send", "[RADIO_SEND] Error sending message of type %u with id %u from Server (Node %u) to %u passing by gateway %u (Node %u).\n", payload_p->type, payload_p->msg_id, SERVER_NODE, payload_p->destination, payload_p->sender - SENSOR_NODES, payload_p->sender);
                }  

            }

        }

        return TRUE;

    }


    //***************** Boot interface ********************//
    event void Boot.booted() {

        dbg("boot", "[BOOT] Application booted for node %u.\n", TOS_NODE_ID);

        if (TOS_NODE_ID >= 1 && TOS_NODE_ID <= SENSOR_NODES) {
            initialize_ack_rec_status();
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
                case 1: call Timer1.startPeriodic(2000);;
                             break;
                case 2: call Timer1.startPeriodic(2500);;
                             break;
                case 3: call Timer1.startPeriodic(3000);;
                              break;
                case 4: call Timer1.startPeriodic(3500);;
                             break;
                case 5: call Timer1.startPeriodic(4000);;
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
        dbg("timer0", "[TIMER0] Timer  fired out.\n");
        actual_send(&queued_packet);
    }

    /*
    * Implement here the logic to trigger the Sensor Node to send the data packet to the gateways.
    */
    event void Timer1.fired() {

        dbg("timer1", "[TIMER1] Timer fired out.\n");   

        if(TOS_NODE_ID <= SENSOR_NODES){

            uint16_t addr[GATEWAY_NODES]; 
            sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&packet, sizeof(sense_msg_t));
            
            payload_p->type = 0;
            payload_p->msg_id = msg_count;
            msg_count++;
            payload_p->data = call Random.rand16(); // Generate random integer
            payload_p->sender = TOS_NODE_ID;

            generate_send(&packet);

            // Reset the ack_received status
            ack_rec_status.sense_msg = payload_p;
            ack_rec_status.ack_received = FALSE;
            call Timer2.startOneShot(1000);
        }
    }

    /*
    * Implementation of the logic to trigger the retransmission of the data packet to the gateways in case of 
    * no ACK received in a 1s window.
    */
    event void Timer2.fired() {
        // This code is executed when the Timer2 expires.
        // a pointer to packet (message_t variable) is declared and assigned to payload_p  
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&packet, sizeof(sense_msg_t));
        
        dbg("timer2", "[TIMER2] Timer fired out.\n");
        
        // Control if the ACK has been received
        if(ack_rec_status.ack_received == FALSE){
            
            // If the ACK has not been received, the packet is retransmitted
            dbg("timer2", "[TIMER2] ACK not received.\n");
            generate_send(&packet);

        }else{
            // If the ACK has been received, the packet is not retransmitted
            dbg("timer2", "[TIMER2] ACK received.\n");
        }

    }


    //***************** Receive interface *****************//
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    /*
    * If Network Server Parse the receive packet, implement functions and call generate_send with the ACK message packet and the ADDRESS of the destination sensor.
      If Gateway parse ACK message and forward to the destination sensor.
      If Sensor Node don't do anything

      TODO: commemts
    */  
        sense_msg_t* new_mess = NULL;

        if (len != sizeof(radio_route_msg_t)) {
            return bufPtr;
        } else {

            // Variable that contains the payload of the received message
            sense_msg_t* mess = (sense_msg_t*) payload;

            dbg("radio_receive", "[RADIO_RECEIVE] Received a message of type %u with id %u at node %u.\n", mess->type, mess->msg_id, TOS_NODE_ID);
            
            // Variable that contains the message that will be sent from the current node
            if (new_mess = (sense_msg_t*) call Packet.getPayload(&packet, sizeof(sense_msg_t)) == NULL) {
                dbgerror("radio_receive", "[RADIO_RECEIVE] ERROR ALLOCATING MEMORY FOR NEW MESSAGE.\n");
                return bufPtr;
            }
    

            if (TOS_NODE_ID >= 1 && TOS_NODE_ID <= SENSOR_NODES) {

                if (mess->type == 1) {

                    ack_rec_status.ack_received = TRUE;

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

                if (!last_sensor_messages[mess->sender] == mess->msg_id) {

                    // TODO : Server forwards to MQTT and NODE-RED Servers

                    last_sensor_messages[mess->sender].msg_id = mess->msg_id;
                    last_sensor_messages[mess->sender].retransmitted = FALSE;

                    new_mess->type = 1;
                    new_mess->msg_id = mess->msg_id;
                    new_mess->data = 0;
                    new_mess->sender = mess->destination;
                    new_mess->destination = mess->sender;

                    generate_send(&packet);

                } else if (last_sensor_messages[mess->sender].retransmitted == FALSE) {
                    
                    last_sensor_messages[mess->sender].retransmitted = TRUE;

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