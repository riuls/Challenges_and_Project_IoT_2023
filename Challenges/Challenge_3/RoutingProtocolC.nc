#include "DataMessage.h"

module {

    uses {

        interface Boot;

        interface SplitControl;
        interface Packet;
        interface AMSend;
        interface Receive;

    }

} implementation {

    message_t packet;

    uint16_t routing_table[6][3];

    // Each node will have its table initialized when the device is started.
    // In particular, all the nodes that we know do belong to the network are inserted into the table,
    // except for self references, checked with the TOS_NODE_ID.
    // Finally, both the next hop column and the cost column are set to UINT16_MAX, that means that
    // the values are not initialized.
    void initialize_routing_table() {

        for (int i = 0; i < 7; i++) {
            if (i + 1 != TOS_NODE_ID) {
                routing_table[i][0] = i + 1;
                routing_table[i][1] = UINT16_MAX;
                routing_table[i][2] = UINT16_MAX;
            }
        }

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

    //***************** Boot interface ********************//
    event void Boot.booted() {

        // TODO print something for the debugging
        call SplitControl.start();

    }
    
    //************** SplitControl interface ***************//
    event void SplitControl.startDone(error_t err) {
      
        if(err == SUCCESS) {
            // TODO print something for the debugging
	        initialize_routing_table();
  	    } else {
	        // TODO print something for the debugging
	        call SplitControl.start();
        }

    }

    // this must be here, no questions needed
    event void SplitControl.stopDone(error_t err){}

    //****************** Read interface *******************//
    event void AMSend.sendDone(message_t* buf, error_t error) {
        
        if (&packet == buf && error == SUCCESS) {
            dbg("radio_send", "Packet sent...");
            dbg_clear("radio_send", " at time %s \n", sim_time_string());
        } else {
            dbgerror("radio_send", "Send done error!");
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