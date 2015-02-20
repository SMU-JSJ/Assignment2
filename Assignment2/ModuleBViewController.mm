//  Team JSJ - Jordan Kayse, Story Zanetti, Jessica Yeh
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

- (Novocaine*)audioManager {
    if (!_audioManager) {
        _audioManager = [Novocaine audioManager];
    }
    return _audioManager;
}

- (float*)audioData {
    if (!_audioData) {
        _audioData = (float*)calloc(kBufferLength,sizeof(float));
    }
    return _audioData;
}

- (GraphHelper*)graphHelper {
    if (!_graphHelper) {
        int framesPerSecond = 30;
        int numDataArraysToGraph = 1;
        _graphHelper = new GraphHelper(self,
                                       framesPerSecond,
                                       numDataArraysToGraph,
                                       PlotStyleSeparated);//drawing starts immediately after call
        
    }
    return _graphHelper;
}

- (SMUFFTHelper*)fftHelper {
    if (!_fftHelper) {
        _fftHelper = new SMUFFTHelper(kBufferLength, kBufferLength, WindowTypeRect);
    }
    return _fftHelper;
}

- (float*)fftMagnitudeBuffer {
    if (!_fftMagnitudeBuffer) {
        _fftMagnitudeBuffer = (float*)calloc(kBufferLength/2, sizeof(float));
    }
    return _fftMagnitudeBuffer;
}

- (float*)fftPhaseBuffer {
    if (!_fftPhaseBuffer) {
        _fftPhaseBuffer = (float*)calloc(kBufferLength/2, sizeof(float));
    }
    return _fftPhaseBuffer;
}

- (float*)fftDecibel {
    if (!_fftDecibel) {
        _fftDecibel = (float*)calloc(kBufferLength/2, sizeof(float));
    }
    return _fftDecibel;
}

- (float*)fftOriginal {
    if (!_fftOriginal) {
        _fftOriginal = (float*)calloc(kBufferLength/2, sizeof(float));
    }
    return _fftOriginal;
}

- (float)frequency {
    if (!_frequency) {
        _frequency = 17500;
    }
    return _frequency;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view, typically from a nib.
    ringBufferB = new RingBuffer(kBufferLength,2);
    
    self.graphHelper->SetBounds(-0.9,0.9,-0.9,0.9); // bottom, top, left, right, full screen==(-1,1,-1,1)
    
    self.shouldSetOriginal = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    //Start playing if it isn't already.
    if (![self.audioManager playing]) {
        [self.audioManager play];
    }
    
    // Get sound samples from the microphone and send it to the audio manager
    [self.audioManager setInputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels)
     {
         if (ringBufferB != nil) {
             ringBufferB->AddNewFloatData(data, numFrames);
         }
     }];
    
    [self setOutputBlock];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause audioManager
    [self.audioManager pause];
}

- (void)viewDidDisappear:(BOOL)animated {
    // stop opengl from running
    self.graphHelper->tearDownGL();
}

// Dealloc things; ARC handles everything else, just clean up what we used c++ for (calloc, malloc, new)
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
}

// If the user clicked Recalibrate, reset the baseline graph
- (IBAction)recalibrateClicked:(UIBarButtonItem*)sender {
    self.shouldSetOriginal = YES;
}

// When the frequency slider is moved, update the frequency value in the label and reset the baseline graph
- (IBAction)frequencySliderChanged:(UISlider*)sender {
    self.frequency = sender.value;
    self.frequencyLabel.text = [NSString stringWithFormat:@"%.0f Hz", self.frequency];
    [self setOutputBlock];
    self.shouldSetOriginal = YES;
}

// Outputs a sine wave with the set frequency
- (void)setOutputBlock {
    __block float frequency = self.frequency; //starting frequency
    __block float phase = 0.0;
    __block float samplingRate = self.audioManager.samplingRate;
    
    [self.audioManager setOutputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels)
     {
         double phaseIncrement = 2 * M_PI * frequency / samplingRate;
         double repeatMax = 2 * M_PI;
         
         for (int i = 0; i < numFrames; i++) {
             for (int j = 0; j < numChannels; j++) {
                 data[i * numChannels + j] = 1.0 * sin(phase);
             }
             
             phase += phaseIncrement;
             
             if (phase > repeatMax) {
                 phase -= repeatMax;
             }
         }
     }];
}

// Show a popup with "You won!" when the progress bar reaches 100%
- (void)showPopup:(float)progressBarValue {
    if (progressBarValue == 1) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Congratulations!"
                                                        message:@"You won!"
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    }
}

// Detects motion via change to the values to the left and right of the playing frequency
- (DopplerState)detectMovement {
    float maxRight = 0;
    float maxLeft = 0;
    int frequencyIndex = self.frequency/kdf;
    
    // Checks to the left of the frequency
    for (int i = frequencyIndex - 23; i < frequencyIndex - 3; i++) {
        float magnitudeDifference = self.fftDecibel[i] - self.fftOriginal[i];
        if (magnitudeDifference > maxLeft) {
            maxLeft = magnitudeDifference;
        }
    }
    
    // Checks to the right of the frequency
    for (int i = frequencyIndex + 4; i < frequencyIndex + 24; i++) {
        float magnitudeDifference = self.fftDecibel[i] - self.fftOriginal[i];
        if (magnitudeDifference > maxRight) {
            maxRight = magnitudeDifference;
        }
    }

    // Returns an enum for which direction the movement is going
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
- (void)update {
    // If a certain amount of time has not passed yet (counter < 20, around .67 sec), don't do anything,
    // so we can wait for the sound to start playing
    if (self.counter < 20) {
        self.counter++;
        return;
    }
    
    // Plot the audio
    ringBufferB->FetchFreshData2(self.audioData, kBufferLength, 0, 1);
    
    // Take the FFT
    self.fftHelper->forward(0, self.audioData, self.fftMagnitudeBuffer, self.fftPhaseBuffer);
    
    // Convert the magnitude to the decibel values
    for (int i = 0; i < kBufferLength/2; i++) {
        self.fftDecibel[i] = 20.0 * log10f(fabs(self.fftMagnitudeBuffer[i]));
    }
    
    // If the volume has been changed, reset the baseline graph, and reset the volume scale value
    float tempVol = [[AVAudioSession sharedInstance] outputVolume];
    if (self.volumeScale != tempVol) {
        self.volumeScale = tempVol;
        self.shouldSetOriginal = YES;
    }
    
    // Reset the baseline graph if it needs to be set
    if (self.shouldSetOriginal) {
        for (int i = 0; i < kBufferLength/2; i++) {
            self.fftOriginal[i] = self.fftDecibel[i];
        }
        
        self.shouldSetOriginal = NO;
    } else {
        // Get the doppler state for the movement detected
        DopplerState dopplerState = [self detectMovement];
        
        if (dopplerState == DOPPLER_FORWARD) {
            // If something is moving towards the phone, then change the text label
            self.dopplerMovementLabel.text = @"Forward Movement";
            
            // If movement is happening, set noMoveCount to 0, to prevent the label from flickering
            self.noMoveCount = 0;
            
            // If the progress is not yet 1, increment the progress by 0.05
            if (self.progressBar.progress < 1) {
                self.progressBar.progress += 0.05;
                [self showPopup:self.progressBar.progress];
            }
            
        } else if (dopplerState == DOPPLER_BACKWARD) {
            // If something is moving away from the phone, then change the text label
            self.dopplerMovementLabel.text = @"Backward Movement";
            
            // If movement is happening, set noMoveCount to 0, to prevent the label from flickering
            self.noMoveCount = 0;
            
            // If the progress is not yet 0, decrement the progress by 0.05
            if (self.progressBar.progress > 0) {
                self.progressBar.progress -= 0.05;
            }
            
        } else if (dopplerState == DOPPLER_NONE) {
            self.noMoveCount++;
            
            // If no movement has occurred more than 5 times in a row, display "No Movement"
            if (self.noMoveCount > 5) {
                self.dopplerMovementLabel.text = @"No Movement";
            }
        }
    }
    
    // Plot the FFT (decibels)
    self.graphHelper->setGraphData(0, self.fftDecibel + 2600, kBufferLength/2 - 2600, sqrt(kBufferLength));
    
    // Update the graph
    self.graphHelper->update();
}

@end
