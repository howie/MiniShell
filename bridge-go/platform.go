package main

import "context"

// Platform is implemented by each messaging platform adapter.
// Run blocks until ctx is cancelled or a fatal error occurs.
type Platform interface {
	Run(ctx context.Context) error
	Name() string
}
