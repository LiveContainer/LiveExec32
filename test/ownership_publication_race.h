#ifndef LC32_OWNERSHIP_PUBLICATION_RACE_H
#define LC32_OWNERSHIP_PUBLICATION_RACE_H

#include <stdint.h>

typedef struct LC32OwnershipPublicationRaceState
    LC32OwnershipPublicationRaceState;

typedef struct {
    LC32OwnershipPublicationRaceState *state;
    unsigned int workerIndex;
} LC32OwnershipPublicationWeakWorkerContext;

enum {
    LC32OwnershipPublicationMarker = UINT32_C(0x4c433332),
};

/* Implemented by the MRC translation unit and used by the ARC weak workers. */
void *LC32OwnershipPublicationRawProbe(
    LC32OwnershipPublicationRaceState *state);
unsigned int LC32OwnershipPublicationIteration(
    LC32OwnershipPublicationRaceState *state);
int LC32OwnershipPublicationWorkerReadyAndWait(
    LC32OwnershipPublicationRaceState *state,
    unsigned int workerIndex);
int LC32OwnershipPublicationWaitForPublisher(
    LC32OwnershipPublicationRaceState *state);
void LC32OwnershipPublicationRecordWeakLoadAndWait(
    LC32OwnershipPublicationRaceState *state,
    unsigned int workerIndex,
    int racyLoadSucceeded, int loadedObject, int markerPassed);

/* Implemented by the ARC translation unit and passed directly to pthread. */
void *LC32OwnershipPublicationWeakWorker(void *opaqueContext);

#endif
