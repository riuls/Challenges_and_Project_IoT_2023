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

    message_t packet;

    // Variables to store the message to send
    message_t queued_packet;
    uint16_t queue_addr;

    //Time delay in milli seconds
    uint16_t time_delays[7] = {61,173,267,371,479,583,689};

    bool route_req_sent=FALSE;
    bool route_rep_sent=FALSE;

    bool locked;

    uint16_t routing_table[6][3];

    /* 
    * Each node will have its table initialized when the device is started.
    * In particular, all the nodes that we know do belong to the network are inserted into the table,
    * except for self references, checked with the TOS_NODE_ID.
    * Finally, both the next hop column and the cost column are set to UINT16_MAX, that means that
    * the values are not initialized.
    */
    void initialize_routing_table() {

        for (int i = 0; i < 7; i++) {
            if (i + 1 != TOS_NODE_ID) {
                routing_table[i][0] = i + 1;
                routing_table[i][1] = UINT16_MAX;
                routing_table[i][2] = UINT16_MAX;
            }
        }

    }

    /*
    * Function to be used when performing the send after the receive message event.
    * It store the packet and address into a global variable and start the timer execution to schedule the send.
    * It allow the sending of only one message for each REQ and REP type
    * @Input:
    *		address: packet destination address
    *		packet: full packet to be sent (Not only Payload)
    *		type: payload message type
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

    bool actual_send (uint16_t address, message_t* packet){
        /*
        * Implement here the logic to perform the actual send of the packet using the tinyOS interfaces
        */  
    }


    //***************** Boot interface ********************//
    event void Boot.booted() {

        dbg("boot","Application booted.\n");
        
        call AMControl.start();

    }


    //*************** AMControl interface *****************//
    event void AMControl.startDone(error_t err) {
        
        if(err == SUCCESS) {
            // TODO print something for the debugging

	        initialize_routing_table();
            // TODO after the radio is ON we should start counting in order to send the first req from 1 to 7

  	    } else {
	        // TODO print something for the debugging
	        
            call AMControl.start();
        }

    }

    event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	/* This event is triggered when a message is sent 
	*  Check if the packet is sent 
	*/ 

        if (&packet == buf && error == SUCCESS) {
            dbg("radio_send", "Packet sent...");
            dbg_clear("radio_send", " at time %s \n", sim_time_string());
        } else {
            dbgerror("radio_send", "Send done error!");
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

    event void Timer1.fired() {
	/*
	* Implement here the logic to trigger the Node 1 to send the first REQ packet
	*/
    }


    //***************** Receive interface *****************//
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
	/*
	* Parse the receive packet.
	* Implement all the functionalities
	* Perform the packet send using the generate_send function if needed
	* Implement the LED logic and print LED status on Debug
	*/
	
    }











    

    // TODO comments
    void sendData(uint8_t type, uint16_t sender, uint16_t destination, uint16_t value) {

	    data_msg_t* mess = (data_msg_t*)(call Packet.getPayload(&packet, sizeof(data_msg_t)));
	    
        if (mess == NULL) {
	        return;
	    }

        // we want to send a ROUTE_REQ message
        if (type == 1) {
            mess->type = type;
            mess->sender = sender;
            mess->destination = -1;
            mess->value = -1;
        } 
        // we want to send a ROUTE_REPLY message
        else if (type == 2) {
            mess->type = type;
            mess->sender = sender;
            mess->destination = destination;
            mess->value = value;
        } 
        // error: we can just send ROUTE_REQ or ROUTE_REPLY messages
        else {
            // TODO print something for the debugging
            return;
        }
	  
	    // we send the created packet
	    if(call AMSend.send(AM_BROADCAST_ADDR, &packet,sizeof(data_msg_t)) == SUCCESS){
            // TODO print something fot the debugging
  	    }

    }

    // TODO comments
    event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
	
        if (len != sizeof(data_msg_t)) {
            return bufPtr;
        } else {
            data_msg_t* mess = (data_msg_t*)payload;

            // TODO in general, print something for the debugging

            // we receive a ROUTE_REQ message
            if (mess->type == 1) {
                // TODO implement the behaviour the node should have when receiving a ROUTE_REQ
            }
            // we receive a ROUTE_REPLY message
            else if (mess->type == 2) {
                // TODO implement the behaviour the node should have when receiving a ROUTE_REPLY
            } 
            // we are receiving that does not make sense
            else {

            }
     
            return bufPtr;
        }

    }

}