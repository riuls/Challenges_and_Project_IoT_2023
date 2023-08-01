print "********************************************"
print "*                                          *"
print "*             TOSSIM Script                *"
print "*                                          *"
print "********************************************"

import sys
import time

from TOSSIM import *

t = Tossim([])


topofile = "topology.txt"
modelfile = "meyer-heavy.txt"


print "Initializing mac...."
mac = t.mac()
print "Initializing radio channels...."
radio = t.radio()
print "    using topology file:", topofile;
print "    using noise file:", modelfile;
print "Initializing simulator...."
t.init()


simulation_outfile = "simulation.txt"
print "Saving sensors simulation output to:", simulation_outfile;
#simulation_out = open(simulation_outfile, "w");

#out = open(simulation_outfile, "w")
out = sys.stdout;

# Add debug channel
print "Activate debug message on channel init"
t.addChannel("init", out)
print "Activate debug message on channel boot"
t.addChannel("boot", out)
print "Activate debug message on channel timer0"
t.addChannel("timer0", out)
print "Activate debug message on channel timer1"
t.addChannel("timer1", out)
print "Activate debug message on channel timer2"
t.addChannel("timer2", out)
print "Activate debug message on channel radio send"
t.addChannel("radio_send", out)
print "Activate debug message on channel radio receive"
t.addChannel("radio_rec", out)
print "Activate debug message on channel server"
t.addChannel("server", out)


print "Creating node 1..."
node1 = t.getNode(1)
time1 = 0  # instant at which each node should be turned on
node1.bootAtTime(time1)
print ">>>Will boot at time", time1, "[sec]"

print "Creating node 2..."
node2 = t.getNode(2)
time2 = 0
node2.bootAtTime(time2)
print ">>>Will boot at time", time2, "[sec]"

print "Creating node 3..."
node3 = t.getNode(3)
time3 = 0  # instant at which each node should be turned on
node3.bootAtTime(time3)
print ">>>Will boot at time", time3, "[sec]"

print "Creating node 4..."
node4 = t.getNode(4)
time4 = 0  # instant at which each node should be turned on
node4.bootAtTime(time4)
print ">>>Will boot at time", time4, "[sec]"

print "Creating node 5..."
node5 = t.getNode(5)
time5 = 0  # instant at which each node should be turned on
node5.bootAtTime(time5)
print ">>>Will boot at time", time5, "[sec]"

print "Creating node 6..."
node6 = t.getNode(6)
time6 = 0  # instant at which each node should be turned on
node6.bootAtTime(time6)
print ">>>Will boot at time", time6, "[sec]"

print "Creating node 7..."
node7 = t.getNode(7)
time7 = 0  # instant at which each node should be turned on
node7.bootAtTime(time7)
print ">>>Will boot at time", time7, "[sec]"

print "Creating node 8..."
node8 = t.getNode(8)
time8 = 0  # instant at which each node should be turned on
node8.bootAtTime(time8)
print ">>>Will boot at time", time8, "[sec]"


print "Creating radio channels..."
f = open(topofile, "r")
lines = f.readlines()
for line in lines:
    s = line.split()
    if (len(s) > 0):
        print ">>>Setting radio channel from node ", s[0], " to node ", s[1], " with gain ", s[2], " dBm"
        radio.add(int(s[0]), int(s[1]), float(s[2]))


# creation of channel model
print "Initializing Closest Pattern Matching (CPM)..."
noise = open(modelfile, "r")
lines = noise.readlines()
compl = 0
mid_compl = 0

print "Reading noise model data file:", modelfile;
print "Loading:",
for line in lines:
    str = line.strip()
    if (str != "") and (compl < 10000):
        val = int(str)
        mid_compl = mid_compl + 1
        if (mid_compl > 5000):
            compl = compl + mid_compl
            mid_compl = 0
            sys.stdout.write("#")
            sys.stdout.flush()
        for i in range(1, 9):
            t.getNode(i).addNoiseTraceReading(val)
print "Done!"

for i in range(1, 9):
    print ">>>Creating noise model for node:", i;
    t.getNode(i).createNoiseModel()

print "Start simulation with TOSSIM! \n\n\n"

for i in range(0, 65536):
    t.runNextEvent()

print "\n\n\nSimulation finished!"
