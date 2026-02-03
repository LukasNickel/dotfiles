;;; ../../../../var/home/lnickel/.config/doom/lsp.el -*- lexical-binding: t; -*-
(setq m/pyright-uvx-command
      '("uvx" "--from" "pyright==1.1.403" "pyright-langserver" "--" "--stdio"))

; Weirdly segfaults although that shouldn't happen on emacs 30...
;(use-package eglot
;  :init
;  (add-hook 'python-mode-hook 'eglot-ensure)
;  :config
;  (add-to-list 'eglot-server-programs `(python-mode . ,m/pyright-uvx-command)))

(use-package treesit-auto
  :custom
  (treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode))

;; typst
;(require 'lsp-mode)
(use-package typst-preview
  :load-path "directory-of-typst-preview.el"
  :config
  (setq typst-preview-browser "default")
  (setq typst-preview-executable "tinymist preview")
  (define-key typst-preview-mode-map (kbd "C-c C-j") 'typst-preview-send-position)
  )

(use-package typst-ts-mode
  :custom
  (typst-ts-mode-watch-options "--open")
  (typst-ts-mode-grammar-location (expand-file-name "tree-sitter/libtree-sitter-typst.so" user-emacs-directory))
  (typst-ts-mode-enable-raw-blocks-highlight t)
  (typst-ts-compile-executable-location "tinymist")
  )

                                        ; https://myriad-dreamin.github.io/tinymist/frontend/emacs.html
(with-eval-after-load 'eglot
  (with-eval-after-load 'typst-ts-mode
    (add-to-list 'eglot-server-programs
                 `((typst-ts-mode) .
                   ,(eglot-alternatives `(,typst-ts-lsp-download-path
                                          "tinymist"
                                          "typst-lsp"))))))
