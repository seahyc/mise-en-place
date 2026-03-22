package repo_test

import "github.com/yingcong/mise-en-place/backend/internal/repo"

// Verify PgConversationRepo satisfies the ConversationRepo interface.
var _ repo.ConversationRepo = (*repo.PgConversationRepo)(nil)
