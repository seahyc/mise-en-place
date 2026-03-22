package voice_test

import (
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/voice"
)

// Verify EnergyVAD satisfies the VAD interface.
var _ voice.VAD = (*voice.EnergyVAD)(nil)

func TestEnergyVAD_Zeros(t *testing.T) {
	vad := voice.NewEnergyVAD()
	silence := make([]int16, 320) // 20ms at 16kHz

	result := vad.ProcessFrame(silence)
	if result.IsSpeech {
		t.Error("expected silence for zero samples")
	}
}

func TestEnergyVAD_LoudSamples(t *testing.T) {
	vad := voice.NewEnergyVAD()
	loud := make([]int16, 320)
	for i := range loud {
		loud[i] = 10000
	}

	result := vad.ProcessFrame(loud)
	if !result.IsSpeech {
		t.Error("expected speech for loud samples")
	}
	if result.Confidence <= 0 {
		t.Error("expected positive confidence for speech")
	}
}

func TestEnergyVAD_EndOfSpeech(t *testing.T) {
	vad := voice.NewEnergyVAD()

	// Generate speech.
	loud := make([]int16, 320)
	for i := range loud {
		loud[i] = 10000
	}
	vad.ProcessFrame(loud)

	// Now send enough silence frames to trigger end-of-speech.
	silence := make([]int16, 320)
	var endDetected bool
	for i := 0; i < 40; i++ {
		result := vad.ProcessFrame(silence)
		if !result.IsSpeech && result.Confidence == -1 {
			endDetected = true
			break
		}
	}

	if !endDetected {
		t.Error("expected end-of-speech to be detected after silence following speech")
	}
}

func TestEnergyVAD_Reset(t *testing.T) {
	vad := voice.NewEnergyVAD()

	// Generate speech then reset.
	loud := make([]int16, 320)
	for i := range loud {
		loud[i] = 10000
	}
	vad.ProcessFrame(loud)
	vad.Reset()

	// Silence after reset should NOT trigger end-of-speech.
	silence := make([]int16, 320)
	for i := 0; i < 40; i++ {
		result := vad.ProcessFrame(silence)
		if result.Confidence == -1 {
			t.Error("did not expect end-of-speech after reset")
			break
		}
	}
}

func TestEnergyVAD_EmptyFrame(t *testing.T) {
	vad := voice.NewEnergyVAD()
	result := vad.ProcessFrame(nil)
	if result.IsSpeech {
		t.Error("expected no speech for empty frame")
	}
}
