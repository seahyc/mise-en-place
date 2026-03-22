package handler_test

import (
	"testing"
	"time"

	"github.com/yingcong/mise-en-place/backend/internal/handler"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

func TestSessionHub_PublishSubscribe(t *testing.T) {
	hub := handler.NewSessionHub()
	sid := types.SessionID("test-session")

	ch := hub.Subscribe(sid)

	event := handler.SessionEvent{
		Type: "step_completed",
		Data: map[string]any{"step_id": "step-1"},
	}
	hub.Publish(sid, event)

	select {
	case received := <-ch:
		if received.Type != "step_completed" {
			t.Errorf("event type = %q, want %q", received.Type, "step_completed")
		}
		if received.Data["step_id"] != "step-1" {
			t.Errorf("event data step_id = %v, want %q", received.Data["step_id"], "step-1")
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for event")
	}

	hub.Unsubscribe(sid, ch)
}

func TestSessionHub_Unsubscribe(t *testing.T) {
	hub := handler.NewSessionHub()
	sid := types.SessionID("test-session")

	ch := hub.Subscribe(sid)
	hub.Unsubscribe(sid, ch)

	// Publish after unsubscribe — should not panic.
	hub.Publish(sid, handler.SessionEvent{Type: "test"})

	// Channel should be closed.
	select {
	case _, ok := <-ch:
		if ok {
			t.Error("expected channel to be closed")
		}
	case <-time.After(time.Second):
		t.Fatal("timed out — channel should be closed")
	}
}

func TestSessionHub_MultipleSubscribers(t *testing.T) {
	hub := handler.NewSessionHub()
	sid := types.SessionID("test-session")

	ch1 := hub.Subscribe(sid)
	ch2 := hub.Subscribe(sid)

	hub.Publish(sid, handler.SessionEvent{Type: "session_started"})

	for i, ch := range []<-chan handler.SessionEvent{ch1, ch2} {
		select {
		case ev := <-ch:
			if ev.Type != "session_started" {
				t.Errorf("subscriber %d: type = %q", i, ev.Type)
			}
		case <-time.After(time.Second):
			t.Fatalf("subscriber %d: timed out", i)
		}
	}

	hub.Unsubscribe(sid, ch1)
	hub.Unsubscribe(sid, ch2)
}
