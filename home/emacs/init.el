(use-package slime
  :defer t
  :init
  (setq inferior-lisp-program "sbcl")
  (slime-setup '(slime-repl slime-fancy slime-banner)) 
  (add-to-list 'auto-mode-alist '("\\.cl\\'" . slime-mode))
  (add-to-list 'auto-mode-alist '("\\.cl\\'" . common-lisp-mode)))

(use-package diff-hl
  :hook ((magit-pre-refresh . diff-hl-magit-pre-refresh)
         (magit-post-refresh . diff-hl-magit-post-refresh)
         (dired-mode . diff-hl-dired-mode))
  :init
  (global-diff-hl-mode +1)
  (global-diff-hl-show-hunk-mouse-mode +1)
  (diff-hl-margin-mode +1))

(use-package treesit-auto
  :custom
  (treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode))

;; indent
(setq-default indent-tabs-mode nil)  ;; indent with space
(setq-default tab-width 4)           ;; set width to 4
(setq indent-line-function 'insert-tab)
