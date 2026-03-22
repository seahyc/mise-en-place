package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"github.com/yingcong/mise-en-place/backend/internal/config"
	"github.com/yingcong/mise-en-place/backend/internal/handler"
	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/stt"
	"github.com/yingcong/mise-en-place/backend/internal/tts"
	"github.com/yingcong/mise-en-place/backend/internal/types"
	"github.com/yingcong/mise-en-place/backend/internal/voice"
	"github.com/yingcong/mise-en-place/backend/internal/worker"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// --- Database ---
	pool, err := repo.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	// --- Repos ---
	userRepo := repo.NewPgUserRepo(pool)
	rtRepo := repo.NewPgRefreshTokenRepo(pool)
	recipeRepo := repo.NewPgRecipeRepo(pool)
	sessionRepo := repo.NewPgSessionRepo(pool)
	jobRepo := repo.NewPgJobRepo(pool)
	convRepo := repo.NewPgConversationRepo(pool)

	// --- External Clients ---
	var llmClient llm.Client
	if cfg.KimiAPIKey != "" {
		llmClient = llm.NewKimiClient(cfg.KimiAPIKey, "moonshot-v1-8k")
		slog.Info("using Kimi LLM")
	} else if cfg.GLMAPIKey != "" {
		llmClient = llm.NewGLMClient(cfg.GLMAPIKey, "glm-4-flash")
		slog.Info("using GLM LLM")
	} else {
		slog.Warn("no LLM API key configured — ingestion and merging will fail")
	}

	var sttClient stt.Client
	if cfg.GroqAPIKey != "" {
		sttClient = stt.NewGroqClient(cfg.GroqAPIKey)
		slog.Info("using Groq Whisper STT")
	} else {
		slog.Warn("no Groq API key configured — voice transcription will fail")
	}

	ttsClient := tts.NewKokoroClient()

	// --- Services ---
	authSvc := service.NewAuthService(userRepo, rtRepo, cfg.JWTSecret)
	recipeSvc := service.NewRecipeService(recipeRepo)
	mergeSvc := service.NewMergeService(llmClient)
	sessionSvc := service.NewSessionService(sessionRepo, recipeRepo, mergeSvc)

	var ingestionSvc *service.IngestionService
	if llmClient != nil && sttClient != nil {
		ingestionSvc = service.NewIngestionService(
			llmClient, sttClient, recipeRepo, jobRepo,
			service.NewYtdlpExtractor(),
		)
	}

	// --- Voice Pipeline ---
	vad := voice.NewEnergyVAD()
	var pipeline *voice.Pipeline
	if llmClient != nil && sttClient != nil {
		pipeline = voice.NewPipeline(sttClient, llmClient, ttsClient, vad, convRepo)
		slog.Info("voice pipeline initialized")
	} else {
		slog.Warn("voice pipeline disabled — missing LLM or STT client")
	}

	// --- Handlers ---
	authHandler := handler.NewAuthHandler(authSvc)
	recipeHandler := handler.NewRecipeHandler(recipeSvc)
	sessionHandler := handler.NewSessionHandler(sessionSvc)
	sessionHub := handler.NewSessionHub()

	// --- Router ---
	r := chi.NewRouter()
	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(chimw.Recoverer)
	r.Use(slogMiddleware)
	r.Use(corsMiddleware)

	// Public routes
	r.Get("/health", handler.HealthCheck)
	r.Post("/auth/register", authHandler.Register)
	r.Post("/auth/login", authHandler.Login)
	r.Post("/auth/refresh", authHandler.Refresh)
	r.Post("/auth/google", authHandler.GoogleLogin)

	// Protected routes
	r.Group(func(r chi.Router) {
		r.Use(handler.AuthMiddleware(cfg.JWTSecret))

		// User
		r.Get("/me", func(w http.ResponseWriter, r *http.Request) {
			userID := handler.GetUserID(r.Context())
			handler.WriteJSON(w, http.StatusOK, map[string]string{"user_id": string(userID)})
		})

		// Recipes
		r.Route("/recipes", func(r chi.Router) {
			r.Post("/", recipeHandler.Create)
			r.Get("/", recipeHandler.List)
			r.Get("/{id}", recipeHandler.Get)
			r.Put("/{id}", recipeHandler.Update)
			r.Delete("/{id}", recipeHandler.Delete)
		})

		// Cooking Sessions
		r.Route("/sessions", func(r chi.Router) {
			r.Post("/", sessionHandler.Create)
			r.Get("/", sessionHandler.List)
			r.Get("/{id}", sessionHandler.Get)
			r.Post("/{id}/start", sessionHandler.Start)
			r.Post("/{id}/pause", sessionHandler.Pause)
			r.Post("/{id}/resume", sessionHandler.Resume)
			r.Post("/{id}/steps/{stepID}/complete", sessionHandler.CompleteStep)
		})

		// Ingestion
		if ingestionSvc != nil {
			ingestHandler := handler.NewIngestHandler(ingestionSvc, jobRepo)
			r.Post("/ingest", ingestHandler.Ingest)
			r.Get("/jobs/{id}", ingestHandler.GetJob)
		}
	})

	// WebSocket routes (auth handled inside)
	if pipeline != nil {
		voiceHandler := handler.NewVoiceHandler(cfg.JWTSecret, pipeline)
		r.Get("/ws/voice", voiceHandler.HandleVoice)
	}
	r.Get("/ws/session/{id}", handler.SessionWebSocket(sessionHub, cfg.JWTSecret))

	// --- Background Workers ---
	if ingestionSvc != nil {
		ingestWorker := worker.NewWorker(jobRepo, types.JobIngestVideo,
			func(ctx context.Context, job *types.Job) (map[string]any, error) {
				return nil, ingestionSvc.ProcessJob(ctx, job.ID)
			}, 2*time.Second)
		go ingestWorker.Run(ctx)
		slog.Info("ingestion worker started")
	}

	if cfg.SiliconFlowKey != "" {
		imgGenerator := service.NewSiliconFlowGenerator(cfg.SiliconFlowKey)
		imgSvc := service.NewImageGenService(imgGenerator, "/data/images")
		imgWorker := worker.NewWorker(jobRepo, types.JobGenerateImages,
			func(ctx context.Context, job *types.Job) (map[string]any, error) {
				recipeID, _ := job.Payload["recipe_id"].(string)
				stepIndex, _ := job.Payload["step_index"].(float64)
				stepText, _ := job.Payload["step_text"].(string)
				path, err := imgSvc.GenerateStepImage(ctx, types.RecipeID(recipeID), int(stepIndex), stepText)
				if err != nil {
					return nil, err
				}
				return map[string]any{"image_path": path}, nil
			}, 5*time.Second)
		go imgWorker.Run(ctx)
		slog.Info("image generation worker started")
	}

	// --- Start Server ---
	srv := &http.Server{Addr: cfg.ListenAddr, Handler: r}

	go func() {
		slog.Info("server starting", "addr", cfg.ListenAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	slog.Info("shutting down server")
	cancel() // stop workers

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("server shutdown error", "error", err)
	}
	slog.Info("server stopped")
}

func slogMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"duration_ms", time.Since(start).Milliseconds(),
			"request_id", chimw.GetReqID(r.Context()),
		)
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}
