#include "DataMessage.h"

configuration RoutingProtocolAppC {}

implementation {

    components MainC, RoutingProtocolC as App;

    components ActiveMessageC;
    components AMSenderC(AM_SEND_MSG);
    components AMReceiverC(AM_SEND_MSG);

    //Boot interface
    App.Boot -> MainC.Boot;

    //Radio control
    App.SplitControl -> AcriveMessageC;
    App.AMSend -> AMSender;
    App.Packet -> AMSenderC;
    App.Receive -> AMReceiverC;
    
}