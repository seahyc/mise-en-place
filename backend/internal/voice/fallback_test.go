package voice_test

import (
	"context"
	"errors"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/voice"
)

func TestFallbackSTT_PrimarySucceeds(t *testing.T) {
	primary := &stubSTT{text: "hello from primary"}
	fallback := &stubSTT{text: "hello from fallback"}

	client := voice.NewFallbackSTTClient(primary, fallback)
	text, err := client.Transcribe(context.Background(), nil, "pcm")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if text != "hello from primary" {
		t.Errorf("got %q, want %q", text, "hello from primary")
	}
}

func TestFallbackSTT_PrimaryFailsFallbackSucceeds(t *testing.T) {
	primary := &stubSTT{err: errors.New("primary down")}
	fallback := &stubSTT{text: "hello from fallback"}

	client := voice.NewFallbackSTTClient(primary, fallback)
	text, err := client.Transcribe(context.Background(), nil, "pcm")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if text != "hello from fallback" {
		t.Errorf("got %q, want %q", text, "hello from fallback")
	}
}

func TestFallbackSTT_BothFail(t *testing.T) {
	primary := &stubSTT{err: errors.New("primary down")}
	fallback := &stubSTT{err: errors.New("fallback down")}

	client := voice.NewFallbackSTTClient(primary, fallback)
	_, err := client.Transcribe(context.Background(), nil, "pcm")
	if err == nil {
		t.Error("expected error when both STT clients fail")
	}
}

func TestFallbackLLM_PrimarySucceeds(t *testing.T) {
	primary := &stubLLM{resp: &llm.Response{Content: "primary response"}}
	secondary := &stubLLM{resp: &llm.Response{Content: "secondary response"}}

	client := voice.NewFallbackLLMClient(primary, secondary)
	resp, err := client.ChatWithTools(context.Background(), nil, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.Content != "primary response" {
		t.Errorf("got %q, want %q", resp.Content, "primary response")
	}
}

func TestFallbackLLM_PrimaryFailsSecondarySucceeds(t *testing.T) {
	primary := &stubLLM{err: errors.New("primary down")}
	secondary := &stubLLM{resp: &llm.Response{Content: "secondary response"}}

	client := voice.NewFallbackLLMClient(primary, secondary)
	resp, err := client.ChatWithTools(context.Background(), nil, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.Content != "secondary response" {
		t.Errorf("got %q, want %q", resp.Content, "secondary response")
	}
}

func TestFallbackLLM_BothFail(t *testing.T) {
	primary := &stubLLM{err: errors.New("primary down")}
	secondary := &stubLLM{err: errors.New("secondary down")}

	client := voice.NewFallbackLLMClient(primary, secondary)
	_, err := client.ChatWithTools(context.Background(), nil, nil)
	if err == nil {
		t.Error("expected error when both LLM clients fail")
	}
}
