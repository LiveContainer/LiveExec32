#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static unsigned checks, failures;
static BOOL check(const char *name, BOOL passed) {
    printf("assetwriter-%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
    return passed;
}

static BOOL waitReady(AVAssetWriterInput *input) {
    for(unsigned i = 0; i < 5000; ++i) {
        if(input.readyForMoreMediaData) return YES;
        usleep(1000);
    }
    return NO;
}

static void checkThumbnail(NSURL *url) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    struct { uint32_t before; CMTime time; uint32_t after; } actual = {
        0x12345678, kCMTimeInvalid, 0x87654321
    };
    NSError *error = nil;
    CGImageRef image = [generator copyCGImageAtTime:CMTimeMake(1, 30)
        actualTime:&actual.time error:&error];
    check("thumbnail-create", image != NULL && error == nil);
    check("thumbnail-dimensions", image && CGImageGetWidth(image) == 32 && CGImageGetHeight(image) == 32);
    check("thumbnail-actual-time", CMTIME_IS_VALID(actual.time) &&
        CMTimeCompare(actual.time, kCMTimeZero) >= 0 &&
        CMTimeCompare(actual.time, asset.duration) < 0);
    check("thumbnail-output-canaries", actual.before == 0x12345678 && actual.after == 0x87654321);
    if(image) CGImageRelease(image);
    image = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:NULL];
    check("thumbnail-null-outputs", image != NULL);
    if(image) CGImageRelease(image);
    image = [generator copyCGImageAtTime:kCMTimeInvalid actualTime:NULL error:&error];
    check("thumbnail-error", image == NULL && error != nil);
    if(image) CGImageRelease(image);
    [generator release];
}

static void checkComposition(NSURL *sourceURL) {
    const CMTime exact = {INT64_C(0x123456789), 600, kCMTimeFlags_Valid, -7};
    CMTime timeCopy = [NSValue valueWithCMTime:exact].CMTimeValue;
    check("time-wide-fields", timeCopy.value == exact.value &&
        timeCopy.timescale == exact.timescale && timeCopy.flags == exact.flags && timeCopy.epoch == exact.epoch);
    CMTimeRange exactRange = {exact, CMTimeMake(1, 600)};
    CMTimeRange rangeCopy = [NSValue valueWithCMTimeRange:exactRange].CMTimeRangeValue;
    check("range-wide-fields", rangeCopy.start.value == exact.value &&
        rangeCopy.start.epoch == exact.epoch && CMTimeCompare(rangeCopy.duration, exactRange.duration) == 0);
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    CMTime duration = asset.duration;
    check("asset-duration", CMTimeCompare(duration, CMTimeMake(2, 30)) == 0);
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if(!check("video-track", tracks.count == 1)) return;
    AVAssetTrack *track = tracks[0];
    CMTimeRange range = track.timeRange;
    check("track-range", CMTimeCompare(range.start, kCMTimeZero) == 0 &&
        CMTimeCompare(range.duration, duration) == 0);

    AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
    composition.frameDuration = CMTimeMake(1, 30);
    composition.renderSize = CGSizeMake(32, 32);
    check("frame-duration-roundtrip", CMTimeCompare(composition.frameDuration, CMTimeMake(1, 30)) == 0);
    AVMutableVideoCompositionInstruction *instruction =
        [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = range;
    check("instruction-range-roundtrip", CMTimeRangeEqual(instruction.timeRange, range));
    AVMutableVideoCompositionLayerInstruction *layer =
        [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
    [layer setTransform:CGAffineTransformIdentity atTime:kCMTimeZero];
    [layer setOpacityRampFromStartOpacity:1 toEndOpacity:1 timeRange:range];
    instruction.layerInstructions = @[layer];
    composition.instructions = @[instruction];

    AVAssetExportSession *export = [[AVAssetExportSession alloc]
        initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
    if(!check("export-create", export != nil)) return;
    export.outputURL = [NSURL fileURLWithPath:[sourceURL.path stringByAppendingString:@".export.mov"]];
    export.outputFileType = AVFileTypeQuickTimeMovie;
    export.videoComposition = composition;
    [export exportAsynchronouslyWithCompletionHandler:^{}];
    for(unsigned i = 0; i < 200; ++i) {
        if(export.status != AVAssetExportSessionStatusWaiting &&
           export.status != AVAssetExportSessionStatusExporting) break;
        usleep(100000);
    }
    check("composed-export", export.status == AVAssetExportSessionStatusCompleted && !export.error);
    if(export.status == AVAssetExportSessionStatusCompleted) checkThumbnail(export.outputURL);
    if(export.error) NSLog(@"%@", export.error);
    if(export.status == AVAssetExportSessionStatusWaiting ||
       export.status == AVAssetExportSessionStatusExporting) [export cancelExport];
    [export release];
}

int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    if(argc != 2) return 2; // caller supplies a new path, never overwrite
    @autoreleasepool {
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url
            fileType:AVFileTypeQuickTimeMovie error:&error];
        if(!check("create", writer != nil)) { NSLog(@"%@", error); return 1; }
        AVAssetWriterInput *video = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
            outputSettings:@{AVVideoCodecKey: AVVideoCodecH264, AVVideoWidthKey: @32, AVVideoHeightKey: @32}];
        AVAssetWriterInput *audio = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
            outputSettings:@{AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @44100,
                AVNumberOfChannelsKey: @1, AVLinearPCMBitDepthKey: @16,
                AVLinearPCMIsFloatKey: @NO, AVLinearPCMIsBigEndianKey: @NO,
                AVLinearPCMIsNonInterleaved: @NO}];
        if(!check("video-input", [writer canAddInput:video]) ||
           !check("audio-input", [writer canAddInput:audio])) return 1;
        [writer addInput:video];
        [writer addInput:audio];
        AVAssetWriterInputPixelBufferAdaptor *adaptor =
            [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:video
                sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                    (id)kCVPixelBufferWidthKey: @32, (id)kCVPixelBufferHeightKey: @32}];
        if(!check("start", [writer startWriting])) { NSLog(@"%@", writer.error); return 1; }
        // Nonzero start ensures the CMTime value is not accidentally lost.
        [writer startSessionAtSourceTime:CMTimeMake(7, 3)];
        check("start-session", writer.status == AVAssetWriterStatusWriting);

        CVPixelBufferRef pixel = NULL;
        if(!check("pixel-create", CVPixelBufferCreate(NULL, 32, 32,
                kCVPixelFormatType_32BGRA, NULL, &pixel) == 0 && pixel)) return 1;
        if(!check("pixel-lock", CVPixelBufferLockBaseAddress(pixel, 0) == 0)) return 1;
        memset(CVPixelBufferGetBaseAddress(pixel), 0x80, CVPixelBufferGetBytesPerRow(pixel) * 32);
        check("pixel-unlock", CVPixelBufferUnlockBaseAddress(pixel, 0) == 0);
        for(unsigned i = 0; i < 2; ++i) {
            if(!check("video-ready", waitReady(video))) return 1;
            check("append-pixel-time", [adaptor appendPixelBuffer:pixel
                withPresentationTime:CMTimeMake(70 + i, 30)]);
        }
        CVPixelBufferRelease(pixel);

        AudioStreamBasicDescription asbd = {44100, kAudioFormatLinearPCM,
            kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 2, 1, 2, 1, 16, 0};
        CMAudioFormatDescriptionRef format = NULL;
        if(!check("audio-format", CMAudioFormatDescriptionCreate(NULL,
                &asbd, 0, NULL, 0, NULL, NULL, &format) == 0 && format)) return 1;
        CMSampleTimingInfo timing = {CMTimeMake(1, 44100), CMTimeMake(7, 3), kCMTimeInvalid};
        CMSampleBufferRef sample = NULL;
        size_t sampleSize = 2;
        OSStatus status = CMSampleBufferCreate(NULL, NULL, false, NULL, NULL,
            format, 2940, 1, &timing, 1, &sampleSize, &sample);
        CFRelease(format);
        if(!check("audio-sample", status == 0 && sample)) return 1;
        int16_t pcm[2940] = {0};
        AudioBufferList buffers = {1, {{1, sizeof(pcm), pcm}}};
        check("audio-data", CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, NULL, NULL, 0, &buffers) == 0);
        check("audio-ready", CMSampleBufferSetDataReady(sample) == 0);
        if(!check("audio-input-ready", waitReady(audio))) return 1;
        check("append-audio", [audio appendSampleBuffer:sample]);
        CFRelease(sample);

        [writer endSessionAtSourceTime:CMTimeMake(72, 30)];
        check("end-session", writer.status == AVAssetWriterStatusWriting);
        [video markAsFinished];
        [audio markAsFinished];
        check("finish", [writer finishWriting]);
        check("completed", writer.status == AVAssetWriterStatusCompleted && writer.error == nil);
        if(writer.error) NSLog(@"%@", writer.error);
        if(writer.status == AVAssetWriterStatusCompleted) checkComposition(url);
        [writer release];
    }
    printf("assetwriter-recording: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
