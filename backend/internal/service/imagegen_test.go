package service

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// stubImageGenerator returns a fixed image.
type stubImageGenerator struct {
	lastPrompt string
}

func (s *stubImageGenerator) Generate(_ context.Context, prompt string) ([]byte, error) {
	s.lastPrompt = prompt
	return []byte("fake-image-data"), nil
}

func TestBuildPrompt(t *testing.T) {
	prompt := BuildPrompt("Boil the pasta")
	if !strings.Contains(prompt, "Boil the pasta") {
		t.Errorf("prompt should contain step text, got %q", prompt)
	}
	if !strings.Contains(prompt, "food photography style") {
		t.Errorf("prompt should contain style directive, got %q", prompt)
	}
	if !strings.Contains(prompt, "Cooking step illustration") {
		t.Errorf("prompt should contain illustration prefix, got %q", prompt)
	}
}

func TestImageGenService_ImagePath(t *testing.T) {
	svc := NewImageGenService(nil, "/data/images")
	path := svc.ImagePath("recipe-123", 2)
	expected := filepath.Join("/data/images", "recipe-123", "2.webp")
	if path != expected {
		t.Errorf("ImagePath = %q, want %q", path, expected)
	}
}

func TestImageGenService_GenerateStepImage(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "imagegen-test")
	if err != nil {
		t.Fatalf("create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	gen := &stubImageGenerator{}
	svc := NewImageGenService(gen, tmpDir)

	path, err := svc.GenerateStepImage(context.Background(), "recipe-abc", 0, "Chop the onions")
	if err != nil {
		t.Fatalf("GenerateStepImage: %v", err)
	}

	// Verify prompt was constructed correctly
	if !strings.Contains(gen.lastPrompt, "Chop the onions") {
		t.Errorf("prompt = %q, should contain step text", gen.lastPrompt)
	}

	// Verify file was written
	expectedPath := filepath.Join(tmpDir, "recipe-abc", "0.webp")
	if path != expectedPath {
		t.Errorf("path = %q, want %q", path, expectedPath)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read file: %v", err)
	}
	if string(data) != "fake-image-data" {
		t.Errorf("file content = %q, want %q", string(data), "fake-image-data")
	}
}

func TestImageGeneratorInterface(t *testing.T) {
	var _ ImageGenerator = (*stubImageGenerator)(nil)
	var _ ImageGenerator = (*SiliconFlowGenerator)(nil)
}
