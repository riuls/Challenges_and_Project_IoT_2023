#include "RadioRoute.h"

configuration RadioRouteAppC {}

implementation {

    components MainC, RadioRouteC as App, LedsC;

    components ActiveMessageC;
    components new AMSenderC(AM_RADIO_COUNT_MSG);
    components new AMReceiverC(AM_RADIO_COUNT_MSG);

    components new TimerMilliC() as Timer0;
    components new TimerMilliC() as Timer1;

    //Boot interface
    App.Boot -> MainC.Boot;

    //Radio control
    App.AMControl -> ActiveMessageC;
    App.AMSend -> AMSenderC;
    App.Packet -> AMSenderC;
    App.Receive -> AMReceiverC;

    // Timer
    App.Timer0 -> Timer0;
    App.Timer1 -> Timer1;

    // Random number generator
    App.Random -> RandomC;
    
}