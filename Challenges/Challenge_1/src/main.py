from scapy.contrib.coap import CoAP
from scapy.layers.inet import IP
from scapy.utils import rdpcap
import socket


def filter_by_destination(ps, dst):
    good_ps = []
    for p in ps:
        if p.haslayer(IP):
            if p[IP].dst == dst:
                good_ps.append(p)
    return good_ps


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
        if p.haslayer(CoAP):
            if p[CoAP].code == code:
                good_ps.append(p)
    return good_ps


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
        if p.haslayer(CoAP):
            if p[CoAP].type == tp:
                good_ps.append(p)
    return good_ps


def not_found_messages(ps):
    good_ps = []
    for p in ps:
        if p.haslayer(CoAP):
            if p[CoAP].code == 132:
                good_ps.append(p)
    return good_ps


# Filters a list of packets, keeping the ones that are get coap requests which receive a 404 not found response
def not_found_messages_of_coap_get_requests(get_ps, not_found_ps):
    good_ps = []
    for g in get_ps:
        for n in not_found_ps:
            if g[CoAP].msg_id == n[CoAP].msg_id:
                good_ps.append(g)
    non = filter_by_coap_type(get_ps, "NON")
    for p in non:
        for n in not_found_ps:
            if p[CoAP].token == n[CoAP].token:
                good_ps.append(p)
    return good_ps


def question_one(packets):
    l = filter_by_destination(packets, "127.0.0.1")
    get_msgs = filter_by_coap_code(l, "GET")
    not_found_msgs = not_found_messages(l)
    answer_a = not_found_messages_of_coap_get_requests(get_msgs, not_found_msgs)
    non_confirmable_get_msgs = filter_by_coap_type(get_msgs, "NON")
    answer_b = not_found_messages_of_coap_get_requests(non_confirmable_get_msgs, not_found_msgs)
    print(len(answer_a))
    print(len(answer_b))


def question_two(packets):
    delete_message_to_coap_me = filter_by_coap_code(
        filter_by_destination(packets, socket.getaddrinfo("coap.me", None)[0][4][0]), "DELETE")
    print(len(delete_message_to_coap_me))


if __name__ == '__main__':
    # Load the pcapng file
    pcapng = rdpcap('resources/challenge2023_1.pcapng')
    # question_one(pcapng)
    question_two(pcapng)
