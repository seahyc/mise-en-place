package voice

import (
	"encoding/binary"
	"fmt"
)

// DecodeToPCM interprets raw bytes as little-endian int16 PCM samples.
// For v1, this is a pass-through — real Opus decoding will be added when
// CGO + libopus are available.
func DecodeToPCM(data []byte, sampleRate, channels int) ([]int16, error) {
	if len(data)%2 != 0 {
		return nil, fmt.Errorf("audio: data length %d is not a multiple of 2", len(data))
	}

	numSamples := len(data) / 2
	samples := make([]int16, numSamples)
	for i := 0; i < numSamples; i++ {
		samples[i] = int16(binary.LittleEndian.Uint16(data[i*2 : i*2+2]))
	}
	return samples, nil
}

// EncodePCM encodes int16 PCM samples as little-endian bytes.
// For v1, this is a pass-through — real Opus encoding will be added when
// CGO + libopus are available.
func EncodePCM(pcm []int16, sampleRate, channels int) ([]byte, error) {
	data := make([]byte, len(pcm)*2)
	for i, s := range pcm {
		binary.LittleEndian.PutUint16(data[i*2:i*2+2], uint16(s))
	}
	return data, nil
}
