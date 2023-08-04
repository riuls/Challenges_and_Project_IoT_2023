#include "Timer.h"
#include "SenseNet.h"

/**
 * Implementation of the SenseNet application with Cooja debug. 
 * SenseNet includes 8 nodes connected through a Radio interface, 
 * the first five are sensor and periodically transmit random data, 
 * while the other two are gateways which receive and forward the data to the last node which acts as a network server: 
 * it transmits the data to a Node-Red and an MQTT server and it sends an ACK to the correspondent gateway. 
 * The Network Server node also eliminates dup-ACKS. 
 * The sensor nodes retransmit the data if an ACK is not received in a 1000ms window from the sending.
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

    /*
    * In order to avoid possible concurrent try of sending a message to both the gateways
    * for those sensor nodes that by topology are connected to them, we use this boolean
    * which is checked when the sendDone event is triggered in order to understand if
    * the previous transmission is referred to the first gateway or to the second.
    * If it refers to the first gateway, then we prepare the packet to be sent to node 7.
    */
    bool transmitted_to_second_gateway = FALSE;

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
    * This function is called by sensor node when they need to transmit a new data message.
    * The id is set considering the counter, the destination is given by the gateway to which
    * the message will be sent, data is randomly generated inside the [0, 99] interval.
    */
    void create_data_message(sense_msg_t *msg, uint16_t addr) {

        msg->type = 0;
        msg->msg_id = counter;
        msg->sender = TOS_NODE_ID;
        msg->destination = addr;
        msg->data = call Random.rand16() % 100; // Generates random integer

    }

    /*
    * The function is used when a node wants to send a message.
    * The first step for the send is to call the generate_send which will launch a Timer to emulate
    * the transmission delay. The packet and its destination are then saved into queued_packet and queue_addr.
    */
    bool generate_send (uint16_t address, message_t* packet){

        if (call Timer0.isRunning()) {

            return FALSE;

        } else {

            call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
            queued_packet = *packet;
            queue_addr = address;

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
                    printf("[RADIO_SEND] NODE %u: ERROR ALLOCATING MEMORY.\n", TOS_NODE_ID);
                    return FALSE;
                }

                if (payload_p->type == 0) {
                    printf("[RADIO_SEND] NODE %u: Sending a data message with ID %u, data %u, generated from node %u to the server.\n", TOS_NODE_ID, payload_p->msg_id, payload_p->data, payload_p->sender);
                } else {
                    printf("[RADIO_SEND] NODE %u: Sending an ack message with ID %u as response from the server to node %u.\n", TOS_NODE_ID, payload_p->msg_id, payload_p->destination);
                }

                locked = TRUE;
            }

        }

        return TRUE;

    }

    /*
    * This message is used to set the msg_tx variable with the values of 
    * the new message the sensor node is transmitting.
    */
    void set_last_message_transmitted(sense_msg_t *msg) {

        msg_tx.sense_msg.type = msg->type;
        msg_tx.sense_msg.msg_id = msg->msg_id;
        msg_tx.sense_msg.data = msg->data;
        msg_tx.sense_msg.sender = msg->sender;
        msg_tx.sense_msg.destination = msg->destination;

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
        } else if (message->sender == 3) {
            snprintf(buffer, sizeof(buffer), "fieldtwo:%u", message->data);
        } else if (message->sender == 5) {
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

        printf("[BOOT] NODE %u: Application booted.\n", TOS_NODE_ID);

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

            printf("[RADIO] NODE %u: Radio successfully started.\n", TOS_NODE_ID);

            switch(TOS_NODE_ID) {
                case 1:
                    call Timer1.startPeriodic(2000);
                    break;
                case 2:
                    call Timer1.startPeriodic(3000);
                    break;
                case 3:
                    call Timer1.startPeriodic(4000);
                    break;
                case 4:
                    call Timer1.startPeriodic(5000);
                    break;
                case 5:
                    call Timer1.startPeriodic(6000);
                    break;
                default:
                    break;
            }

        } 
        // If the radio didn't turn on successfully, the start is performed again
        else {

            printf("[RADIO] NODE %u: Radio failed to start...restarting.\n", TOS_NODE_ID);
            call AMControl.start();

        }

    }

    /*
    * Not used in our case, but needed to execute the program
    */
    event void AMControl.stopDone(error_t err) {

        printf("[RADIO] NODE %u: Radio stopped.\n", TOS_NODE_ID);

    }
    

    //***************** AMSend interface ******************//
    /* 
    * This event is triggered when a message is sent.
    * When the send process terminates, the lock is put to FALSE in order to allow other process to use
    * the radio transmission.
    * As explained in the description of the trasmitted_to_second_gateway variable, in the sendDone event
    * it is also performed the transmission to the second gateway for those sensor nodes which are connected to both
    * the gateways (which are node 2 and node 4).
    */
    event void AMSend.sendDone(message_t* bufPtr, error_t error) {

        uint8_t addr;
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&globalpacket, sizeof(sense_msg_t));

        if (error == SUCCESS) {

            printf("[RADIO_SEND] NODE %u: Packet successfully sent from %u.\n", TOS_NODE_ID, TOS_NODE_ID);

            if (TOS_NODE_ID == 2 || TOS_NODE_ID == 4) {

                if (transmitted_to_second_gateway == FALSE) {

                    transmitted_to_second_gateway = TRUE;

                    // Data packet is prepared for gateway 2
                    addr = 7;

                    payload_p->destination = addr;

                    // The data packet is sent to gateway 2
                    generate_send(addr, &globalpacket);

                }

            }

        } else {

            printf("[RADIO_SEND] NODE %u: Send done error for node!\n", TOS_NODE_ID);

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
    * This timer is used for the periodic transmission of a new message from each sensor node.
    * Their period is defined in the Boot.booted event.
    * We generate the packet to be sent defining the fields, which are type (0 for data and 1 for ack),
    * msg_id, sender (which for sensor nodes is always the TOS_NODE_ID), destination (sensor nodes always
    * set it to the ID of the gatway they are transmitting to, then they will forward it to the server).
    * Once the packet is ready, we call the generate_send function to start the sending process.
    * After that, we save in msg_tx the new message that is being transmitted since if the node
    * does not receive any ack, it will need to re-create the packet and retransmit it again.
    */
    event void Timer1.fired() {

        // Pointer to globalpacket (message_t variable) is declared and assigned to payload_p 
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&globalpacket, sizeof(sense_msg_t));
        uint16_t addr = 0;

        printf("[TIMER1] NODE %u: Timer fired out. Time to send a new message.\n", TOS_NODE_ID);

        if (payload_p == NULL){
            return;
        }

        // When Timer1 fires out, the sensor prepares a data packet
        if (TOS_NODE_ID == 2 || TOS_NODE_ID == 4) {

            // Data packet is prepared for gateway 1 
            addr = 6;

            // When the first send will end successfully, this boolean will be used to check
            // if we need to send also to the second gateway (just for node 2 and 4)
            transmitted_to_second_gateway = FALSE;

        } else if (TOS_NODE_ID == 1) {

            // Data packet is prepared for gateway 1 
            addr = 6;

        } else if (TOS_NODE_ID == 3 || TOS_NODE_ID == 5){

            // Data packet is prepared for gateway 2
            addr = 7;
        
        }

        create_data_message(payload_p, addr);

        generate_send(addr, &globalpacket);

        // Increase message id counter
        counter++;

        // We save the last message transmitted in case we need to retransmit it again due to ack not received
        set_last_message_transmitted(payload_p);

        call Timer2.startOneShot(1000);
    }

    /*
    * This timer is used for the 1000ms window that sensor nodes open after a transmission in order to
    * receive an ack. When the timer fires out, we check the value ack_received of the msg_tx variable.
    * If the ack has not been received, we retransmit it again, otherwise we do nothing.
    */
    event void Timer2.fired() {
    
        // Pointer to globalpacket (message_t variable) is declared and assigned to payload_p 
        sense_msg_t* payload_p = (sense_msg_t*)call Packet.getPayload(&globalpacket, sizeof(sense_msg_t));
        uint16_t addr = 0;

        if (payload_p == NULL){
            return;
        }

        printf("[TIMER2] NODE %u: Timer fired out.\n", TOS_NODE_ID);

        if (msg_tx.ack_received == FALSE) {

            printf("[TIMER2] NODE %u: 1000ms passed and no ACK has been received. Going to retransmit...\n", TOS_NODE_ID);

            if (TOS_NODE_ID == 2 || TOS_NODE_ID == 4) {

                // Data packet is prepared for gateway 1 
                addr = 6;

                // When the first send will end successfully, this boolean will be used to check
                // if we need to send also to the second gateway (just for node 2 and 4)
                transmitted_to_second_gateway = FALSE;

            } else if (TOS_NODE_ID == 1) {

                // Data packet is prepared for gateway 1 
                addr = 6;

            } else if (TOS_NODE_ID == 3 || TOS_NODE_ID == 5){

                // Data packet is prepared for gateway 2
                addr = 7;
            
            }

            payload_p->type = msg_tx.sense_msg.type;
            payload_p->msg_id = msg_tx.sense_msg.msg_id;
            payload_p->sender = msg_tx.sense_msg.sender;
            payload_p->destination = addr;
            payload_p->data = msg_tx.sense_msg.data;

            generate_send(addr, &globalpacket);
            
        } else {

            printf("[TIMER2] NODE %u: ack has been received, so there is no need to retransmit.\n", TOS_NODE_ID);

        }
        
    }


    //***************** Receive interface *****************//
    /*
    * When a message is received by a node, this event is triggered.
    * Depending on the type of message and depending on the TOS_NODE_ID, we behave in different ways.
    * When the server receives a data message it prepares the ack and sends it back passing by the
    * gateway which forwarded the message.
    * When a gateway receives a messages check what is its type and forwards to the sensor node if it is an ack,
    * or sends it to the server if it is a data message.
    * Finally, a sensor node sets the ack_received field of msg_tx to true when receives an ack.
    */
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {

        if (len != sizeof(sense_msg_t)) {
            return bufPtr;
        } else {

            // Variable that contains the payload of the received message
            sense_msg_t* mess = (sense_msg_t*) payload;
            // Variable that will contain the payload of the message that will be sent
            sense_msg_t* new_mess = (sense_msg_t*)call Packet.getPayload(&globalpacket, sizeof(sense_msg_t));
            
            uint16_t addr = 0;

            if (new_mess == NULL) {
                printf("[RADIO_REC] NODE %u: ERROR ALLOCATING MEMORY FOR NEW MESSAGE.\n", TOS_NODE_ID);
                return bufPtr;
            }
 
            printf("[RADIO_REC] NODE %u: Received a message of type %u, ID %u.\n", TOS_NODE_ID, mess->type, mess->msg_id);
           
            if (TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5) {

                printf("[RADIO_REC] NODE %u: Received ack for message with ID %u.\n", TOS_NODE_ID, mess->msg_id);
                msg_tx.ack_received = TRUE;

            } else if(TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {
                
                if(mess->type == 0){

                    // If a gateway is receiveing a data message, it needs to forward it to the server
                    addr = SERVER_NODE;

                } else if (mess->type == 1) {
                    
                    // If a gateway is receiving an ack, it needs to send it to the sensor node which is waiting
                    addr = mess->destination;
                    
                }

                printf("[RADIO_REC] NODE %u: Gateway forwarding the received message to %u.\n", TOS_NODE_ID, addr);

                // We copy the content of the message we received in order to forward it to the defined destination
                new_mess->type = mess->type;
                new_mess->msg_id = mess->msg_id;
                new_mess->data = mess->data;
                new_mess->sender = mess->sender;
                new_mess->destination = mess->destination;

                generate_send(addr, &globalpacket);

            } else if (TOS_NODE_ID == SERVER_NODE) {
                
                // Send data over the network using Cooja        
                send_data_to_node_red(mess);
                printfflush();

                if (msg_from_sensor[mess->sender - 1].msg_id != mess->msg_id) {

                    printf("[SERVER] Generating the ack of the message sent by %u with ID %u.\n", mess->sender, mess->msg_id);

                    msg_from_sensor[mess->sender - 1].msg_id = mess->msg_id;
                    msg_from_sensor[mess->sender - 1].gateway = mess->destination;
                    msg_from_sensor[mess->sender - 1].retransmitted = FALSE;

                    new_mess->type = 1;
                    new_mess->msg_id = mess->msg_id;
                    new_mess->data = 0;
                    new_mess->sender = mess->destination;
                    new_mess->destination = mess->sender;
                        
                    addr = new_mess->sender;
                    generate_send(addr, &globalpacket);
                
                } else if (msg_from_sensor[mess->sender - 1].gateway == mess->destination &&
                    msg_from_sensor[mess->sender - 1].retransmitted == FALSE) {

                    printf("[SERVER] Retransmitting the ack of the message sent by %u with ID %u.\n", mess->sender, mess->msg_id);

                    msg_from_sensor[mess->sender - 1].retransmitted = TRUE;

                    new_mess->type = 1;
                    new_mess->msg_id = mess->msg_id;
                    new_mess->data = 0;
                    new_mess->sender = mess->destination;
                    new_mess->destination = mess->sender;

                    addr = new_mess->sender;
                    generate_send(addr, &globalpacket);

                } else {

                    printf("[SERVER] The received message with ID %u sent by %u is a duplicate, discarding it...\n", mess->msg_id, mess->sender);

                }

            }
            
            return bufPtr;
        }
    }
}
