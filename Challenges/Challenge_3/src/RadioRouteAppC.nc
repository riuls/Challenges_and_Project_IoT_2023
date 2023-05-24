#include "RadioRoute.h"

configuration RadioRouteAppC {}

implementation {

    components MainC, RadioRouteC as App;

    components ActiveMessageC;
    components AMSenderC(AM_RADIO_COUNT_MSG);
    components AMReceiverC(AM_RADIO_COUNT_MSG);

    components new TimerMilliC() as Timer0;
    components new TimerMilliC() as Timer1;

    //Boot interface
    App.Boot -> MainC.Boot;

    //Radio control
    App.SplitControl -> AcriveMessageC;
    App.AMSend -> AMSender;
    App.Packet -> AMSenderC;
    App.Receive -> AMReceiverC;

    App.Timer0 -> Timer0;
    App.Timer1 -> Timer1;

    App.Leds -> LedsC;
    
}