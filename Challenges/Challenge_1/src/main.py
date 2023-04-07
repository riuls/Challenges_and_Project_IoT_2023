import socket

from scapy.contrib.coap import CoAP
from scapy.layers.inet import IP
from scapy.utils import rdpcap


def get_coap(ps):
    good_ps = []
    for p in ps:
        if p.haslayer(CoAP):
            good_ps.append(p)
    return good_ps


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
        if p[CoAP].type == tp:
            good_ps.append(p)
    return good_ps


def filter_coap_by_uri_path(ps, uri):
    good_ps = []
    for p in ps:
        if p[CoAP].options[0][1].decode() == uri:
            good_ps.append(p)
    return good_ps


def not_found_coap_messages(ps):
    good_ps = []
    for p in ps:
        if p[CoAP].code == 132:
            good_ps.append(p)
    return good_ps


def unsuccessful_coap_messages(ps):
    good_ps = []
    for p in ps:
        if type_of_coap_response(p) == 1 or type_of_coap_response(p) == 2:
            good_ps.append(p)
    return good_ps


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


def question_one(packets):
    coap = get_coap(packets)
    local = filter_by_destination(coap, "127.0.0.1")

    get_msgs = filter_by_coap_code(local, "GET")
    not_found_msgs = not_found_coap_messages(local)
    non_confirmable_get_msgs = filter_by_coap_type(get_msgs, "NON")

    answer_a = coap_request_that_receive_particular_response(get_msgs, not_found_msgs)
    answer_b = coap_request_that_receive_particular_response(non_confirmable_get_msgs, not_found_msgs)

    print('Question 1.')
    print('Q: How many CoAP GET requests are directed to non-existing resources in the local CoAP server?')
    print(f'A: {len(answer_a)}')
    print('Q: How many of these requests are of type Non confirmable?')
    print(f'A: {len(answer_b)}')


def question_two(packets):
    coap = get_coap(packets)
    delete_message_to_coap_me = filter_by_coap_code(
        filter_by_destination(coap, socket.getaddrinfo("coap.me", None)[0][4][0]), "DELETE")
    unsuccessful_msgs = unsuccessful_coap_messages(coap)
    answer_a = coap_request_that_receive_particular_response(delete_message_to_coap_me, unsuccessful_msgs)
    answer_b = filter_coap_by_uri_path(answer_a, "hello")
    print('Question 2.')
    print('Q: How many CoAP DELETE requests directed to the "coap.me" server did not produce a successful result?')
    print(f'A: {len(answer_a)}')
    print('Q: How many of these are directed to the "/hello" resource?')
    print(f'A: {len(answer_b)}')


def question_three(packets):
    print('Question 3.')


def question_four(packets):
    print('Question 4.')


def question_five(packets):
    print('Question 5.')


def question_six(packets):
    print('Question 6.')


if __name__ == '__main__':
    # Load the pcapng file
    pcapng = rdpcap('resources/challenge2023_1.pcapng')

    # Answer to the questions
    question_one(pcapng)
    question_two(pcapng)
    question_three(pcapng)
    question_four(pcapng)
    question_five(pcapng)
    question_six(pcapng)
