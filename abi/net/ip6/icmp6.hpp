#pragma once

#include "../class_packet.hpp"
#include "../util.hpp"
#include "ip6.hpp"

namespace net
{
  class PacketICMP6;
  
  class ICMPv6
  {
  public:
    static const int ECHO_REQUEST = 128;
    static const int ECHO_REPLY   = 129;
    
    
    ICMPv6(IP6::addr& local_ip)
      : localIP(local_ip) {}
    
    struct header
    {
      uint8_t  type_;
      uint8_t  code_;
      uint16_t checksum_;
    };
    struct pseudo_header
    {
      IP6::addr src;
      IP6::addr dst;
      uint32_t  len;
      uint8_t   zeroes[3];
      uint8_t   next;
    };
    
    struct icmp6_echo
    {
      uint8_t  type;
      uint8_t  code;
      uint16_t checksum;
      uint16_t identifier;
      uint16_t sequence;
      uint8_t  data[0];
    };
    
    // handles ICMP type 128 (echo requests)
    int echo_request(std::shared_ptr<PacketICMP6>& pckt);
    
    // packet from IP6 layer
    int bottom(std::shared_ptr<Packet>& pckt);
    
    // set the downstream delegate
    inline void set_ip6_out(downstream del)
    {
      this->ip6_out = del;
    }
    
    // message types & codes
    static inline bool is_error(uint8_t type)
    {
      return type < 128;
    }
    static std::string code_string(uint8_t type, uint8_t code);
    
    // calculate checksum of any ICMP message
    static uint16_t checksum(std::shared_ptr<PacketICMP6>& pckt);
    
  private:
    // connection to IP6 layer
    downstream ip6_out;
    // IP6 instance
    IP6::addr localIP;
  };
  
  class PacketICMP6 : public Packet
  {
  public:
    inline ICMPv6::header& header()
    {
      return *(ICMPv6::header*) this->payload();
    }
    inline const ICMPv6::header& header() const
    {
      return *(ICMPv6::header*) this->payload();
    }
    
    uint8_t type() const
    {
      return header().type_;
    }
    uint8_t code() const
    {
      return header().code_;
    }
    uint16_t checksum() const
    {
      return ntohs(header().checksum_);
    }
    
    // transformed back to normal packet
    std::shared_ptr<Packet>& packet()
    {
      return *reinterpret_cast<std::shared_ptr<Packet>*>(this);
    }
 };
  
}
