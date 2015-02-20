//
//  ModuleBViewController.m
//  Assignment2
//
//  Created by ch484-mac7 on 2/12/15.
//  Copyright (c) 2015 SMU. All rights reserved.
//

#import "ModuleBViewController.h"
#import "Novocaine.h"
#import "AudioFileReader.h"
#import "RingBuffer.h"
#import "SMUGraphHelper.h"
#import "SMUFFTHelper.h"

#define kBufferLength 8192
#define kdf 5.3833007813
#define kDoppler 15

@interface ModuleBViewController ()

@property (strong, nonatomic) Novocaine *audioManager;
@property (nonatomic) float *audioData;
@property (nonatomic) GraphHelper *graphHelper;

@property (nonatomic) SMUFFTHelper *fftHelper;
@property (nonatomic) float *fftMagnitudeBuffer;
@property (nonatomic) float *fftPhaseBuffer;
@property (nonatomic) float *fftDecibel;
@property (nonatomic) float *fftOriginal;

@property (strong, nonatomic) NSTimer *timer;

@property (nonatomic) float frequency;
@property (nonatomic) float volumeScale;
@property (nonatomic) BOOL shouldSetOriginal;
@property (nonatomic) int noMoveCount;
@property (nonatomic) int counter;

@property (weak, nonatomic) IBOutlet UILabel *frequencyLabel;
@property (weak, nonatomic) IBOutlet UILabel *dopplerMovementLabel;
@property (weak, nonatomic) IBOutlet UIProgressView *progressBar;

@end

@implementation ModuleBViewController

RingBuffer *ringBufferB;

typedef enum dopplerStates {
    DOPPLER_NONE,
    DOPPLER_FORWARD,
    DOPPLER_BACKWARD
} DopplerState;

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

- (GraphHelper*) graphHelper {
    if(!_graphHelper){
        int framesPerSecond = 30;
        int numDataArraysToGraph = 1;
        _graphHelper = new GraphHelper(self,
                                       framesPerSecond,
                                       numDataArraysToGraph,
                                       PlotStyleSeparated);//drawing starts immediately after call
        
    }
    return _graphHelper;
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

- (float*) fftDecibel {
    if(!_fftDecibel){
        _fftDecibel = (float *)calloc(kBufferLength/2,sizeof(float));
    }
    return _fftDecibel;
}

- (float*) fftOriginal {
    if(!_fftOriginal){
        _fftOriginal = (float *)calloc(kBufferLength/2,sizeof(float));
    }
    return _fftOriginal;
}

- (float) frequency {
    if(!_frequency){
        _frequency = 17500;
    }
    return _frequency;
}

- (IBAction)recalibrateClicked:(UIBarButtonItem *)sender {
    self.shouldSetOriginal = YES;
}


- (void)createTimer {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:.1
                                                  target:self
                                                selector:@selector(update)
                                                userInfo:nil
                                                 repeats:YES];
    
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (IBAction)frequencySliderChanged:(UISlider *)sender {
    self.frequency = sender.value;
    self.frequencyLabel.text = [NSString stringWithFormat:@"%.0f Hz", self.frequency];
    [self setOutputBlock];
    self.shouldSetOriginal = YES;
}

- (void)setOutputBlock {
    __block float frequency = self.frequency; //starting frequency
    __block float phase = 0.0;
    __block float samplingRate = self.audioManager.samplingRate;
    
    [self.audioManager setOutputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels)
     {
         
         double phaseIncrement = 2*M_PI*frequency/samplingRate;
         double repeatMax = 2*M_PI;
         for (int i=0; i < numFrames; ++i)
         {
             for(int j=0;j<numChannels;j++){
                 data[i*numChannels+j] = 1.0*sin(phase);
                 
             }
             phase += phaseIncrement;
             
             if(phase>repeatMax)
                 phase -= repeatMax;
         }
         
     }];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    ringBufferB = new RingBuffer(kBufferLength,2);
    
    self.graphHelper->SetBounds(-0.9,0.9,-0.9,0.9); // bottom, top, left, right, full screen==(-1,1,-1,1)
    
    self.shouldSetOriginal = YES;
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    //[self createTimer];
    
         //Start playing if it isn't already.
    if(![self.audioManager playing]){
        [self.audioManager play];
    }
    
    [self.audioManager setInputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels)
     {
         if(ringBufferB!=nil)
             ringBufferB->AddNewFloatData(data, numFrames);
     }];
    
    [self setOutputBlock];
    
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause audioManager and stop timer
    [self.audioManager pause];
    //[self.timer invalidate];
}

-(void) viewDidDisappear:(BOOL)animated {
    // stop opengl from running
    self.graphHelper->tearDownGL();
}

- (void)dealloc {
    self.graphHelper->tearDownGL();
    
    free(self.audioData);
    
    free(self.fftMagnitudeBuffer);
    free(self.fftPhaseBuffer);
    free(self.fftDecibel);
    free(self.fftOriginal);
    
    delete self.fftHelper;
    delete ringBufferB;
    delete self.graphHelper;
    
    ringBufferB = nil;
    self.fftHelper  = nil;
    self.audioManager = nil;
    self.graphHelper = nil;
    
    // ARC handles everything else, just clean up what we used c++ for (calloc, malloc, new)
    
}

- (DopplerState)detectMovement {
    float maxRight = 0;
    float maxLeft = 0;
    int frequencyIndex = self.frequency/kdf;
    
    for (int i = frequencyIndex - 23; i < frequencyIndex - 3; i++) {
        float magnitudeDifference = self.fftDecibel[i] - self.fftOriginal[i];
        if (magnitudeDifference > maxLeft) {
            maxLeft = magnitudeDifference;
        }
    }
    
    for (int i = frequencyIndex + 4; i < frequencyIndex + 24; i++) {
        float magnitudeDifference = self.fftDecibel[i] - self.fftOriginal[i];
        if (magnitudeDifference > maxRight) {
            maxRight = magnitudeDifference;
        }
    }

    if (maxRight > kDoppler * self.volumeScale && maxRight > maxLeft) {
        return DOPPLER_FORWARD;
    } else if (maxLeft > kDoppler * self.volumeScale) {
        return DOPPLER_BACKWARD;
    } else {
        return DOPPLER_NONE;
    }
}

#pragma mark - OpenGL and Update functions
//  override the GLKView draw function, from OpenGLES
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    self.graphHelper->draw(); // draw the graph
}

//  override the GLKViewController update function, from OpenGLES
- (void)update{
    if (self.counter < 20) {
        self.counter++;
        return;
    }
    
    // plot the audio
    ringBufferB->FetchFreshData2(self.audioData, kBufferLength, 0, 1);
    
    //take the FFT
    self.fftHelper->forward(0, self.audioData, self.fftMagnitudeBuffer, self.fftPhaseBuffer);
    
    for (int i = 0; i < kBufferLength/2; i++) {
        self.fftDecibel[i] = 20.0 * log10f(fabs(self.fftMagnitudeBuffer[i]));
    }
    
//    self.volumeScale = [[AVAudioSession sharedInstance] outputVolume];
    float tempVol = [[AVAudioSession sharedInstance] outputVolume];
    if(self.volumeScale != tempVol) {
        self.volumeScale = tempVol;
        self.shouldSetOriginal = YES;
    }
    
    if (self.shouldSetOriginal) {
        for (int i = 0; i < kBufferLength/2; i++) {
            self.fftOriginal[i] = self.fftDecibel[i];
        }
        
        self.shouldSetOriginal = NO;
    }
    
    if (!self.shouldSetOriginal) {
        DopplerState dopplerState = [self detectMovement];
        
        if (dopplerState == DOPPLER_FORWARD) {
            self.dopplerMovementLabel.text = @"Forward Movement";
            self.noMoveCount = 0;
            
            if (self.progressBar.progress < 1)
                self.progressBar.progress += 0.05;
            
        } else if (dopplerState == DOPPLER_BACKWARD) {
            self.dopplerMovementLabel.text = @"Backward Movement";
            self.noMoveCount = 0;
            
            if (self.progressBar.progress > 0)
                self.progressBar.progress -= 0.05;
            
        } else if (dopplerState == DOPPLER_NONE) {
            self.noMoveCount++;
            if (self.noMoveCount > 5) {
                self.dopplerMovementLabel.text = @"No Movement";
            }
        }
    }
    
    // plot the FFT
    //self.graphHelper->setGraphData(0, self.fftMagnitudeBuffer + 2600, kBufferLength/2 - 2600, sqrt(kBufferLength)); // set graph channel
    self.graphHelper->setGraphData(0, self.fftDecibel + 2600, kBufferLength/2 - 2600, sqrt(kBufferLength)); // set graph channel
    
    self.graphHelper->update(); // update the graph
}

@end
