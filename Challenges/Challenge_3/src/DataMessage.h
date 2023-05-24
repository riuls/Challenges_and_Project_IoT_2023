#ifndef DATA_MESSAGE_H
#define DATA_MESSAGE_H

typedef nx_struct data_msg {
  nx_uint8_t type;
  nx_uint16_t sender;
  nx_uint16_t destination;
  nx_uint16_t value;
} data_msg_t;

enum {
  AM_SEND_MSG = 6,
};

#endif
