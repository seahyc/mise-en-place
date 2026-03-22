package handler

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"

	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// SessionEvent is an event broadcast to WebSocket subscribers.
type SessionEvent struct {
	Type string         `json:"type"` // step_completed, session_started, etc.
	Data map[string]any `json:"data"`
}

// SessionHub manages pub/sub for session events.
type SessionHub struct {
	mu       sync.RWMutex
	sessions map[types.SessionID][]chan SessionEvent
}

// NewSessionHub creates a new SessionHub.
func NewSessionHub() *SessionHub {
	return &SessionHub{
		sessions: make(map[types.SessionID][]chan SessionEvent),
	}
}

// Subscribe returns a channel that receives events for the given session.
func (h *SessionHub) Subscribe(sessionID types.SessionID) <-chan SessionEvent {
	h.mu.Lock()
	defer h.mu.Unlock()
	ch := make(chan SessionEvent, 16)
	h.sessions[sessionID] = append(h.sessions[sessionID], ch)
	return ch
}

// Unsubscribe removes a subscriber channel from the session.
func (h *SessionHub) Unsubscribe(sessionID types.SessionID, ch <-chan SessionEvent) {
	h.mu.Lock()
	defer h.mu.Unlock()
	subs := h.sessions[sessionID]
	for i, sub := range subs {
		if sub == ch {
			h.sessions[sessionID] = append(subs[:i], subs[i+1:]...)
			close(sub)
			break
		}
	}
	if len(h.sessions[sessionID]) == 0 {
		delete(h.sessions, sessionID)
	}
}

// Publish sends an event to all subscribers of the session.
func (h *SessionHub) Publish(sessionID types.SessionID, event SessionEvent) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, ch := range h.sessions[sessionID] {
		select {
		case ch <- event:
		default:
			// Drop if subscriber is slow.
		}
	}
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// SessionWebSocket handles WebSocket connections for session events.
// Authenticates via JWT in the "token" query parameter.
func SessionWebSocket(hub *SessionHub, jwtSecret string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Authenticate.
		token := r.URL.Query().Get("token")
		if token == "" {
			http.Error(w, "missing token", http.StatusUnauthorized)
			return
		}
		_, err := service.ParseAccessToken(token, jwtSecret)
		if err != nil {
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return
		}

		sessionID := types.SessionID(r.URL.Query().Get("session_id"))
		if sessionID == "" {
			http.Error(w, "missing session_id", http.StatusBadRequest)
			return
		}

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("ws upgrade: %v", err)
			return
		}
		defer conn.Close()

		ch := hub.Subscribe(sessionID)
		defer hub.Unsubscribe(sessionID, ch)

		// Read pump: discard incoming messages, detect close.
		done := make(chan struct{})
		go func() {
			defer close(done)
			for {
				if _, _, err := conn.ReadMessage(); err != nil {
					return
				}
			}
		}()

		// Write pump: forward events from hub to client.
		for {
			select {
			case event, ok := <-ch:
				if !ok {
					return
				}
				data, err := json.Marshal(event)
				if err != nil {
					log.Printf("ws marshal: %v", err)
					return
				}
				if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
					return
				}
			case <-done:
				return
			}
		}
	}
}
