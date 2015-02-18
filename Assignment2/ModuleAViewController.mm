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

#define kBufferLength 8192
#define kWindowSize 7
#define kdf 5.3833007813

@interface ModuleAViewController ()

@property (strong, nonatomic) Novocaine *audioManager;
@property (nonatomic) float *audioData;

@property (nonatomic) SMUFFTHelper *fftHelper;
@property (nonatomic) float *fftMagnitudeBuffer;
@property (nonatomic) float *fftPhaseBuffer;
@property (strong, nonatomic) NSTimer *timer;

@property (nonatomic) int peakOneIndex;
@property (nonatomic) int peakTwoIndex;

@property (nonatomic) float peakOneFreq;
@property (nonatomic) float peakTwoFreq;

@property (weak, nonatomic) IBOutlet UILabel *peakOneLabel;
@property (weak, nonatomic) IBOutlet UILabel *peakTwoLabel;

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


- (IBAction)togglePausePlayWhenClicked:(UIButton *)sender {
    if([sender.currentTitle isEqualToString:@"Pause"]) {
        [self.timer invalidate];
        [sender setTitle:@"Play" forState:normal];
    } else {
        [self createTimer];
        [sender setTitle:@"Pause" forState:normal];
    }
}

- (void)createTimer {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:.1
                                                  target:self
                                                selector:@selector(update)
                                                userInfo:nil
                                                 repeats:YES];
    
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    ringBuffer = new RingBuffer(kBufferLength,2);
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    [self createTimer];
    
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
    
    // Pause audioManager and stop timer
    [self.audioManager pause];
    [self.timer invalidate];
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
    
    float oldPeakOneFreq = self.peakOneFreq;
    float oldPeakTwoFreq = self.peakTwoFreq;
    
    self.peakOneIndex = 0;
    self.peakTwoIndex = 0;
    
    self.peakOneFreq = 0;
    self.peakTwoFreq = 0;
    
    for (int i = 0; i < kBufferLength/2 - kWindowSize; i++) {
        int index = [self maxIndex:self.fftMagnitudeBuffer startIndex:i length:kWindowSize];
        // check the index is the midpoint
        if (index == i + (kWindowSize - 1)/2 && self.fftMagnitudeBuffer[index] > 5) {
            [self compareAndSetPeakValues:index peakOneIndex:self.peakOneIndex peakTwoIndex:self.peakTwoIndex data:self.fftMagnitudeBuffer];
        }
    }
    
    self.peakOneFreq = [self getFrequency:self.peakOneIndex data:self.fftMagnitudeBuffer];
    self.peakTwoFreq = [self getFrequency:self.peakTwoIndex data:self.fftMagnitudeBuffer];
    
    [self chooseAndSetPeakIndex:oldPeakOneIndex oldFreq:oldPeakOneFreq newIndex:self.peakOneIndex newFreq:self.peakOneFreq peak:1];
    [self chooseAndSetPeakIndex:oldPeakTwoIndex oldFreq:oldPeakTwoFreq newIndex:self.peakTwoIndex newFreq:self.peakTwoFreq peak:2];
    
    [self orderPeaks];
    
    self.peakOneLabel.text = [NSString stringWithFormat:@"%.0f Hz", self.peakOneFreq];
    self.peakTwoLabel.text = [NSString stringWithFormat:@"%.0f Hz", self.peakTwoFreq];

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

- (void)compareAndSetPeakValues:(int)index
         peakOneIndex:(int)peakOneIndex
         peakTwoIndex:(int)peakTwoIndex
                 data:(float*)data{
    // see which peak value is smaller
    if (data[peakOneIndex] > data[peakTwoIndex] &&
        data[index] > data[peakTwoIndex]) {
        self.peakTwoIndex = index;
    }
    else if (data[peakTwoIndex] >= data[peakOneIndex] &&
             data[index] > data[peakOneIndex]) {
        self.peakOneIndex = index;
    }
}

- (void)orderPeaks {
    if (self.peakOneIndex < self.peakTwoIndex){
        int tempIndex = self.peakOneIndex;
        self.peakOneIndex = self.peakTwoIndex;
        self.peakTwoIndex = tempIndex;
        
        int tempFreq = self.peakOneFreq;
        self.peakOneFreq = self.peakTwoFreq;
        self.peakTwoFreq = tempFreq;
    }
}

- (float)getFrequency:(int)index
                 data:(float*)data {
    if(index == 0)
        return 0;
    
    float f2 = index * kdf;
    float m1 = data[index - 1];
    float m2 = data[index];
    float m3 = data[index + 1];
    
    return f2 + ((m3 - m2) / (2.0 * m2 - m1 - m2)) * kdf / 2.0;
    
}

- (void)chooseAndSetPeakIndex:(int)oldIndex
                      oldFreq:(float)oldFreq
                     newIndex:(int)newIndex
                      newFreq:(float)newFreq
                         peak:(int)peak {
    if ((oldFreq + 3 < newFreq ||
         oldFreq - 3 > newFreq) &&
         newIndex != 0) {
        return;
    } else {
        if(peak == 1) {
            self.peakOneIndex = oldIndex;
            self.peakOneFreq = oldFreq;
        } else {
            self.peakTwoIndex = oldIndex;
            self.peakTwoFreq = oldFreq;
        }
    }
}

@end
