;;; test.el -*- lexical-binding: t; -*-
;;;
                                        ; custom ocr import by chatgpt
                                        ; 
(setq handwritten-ocr-python-script
      "~/Downloads/ocrtest/handwritten-ocr.py")
                                        ;(add-to-list 'load-path doom-private-dir)
                                        ;(require 'handwritten-ocr-import)
(load! (expand-file-name "handwritten-ocr-import.el" doom-private-dir ))
                                        ;(global-set-key (kbd "C-c n o") #'handwritten-ocr-import)
(setq handwritten-ocr-auth-sources '(default)) ; make sure we actually use kwallet etc
(setq handwritten-ocr-auth-user nil) ; i saved the api key with no user?

(load-file (expand-file-name "org-attach-migrate.el" doom-private-dir ))
                                        ; obsidian
(use-package obsidian
  :config
  (global-obsidian-mode t)
  (obsidian-backlinks-mode t)
  :custom
  ;; location of obsidian vault
  (obsidian-directory "~/repos/arch-implantiq")
  ;; Default location for new notes from `obsidian-capture'
  (obsidian-inbox-directory "Inbox")
  ;; Useful if you're going to be using wiki links
  (markdown-enable-wiki-links t)

  ;; These bindings are only suggestions; it's okay to use other bindings
  :bind (:map obsidian-mode-map
              ;; Create note
              ("C-c C-n" . obsidian-capture)
              ;; If you prefer you can use `obsidian-insert-wikilink'
              ("C-c C-l" . obsidian-insert-link)
              ;; Open file pointed to by link at point
              ("C-c C-o" . obsidian-follow-link-at-point)
              ;; Open a different note from vault
              ("C-c C-p" . obsidian-jump)
              ;; Follow a backlink for the current file
              ("C-c C-b" . obsidian-backlink-jump)))
