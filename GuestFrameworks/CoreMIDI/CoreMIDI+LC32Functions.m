#import <CoreMIDI/CoreMIDI.h>

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#pragma clang diagnostic ignored "-Wnonnull"

MIDIPacket *MIDIPacketListInit(MIDIPacketList *packetList) {
    if(!packetList) return NULL;
    packetList->numPackets = 0;
    packetList->packet[0].timeStamp = 0;
    packetList->packet[0].length = 0;
    return &packetList->packet[0];
}

MIDIPacket *MIDIPacketListAdd(MIDIPacketList *packetList,
                              ByteCount listSize,
                              MIDIPacket *currentPacket,
                              MIDITimeStamp time,
                              ByteCount dataLength,
                              const Byte *data) {
    if(!packetList || !currentPacket || (dataLength && !data) ||
       dataLength > UINT16_MAX) {
        return NULL;
    }

    const uintptr_t listStart = (uintptr_t)packetList;
    if(listSize < offsetof(MIDIPacketList, packet) ||
       listStart > UINTPTR_MAX - listSize) {
        return NULL;
    }
    const uintptr_t listEnd = listStart + listSize;
    const uintptr_t firstPacket = (uintptr_t)&packetList->packet[0];
    const uintptr_t current = (uintptr_t)currentPacket;
    if(current < firstPacket || current >= listEnd) return NULL;

    MIDIPacket *newPacket;
    if(packetList->numPackets == 0) {
        if(currentPacket != &packetList->packet[0]) return NULL;
        newPacket = currentPacket;
    } else {
        if(current > UINTPTR_MAX - offsetof(MIDIPacket, data) -
               currentPacket->length) {
            return NULL;
        }
        newPacket = MIDIPacketNext(currentPacket);
    }

    const uintptr_t packetStart = (uintptr_t)newPacket;
    const size_t unalignedSize = offsetof(MIDIPacket, data) + dataLength;
    if(unalignedSize > SIZE_MAX - 3) return NULL;
    const size_t packetSize = (unalignedSize + 3) & ~(size_t)3;
    if(packetStart < firstPacket || packetStart > listEnd ||
       packetSize > listEnd - packetStart ||
       packetList->numPackets == UINT32_MAX) {
        return NULL;
    }

    newPacket->timeStamp = time;
    newPacket->length = (UInt16)dataLength;
    if(dataLength) memcpy(newPacket->data, data, dataLength);
    packetList->numPackets++;
    return newPacket;
}

void MIDIThruConnectionParamsInitialize(
        MIDIThruConnectionParams *parameters) {
    if(!parameters) return;
    memset(parameters, 0, sizeof(*parameters));
    for(UInt8 channel = 0; channel < 16; channel++)
        parameters->channelMap[channel] = channel;
    parameters->highNote = 127;
}
