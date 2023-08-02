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

    message_t globalpacket;

    // Variables to store the message to send
    message_t queued_packet;
    uint16_t queue_addr;

    // Time delay in milli seconds
    uint16_t time_delays[8] = {40, 60, 45, 50, 55, 30, 30, 75};

    bool locked;

    // Counter to update message id
    uint16_t counter;

    // TODO: comments
    last_message_transmitted msg_tx;

    // TODO: comments
    last_message_received msg_from_sensor[SENSOR_NODES];


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
    bool generate_send (uint16_t address, message_t* packet, uint8_t type){

        if (call Timer0.isRunning()) {
            return FALSE;
        } else {
            if (type == 1) {
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
    bool actual_send (uint16_t address, message_t* packet){

        if (locked) {
            return FALSE;
        } else {

            if (call AMSend.send(address, packet, sizeof(sense_msg_t)) == SUCCESS) {
                sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(packet, sizeof(sense_msg_t));

                if (payload_p == NULL) {
                    dbgerror("radio_send", "[RADIO_SEND] ERROR ALLOCATING MEMORY.\n");
                    return FALSE;
                }

                dbg("radio_send", "[RADIO_SEND] Sending message of type %u from %u to %u passing by %u.\n", payload_p->type, payload_p->sender, payload_p->destination, address);
                locked = TRUE;
            }

        }

        return TRUE;

    }

    /*
    * TODO: comments
    */
    void initialize_counter(){
        counter = 0;
    }

    /*
    * TODO: comments
    */
    void initialize_last_message_received(){
        
        uint8_t i;
    
        for(i = 0; i < SENSOR_NODES; i++) {
            msg_from_sensor[i].msg_id = -1;
            msg_from_sensor[i].gateway = -1;
            msg_from_sensor[i].retransmitted = FALSE;
        }

    }

    void set_last_message_transmitted(sense_msg_t *m) {

        msg_tx.sense_msg.type = m->type;
        msg_tx.sense_msg.msg_id = m->msg_id;
        msg_tx.sense_msg.data = m->data;
        msg_tx.sense_msg.sender = m->sender;
        msg_tx.sense_msg.destination = m->destination;

        msg_tx.ack_received = FALSE;

    }

    static void send_data_to_node_red(sense_msg_t* message) {   
    char json_buffer[128];    uint16_t randn;
    randn = call Random.rand16();  
    if(message->sender == 1){
        snprintf(json_buffer, sizeof(json_buffer), "field1=%u&status=MQTTPUBLISH", randn);    
     }else if(message->sender == 2){
        snprintf(json_buffer, sizeof(json_buffer), "field2=%u&status=MQTTPUBLISH", randn);    
     }else if(message->sender == 3){
        snprintf(json_buffer, sizeof(json_buffer), "field3=%u&status=MQTTPUBLISH", randn);    
     }else
        return;
    // print the json string    
    printf("%s\n", json_buffer);
    }


    //***************** Boot interface ********************//
    /*
    * TODO: comments
    */
    event void Boot.booted() {

        dbg("boot", "[BOOT] Application booted for node %u.\n", TOS_NODE_ID);

        if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5){
            initialize_counter();
            dbg("init", "[INIT] Counter table initialized for node %u.\n", TOS_NODE_ID);
        }

        if (TOS_NODE_ID == SERVER_NODE) {
            initialize_last_message_received();
        }

        // When the device is booted, the radio is started
        call AMControl.start();

    }


    //*************** AMControl interface *****************//
    /*
    * TODO: comments
    */
    event void AMControl.startDone(error_t err) {

        // If the radio is correctly turned on, Timer1 starts
        if(err == SUCCESS) {

            dbg("radio", "[RADIO] Radio successfully started for node %u.\n", TOS_NODE_ID);

            switch(TOS_NODE_ID) {
                case 1:
                    call Timer1.startPeriodic(2000);
                    break;
                case 2:
                    call Timer1.startPeriodic(2500);
                    break;
                case 3:
                    call Timer1.startPeriodic(3000);
                    break;
                case 4:
                    call Timer1.startPeriodic(3500);
                    break;
                case 5:
                    call Timer1.startPeriodic(4000);
                    break;
                default:
                    break;
            }

        } 
        // If the radio didn't turn on successfully, the start is performed again
        else {

            dbg("radio", "[RADIO] Radio starting failed for node %u...restarting.\n", TOS_NODE_ID);
            call AMControl.start();

        }

    }

    event void AMControl.stopDone(error_t err) {

        dbg("radio", "[RADIO] Radio stopped for node %u.\n", TOS_NODE_ID);

    }
    

    //***************** AMSend interface ******************//
    /* 
    * This event is triggered when a message is sent.
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
    /*
    * Timer triggered to perform the send.
    */
    event void Timer0.fired() {

        actual_send (queue_addr, &queued_packet);
    
    }

    /*
    * TODO: comments
    */
    event void Timer1.fired() {

        // a pointer to globalpacket (message_t variable) is declared and assigned to payload_p 
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&globalpacket, sizeof(sense_msg_t));
        uint16_t addr;

        dbg("timer1", "[TIMER1] Timer fired out.\n");

        if (payload_p == NULL){
            return;
        }

        // When Timer1 fires out, the sensor prepares a data packet
        if (TOS_NODE_ID == 2 || TOS_NODE_ID == 4) {

            // data packet is prepared for gateway 1 
            addr = 6;

            payload_p->type = 0;
            payload_p->msg_id = counter;
            payload_p->sender = TOS_NODE_ID;
            payload_p->destination = addr;
            payload_p->data = call Random.rand16() % 100; // Generates random integer

            // The data packet is sent to gateway 1
            generate_send(addr, &globalpacket, 0);

            // data packet is prepared for gateway 2
            addr = 7;

            payload_p->type = 0;
            payload_p->msg_id = counter;
            payload_p->sender = TOS_NODE_ID;
            payload_p->destination = addr;
            payload_p->data = call Random.rand16() % 100; // Generate random integer

            // Increase message id counter
            counter++;

            // The data packet is sent to gateway 2
            generate_send(addr, &globalpacket, 0);

            msg_tx.sense_msg.type = payload_p->type;
            msg_tx.sense_msg.sender = payload_p->sender;
            msg_tx.sense_msg.destination = payload_p->destination;
            msg_tx.sense_msg.data = payload_p->data;
            msg_tx.sense_msg.msg_id = payload_p->msg_id;

        } else if (TOS_NODE_ID == 1) {

            // data packet is prepared for gateway 1 
            addr = 6;

            payload_p->type = 0;
            payload_p->msg_id = counter;
            payload_p->sender = TOS_NODE_ID;
            payload_p->destination = addr;
            payload_p->data = call Random.rand16() % 100; // Generate random integer

            // Increase message id counter
            counter++;

            // The data packet is sent to gateway 1
            generate_send(addr, &globalpacket, 0);

            msg_tx.sense_msg.type = payload_p->type;
            msg_tx.sense_msg.sender = payload_p->sender;
            msg_tx.sense_msg.destination = payload_p->destination;
            msg_tx.sense_msg.data = payload_p->data;
            msg_tx.sense_msg.msg_id = payload_p->msg_id;

        } else if (TOS_NODE_ID == 3 || TOS_NODE_ID == 5){

            // data packet is prepared for gateway 2
            addr = 7;

            payload_p->type = 0;
            payload_p->msg_id = counter;
            payload_p->sender = TOS_NODE_ID;
            payload_p->destination = addr;
            payload_p->data = call Random.rand16() % 100; // Generate random integer

            // Increase message id counter
            counter++;

            // The data packet is sent to gateway 2
            generate_send(addr, &globalpacket, 0);

            msg_tx.sense_msg.type = payload_p->type;
            msg_tx.sense_msg.sender = payload_p->sender;
            msg_tx.sense_msg.destination = payload_p->destination;
            msg_tx.sense_msg.data = payload_p->data;
            msg_tx.sense_msg.msg_id = payload_p->msg_id;
        
        } else {

            //dbg("timer1", "[TIMER1] Error : selected node doesn't exist.\n");
            printf("[TIMER1] Error : selected node doesn't exist.\n");

        }

        call Timer2.startOneShot(1000);
    }

    /*
    * TODO: comments
    */
    event void Timer2.fired() {
    
        // a pointer to globalpacket (message_t variable) is declared and assigned to payload_p 
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&globalpacket, sizeof(sense_msg_t));
        uint16_t addr;

        if (payload_p == NULL){
            return;
        }

        //dbg("timer2", "[TIMER2] Timer fired out.\n");
        printf("[TIMER2] Timer fired out.\n");

        if (msg_tx.ack_received == FALSE) {

            //dbg("timer2", "[TIMER2] 1000ms passed and no ACK has been received. Going to retransmit...\n");
            printf("[TIMER2] 1000ms passed and no ACK has been received. Going to retransmit...\n");

            if (TOS_NODE_ID == 2 || TOS_NODE_ID == 4) {

                // data packet is prepared for gateway 1 
                addr = 6;

                payload_p->type = msg_tx.sense_msg.type;
                payload_p->msg_id = msg_tx.sense_msg.msg_id;
                payload_p->sender = msg_tx.sense_msg.sender;
                payload_p->destination = addr;
                payload_p->data = msg_tx.sense_msg.data;

                // The data packet is sent to gateway 1
                generate_send(addr, &globalpacket, 0);

                // data packet is prepared for gateway 2
                addr = 7;

                payload_p->type = msg_tx.sense_msg.type;
                payload_p->msg_id = msg_tx.sense_msg.msg_id;
                payload_p->sender = msg_tx.sense_msg.sender;
                payload_p->destination = addr;
                payload_p->data = msg_tx.sense_msg.data;

                // The data packet is sent to gateway 2
                generate_send(addr, &globalpacket, 0);

            } else if (TOS_NODE_ID == 1) {

                // data packet is prepared for gateway 1 
                addr = 6;

                payload_p->type = msg_tx.sense_msg.type;
                payload_p->msg_id = msg_tx.sense_msg.msg_id;
                payload_p->sender = msg_tx.sense_msg.sender;
                payload_p->destination = addr;
                payload_p->data = msg_tx.sense_msg.data;

                // The data packet is sent to gateway 1
                generate_send(addr, &globalpacket, 0);

            } else if (TOS_NODE_ID == 3 || TOS_NODE_ID == 5){

                // data packet is prepared for gateway 2
                addr = 7;

                payload_p->type = msg_tx.sense_msg.type;
                payload_p->msg_id = msg_tx.sense_msg.msg_id;
                payload_p->sender = msg_tx.sense_msg.sender;
                payload_p->destination = addr;
                payload_p->data = msg_tx.sense_msg.data; // Generates random integer

                // The data packet is sent to gateway 2
                generate_send(addr, &globalpacket, 0);
            
            }
        }
        
    }


    //***************** Receive interface *****************//
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    /*
    * Parse the receive packet.
    * Implement all the functionalities.
    * Perform the packet send using the generate_send function if needed.
    */

        if (len != sizeof(sense_msg_t)) {
            return bufPtr;
        } else {

            // Variable that contains the payload of the received message
            sense_msg_t* mess = (sense_msg_t*) payload;
            // Variable that will contain the payload of the message that will be sent
            sense_msg_t* new_mess = (sense_msg_t*)call Packet.getPayload(&globalpacket, sizeof(sense_msg_t));
            uint16_t addr;
 
            //dbg("radio_rec", "[RADIO_REC] Received a message of type %u at node %u.\n", mess->type, TOS_NODE_ID);
            printf("[RADIO_REC] Received a message of type %u at node %u.\n", mess->type, TOS_NODE_ID);

            if (new_mess == NULL) {
                //dbgerror("radio_rec", "[RADIO_REC] ERROR ALLOCATING MEMORY FOR NEW MESSAGE.\n");
                printf("[RADIO_REC] ERROR ALLOCATING MEMORY FOR NEW MESSAGE.\n");
                return bufPtr;
            }
   
            // A data message is received, debug messages are sent
            if (mess->type == 0) {

                // If the current node is node 7, that is the destination of the data message, we don't need to forward packets anymore
                if (TOS_NODE_ID == 8) {

                    // WE'RE DONE
                    //dbg ("radio_rec", "[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u WITH VALUE %u.\n", TOS_NODE_ID, mess->type, mess->data);
                    printf("[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u WITH VALUE %u.\n", TOS_NODE_ID, mess->type, mess->data);

                } else if ( TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {
                    
                    //dbg ("radio_rec", "[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u WITH VALUE %u.\n", TOS_NODE_ID, mess->type, mess->data);
                    printf("[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u WITH VALUE %u.\n", TOS_NODE_ID, mess->type, mess->data);

                } else {

                    //dbg ("radio_rec", "[RADIO_REC] ERROR : SENSOR NODE RECEIVED A DATA PACKET\n");
                    printf("[RADIO_REC] ERROR : SENSOR NODE RECEIVED A DATA PACKET\n");

                }
           
            } else if (mess->type == 1) {

                if (TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5) {

                    //dbg ("radio_rec", "[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u. WE'RE DONE!\n", TOS_NODE_ID, mess->type);
                    printf("[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u. WE'RE DONE!\n", TOS_NODE_ID, mess->type);

                } else if(TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {

                    //dbg ("radio_rec", "[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u.\n", TOS_NODE_ID, mess->type);
                    printf("[RADIO_REC] HERE IT IS NODE %u AND I RECEIVED THE PACKET OF TYPE %u.\n", TOS_NODE_ID, mess->type);

                } else {

                    //dbg ("radio_rec", "[RADIO_REC] ERROR : SENSOR NODE RECEIVED AN ACK PACKET\n");
                    printf("[RADIO_REC] ERROR : SENSOR NODE RECEIVED AN ACK PACKET\n");

                }

            } else {

                //dbg ("radio_rec", "[RADIO_REC] ERROR : INVALID MESSAGE TYPE RECEIVED AT NODE %u\n", TOS_NODE_ID);
                printf("[RADIO_REC] ERROR : INVALID MESSAGE TYPE RECEIVED AT NODE %u\n", TOS_NODE_ID);

            }
             
            // Logic implementation at the receiver 
           
            if(TOS_NODE_ID == 6 || TOS_NODE_ID == 7){
                
                if(mess->type == 0){

                    // Forward data packet to Server node
                    new_mess->type = mess->type;
                    new_mess->msg_id = mess->msg_id;
                    new_mess->data = mess->data;
                    new_mess->sender = mess->sender;
                    new_mess->destination = mess->destination;
                    
                    addr = 8;
              
                    generate_send(addr, &globalpacket, 0);

                } else if (mess->type == 1) {
                    
                    // Forward ack to correspondent sensor node
                    new_mess->type = mess->type;
                    new_mess->msg_id = mess->msg_id;
                    new_mess->data = mess->data;
                    new_mess->sender = mess->sender;
                    new_mess->destination = mess->destination;
                    
                    addr = new_mess->destination;
                    generate_send(addr, &globalpacket, 1);

                    //dbg("radio_rec", "[RADIO_REC] GATEWAY RECEIVED ACK\n");
                    printf("[RADIO_REC] GATEWAY RECEIVED ACK\n");

                } else {

                    //dbg ("radio_rec", "[RADIO_REC] ERROR : INVALID MESSAGE TYPE\n");
                    printf("[RADIO_REC] ERROR : INVALID MESSAGE TYPE\n");

                }

            } else if (TOS_NODE_ID == 8) {

                //dbg("radio_rec", "[RADIO_REC] WE ARE THE SERVER AND WE HAVE last_message_received[mess->sender - 1].msg_id = %u and mess->msg_id = %u.\n", msg_from_sensor[mess->sender - 1].msg_id, mess->msg_id);
                printf("[RADIO_REC] WE ARE THE SERVER AND WE HAVE last_message_received[mess->sender - 1].msg_id = %u and mess->msg_id = %u.\n", msg_from_sensor[mess->sender - 1].msg_id, mess->msg_id);
                
                // Send data over the network using Cooja        
                send_data_to_node_red(mess);
                printfflush();

                if (msg_from_sensor[mess->sender - 1].msg_id != mess->msg_id) {

                    msg_from_sensor[mess->sender - 1].msg_id = mess->msg_id;
                    msg_from_sensor[mess->sender - 1].gateway = mess->destination;
                    msg_from_sensor[mess->sender - 1].retransmitted = FALSE;

                    new_mess->type = 1;
                    new_mess->msg_id = mess->msg_id;
                    new_mess->data = 0;
                    new_mess->sender = mess->destination;
                    new_mess->destination = mess->sender;
                        
                    addr = new_mess->sender;
                    generate_send(addr, &globalpacket, 1);
                    //dbg("radio_rec", "[RADIO_REC] COPYING FROM MESSAGE WITH ID %u SENDER ADDRESS %u and DEST ADDRESS %u\n", mess->msg_id, mess->sender, mess->destination);
                    printf("[RADIO_REC] COPYING FROM MESSAGE WITH ID %u SENDER ADDRESS %u and DEST ADDRESS %u\n", mess->msg_id, mess->sender, mess->destination);
                    
                    //dbg("radio_rec", "[RADIO_REC] SENDING ACK PACKET FROM SERVER WITH ID %u SENDER ADDRESS %u and DEST ADDRESS %u\n", new_mess->msg_id, new_mess->sender, new_mess->destination);
                    printf("[RADIO_REC] SENDING ACK PACKET FROM SERVER WITH ID %u SENDER ADDRESS %u and DEST ADDRESS %u\n", new_mess->msg_id, new_mess->sender, new_mess->destination);
                
                } else if (msg_from_sensor[mess->sender - 1].gateway == mess->destination &&
                    msg_from_sensor[mess->sender - 1].retransmitted == FALSE) {

                    msg_from_sensor[mess->sender - 1].retransmitted = TRUE;

                    new_mess->type = 1;
                    new_mess->msg_id = mess->msg_id;
                    new_mess->data = 0;
                    new_mess->sender = mess->destination;
                    new_mess->destination = mess->sender;

                    addr = new_mess->sender;
                    generate_send(addr, &globalpacket, 1);
                    //dbg("radio_rec", "[RADIO_REC] COPYING FROM MESSAGE WITH ID %u SENDER ADDRESS %u and DEST ADDRESS %u\n", mess->msg_id, mess->sender, mess->destination);
                    printf("[RADIO_REC] COPYING FROM MESSAGE WITH ID %u SENDER ADDRESS %u and DEST ADDRESS %u\n", mess->msg_id, mess->sender, mess->destination);
                    
                    //dbg("radio_rec", "[RADIO_REC] SENDING ACK PACKET FROM SERVER WITH ID %u SENDER ADDRESS %u and DEST ADDRESS %u\n", new_mess->msg_id, new_mess->sender, new_mess->destination);
                    printf("[RADIO_REC] SENDING ACK PACKET FROM SERVER WITH ID %u SENDER ADDRESS %u and DEST ADDRESS %u\n", new_mess->msg_id, new_mess->sender, new_mess->destination);

                } else {
                    //dbg("radio_rec", "[RADIO_REC] RECEIVING A DUPLICATE AND DISCARDING IT.\n");
                    printf("[RADIO_REC] RECEIVING A DUPLICATE AND DISCARDING IT.\n");
                }

                // TODO Implementation of dup-ACK suppression

            } else if (TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5) {

                //dbg("radio_rec", "[RADIO_REC] SENSOR RECEIVED ACK\n");
                printf("[RADIO_REC] SENSOR RECEIVED ACK\n");
                // TODO Implementation of data packet retransmission

            } else {

                //dbg("radio_rec", "[RADIO_REC] ERROR : INVALID NODE\n");
                printf("[RADIO_REC] ERROR : INVALID NODE\n");

            }
            
            return bufPtr;
        }
    }
}
