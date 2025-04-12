;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(setq user-full-name "Lukas Nickel"
      user-mail-address "lukasnickel@outlook.de")

(setq doom-font (font-spec :family "BerkeleyMono" :size 18)
      doom-variable-pitch-font (font-spec :family "BerkeleyMono" :size 18)
      doom-big-font (font-spec :family "BerkeleyMono" :size 24))


(setq fancy-splash-image "~/.config/doom/blackhole.png")
(setq doom-theme 'doom-gruvbox)
(setq display-line-numbers-type nil)

(setq evil-escape-key-sequence "jk")

(setq org-directory "~/org"
      org-roam-directory "~/org"
      org-agenda-files (directory-files-recursively "~/org/" "\\.org$")
      org-roam-db-location "~/org/org-roam.db"
      )

(use-package! org-modern-indent
  :config
  (add-hook 'org-mode-hook #'org-modern-indent-mode 90))
(with-eval-after-load 'org (global-org-modern-mode))


(load-file (expand-file-name "org-roam.el" doom-private-dir ))
(load-file (expand-file-name "org-ref.el" doom-private-dir ))
(load-file (expand-file-name "org-latex.el" doom-private-dir ))
