;;; emms.el -*- lexical-binding: t; -*-

; https://sqrtminusone.xyz/posts/2021-09-07-emms/
(use-package emms-setup)
(use-package emms
  :after emms-setup
  :config
  (emms-all)
  (setq emms-source-file-default-directory "~/Nextcloud/music/")
  (setq emms-player-mpd-music-directory "~/Nextcloud/music")
  (setq emms-player-mpd-server-name "localhost")
  (setq emms-player-mpd-server-port "6600")
  (add-to-list 'emms-info-functions 'emms-info-mpd)
  (add-to-list 'emms-player-list 'emms-player-mpd)
  (emms-player-mpd-connect)
  (add-hook 'emms-playlist-cleared-hook 'emms-player-mpd-clear)
)
