#ifndef SENSE_NET_H
#define SENSE_NET_H

typedef nx_struct sense_msg {
  nx_uint8_t type;
  nx_uint16_t msg_id;
  nx_uint16_t data;
  nx_uint16_t sender;
  nx_uint16_t destination;
} sense_msg_t;

typedef nx_struct list_msg {
  sense_msg_t sense_msg;
  bool ack_received;
} list_msg;

enum {
  AM_RADIO_COUNT_MSG = 10,
};

#endif