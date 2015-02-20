//  Team JSJ - Jordan Kayse, Story Zanetti, Jessica Yeh
//  ModuleAViewController.m
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
#define kPaddedBufferLength 16384
#define kWindowSize 9
#define kdf 2.6916503906

@interface ModuleAViewController ()

@property (strong, nonatomic) NSArray *notes;

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
@property (weak, nonatomic) IBOutlet UILabel *peakOneNoteLabel;
@property (weak, nonatomic) IBOutlet UILabel *peakTwoNoteLabel;

@end

@implementation ModuleAViewController

RingBuffer *ringBuffer;

// Lazily instantiate all the variables

// Array of notes to be able to convert from frequency to notes
- (NSArray*)notes {
    if (!_notes) {
        _notes = @[@"C0", @"C#0/Db0", @"D0", @"D#0/Eb0", @"E0", @"F0", @"F#0/Gb0",
                   @"G0", @"G#0/Ab0", @"A0", @"A#0/Bb0", @"B0", @"C1", @"C#1/Db1",
                   @"D1", @"D#1/Eb1", @"E1", @"F1", @"F#1/Gb1", @"G1", @"G#1/Ab1",
                   @"A1", @"A#1/Bb1", @"B1", @"C2", @"C#2/Db2", @"D2", @"D#2/Eb2",
                   @"E2", @"F2", @"F#2/Gb2", @"G2", @"G#2/Ab2", @"A2", @"A#2/Bb2",
                   @"B2", @"C3", @"C#3/Db3", @"D3", @"D#3/Eb3", @"E3", @"F3",
                   @"F#3/Gb3", @"G3", @"G#3/Ab3", @"A3", @"A#3/Bb3", @"B3", @"C4",
                   @"C#4/Db4", @"D4", @"D#4/Eb4", @"E4", @"F4", @"F#4/Gb4", @"G4",
                   @"G#4/Ab4", @"A4", @"A#4/Bb4", @"B4", @"C5", @"C#5/Db5", @"D5",
                   @"D#5/Eb5", @"E5", @"F5", @"F#5/Gb5", @"G5", @"G#5/Ab5", @"A5",
                   @"A#5/Bb5", @"B5", @"C6", @"C#6/Db6", @"D6", @"D#6/Eb6", @"E6",
                   @"F6", @"F#6/Gb6", @"G6", @"G#6/Ab6", @"A6", @"A#6/Bb6", @"B6",
                   @"C7", @"C#7/Db7", @"D7", @"D#7/Eb7", @"E7", @"F7", @"F#7/Gb7",
                   @"G7", @"G#7/Ab7", @"A7", @"A#7/Bb7", @"B7", @"C8", @"C#8/Db8",
                   @"D8", @"D#8/Eb8", @"E8", @"F8", @"F#8/Gb8", @"G8", @"G#8/Ab8",
                   @"A8", @"A#8/Bb8", @"B8"];
    }
    return _notes;
}

- (Novocaine*)audioManager {
    if (!_audioManager) {
        _audioManager = [Novocaine audioManager];
    }
    return _audioManager;
}

- (float*)audioData {
    if (!_audioData) {
        _audioData = (float*)calloc(kBufferLength, sizeof(float));
    }
    return _audioData;
}

- (SMUFFTHelper*)fftHelper {
    if (!_fftHelper) {
        _fftHelper = new SMUFFTHelper(kPaddedBufferLength, kPaddedBufferLength, WindowTypeRect);
    }
    return _fftHelper;
}

- (float*)fftMagnitudeBuffer {
    if (!_fftMagnitudeBuffer) {
        _fftMagnitudeBuffer = (float*)calloc(kPaddedBufferLength/2, sizeof(float));
    }
    return _fftMagnitudeBuffer;
}

- (float*)fftPhaseBuffer {
    if (!_fftPhaseBuffer) {
        _fftPhaseBuffer = (float*)calloc(kPaddedBufferLength/2, sizeof(float));
    }
    return _fftPhaseBuffer;
}

// When the Pause button is clicked, the updating is stopped
// When the Play button is clicked, the updating is restarted
- (IBAction)togglePausePlayWhenClicked:(UIButton*)sender {
    if ([sender.currentTitle isEqualToString:@"Pause"]) {
        [self.timer invalidate];
        [sender setTitle:@"Play" forState:normal];
    } else {
        [self createTimer];
        [sender setTitle:@"Pause" forState:normal];
    }
}

// Creates a timer to update the frequency values
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self createTimer];
    
    //Start playing if it isn't already.
    if (![self.audioManager playing]) {
        [self.audioManager play];
    }
    
    // Get sound samples from the microphone and send it to the audio manager
    [self.audioManager setInputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels)
     {
         if (ringBuffer != nil) {
             ringBuffer->AddNewFloatData(data, numFrames);
         }
     }];
    
    // Set the output block to nil so that the sound from Module B isn't playing
    [self.audioManager setOutputBlock:nil];

    
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause audioManager and stop timer
    [self.audioManager pause];
    [self.timer invalidate];
}

// Convert the frequency to the note played
- (NSString*)getNoteFromFrequency:(float)frequency {
    int index = (int)round(log10f(frequency / 16.35) / log10f(pow(2.0, 1.0/12.0)));
    
    // Make sure the frequency is within the range of notes we have
    if (index < 0 || index > 107) {
        return @"--";
    }
    
    return self.notes[index];
}

// Dealloc things; ARC handles everything else, just clean up what we used c++ for (calloc, malloc, new)
- (void)dealloc {
    free(self.audioData);
    free(self.fftMagnitudeBuffer);
    free(self.fftPhaseBuffer);
    
    delete self.fftHelper;
    delete ringBuffer;
    
    ringBuffer = nil;
    self.fftHelper  = nil;
    self.audioManager = nil;
}

- (void)update {
    // Plot the audio
    ringBuffer->FetchFreshData2(self.audioData, kBufferLength, 0, 1);
    
    // Take the FFT
    self.fftHelper->forward(0,self.audioData, self.fftMagnitudeBuffer, self.fftPhaseBuffer);
    
    // Saves the old peak one/two values to compare later to see if we actually want to replace them
    int oldPeakOneIndex = self.peakOneIndex;
    int oldPeakTwoIndex = self.peakTwoIndex;
    float oldPeakOneFreq = self.peakOneFreq;
    float oldPeakTwoFreq = self.peakTwoFreq;
    
    // Resets the peak indices and frequencies to 0
    self.peakOneIndex = 0;
    self.peakTwoIndex = 0;
    self.peakOneFreq = 0;
    self.peakTwoFreq = 0;
    
    // Loops through the buffer to find peak one and peak two
    for (int i = 0; i < kPaddedBufferLength/2 - kWindowSize; i++) {
        int index = [self maxIndex:self.fftMagnitudeBuffer startIndex:i length:kWindowSize];
        // Check the index is the midpoint
        if (index == i + (kWindowSize - 1)/2 && self.fftMagnitudeBuffer[index] > 20) {
            [self compareAndSetPeakValues:index peakOneIndex:self.peakOneIndex peakTwoIndex:self.peakTwoIndex data:self.fftMagnitudeBuffer];
        }
    }
    
    // Uses interpolation to find the frequency for peak one/two
    self.peakOneFreq = [self getFrequency:self.peakOneIndex data:self.fftMagnitudeBuffer];
    self.peakTwoFreq = [self getFrequency:self.peakTwoIndex data:self.fftMagnitudeBuffer];
    
    // Compares the new peak values to the old peak values and resets
    // the new peak values to the old peak values if they are within
    // a 6Hz range of each other
    [self chooseAndSetPeakIndex:oldPeakOneIndex oldFreq:oldPeakOneFreq newIndex:self.peakOneIndex newFreq:self.peakOneFreq peak:1];
    [self chooseAndSetPeakIndex:oldPeakTwoIndex oldFreq:oldPeakTwoFreq newIndex:self.peakTwoIndex newFreq:self.peakTwoFreq peak:2];
    
    // Makes peak one have the higher frequency and peak two the lower frequency
    [self orderPeaks];
    
    // Sets peak one labels for frequency and note
    if (self.peakOneFreq == 0) {
        self.peakOneLabel.text = [NSString stringWithFormat:@"-- Hz"];
        self.peakOneNoteLabel.text = [NSString stringWithFormat:@"--"];
    } else {
        self.peakOneLabel.text = [NSString stringWithFormat:@"%.0f Hz", self.peakOneFreq];
        self.peakOneNoteLabel.text = [NSString stringWithFormat:@"%@", [self getNoteFromFrequency:self.peakOneFreq]];
    }
    
    // Sets peak two labels for frequency and note
    if (self.peakTwoFreq == 0) {
        self.peakTwoLabel.text = [NSString stringWithFormat:@"-- Hz"];
        self.peakTwoNoteLabel.text = [NSString stringWithFormat:@"--"];
    } else {
        self.peakTwoLabel.text = [NSString stringWithFormat:@"%.0f Hz", self.peakTwoFreq];
        self.peakTwoNoteLabel.text = [NSString stringWithFormat:@"%@", [self getNoteFromFrequency:self.peakTwoFreq]];
    }

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

// Replaces the smaller of the two peaks with the new index (which has the potential peak if it's higher)
- (void)compareAndSetPeakValues:(int)index
         peakOneIndex:(int)peakOneIndex
         peakTwoIndex:(int)peakTwoIndex
                 data:(float*)data {
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

// Makes peak one larger in frequency than peak two
- (void)orderPeaks {
    if (self.peakOneIndex < self.peakTwoIndex) {
        int tempIndex = self.peakOneIndex;
        self.peakOneIndex = self.peakTwoIndex;
        self.peakTwoIndex = tempIndex;
        
        int tempFreq = self.peakOneFreq;
        self.peakOneFreq = self.peakTwoFreq;
        self.peakTwoFreq = tempFreq;
    }
}

// Uses quadratic interpolation to estimate the peak frequency given an index and an array of data
- (float)getFrequency:(int)index
                 data:(float*)data {
    if (index == 0) {
        return 0;
    }
    
    float f2 = index * kdf;
    float m1 = data[index - 1];
    float m2 = data[index];
    float m3 = data[index + 1];
    
    return f2 + ((m3 - m2) / (2.0 * m2 - m1 - m2)) * kdf / 2.0;
}

// Compares the old frequencies to the new frequencies, and if the new frequencies and within
// bounds of the old frequencies it sets the peaks the old values
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
