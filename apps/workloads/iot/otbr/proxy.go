package main

import (
	"encoding/binary"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func checksum(data []byte) uint16 {
	var sum uint32
	for i := 0; i < len(data)-1; i += 2 {
		sum += uint32(binary.BigEndian.Uint16(data[i : i+2]))
	}
	if len(data)%2 == 1 {
		sum += uint32(data[len(data)-1]) << 8
	}
	for sum>>16 > 0 {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	return ^uint16(sum)
}

func htons(i uint16) uint16 {
	return (i<<8)&0xff00 | (i>>8)&0xff
}

func ipv6PseudoHeader(src, dst []byte, payloadLen uint32, nextHeader uint8) []byte {
	ph := make([]byte, 40)
	copy(ph[0:16], src)
	copy(ph[16:32], dst)
	binary.BigEndian.PutUint32(ph[32:36], payloadLen)
	ph[39] = nextHeader
	return ph
}

func makeIPv6UDPPacket(srcIP, dstIP net.IP, srcPort, dstPort uint16, payload []byte) []byte {
	udpLen := len(payload) + 8
	ph := ipv6PseudoHeader(srcIP.To16(), dstIP.To16(), uint32(udpLen), 17) // 17 is UDP

	udpHeader := make([]byte, 8)
	binary.BigEndian.PutUint16(udpHeader[0:2], srcPort)
	binary.BigEndian.PutUint16(udpHeader[2:4], dstPort)
	binary.BigEndian.PutUint16(udpHeader[4:6], uint16(udpLen))
	
	chkData := append(ph, udpHeader...)
	chkData = append(chkData, payload...)
	chk := checksum(chkData)
	if chk == 0 {
		chk = 0xffff
	}
	binary.BigEndian.PutUint16(udpHeader[6:8], chk)

	ipv6Header := make([]byte, 40)
	binary.BigEndian.PutUint32(ipv6Header[0:4], 0x60000000)
	binary.BigEndian.PutUint16(ipv6Header[4:6], uint16(udpLen))
	ipv6Header[6] = 17 // NextHeader: UDP
	ipv6Header[7] = 64 // HopLimit
	copy(ipv6Header[8:24], srcIP.To16())
	copy(ipv6Header[24:40], dstIP.To16())

	packet := append(ipv6Header, udpHeader...)
	packet = append(packet, payload...)
	return packet
}

type clientMapping struct {
	clientIP   net.IP
	clientPort uint16
	clientMAC  []byte
	targetIP   net.IP
	conn       *net.UDPConn
}

func main() {
	fmt.Println("User-space Thread UDP NAT Proxy (Go version) starting...")

	// 1. Raw RX Socket (AF_PACKET)
	rxFd, err := syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW, int(htons(0x86DD)))
	if err != nil {
		fmt.Printf("Failed to create RX socket: %v\n", err)
		os.Exit(1)
	}
	defer syscall.Close(rxFd)

	ifi, err := net.InterfaceByName("net1")
	if err != nil {
		fmt.Printf("Failed to get net1 interface: %v\n", err)
		os.Exit(1)
	}

	addr := &syscall.SockaddrLinklayer{
		Protocol: htons(0x86DD),
		Ifindex:  ifi.Index,
	}
	if err := syscall.Bind(rxFd, addr); err != nil {
		fmt.Printf("Failed to bind RX socket: %v\n", err)
		os.Exit(1)
	}

	// (Raw TX Socket not needed, reusing AF_PACKET rxFd for sending)

	mappings := make(map[uint16]*clientMapping)
	
	rxChan := make(chan []byte, 1024)
	replyChan := make(chan struct {
		port    uint16
		payload []byte
		addr    *net.UDPAddr
	}, 1024)

	// Read loop for RX raw socket
	go func() {
		buf := make([]byte, 65536)
		for {
			n, _, err := syscall.Recvfrom(rxFd, buf, 0)
			if err != nil {
				time.Sleep(10 * time.Millisecond)
				continue
			}
			if n > 0 {
				packetCopy := make([]byte, n)
				copy(packetCopy, buf[:n])
				rxChan <- packetCopy
			}
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	fmt.Println("User-space Thread UDP NAT Proxy started.")

	for {
		select {
		case packet := <-rxChan:
			if len(packet) < 62 { // 14 (Ethernet) + 40 (IPv6) + 8 (UDP)
				continue
			}
			ipHeader := packet[14:54]
			nextHeader := ipHeader[6]
			if nextHeader != 17 {
				continue
			}
			srcIP := net.IP(ipHeader[8:24])
			dstIP := net.IP(ipHeader[24:40])

			udpHeader := packet[54:62]
			srcPort := binary.BigEndian.Uint16(udpHeader[0:2])
			dstPort := binary.BigEndian.Uint16(udpHeader[2:4])
			udpLen := binary.BigEndian.Uint16(udpHeader[4:6])

			if dstPort == 5540 && (dstIP[0] == 0xfd || dstIP[0] == 0xfc) {
				payload := packet[62 : 62+int(udpLen-8)]

				clientMAC := make([]byte, 6)
				copy(clientMAC, packet[6:12]) // Source MAC in Ethernet header

				mapping, exists := mappings[srcPort]
				if !exists {
					fmt.Printf("Mapping new client: %s:%d -> %s:5540\n", srcIP.String(), srcPort, dstIP.String())
					conn, err := net.ListenUDP("udp6", &net.UDPAddr{IP: net.IPv6unspecified})
					if err != nil {
						fmt.Printf("Failed to bind UDP socket: %v\n", err)
						continue
					}
					
					mapping = &clientMapping{
						clientIP:   srcIP,
						clientPort: srcPort,
						clientMAC:  clientMAC,
						targetIP:   dstIP,
						conn:       conn,
					}
					mappings[srcPort] = mapping

					go func(p uint16, c *net.UDPConn) {
						replyBuf := make([]byte, 65536)
						for {
							n, raddr, err := c.ReadFromUDP(replyBuf)
							if err != nil {
								break
							}
							if n > 0 {
								fmt.Printf("[<-] Received Thread Reply from %s:%d for client port %d (%d bytes)\n", raddr.IP.String(), raddr.Port, p, n)
								payloadCopy := make([]byte, n)
								copy(payloadCopy, replyBuf[:n])
								replyChan <- struct {
									port    uint16
									payload []byte
									addr    *net.UDPAddr
								}{port: p, payload: payloadCopy, addr: raddr}
							}
						}
					}(srcPort, conn)
				}

				raddr := &net.UDPAddr{IP: dstIP, Port: 5540}
				fmt.Printf("[->] Forwarding client packet to Thread: %s:%d -> %s:5540 (%d bytes)\n", srcIP.String(), srcPort, dstIP.String(), len(payload))
				_, _ = mapping.conn.WriteTo(payload, raddr)
			}

		case reply := <-replyChan:
			mapping, exists := mappings[reply.port]
			if exists {
				// Build Ethernet header
				ethHeader := make([]byte, 14)
				copy(ethHeader[0:6], mapping.clientMAC)
				copy(ethHeader[6:12], ifi.HardwareAddr)
				binary.BigEndian.PutUint16(ethHeader[12:14], 0x86DD)

				rawPacket := makeIPv6UDPPacket(reply.addr.IP, mapping.clientIP, 5540, mapping.clientPort, reply.payload)
				rawFrame := append(ethHeader, rawPacket...)

				destAddr := &syscall.SockaddrLinklayer{
					Protocol: htons(0x86DD),
					Ifindex:  ifi.Index,
				}
				fmt.Printf("[<-] Forwarding reply to client: %s:%d (%d bytes)\n", mapping.clientIP.String(), mapping.clientPort, len(reply.payload))
				_ = syscall.Sendto(rxFd, rawFrame, 0, destAddr)
			}

		case <-sigChan:
			fmt.Println("Stopping proxy.")
			return
		}
	}
}
