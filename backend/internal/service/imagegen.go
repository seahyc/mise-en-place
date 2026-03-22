package service

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// ImageGenerator generates images from text prompts.
type ImageGenerator interface {
	Generate(ctx context.Context, prompt string) ([]byte, error)
}

// SiliconFlowGenerator implements ImageGenerator using the Silicon Flow API.
type SiliconFlowGenerator struct {
	apiKey  string
	baseURL string
}

// NewSiliconFlowGenerator creates a new SiliconFlowGenerator.
func NewSiliconFlowGenerator(apiKey string) *SiliconFlowGenerator {
	return &SiliconFlowGenerator{
		apiKey:  apiKey,
		baseURL: "https://api.siliconflow.cn/v1/images/generations",
	}
}

// Generate sends a prompt to the Silicon Flow API and returns the image bytes.
func (g *SiliconFlowGenerator) Generate(_ context.Context, _ string) ([]byte, error) {
	// Implementation would POST to Silicon Flow API
	// Stub for now — real implementation requires API integration
	return nil, fmt.Errorf("imagegen: not implemented")
}

// ImageGenService handles step image generation.
type ImageGenService struct {
	generator ImageGenerator
	dataDir   string
}

// NewImageGenService creates a new ImageGenService.
func NewImageGenService(generator ImageGenerator, dataDir string) *ImageGenService {
	if dataDir == "" {
		dataDir = "/data/images"
	}
	return &ImageGenService{
		generator: generator,
		dataDir:   dataDir,
	}
}

// BuildPrompt constructs a prompt for generating a step illustration.
func BuildPrompt(stepText string) string {
	return fmt.Sprintf("Cooking step illustration: %s, food photography style", stepText)
}

// ImagePath returns the file path for a step image.
func (s *ImageGenService) ImagePath(recipeID types.RecipeID, stepIndex int) string {
	return filepath.Join(s.dataDir, string(recipeID), fmt.Sprintf("%d.webp", stepIndex))
}

// GenerateStepImage generates an image for a recipe step and saves it to disk.
func (s *ImageGenService) GenerateStepImage(ctx context.Context, recipeID types.RecipeID, stepIndex int, stepText string) (string, error) {
	prompt := BuildPrompt(stepText)

	imageData, err := s.generator.Generate(ctx, prompt)
	if err != nil {
		return "", fmt.Errorf("imagegen: generate: %w", err)
	}

	imgPath := s.ImagePath(recipeID, stepIndex)
	dir := filepath.Dir(imgPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("imagegen: mkdir: %w", err)
	}

	if err := os.WriteFile(imgPath, imageData, 0o644); err != nil {
		return "", fmt.Errorf("imagegen: write file: %w", err)
	}

	return imgPath, nil
}
