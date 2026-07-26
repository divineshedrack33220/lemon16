package handlers

import (
	"coded/config"
	"coded/notify"
	"coded/repository"
	"coded/websocket"
)

type Handler struct {
	Repos     *repository.Repositories
	WS        *websocket.Manager
	Cfg       *config.Config
	Notifier  *notify.Notifier
}

func NewHandler(repos *repository.Repositories, ws *websocket.Manager, cfg *config.Config) *Handler {
	return &Handler{
		Repos:    repos,
		WS:       ws,
		Cfg:      cfg,
		Notifier: notify.NewNotifier(),
	}
}
