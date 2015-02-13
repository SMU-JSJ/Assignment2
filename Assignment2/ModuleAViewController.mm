//
//  ViewController.m
//  Assignment2
//
//  Created by ch484-mac7 on 2/12/15.
//  Copyright (c) 2015 SMU. All rights reserved.
//

#import "ModuleAViewController.h"
#import "Novocaine.h"
#import "AudioFileReader.h"
#import "RingBuffer.h"
#import "SMUGraphHelper.h"
#import "SMUFFTHelper.h"

#define kBufferLength 4096
#define kWindowSize 3

@interface ModuleAViewController ()

@property (strong, nonatomic) Novocaine *audioManager;
@property (nonatomic) float *audioData;

@property (nonatomic) SMUFFTHelper *fftHelper;
@property (nonatomic) float *fftMagnitudeBuffer;
@property (nonatomic) float *fftPhaseBuffer;
@property (strong, nonatomic) NSTimer *timer;

@property (nonatomic) int peakOneIndex;
@property (nonatomic) int peakTwoIndex;

@end

@implementation ModuleAViewController

RingBuffer *ringBuffer;

// Lazily instantiate all the variables

- (Novocaine*) audioManager {
    if(!_audioManager){
        _audioManager = [Novocaine audioManager];
    }
    return _audioManager;
}

- (float*) audioData {
    if(!_audioData){
        _audioData = (float*)calloc(kBufferLength,sizeof(float));
    }
    return _audioData;
}

- (SMUFFTHelper*) fftHelper {
    if(!_fftHelper){
        _fftHelper = new SMUFFTHelper(kBufferLength,kBufferLength,WindowTypeRect);
    }
    return _fftHelper;
}

- (float*) fftMagnitudeBuffer {
    if(!_fftMagnitudeBuffer){
        _fftMagnitudeBuffer = (float *)calloc(kBufferLength/2,sizeof(float));
    }
    return _fftMagnitudeBuffer;
}

- (float*) fftPhaseBuffer {
    if(!_fftPhaseBuffer){
        _fftPhaseBuffer = (float *)calloc(kBufferLength/2,sizeof(float));
    }
    return _fftPhaseBuffer;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    ringBuffer = new RingBuffer(kBufferLength,2);
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2
                                                  target:self
                                                selector:@selector(update)
                                                userInfo:nil
                                                 repeats:YES];
    
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    
    
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    //Start playing if it isn't already.
    if(![self.audioManager playing]){
        [self.audioManager play];
    }
    
    [self.audioManager setInputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels)
     {
         if(ringBuffer!=nil)
             ringBuffer->AddNewFloatData(data, numFrames);
     }];
    
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause audioManager
    [self.audioManager pause];
}

-(void) viewDidDisappear:(BOOL)animated {
}

-(void)dealloc{
    
    free(self.audioData);
    
    free(self.fftMagnitudeBuffer);
    free(self.fftPhaseBuffer);
    
    delete self.fftHelper;
    delete ringBuffer;
    
    ringBuffer = nil;
    self.fftHelper  = nil;
    self.audioManager = nil;
    
    // ARC handles everything else, just clean up what we used c++ for (calloc, malloc, new)
    
}

- (void)update{
    // plot the audio
    ringBuffer->FetchFreshData2(self.audioData, kBufferLength, 0, 1);
    
    //take the FFT
    self.fftHelper->forward(0,self.audioData, self.fftMagnitudeBuffer, self.fftPhaseBuffer);
    
    int oldPeakOneIndex = self.peakOneIndex;
    int oldPeakTwoIndex = self.peakTwoIndex;
    
    self.peakOneIndex = 0;
    self.peakTwoIndex = 0;
    
    for (int i = 0; i < kBufferLength/2 - kWindowSize; i++) {
        int index = [self maxIndex:self.fftMagnitudeBuffer startIndex:i length:kWindowSize];
        // check the index is the midpoint
        if (index == i + (kWindowSize - 1)/2) {
            [self compareToPeaksAndSetSmallest:index];
        }
    }
    
    NSLog(@"%f", self.fftMagnitudeBuffer[self.peakOneIndex]);
    NSLog(@"%f", self.fftMagnitudeBuffer[self.peakTwoIndex]);
    // silence is less than like 5
    
//    if (oldPeakOneIndex * 10.766 + 3 < self.peakOneIndex * 10.766 ||
//        oldPeakOneIndex * 10.766 - 3 > self.peakOneIndex * 10.766) {
//        NSLog(@"Peak one: %f", self.peakOneIndex * 10.766);
//    }
//    else {
//        NSLog(@"Peak one not replaced");
//    }
//    
//    if (oldPeakTwoIndex * 10.766 + 3 < self.peakTwoIndex * 10.766 ||
//        oldPeakTwoIndex * 10.766 - 3 > self.peakTwoIndex * 10.766) {
//        NSLog(@"Peak two: %f", self.peakTwoIndex * 10.766);
//    }
//    else {
//        NSLog(@"Peak two not replaced");
//    }
    
//    // Take the max value in each chunk
//    for (int i = 0; i < kBufferLength/2; i++) {
//        int chunk = i/kChunkSize;
//        
//        //        if (self.fftMagnitudeBuffer[i] > self.fftEqBuffer[chunk]) {
//        //            self.fftEqBuffer[chunk] = self.fftMagnitudeBuffer[i];
//        //        }
//    }
}

// Find the maximum index in an array given a starting index and length of subarray
- (int)maxIndex:(float*)data
  startIndex:(int)startIndex
      length:(int)length {
    float max = -1;
    int maxIndex = -1;
    for (int i = startIndex; i < startIndex + length; i++) {
        if (data[i] > max) {
            max = data[i];
            maxIndex = i;
        }
    }
    return maxIndex;
}

- (void)compareToPeaksAndSetSmallest:(int)index {
    // see which peak value is smaller
    if (self.fftMagnitudeBuffer[self.peakOneIndex] > self.fftMagnitudeBuffer[self.peakTwoIndex] &&
        self.fftMagnitudeBuffer[index] > self.fftMagnitudeBuffer[self.peakTwoIndex]) {
        self.peakTwoIndex = index;
    }
    else if (self.fftMagnitudeBuffer[self.peakTwoIndex] >= self.fftMagnitudeBuffer[self.peakOneIndex] &&
             self.fftMagnitudeBuffer[index] > self.fftMagnitudeBuffer[self.peakOneIndex]) {
        self.peakOneIndex = index;
    }

}


@end
