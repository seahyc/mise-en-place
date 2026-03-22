package voice_test

import (
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/voice"
)

func TestRoundTrip(t *testing.T) {
	original := []int16{0, 1, -1, 32767, -32768, 1000, -1000}

	encoded, err := voice.EncodePCM(original, 16000, 1)
	if err != nil {
		t.Fatalf("EncodePCM: %v", err)
	}

	decoded, err := voice.DecodeToPCM(encoded, 16000, 1)
	if err != nil {
		t.Fatalf("DecodeToPCM: %v", err)
	}

	if len(decoded) != len(original) {
		t.Fatalf("got %d samples, want %d", len(decoded), len(original))
	}

	for i := range original {
		if decoded[i] != original[i] {
			t.Errorf("sample %d: got %d, want %d", i, decoded[i], original[i])
		}
	}
}

func TestDecodeToPCM_OddLength(t *testing.T) {
	_, err := voice.DecodeToPCM([]byte{0x01, 0x02, 0x03}, 16000, 1)
	if err == nil {
		t.Error("expected error for odd-length data")
	}
}

func TestEncodePCM_Empty(t *testing.T) {
	data, err := voice.EncodePCM(nil, 16000, 1)
	if err != nil {
		t.Fatalf("EncodePCM: %v", err)
	}
	if len(data) != 0 {
		t.Errorf("expected empty data, got %d bytes", len(data))
	}
}
