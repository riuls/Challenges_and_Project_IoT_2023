#include "SenseNet.h"

configuration SenseNetAppC {}

implementation {

    components MainC, SenseNetC as App;

    components ActiveMessageC;
    components new AMSenderC(AM_RADIO_COUNT_MSG);
    components new AMReceiverC(AM_RADIO_COUNT_MSG);

    components new TimerMilliC() as Timer0;
    components new TimerMilliC() as Timer1;
    components new TimerMilliC() as Timer2;

    components RandomC as Random;

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
    App.Timer2 -> Timer2;

    // Random
    App.Random -> Random;
    
}