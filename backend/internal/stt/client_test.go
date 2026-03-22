package stt_test

import (
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/stt"
)

// TestGroqClientInterface verifies GroqClient satisfies Client at compile time.
func TestGroqClientInterface(t *testing.T) {
	var _ stt.Client = (*stt.GroqClient)(nil)
}
