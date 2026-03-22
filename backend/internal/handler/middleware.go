package handler

import (
	"context"
	"net/http"
	"strings"

	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// contextKey is an unexported type used for context keys to avoid collisions.
type contextKey string

const userIDKey contextKey = "userID"

// AuthMiddleware returns middleware that extracts a Bearer token from the
// Authorization header, validates it as a JWT, and puts the UserID into the
// request context.
func AuthMiddleware(jwtSecret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing authorization header"})
				return
			}

			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
				WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid authorization header"})
				return
			}

			userID, err := service.ParseAccessToken(parts[1], jwtSecret)
			if err != nil {
				WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid token"})
				return
			}

			ctx := context.WithValue(r.Context(), userIDKey, userID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// GetUserID extracts the UserID from the context. Returns an empty UserID if
// not present.
func GetUserID(ctx context.Context) types.UserID {
	uid, _ := ctx.Value(userIDKey).(types.UserID)
	return uid
}
