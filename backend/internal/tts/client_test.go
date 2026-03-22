package tts_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/tts"
)

// Verify KokoroClient satisfies the Client interface.
var _ tts.Client = (*tts.KokoroClient)(nil)

func TestKokoroSynthesize(t *testing.T) {
	wantPCM := []byte{0x01, 0x02, 0x03, 0x04}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/audio/speech" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		if r.Method != http.MethodPost {
			t.Errorf("unexpected method: %s", r.Method)
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		var req map[string]any
		if err := json.Unmarshal(body, &req); err != nil {
			t.Fatalf("unmarshal: %v", err)
		}
		if req["model"] != "kokoro" {
			t.Errorf("expected model kokoro, got %v", req["model"])
		}
		if req["voice"] != "af_sarah" {
			t.Errorf("expected voice af_sarah, got %v", req["voice"])
		}
		if req["response_format"] != "pcm" {
			t.Errorf("expected format pcm, got %v", req["response_format"])
		}
		if req["stream"] != false {
			t.Errorf("expected stream false, got %v", req["stream"])
		}
		if req["input"] != "hello world" {
			t.Errorf("expected input 'hello world', got %v", req["input"])
		}

		w.WriteHeader(http.StatusOK)
		w.Write(wantPCM)
	}))
	defer srv.Close()

	client := tts.NewKokoroClient(tts.WithBaseURL(srv.URL))

	got, err := client.Synthesize(context.Background(), "hello world")
	if err != nil {
		t.Fatalf("Synthesize: %v", err)
	}
	if len(got) != len(wantPCM) {
		t.Fatalf("got %d bytes, want %d", len(got), len(wantPCM))
	}
	for i := range wantPCM {
		if got[i] != wantPCM[i] {
			t.Errorf("byte %d: got %02x, want %02x", i, got[i], wantPCM[i])
		}
	}
}

func TestKokoroSynthesizeStream(t *testing.T) {
	wantChunks := [][]byte{{0x01, 0x02}, {0x03, 0x04}}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var req map[string]any
		json.Unmarshal(body, &req)
		if req["stream"] != true {
			t.Errorf("expected stream true, got %v", req["stream"])
		}

		flusher, ok := w.(http.Flusher)
		if !ok {
			t.Fatal("expected flusher")
		}
		w.WriteHeader(http.StatusOK)
		for _, chunk := range wantChunks {
			w.Write(chunk)
			flusher.Flush()
		}
	}))
	defer srv.Close()

	client := tts.NewKokoroClient(tts.WithBaseURL(srv.URL))
	out := make(chan []byte, 10)

	err := client.SynthesizeStream(context.Background(), "hello", out)
	if err != nil {
		t.Fatalf("SynthesizeStream: %v", err)
	}

	var gotBytes []byte
	for chunk := range out {
		gotBytes = append(gotBytes, chunk...)
	}
	if len(gotBytes) != 4 {
		t.Fatalf("got %d total bytes, want 4", len(gotBytes))
	}
}

func TestKokoroHealthy(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/health" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	client := tts.NewKokoroClient(tts.WithBaseURL(srv.URL))
	if !client.Healthy(context.Background()) {
		t.Error("expected healthy = true")
	}
}

func TestKokoroHealthyDown(t *testing.T) {
	// Point at a server that doesn't exist.
	client := tts.NewKokoroClient(tts.WithBaseURL("http://127.0.0.1:1"))
	if client.Healthy(context.Background()) {
		t.Error("expected healthy = false for unreachable server")
	}
}
