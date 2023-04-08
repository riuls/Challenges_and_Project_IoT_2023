import socket

from scapy.contrib.coap import CoAP
from scapy.contrib.mqtt import MQTT
from scapy.layers.inet import IP, TCP
from scapy.utils import rdpcap


# Returns all the packets that have a CoAP layer, so that are sent using CoAP as communication protocol
def get_coap(ps):
    good_ps = []
    for p in ps:
        if p.haslayer(CoAP):
            good_ps.append(p)
    return good_ps


# Returns all the packets that have a MQTT layer, so that are sent using MQTT as communication protocol
def get_mqtt(ps):
    good_ps = []
    for p in ps:
        if p.haslayer(MQTT):
            good_ps.append(p)
    return good_ps


# Returns 0 if it is a successful response, 0 if it is a client error, 2 if it is a server error
def type_of_coap_response(p):
    if p[CoAP].code == 65 or p[CoAP].code == 66 or p[CoAP].code == 67 or p[CoAP].code == 68 or p[CoAP].code == 69:
        return 0
    elif p[CoAP].code == 128 or p[CoAP].code == 129 or p[CoAP].code == 130 or p[CoAP].code == 131 or \
            p[CoAP].code == 132 or p[CoAP].code == 133 or p[CoAP].code == 134 or p[CoAP].code == 140 or \
            p[CoAP].code == 141 or p[CoAP].code == 143:
        return 1
    elif p[CoAP].code == 160 or p[CoAP].code == 161 or p[CoAP].code == 162 or p[CoAP].code == 163 or \
            p[CoAP].code == 164 or p[CoAP].code == 165:
        return 2


# Returns all the packets that are sent to the specified destination
def filter_by_destination(ps, dst):
    good_ps = []
    for p in ps:
        if p.haslayer(IP):
            if p[IP].dst == dst:
                good_ps.append(p)
    return good_ps


# Returns the list of packets that are of the requested function
def filter_by_coap_code(ps, c):
    # Map of the input for the type-based filter
    if c == "GET":
        code = 1
    elif c == "POST":
        code = 2
    elif c == "PUT":
        code = 3
    elif c == "DELETE":
        code = 4

    good_ps = []
    for p in ps:
        if p[CoAP].code == code:
            good_ps.append(p)
    return good_ps


# Returns the list of packets that are of the requested type
def filter_by_coap_type(ps, t):
    if t == "CON":
        tp = 0
    elif t == "NON":
        tp = 1
    elif t == "ACL":
        tp = 2
    elif t == "RST":
        tp = 3

    good_ps = []
    for p in ps:
        if p[CoAP].type == tp:
            good_ps.append(p)
    return good_ps


# Returns the list of packets directed to the specified topic
def filter_coap_by_uri_path(ps, uri):
    good_ps = []
    for p in ps:
        if p[CoAP].options[0][1].decode() == uri:
            good_ps.append(p)
    return good_ps


# Returns the list of packets that contain the 404 error message
def not_found_coap_messages(ps):
    good_ps = []
    for p in ps:
        if p[CoAP].code == 132:
            good_ps.append(p)
    return good_ps


# Returns the list of packets that are unsuccessful
def unsuccessful_coap_messages(ps):
    good_ps = []
    for p in ps:
        if type_of_coap_response(p) == 1 or type_of_coap_response(p) == 2:
            good_ps.append(p)
    return good_ps


# Given a type of response, returns the list of packets that are the requests that generated those responses
def coap_request_that_receive_particular_response(requests, responses):
    good_ps = []
    for g in requests:
        for n in responses:
            if g[CoAP].msg_id == n[CoAP].msg_id:
                good_ps.append(g)
    non = filter_by_coap_type(requests, "NON")
    for p in non:
        for n in responses:
            if p[CoAP].token == n[CoAP].token:
                good_ps.append(p)
    return good_ps


# Returns the list of packets that are of the requested type
def filter_by_mqtt_type(ps, t):
    if t == "CONNECT":
        tp = 1
    elif t == "CONNACK":
        tp = 2
    elif t == "PUBLISH":
        tp = 3
    elif t == "PUBACK":
        tp = 4
    elif t == "PUBREC":
        tp = 5
    elif t == "PUBREL":
        tp = 6
    elif t == "PUBCOMP":
        tp = 7
    elif t == "SUBSCRIBE":
        tp = 8
    elif t == "SUBACK":
        tp = 9
    elif t == "UNSUBSCRIBE":
        tp = 10
    elif t == "UNSUBACK":
        tp = 11
    elif t == "PINGREQ":
        tp = 12
    elif t == "PINGRESP":
        tp = 13
    elif t == "DISCONNECT":
        tp = 14
    elif t == "AUTH":
        tp = 15

    good_ps = []
    for p in ps:
        if p[MQTT].type == tp:
            good_ps.append(p)
    return good_ps


# Algorithm to answer to the first question
def question_one(packets):
    # We get all the packets that used CoAP as communication protocol
    coap = get_coap(packets)
    # We filter the previous list, keeping those packets sent to localhost
    local = filter_by_destination(coap, "127.0.0.1")
    # We filter the previous list, keeping those packets that are GET requests
    get_msgs = filter_by_coap_code(local, "GET")
    # Starting from coap messages sent to localhost, we keep those packets that contain a 404 error message
    not_found_msgs = not_found_coap_messages(local)

    # We get the answer to the first part of the question
    answer_a = coap_request_that_receive_particular_response(get_msgs, not_found_msgs)

    # Starting from get messages sent to localhost, we keep those packets that are of type non-confirmable
    non_confirmable_get_msgs = filter_by_coap_type(get_msgs, "NON")

    # We get the answer to the second part of the question
    answer_b = coap_request_that_receive_particular_response(non_confirmable_get_msgs, not_found_msgs)

    print('Question 1.')
    print('Q: How many CoAP GET requests are directed to non-existing resources in the local CoAP server?')
    print(f'A: {len(answer_a)}')
    print('Q: How many of these requests are of type Non confirmable?')
    print(f'A: {len(answer_b)}')


# Algorithm to answer to the second question
def question_two(packets):
    # We get all the packets that used CoAP as communication protocol
    coap = get_coap(packets)
    # We filter the previous list, keeping those messages that are DELETE requests that are sent to coap.me
    delete_message_to_coap_me = filter_by_coap_code(
        filter_by_destination(coap, socket.getaddrinfo("coap.me", None)[0][4][0]), "DELETE")
    # Starting from all the CoAP messages, we get all the unsuccessful responses
    unsuccessful_msgs = unsuccessful_coap_messages(coap)

    # We get the answer to the first part of the question
    answer_a = coap_request_that_receive_particular_response(delete_message_to_coap_me, unsuccessful_msgs)

    # We get the answer to the second part of the question
    answer_b = filter_coap_by_uri_path(answer_a, "hello")

    print('Question 2.')
    print('Q: How many CoAP DELETE requests directed to the "coap.me" server did not produce a successful result?')
    print(f'A: {len(answer_a)}')
    print('Q: How many of these are directed to the "/hello" resource?')
    print(f'A: {len(answer_b)}')


# Algorithm to answer to the third question
def question_three(packets):
    # We get all the packets that used MQTT as communication protocol
    mqtt = get_mqtt(packets)
    # Starting from the previous list, we keep those that are sent to the public broker test.mosquitto.org
    mqtt_mosquitto = filter_by_destination(mqtt, socket.getaddrinfo("test.mosquitto.org", None)[0][4][0])
    # We filter the previous list, keeping those packets that are SUBSCRIBE requests
    mqtt_mosquitto_sub = filter_by_mqtt_type(mqtt_mosquitto, "SUBSCRIBE")

    # If there is a subscription using a single level wildcard, we save the port of the client, in order to keep a list
    # of all the different clients
    ports = []
    for m in mqtt_mosquitto_sub:
        topic = m[MQTT].topics[0].topic.decode()
        if '+' in topic:
            if m[TCP].sport not in ports:
                ports.append(m[TCP].sport)

    print('Question 3.')
    print('Q: How many different MQTT clients subscribe to the public broker mosquitto using single-level wildcards?')
    print(f'A: {len(ports)}')
    # The second part of the question has been done "manually" using Wireshark
    print('Q: How many of these clients WOULD receive a publish message issued to the topic "hospital/room2/area0“?')
    print(f'A: The ports assigned to the clients are {ports[0]}, {ports[1]}, and {ports[2]}. '
          f'We get from wireshark that the answer is 2')


# Algorithm to answer to the fourth question
def question_four(packets):
    # We get all the packets that used MQTT as communication protocol
    mqtt = get_mqtt(packets)
    # We filter the previous list, keeping those packets that are CONNECT requests, in order to check which of them set
    # the lastWillMessage flag to 1
    mqtt_connect = filter_by_mqtt_type(mqtt, "CONNECT")
    # We save all the clients that connected to a topic that starts with university and that had to 1 the
    # lastWillMessage flag
    answer_a = []
    for m in mqtt_connect:
        if m[MQTT].willflag == 1 and m[MQTT].willtopic.decode().startswith("university"):
            answer_a.append(m)
    # We save the content of lastWillMessages
    lwmsgs = []
    for m in answer_a:
        lwmsgs.append(m[MQTT].willmsg.decode())

    # We check which of the previous lwm has been sent back
    lwm_sent_back = []
    mqtt_pub = filter_by_mqtt_type(mqtt, "PUBLISH")
    for m in mqtt_pub:
        for l in lwmsgs:
            if m[MQTT].value.decode() == l:
                lwm_sent_back.append(l)

    print('Question 4.')
    print(
        'Q: How many MQTT clients specify a last Will Message directed to a topic having as first level "university"?')
    print(f'A: {len(answer_a)}')
    print('Q: How many of these Will Messages are sent from the broker to the subscribers?')
    print(f'A: {len(lwm_sent_back)}')


if __name__ == '__main__':
    # Load the pcapng file
    pcapng = rdpcap('resources/challenge2023_1.pcapng')

    # Answer to the questions
    question_one(pcapng)
    question_two(pcapng)
    question_three(pcapng)
    question_four(pcapng)

    print('For the answers of question 5 and 6 check the pdf, I have answered to them working "manually" on Wireshark')
