#ifndef SENSE_NET_H
#define SENSE_NET_H

typedef nx_struct msg {
	nx_uint8_t type;
  nx_uint16_t msg_id;
  nx_uint16_t data;
  nx_uint16_t sender;
  nx_uint16_t destination;
  nx_uint16_t gateway;
} payload_t;

enum {
  AM_RADIO_COUNT_MSG = 10,
};

#endif