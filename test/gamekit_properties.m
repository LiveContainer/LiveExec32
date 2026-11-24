#import <Foundation/Foundation.h>
#import <GameKit/GameKit.h>
#import <LC32/LC32.h>
#include <stdint.h>
#include <stdio.h>

/* Local objects only: never authenticate, report scores, or start a match.
 * Always compare against native state: a pair of synthesized guest accessors
 * can agree with each other while GameKit still sees an unset property. */
static unsigned checks, failures;
static void check(BOOL result, const char *name) {
    ++checks;
    failures += !result;
    printf("gamekit-%s: %s\n", name, result ? "PASS" : "FAIL");
    fflush(stdout);
}

static id nativeObject(id object, SEL selector) {
    return LC32ReturnBorrowedGuestObject(LC32InvokeHostObjectSelector(
        [object host_self], LC32GetHostSelector(selector), (uint64_t)0));
}

static id nativeKey(id object, NSString *key) {
    return LC32ReturnBorrowedGuestObject(LC32InvokeHostObjectSelector(
        [object host_self], LC32GetHostSelector(@selector(valueForKey:)),
        [key host_self], (uint64_t)0));
}

static void setNativeKey(id object, NSString *key, id value) {
    LC32InvokeHostSelector([object host_self],
        LC32GetHostSelector(@selector(setValue:forKey:)),
        [value host_self], [key host_self], (uint64_t)0);
}

static BOOL equalObjects(id a, id b) {
    return a == b || [a isEqual:b];
}

static id internalObject(id object, const char *className) {
    id internal = nativeObject(object, @selector(internal));
    if(!internal && className) {
        /* Server-created models need a backing record. This test-only native
         * fixture avoids relying on a Game Center account or server data. */
        internal = LC32InvokeHostObjectSelector(
            LC32GetHostObject(nil, className, true),
            LC32HostSelectorAllowingUnmappedReceiver(
                LC32GetHostSelector(@selector(new))), (uint64_t)0);
        setNativeKey(object, @"internal", internal);
        [internal autorelease];
    }
    check(internal != nil, "native-backing-record");
    return internal;
}

#define CHECK_OBJECT(object, property, value) do { \
    id expected = (value); \
    setNativeKey(internalObject(object, NULL), @#property, expected); \
    check([object.property isEqual:expected], #property "-reads-native-state"); \
} while(0)

#define CHECK_SCALAR(object, property, value) do { \
    setNativeKey(internalObject(object, NULL), @#property, @(value)); \
    check(object.property == (value), #property "-reads-native-state"); \
} while(0)

#define CHECK_WRITABLE(object, property, value, changed) do { \
    object.property = (value); \
    check([nativeKey(object, @#property) isEqual:@(value)], \
        #property "-setter-updates-native-state"); \
    setNativeKey(object, @#property, @(changed)); \
    check(object.property == (changed), #property "-getter-sees-native-change"); \
} while(0)

static void checkScores(void) {
    NSString *identifier = @"org.liveexec32.local-score";
    GKScore *score = [[GKScore alloc] initWithLeaderboardIdentifier:identifier];
    check([score.leaderboardIdentifier isEqual:identifier], "score-initial-identifier");
    check(score.date != nil && [score.date isEqual:nativeObject(score, @selector(date))],
        "score-initial-date");
    /* This flag is what native score reporting checks before submission.
     * Setting zero is significant even though a fresh score also reads zero. */
    SEL valueSet = NSSelectorFromString(@"valueSet");
    check(!LC32InvokeHostSelector(score.host_self, LC32GetHostSelector(valueSet),
        (uint64_t)0), "score-starts-uninitialized");
    const int64_t values[] = {0, INT64_C(0x123456789abcdef),
        -INT64_C(0x123456789abcdef), INT64_MIN, INT64_MAX};
    for(unsigned i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
        setNativeKey(score, @"valueSet", @NO);
        score.value = values[i];
        check(LC32InvokeHostSelector(score.host_self, LC32GetHostSelector(valueSet),
            (uint64_t)0) != 0, "score-setter-initializes-native-value");
        check([nativeKey(score, @"value") longLongValue] == values[i],
            "score-setter-preserves-signed-64-bits");
        const int64_t changed = ~values[i];
        setNativeKey(score, @"value", @(changed));
        check(score.value == changed, "score-getter-preserves-signed-64-bits");
    }
    CHECK_WRITABLE(score, context, UINT64_C(0xfedcba9876543210), UINT64_MAX);
    score.leaderboardIdentifier = @"org.liveexec32.changed-score";
    check([nativeKey(score, @"leaderboardIdentifier") isEqual:score.leaderboardIdentifier],
        "score-identifier-setter");
    setNativeKey(score, @"leaderboardIdentifier", identifier);
    check([score.leaderboardIdentifier isEqual:identifier], "score-identifier-getter");
    score.category = @"org.liveexec32.legacy-score";
    check([nativeKey(score, @"leaderboardIdentifier") isEqual:score.category] &&
        [score.category isEqual:@"org.liveexec32.legacy-score"], "score-legacy-category-alias");
    GKScore *legacy = [[GKScore alloc] initWithCategory:identifier];
    check([legacy.category isEqual:identifier], "score-legacy-initializer");
    legacy.value = 0;
    check(LC32InvokeHostSelector(legacy.host_self, LC32GetHostSelector(valueSet),
        (uint64_t)0) != 0, "legacy-score-zero-initializes-native-value");
    [legacy release];
    CHECK_OBJECT(score, formattedValue, @"1,234 points");
    CHECK_SCALAR(score, rank, 1234);
    [score release];
}

static void checkMatchmaking(void) {
    GKMatchRequest *request = [[GKMatchRequest alloc] init];
    CHECK_WRITABLE(request, minPlayers, 2U, 3U);
    CHECK_WRITABLE(request, maxPlayers, 4U, 5U);
    CHECK_WRITABLE(request, defaultNumberOfPlayers, 3U, 4U);
    CHECK_WRITABLE(request, playerGroup, 0x87654321U, 0xfedcba98U);
    CHECK_WRITABLE(request, playerAttributes, 0x80000001U, 0xffffffffU);
    /* Newer GameKit versions ignore invitation text. Compare with a native
     * control rather than requiring the OS to retain the submitted string. */
    GKMatchRequest *control = [[GKMatchRequest alloc] init];
    setNativeKey(control, @"inviteMessage", @"Local invitation");
    request.inviteMessage = @"Local invitation";
    check(equalObjects(nativeKey(request, @"inviteMessage"), nativeKey(control, @"inviteMessage")),
        "invite-message-setter");
    setNativeKey(request, @"inviteMessage", @"Native invitation");
    check(equalObjects(request.inviteMessage, nativeKey(request, @"inviteMessage")), "invite-message-getter");
    [control release];
    [request release];
    GKInvite *invite = [[GKInvite alloc] init];
    CHECK_SCALAR(invite, playerGroup, 0x87654321U);
    CHECK_SCALAR(invite, playerAttributes, 0x80000001U);
    [invite release];
}

static void checkLeaderboards(void) {
    GKLeaderboard *board = [[GKLeaderboard alloc] init];
    board.identifier = @"org.liveexec32.local-board";
    check([nativeKey(board, @"identifier") isEqual:board.identifier], "leaderboard-identifier-setter");
    setNativeKey(board, @"identifier", @"org.liveexec32.native-board");
    check([board.identifier isEqual:@"org.liveexec32.native-board"], "leaderboard-identifier-getter");
    board.category = @"org.liveexec32.legacy-board";
    check([nativeKey(board, @"identifier") isEqual:board.category], "leaderboard-legacy-category");
    CHECK_OBJECT(board, title, @"Local board");
    CHECK_OBJECT(board, groupIdentifier, @"local-board-group");
    setNativeKey(internalObject(board, NULL), @"maxRank", @12345);
    check(board.maxRange == 12345, "leaderboard-computed-max-range");
    [board release];
    GKLeaderboardSet *set = [[GKLeaderboardSet alloc] init];
    set.identifier = @"org.liveexec32.local-set";
    check([nativeKey(set, @"identifier") isEqual:set.identifier], "leaderboard-set-identifier-setter");
    CHECK_OBJECT(set, identifier, @"org.liveexec32.native-set");
    CHECK_OBJECT(set, title, @"Local set");
    CHECK_OBJECT(set, groupIdentifier, @"local-set-group");
    [set release];
}

static void checkDescriptionsAndPlayers(void) {
    GKAchievementDescription *description = [[GKAchievementDescription alloc] init];
    CHECK_OBJECT(description, identifier, @"org.liveexec32.local-achievement");
    CHECK_OBJECT(description, groupIdentifier, @"local-achievement-group");
    CHECK_OBJECT(description, title, @"Local achievement");
    CHECK_OBJECT(description, achievedDescription, @"Completed");
    CHECK_OBJECT(description, unachievedDescription, @"Not completed");
    CHECK_SCALAR(description, maximumPoints, 123);
    CHECK_SCALAR(description, hidden, YES);
    CHECK_SCALAR(description, replayable, YES);
    [description release];
    GKPlayer *player = [[GKPlayer alloc] init];
    CHECK_OBJECT(player, alias, @"Local player");
    [player release];
    GKPlayer *guest = [GKPlayer anonymousGuestPlayerWithIdentifier:@"local-guest"];
    check([guest.guestIdentifier isEqual:@"local-guest"], "player-guest-identifier");
    /* Not the singleton: changing the fixture must not alter account state. */
    GKLocalPlayer *local = [[GKLocalPlayer alloc] init];
    setNativeKey(internalObject(local, NULL), @"underage", @YES);
    check(local.isUnderage == (BOOL)LC32InvokeHostSelector(local.host_self,
        LC32GetHostSelector(@selector(isUnderage)), (uint64_t)0),
        "underage-matches-native-policy");
    [local release];
}

static void checkTurnBasedModels(void) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:123456789];
    NSData *data = [@"local match bytes" dataUsingEncoding:NSUTF8StringEncoding];
    GKTurnBasedParticipant *participant = [[GKTurnBasedParticipant alloc] init];
    CHECK_WRITABLE(participant, matchOutcome, GKTurnBasedMatchOutcomeWon, GKTurnBasedMatchOutcomeLost);
    CHECK_OBJECT(participant, timeoutDate, date);
    [participant release];
    GKTurnBasedMatch *match = [[GKTurnBasedMatch alloc] init];
    CHECK_OBJECT(match, matchID, @"local-match");
    CHECK_OBJECT(match, creationDate, date);
    CHECK_OBJECT(match, matchData, data);
    [match release];
    GKTurnBasedExchange *exchange = [[GKTurnBasedExchange alloc] init];
    internalObject(exchange, "GKTurnBasedExchangeInternal");
    CHECK_OBJECT(exchange, exchangeID, @"local-exchange");
    CHECK_OBJECT(exchange, data, data);
    CHECK_OBJECT(exchange, sendDate, date);
    CHECK_OBJECT(exchange, timeoutDate, date);
    CHECK_OBJECT(exchange, completionDate, date);
    [exchange release];
    GKTurnBasedExchangeReply *reply = [[GKTurnBasedExchangeReply alloc] init];
    internalObject(reply, "GKTurnBasedExchangeReplyInternal");
    CHECK_OBJECT(reply, data, data);
    CHECK_OBJECT(reply, replyDate, date);
    [reply release];
    GKChallenge *challenge = [[GKChallenge alloc] init];
    internalObject(challenge, "GKChallengeInternal");
    CHECK_SCALAR(challenge, state, GKChallengeStateCompleted);
    CHECK_OBJECT(challenge, issueDate, date);
    CHECK_OBJECT(challenge, completionDate, date);
    CHECK_OBJECT(challenge, message, @"Local challenge");
    [challenge release];
}

int main(void) {
    @autoreleasepool {
        checkScores();
        checkMatchmaking();
        checkLeaderboards();
        checkDescriptionsAndPlayers();
        checkTurnBasedModels();
    }
    printf("gamekit-properties: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
