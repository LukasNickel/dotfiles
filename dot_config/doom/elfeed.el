;;; elfeed.el -*- lexical-binding: t; -*-

(setq-default elfeed-search-filter "@1-week-ago +unread ")
(require 'elfeed-org)
(use-package! elfeed-org
    :after elfeed
    :init
    (setq rmh-elfeed-org-files (list "~/Nextcloud/org/elfeed.org"))
    )
(elfeed-org)

(use-package elfeed-tube
  :ensure t ;; or :straight t
  :after elfeed
  :demand t
  :config
  ;; (setq elfeed-tube-auto-save-p nil) ; default value
  ;; (setq elfeed-tube-auto-fetch-p t)  ; default value
  (elfeed-tube-setup)

  :bind (:map elfeed-show-mode-map
         ("F" . elfeed-tube-fetch)
         ([remap save-buffer] . elfeed-tube-save)
         :map elfeed-search-mode-map
         ("F" . elfeed-tube-fetch)
         ([remap save-buffer] . elfeed-tube-save)))

(use-package elfeed-tube-mpv
  :ensure t ;; or :straight t
  :bind (:map elfeed-show-mode-map
              ("C-c C-f" . elfeed-tube-mpv-follow-mode)
              ("C-c C-w" . elfeed-tube-mpv-where)))

; refresh feeds every 2 hours
(run-at-time nil (* 2 60 60) #'elfeed-update)
(setq elfeed-db-directory "~/Nextcloud/stuff_to_sync")
