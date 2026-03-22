package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os/exec"
	"strings"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/stt"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// Sentinel errors for the ingestion service.
var (
	ErrInvalidURL       = errors.New("ingestion: invalid or unsupported URL")
	ErrExtractionFailed = errors.New("ingestion: media extraction failed")
)

// Allowed hostnames for video ingestion.
var allowedHosts = map[string]bool{
	"youtube.com":     true,
	"www.youtube.com": true,
	"youtu.be":        true,
	"tiktok.com":      true,
	"www.tiktok.com":  true,
	"instagram.com":   true,
	"www.instagram.com": true,
	"bilibili.com":    true,
	"www.bilibili.com": true,
	"xiaohongshu.com":  true,
	"www.xiaohongshu.com": true,
}

// ExtractionResult holds the output of a media extraction.
type ExtractionResult struct {
	AudioPath   string
	Title       string
	Description string
	Comments    string
}

// MediaExtractor extracts audio and metadata from a URL.
type MediaExtractor interface {
	Extract(ctx context.Context, url, outputDir string) (*ExtractionResult, error)
}

// YtdlpExtractor implements MediaExtractor using yt-dlp.
type YtdlpExtractor struct{}

// NewYtdlpExtractor creates a new YtdlpExtractor.
func NewYtdlpExtractor() *YtdlpExtractor {
	return &YtdlpExtractor{}
}

// Extract uses yt-dlp to download audio and extract metadata.
func (e *YtdlpExtractor) Extract(ctx context.Context, videoURL, outputDir string) (*ExtractionResult, error) {
	audioPath := outputDir + "/audio.m4a"

	cmd := exec.CommandContext(ctx, "yt-dlp",
		"-x",
		"--audio-format", "m4a",
		"-o", audioPath,
		"--write-info-json",
		videoURL,
	)
	if output, err := cmd.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("%w: %s: %s", ErrExtractionFailed, err, string(output))
	}

	return &ExtractionResult{
		AudioPath: audioPath,
	}, nil
}

// JobRepo defines the interface needed by the ingestion service for job tracking.
type JobRepo interface {
	Create(ctx context.Context, jobType types.JobType, userID types.UserID, payload map[string]any) (string, error)
	GetByID(ctx context.Context, id string) (*types.Job, error)
	Complete(ctx context.Context, id string, result map[string]any) error
	Fail(ctx context.Context, id string, errMsg string) error
}

// ParsedRecipe represents a recipe extracted from a transcript by the LLM.
type ParsedRecipe struct {
	Title       string       `json:"title"`
	Description string       `json:"description"`
	Cuisine     string       `json:"cuisine"`
	Ingredients []string     `json:"ingredients"`
	Steps       []ParsedStep `json:"steps"`
}

// ParsedStep represents a step in a parsed recipe.
type ParsedStep struct {
	OrderIndex int    `json:"order_index"`
	Text       string `json:"text"`
}

// IngestionService handles video ingestion workflow.
type IngestionService struct {
	llmClient llm.Client
	sttClient stt.Client
	recipes   repo.RecipeRepo
	jobs      JobRepo
	extractor MediaExtractor
}

// NewIngestionService creates a new IngestionService.
func NewIngestionService(
	llmClient llm.Client,
	sttClient stt.Client,
	recipes repo.RecipeRepo,
	jobs JobRepo,
	extractor MediaExtractor,
) *IngestionService {
	return &IngestionService{
		llmClient: llmClient,
		sttClient: sttClient,
		recipes:   recipes,
		jobs:       jobs,
		extractor: extractor,
	}
}

// ValidateIngestionURL checks that a URL is from an allowed host.
func ValidateIngestionURL(rawURL string) error {
	u, err := url.Parse(rawURL)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return ErrInvalidURL
	}
	host := strings.ToLower(u.Hostname())
	if !allowedHosts[host] {
		return ErrInvalidURL
	}
	return nil
}

// Ingest validates the URL, creates a job, and returns the job ID.
func (s *IngestionService) Ingest(ctx context.Context, userID types.UserID, videoURL string) (string, error) {
	if err := ValidateIngestionURL(videoURL); err != nil {
		return "", err
	}

	jobID, err := s.jobs.Create(ctx, types.JobIngestVideo, userID, map[string]any{
		"url": videoURL,
	})
	if err != nil {
		return "", fmt.Errorf("ingestion: create job: %w", err)
	}

	return jobID, nil
}

// ProcessJob executes the full ingestion pipeline for a job.
func (s *IngestionService) ProcessJob(ctx context.Context, jobID string) error {
	job, err := s.jobs.GetByID(ctx, jobID)
	if err != nil {
		return fmt.Errorf("ingestion: get job: %w", err)
	}
	if job == nil {
		return fmt.Errorf("ingestion: job not found: %s", jobID)
	}

	videoURL, _ := job.Payload["url"].(string)

	// Step 1: Extract audio
	outputDir := fmt.Sprintf("/tmp/ingestion/%s", jobID)
	result, err := s.extractor.Extract(ctx, videoURL, outputDir)
	if err != nil {
		_ = s.jobs.Fail(ctx, jobID, err.Error())
		return err
	}

	// Step 2: Transcribe
	// In production, we'd read the audio file. Here we pass the path as placeholder.
	transcript, err := s.sttClient.Transcribe(ctx, []byte(result.AudioPath), "m4a")
	if err != nil {
		_ = s.jobs.Fail(ctx, jobID, err.Error())
		return fmt.Errorf("ingestion: transcribe: %w", err)
	}

	// Step 3: Parse recipe from transcript using LLM
	parsed, err := s.parseRecipe(ctx, transcript)
	if err != nil {
		_ = s.jobs.Fail(ctx, jobID, err.Error())
		return fmt.Errorf("ingestion: parse recipe: %w", err)
	}

	// Step 4: Save to DB
	steps := make([]repo.StepInput, len(parsed.Steps))
	for i, step := range parsed.Steps {
		steps[i] = repo.StepInput{OrderIndex: step.OrderIndex, Text: step.Text}
	}

	recipe, err := s.recipes.Create(ctx, repo.CreateRecipeArgs{
		UserID:      job.UserID,
		Title:       parsed.Title,
		Description: parsed.Description,
		SourceURL:   videoURL,
		SourceType:  "video",
		Cuisine:     parsed.Cuisine,
		Ingredients: parsed.Ingredients,
		Steps:       steps,
	})
	if err != nil {
		_ = s.jobs.Fail(ctx, jobID, err.Error())
		return fmt.Errorf("ingestion: save recipe: %w", err)
	}

	_ = s.jobs.Complete(ctx, jobID, map[string]any{
		"recipe_id": string(recipe.ID),
	})

	return nil
}

// parseRecipe sends the transcript to the LLM and parses the structured recipe response.
func (s *IngestionService) parseRecipe(ctx context.Context, transcript string) (*ParsedRecipe, error) {
	prompt := `You are a recipe parser. Given the following transcript from a cooking video, extract a structured recipe in JSON format with fields: title, description, cuisine, ingredients (array of strings), steps (array of objects with order_index and text). Return ONLY the JSON.

Transcript:
` + transcript

	resp, err := s.llmClient.Chat(ctx, []llm.Message{
		{Role: "user", Content: prompt},
	})
	if err != nil {
		return nil, err
	}

	var parsed ParsedRecipe
	content := strings.TrimSpace(resp.Content)
	// Strip markdown code fences if present
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	if err := json.Unmarshal([]byte(content), &parsed); err != nil {
		return nil, fmt.Errorf("parse recipe JSON: %w", err)
	}

	return &parsed, nil
}
