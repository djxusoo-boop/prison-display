#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
typedef struct { int count; } Stats;
static void encoded(void *ref, void *frame, OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
    Stats *stats = ref; stats->count++;
    CMBlockBufferRef block = sample ? CMSampleBufferGetDataBuffer(sample) : NULL;
    unsigned char bytes[5] = {0};
    if (block && CMBlockBufferGetDataLength(block)>=5) CMBlockBufferCopyDataBytes(block,0,5,bytes);
    fprintf(stdout,"OUTPUT count=%d status=%d bytes=%zu nal=%u\n",stats->count,(int)status,block ? CMBlockBufferGetDataLength(block) : 0,bytes[4]&31);
}
int main(void) { @autoreleasepool {
    setbuf(stdout,NULL);
    for (int baseline=0;baseline<2;baseline++) { for (int flush=0;flush<2;flush++) {
        Stats stats={0}; VTCompressionSessionRef session=NULL;
        NSDictionary *spec=@{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:@YES};
        OSStatus result=VTCompressionSessionCreate(NULL,1280,720,kCMVideoCodecType_H264,(__bridge CFDictionaryRef)spec,NULL,NULL,encoded,&stats,&session);
        if (result) return 1;
        NSDictionary *properties=@{(__bridge NSString *)kVTCompressionPropertyKey_RealTime:@YES,(__bridge NSString *)kVTCompressionPropertyKey_AllowFrameReordering:@NO,(__bridge NSString *)kVTCompressionPropertyKey_ProfileLevel:(__bridge NSString *)(baseline ? kVTProfileLevel_H264_Baseline_AutoLevel : kVTProfileLevel_H264_Main_AutoLevel),(__bridge NSString *)kVTCompressionPropertyKey_ExpectedFrameRate:@30,(__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate:@6000000};
        VTSessionSetProperties(session,(__bridge CFDictionaryRef)properties);
        OSStatus delay=VTSessionSetProperty(session,kVTCompressionPropertyKey_MaxFrameDelayCount,(__bridge CFTypeRef)@0);
        VTCompressionSessionPrepareToEncodeFrames(session);
        printf("PROFILE %s delayStatus=%d flush=%d\n",baseline?"baseline":"main",(int)delay,flush);
        CVPixelBufferRef pixel=NULL; CVPixelBufferCreate(NULL,1280,720,kCVPixelFormatType_32BGRA,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{}},&pixel);
        CVPixelBufferLockBaseAddress(pixel,0); memset(CVPixelBufferGetBaseAddress(pixel),120,CVPixelBufferGetBytesPerRow(pixel)*720); CVPixelBufferUnlockBaseAddress(pixel,0);
        for (int i=0;i<5;i++) {
            VTCompressionSessionEncodeFrame(session,pixel,CMTimeMake(i+1,30),CMTimeMake(1,30),NULL,NULL,NULL);
            [NSThread sleepForTimeInterval:.3]; printf("BEFORE_FLUSH frame=%d outputs=%d\n",i+1,stats.count);
            if (flush) VTCompressionSessionCompleteFrames(session,kCMTimeInvalid);
        }
        VTCompressionSessionCompleteFrames(session,kCMTimeInvalid);
        CVPixelBufferRelease(pixel); VTCompressionSessionInvalidate(session); CFRelease(session);
    } }
} return 0; }
