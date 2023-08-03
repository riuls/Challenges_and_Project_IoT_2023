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

    // Time delay in milli seconds that emulates transmission delays
    uint16_t time_delays[8] = {40, 60, 45, 50, 55, 30, 30, 75};

    // Variable used to grant access to the send function to one process at the time
    bool locked;

    // Counter to update message id
    uint16_t counter;

    /*
    * Variable used just by the sensor nodes.
    * Variable used to store the last message sent by the node.
    * When an ack is received, the field ack_received will be set to TRUE.
    * ack_received is checked when Timer2 fires out: if it is still set to FALSE, the retranmission process starts.
    */
    last_message_transmitted msg_tx;

    /*
    * Variable used just by the server.
    * Variable used to store the last message received by the server for all the sensor nodes.
    * The purpose of the variable is to give the needed information to suppress duplicates and to retransmit once
    * an ack message.
    */
    last_message_received msg_from_sensor[SENSOR_NODES];


    /*
    * The function is used when a node wants to send a message.
    * The first step for the send is to call the generate_send which will launch a Timer to emulate
    * the transmission delay. The packet and its destination are then saved into queued_packet and queue_addr.
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
    * The function is called when the Timer that emulates the transmission delay fires out.
    * First of all, a lock grants the access to the function to one process at the time.
    * Then, the send function provided by the AMSend interface is called.
    * The lock is set to true until the send will be completed (means until sendDone will be triggered).
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
    * Each node when booted will initialize its counter to 0.
    * Notice that the key of a message is not given just by the id, but by the couple <nodeid, msgid>.
    * So, for example, all the sensor nodes will have a message with msg_id = 0.
    */
    void initialize_counter(){
        counter = 0;
    }

    /*
    * When the server is booted, it initializes the array containing the last message 
    * it received by all the sensor nodes.
    */
    void initialize_last_message_received(){
        
        uint8_t i;
    
        for(i = 0; i < SENSOR_NODES; i++) {
            msg_from_sensor[i].msg_id = -1;
            msg_from_sensor[i].gateway = -1;
            msg_from_sensor[i].retransmitted = FALSE;
        }

    }

    /*
    * This message is used to set the msg_tx variable with the values of 
    * the new message the sensor node is transmitting.
    */
    void set_last_message_transmitted(sense_msg_t *m) {

        msg_tx.sense_msg.type = m->type;
        msg_tx.sense_msg.msg_id = m->msg_id;
        msg_tx.sense_msg.data = m->data;
        msg_tx.sense_msg.sender = m->sender;
        msg_tx.sense_msg.destination = m->destination;

        msg_tx.ack_received = FALSE;

    }

    /*
    * The function sends to node-red the value that the server has just received. 
    * It works by performing the printf of the value, which will be printed on the output console on
    * Cooja (the simulation environment we used) and then forwarded to node-red.
    */
    static void send_data_to_node_red(sense_msg_t* message) {    
        // Convert data to string format
        char buffer[128];    
        if (message->sender == 1) {
            snprintf(buffer, sizeof(buffer), "fieldone:%u", message->data);
        } else if (message->sender == 2) {
            snprintf(buffer, sizeof(buffer), "fieldtwo:%u", message->data);
        } else if (message->sender == 3) {
            snprintf(buffer, sizeof(buffer), "fieldthree:%u", message->data);
        } else {
            return;
        }

        printf("[SERVER] Sending to NODE-RED the value %u sent by node %u.\n", message->data, message->sender);
        printf("%s\n", buffer);
    }


    //***************** Boot interface ********************//
    /*
    * When a node is booted it initializes the variable(s) it will use along the execution.
    * Then, all the nodes start the radio.
    */
    event void Boot.booted() {

        printf("[BOOT] Application booted for node %u.\n", TOS_NODE_ID);

        if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5){
            initialize_counter();
        }

        if (TOS_NODE_ID == SERVER_NODE) {
            initialize_last_message_received();
        }

        // When the device is booted, the radio is started
        call AMControl.start();

    }


    //*************** AMControl interface *****************//
    /*
    * If the start of the radio failed, the start function is called again.
    * Otherwise, if the start was successfull, if the node is a sensor, it will launch a periodic timer
    * which defines the period between trasmissions of new messages.
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

    /*
    * Not used in our case, but needed to execute the program
    */
    event void AMControl.stopDone(error_t err) {

        dbg("radio", "[RADIO] Radio stopped for node %u.\n", TOS_NODE_ID);

    }
    

    //***************** AMSend interface ******************//
    /* 
    * This event is triggered when a message is sent.
    * When the send process terminates, the lock is put to FALSE in order to allow other process to use
    * the radio transmission.
    */
    event void AMSend.sendDone(message_t* bufPtr, error_t error) {

        if (error == SUCCESS) {

            dbg("radio_send", "[RADIO_SEND] Packet sent from %u at time %s.\n", TOS_NODE_ID, sim_time_string());

        } else {

            dbgerror("radio_send", "[RADIO_SEND] Send done error for node %u!\n", TOS_NODE_ID);

        }

        locked = FALSE;
    
    }


    //****************** Timer interface ******************//
    /*
    * The timer is called by the generate_send function to emulate the transmission delay.
    * So, once the timer fires out, the actual send can be performed.
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
                    msg_tx.ack_received = TRUE;

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
