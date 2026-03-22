package voice

import "math"

// VADResult reports whether a frame contains speech.
type VADResult struct {
	IsSpeech   bool
	Confidence float32
}

// VAD defines the interface for voice activity detection.
// ProcessFrame takes PCM int16 samples (NOT Opus-encoded bytes).
type VAD interface {
	ProcessFrame(pcmSamples []int16) VADResult
	Reset()
}

// EnergyVAD is a simple energy-based voice activity detector.
// It computes the RMS energy of each PCM frame and compares it to a threshold.
// After speech is detected, it tracks consecutive silent frames to detect
// end-of-speech. When end-of-speech is detected it returns IsSpeech=false
// with Confidence=-1 as a sentinel value.
type EnergyVAD struct {
	// Threshold is the minimum RMS energy to consider speech.
	Threshold float64

	// MaxSilenceFrames is the number of consecutive silent frames after speech
	// before end-of-speech is signalled. At 20ms per frame, 30 frames = 600ms.
	MaxSilenceFrames int

	inSpeech      bool
	silenceFrames int
}

// NewEnergyVAD creates a new EnergyVAD with sensible defaults.
func NewEnergyVAD() *EnergyVAD {
	return &EnergyVAD{
		Threshold:        500,
		MaxSilenceFrames: 30, // 30 frames * 20ms = 600ms
	}
}

// ProcessFrame computes RMS energy of a PCM int16 frame and returns a VADResult.
// When end-of-speech is detected (silence after speech), it returns
// VADResult{IsSpeech: false, Confidence: -1} as a sentinel.
func (v *EnergyVAD) ProcessFrame(pcmSamples []int16) VADResult {
	if len(pcmSamples) == 0 {
		return VADResult{IsSpeech: false, Confidence: 0}
	}

	rms := computeRMS(pcmSamples)
	isSpeech := rms >= v.Threshold

	if isSpeech {
		v.inSpeech = true
		v.silenceFrames = 0
		confidence := float32(math.Min(rms/v.Threshold, 10.0) / 10.0)
		return VADResult{IsSpeech: true, Confidence: confidence}
	}

	// Not speech.
	if v.inSpeech {
		v.silenceFrames++
		if v.silenceFrames >= v.MaxSilenceFrames {
			// End-of-speech detected.
			v.inSpeech = false
			v.silenceFrames = 0
			return VADResult{IsSpeech: false, Confidence: -1}
		}
		// Still within the silence tolerance window.
		return VADResult{IsSpeech: false, Confidence: 0}
	}

	return VADResult{IsSpeech: false, Confidence: 0}
}

// Reset clears the internal state.
func (v *EnergyVAD) Reset() {
	v.inSpeech = false
	v.silenceFrames = 0
}

// computeRMS computes the root-mean-square energy of PCM int16 samples.
func computeRMS(samples []int16) float64 {
	var sumSq float64
	for _, s := range samples {
		sumSq += float64(s) * float64(s)
	}
	return math.Sqrt(sumSq / float64(len(samples)))
}
