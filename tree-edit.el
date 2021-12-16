;;; tree-edit.el --- A library for structural refactoring and editing -*- lexical-binding: t; -*-
;;
;; Copyright (C) Ethan Leba <https://github.com/ethan-leba>
;;
;; Author: Ethan Leba <ethanleba5@gmail.com>
;; Version: 0.1.0
;; Homepage: https://github.com/ethan-leba/tree-edit
;; Package-Requires: ((emacs "27.0") (tree-sitter "0.15.0") (tsc "0.15.0") (tree-sitter-langs "0.10.0") (dash "2.19") (reazon "0.4.0") (s "0.0.0"))
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; Provides a set of functions for structural editing or refactoring in any
;; language supported by tree-sitter.
;;
;; The interface for this package is currently unstable, developing against it is
;; unadvised!
;;
;; See `evil-tree-edit' if you're looking for a complete editing package.
;;
;;; Code:
;;* Requires
(require 'tree-sitter)
(require 'dash)
(require 'reazon)
(require 's)

;;* Internal variables
(defvar tree-edit-grammar nil
  "The grammar rules generated by tree-sitter. Set by mode-local grammar file.")
(defvar tree-edit--supertypes nil
  "A mapping from type to supertype, i.e. if_statement is a statement. Set by mode-local grammar file.")
(defvar tree-edit--subtypes nil
  "A mapping from type to subtype, i.e. statement is subtyped by if_statement. Set by mode-local grammar file.")
(defvar tree-edit--containing-types nil
  "A mapping from a type to all possible types that can exist as it's children. Set by mode-local grammar file.")
(defvar tree-edit--alias-map nil
  "A mapping from a type to a mapping from original name to aliased name. Set by mode-local grammar file.")
(defvar tree-edit--identifier-regex nil
  "The regex used to determine if a string is an identifier. Set by mode-local grammar file.")
(defvar tree-edit--hidden-node-types nil
  "Nodes which are hidden by tree-sitter. Set by mode-local grammar file.

Unfortunately tree-sitter allows certain nodes to be hidden from
the syntax tree, which will throw off tree-edit's parser. The
best we can do for now is pretend that these nodes don't exist at
all.

https://tree-sitter.github.io/tree-sitter/creating-parsers#hiding-rules")
(defvar tree-edit-parse-comments t
  "If non-nil, allow abritrary 'comment' nodes when parsing.

This should be enabled when using parser for insertions, but
seeing the comments is unnecessary when previewing the parser.")
(defvar tree-edit-node-insertion-override nil
  "A mapping from type to function, overriding `tree-edit--valid-insertions'.

Set by mode-local grammar file.

This should only be used in one of the following cases:

1. Performance, i.e. blocks or compound statements, where there
is no syntax between nodes, and the amount of nodes present can
be very high.

2. Nodes containing tree-sitter externals, so the JSON grammar
may not truly capture what qualifies as a valid node.")
(defvar tree-edit-node-deletion-override nil
  "A mapping from type to function, overriding `tree-edit--valid-deletions'.

Set by mode-local grammar file.

This should only be used in one of the following cases:

1. Performance, i.e. blocks or compound statements, where there
is no syntax between nodes, and the amount of nodes present can
be very high.

2. Nodes containing tree-sitter externals, so the JSON grammar
may not truly capture what qualifies as a valid node.")
(defvar tree-edit-node-replacement-override nil
  "A mapping from type to function, overriding `tree-edit--valid-replacement-p'.

Set by mode-local grammar file.

This should only be used in one of the following cases:

1. Performance, i.e. blocks or compound statements, where there
is no syntax between nodes, and the amount of nodes present can
be very high.

2. Nodes containing tree-sitter externals, so the JSON grammar
may not truly capture what qualifies as a valid node.")
(defvar tree-edit-significant-node-types nil
  "List of nodes that are considered significant, like methods or classes. Set by mode-local grammar file.")
(defvar tree-edit-syntax-snippets nil
  "Snippets for constructing nodes. Set by mode-local grammar file.

Must be an alist of node type (as a symbol) to list, where the list can
contain any string or a symbol referencing another node type in the alist.

The syntax snippets are intended to mirror the grammar constructions
of the tree-sitter grammar, but is currently not validated by tree-edit.")
(defvar tree-edit-nodes nil
  "Nodes that a user can create via tree-edit. Set by mode-local grammar file.

Must be a list of plists, with the following properties:

Properties
  :type           the node's type
  :key            the keybinding for the given node
  :name           human readable name for which-key, defaults to
                  :type if left unset
  :node-override  overrides syntax snippets for the verb
  :wrap-override  overrides syntax snippets for the verb when wrapping")
(defvar tree-edit-query-nodes nil
  "Nodes that users can query for jumping. Set by mode-local grammar file.

Must be a list of plists, with the following properties:

Properties
  :type           the node's type, or a list of types
  :key            the keybinding for the given node
  :name           human readable name for which-key, defaults to
                  :type if left unset")
(defvar tree-edit-whitespace-rules nil
  "Rules for formatting nodes. Set by mode-local grammar file.

Must by an alist of node type to a pair of lists, where the car
is the whitespace rules before the node, and the cdr is after.

The following keywords are valid whitespace rules:

  :newline      insert a newline before the next text
  :indent       increase the indentation by 4 for the next newline
  :dedent       decrease the indentation by 4 for the next newline")
(defvar tree-edit-placeholder-node-type nil
  "Node considered a placeholder. Set by mode-local grammar file.

Typically an identifier, but can conceivably be any type of node.")

;;* User settings
(defgroup tree-edit nil
  "Structural editing library for tree-sitter languages."
  :group 'bindings
  :prefix "tree-edit-")
(defcustom tree-edit-language-alist '((java-mode . tree-edit-java)
                                      (python-mode . tree-edit-python))
  "Mapping from mode to language file."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'tree-edit)
;; TODO: Add timeout to queries
;; (defcustom tree-edit-query-timeout 0.1
;;   "How long a query should take before giving up."
;;   :type 'float
;;   :group 'tree-edit)

;;* Utilities
(defun tree-edit--boring-nodep (node)
  "Check if the NODE is not a named node."
  (and (tsc-node-p node) (not (tsc-node-named-p node))))

(defun tree-edit--get-current-index (node)
  "Return a pair containing the siblings of the NODE and the index of NODE within it's parent."
  (let* ((parent (tsc-get-parent node))
         (pnodes (--map (tsc-get-nth-named-child parent it)
                        (number-sequence 0 (1- (tsc-count-named-children parent))))))
    (--find-index (equal (tsc-node-position-range node) (tsc-node-position-range it)) pnodes)))

(defun tree-edit--save-location (node)
  "Save the current location of the NODE."
  (cons (tsc--node-steps (tsc-get-parent node))
        (tree-edit--get-current-index node)))

(defun tree-edit--restore-location (location)
  "Restore the current node to LOCATION.

More permissive than `tsc--node-from-steps' in that the parent
will be selected if an only child is deleted and nearest sibling
will be selected if the last one is deleted."
  (condition-case nil
      (-let* (((steps . child-index) location)
              (recovered-parent (tsc--node-from-steps tree-sitter-tree steps))
              (num-children (tsc-count-named-children recovered-parent)))
        (if (equal num-children 0) recovered-parent
          (tsc-get-nth-named-child recovered-parent
                                   (min child-index (1- num-children)))))
    (tsc--invalid-node-step (message "Tree-edit could not restore location"))))

(defun tree-edit--apply-until-interesting (fun node)
  "Apply FUN to NODE until a named node is hit."
  (let ((parent (funcall fun node)))
    (if (tree-edit--boring-nodep parent)
        (tree-edit--apply-until-interesting fun parent)
      parent)))

(defun tree-edit-query (patterns node)
  "Execute query PATTERNS against the children of NODE and return captures.

TODO: Build queries and cursors once, then reuse them?"
  (let* ((query (tsc-make-query tree-sitter-language patterns)))
    (-map #'cdr (tsc-query-captures query node #'tsc--buffer-substring-no-properties))))

(defun tree-edit--relevant-types (type parent-type)
  "Return a list of the TYPE and all relevant types that occur in PARENT-TYPE.

Relevant types are either supertypes of TYPE or alias names referring to TYPE."
  (-intersection
   (cons
    (alist-get type (alist-get parent-type tree-edit--alias-map))
    (alist-get type tree-edit--supertypes `(,type)))
   (alist-get parent-type tree-edit--containing-types)))

;;* Locals: node transformations


;; Error recovery seems to be a bit arbitrary:
;; - "foo.readl" in java parses as (program (expression_statement (...) (MISSING \";\")))
;; - "foo.read" in java parses as (program (ERROR (...)))
(defun tree-edit--parse-fragment (fragment)
  "Return the possible nodes of FRAGMENT, or nil if unparseable.

For example, `foo()` in Python parses as an expression_statement
with a call inside. Depending on the context, we may want either:
so we return both.

Fragments should parse as one of the following structures:
- (program (type ...)
- (program (ERROR (type ...))
- (program (... (type ...) (MISSING ...))"
  (cl-flet ((tree-edit--get-only-child
             (lambda (node) (if (equal (tsc-count-named-children node) 1)
                                (tsc-get-nth-named-child node 0)))))
    (if-let ((first-node (->> fragment
                              (tsc-parse-string tree-sitter-parser)
                              (tsc-root-node)
                              (tree-edit--get-only-child))))
        (if-let (node (if (tsc-node-has-error-p first-node)
                          (-some-> first-node
                            (tree-edit--get-only-child))
                        first-node))
            (let (result)
              (while node
                (push node result)
                (setq node (tree-edit--get-only-child node)))
              (reverse result))))))

(defun tree-edit--type-of-fragment (fragment)
  "Return the node-type of the FRAGMENT, or nil if unparseable.

Fragments should parse as one of the following structures:
- (program (type))
- (program (ERROR (type))
- (program (... (type) (MISSING ...))"
  (-some-> fragment (tree-edit--parse-fragment) (tsc-node-type)))

(defun tree-edit--get-all-children (node)
  "Return all of NODE's children."
  (--map (tsc-get-nth-child node it)
         (number-sequence 0 (1- (tsc-count-children node)))))

(defun tree-edit--get-parent-tokens (node)
  "Return a pair containing the siblings of the NODE and the index of itself."
  (let* ((parent (tsc-get-parent node))
         (children (tree-edit--get-all-children parent)))
    (cons (-map #'tsc-node-type children)
          (--find-index (equal (tsc-node-position-range node) (tsc-node-position-range it)) children))))

(defun tree-edit-simple-delete-override (node)
  "Allow deletion of NODE."
  (-let [(_ . index) (tree-edit--get-parent-tokens node)]
    `(,index ,index nil)))

(defun tree-edit-simple-insertion-override (type node)
  "Allow insertion of TYPE if it appears in NODE's parent's grammar."
  (when-let (types (tree-edit--relevant-types
                    type (-> node (tsc-get-parent) (tsc-node-type))))
    `(,(car types))))

(defun tree-edit-simple-replacement-override (type node)
  "Allow replacement of NODE by TYPE if it appears in NODE's parent's grammar."
  (tree-edit--relevant-types type (-> node (tsc-get-parent) (tsc-node-type))))


;;* Globals: Syntax generation
;; TODO: Handle less restrictively by ripping out surrounding syntax (ie delete)
(defun tree-edit--valid-replacement-p (type node)
  "Return non-nil if NODE can be replaced with a node of TYPE."
  (let ((parent-type (tsc-node-type (tsc-get-parent node))))
    (if-let (override (alist-get parent-type tree-edit-node-replacement-override))
        (funcall override type node)
      (-let* ((reazon-occurs-check nil)
              (grammar (alist-get parent-type tree-edit-grammar))
              ((children . index) (tree-edit--get-parent-tokens node))
              ;; removing the selected element
              ((left (_ . right)) (-split-at index children))
              (relevant-types (tree-edit--relevant-types type parent-type)))
        (if-let (result (reazon-run 1 q
                          (reazon-fresh (tokens qr ql)
                            (tree-edit--superpositiono right qr parent-type)
                            (tree-edit--superpositiono left ql parent-type)
                            (tree-edit--max-lengtho q 3)
                            ;; FIXME: this should be limited to only 1 new named node, of the requested type
                            (tree-edit--includes-typeo q relevant-types)
                            (tree-edit--prefixpostfixo ql q qr tokens)
                            (tree-edit-parseo grammar tokens '()))))
            ;; TODO: Put this in the query
            ;; Rejecting multi-node solutions
            (and result (equal (length (car result)) 1)))))))

(defun tree-edit--find-raise-ancestor (ancestor child)
  "Find a suitable ANCESTOR to be replaced with CHILD."
  (interactive)
  (let ((child-type (tsc-node-type child)))
    (cond
     ((not (and ancestor (tsc-get-parent ancestor))) (user-error "Can't raise node!"))
     ;; XXX: For cases like (expression_statement (call)), where both represent the same text.
     ;;      This might only apply to Python.
     ((equal (tsc-node-byte-range ancestor) (tsc-node-byte-range child))
      (tree-edit--find-raise-ancestor (tsc-get-parent ancestor) child))
     ((tree-edit--valid-replacement-p child-type ancestor) ancestor)
     (t (tree-edit--find-raise-ancestor (tsc-get-parent ancestor) child)))))

;; TODO: Refactor commonalities between syntax generators
(defun tree-edit--valid-insertions (type after node)
  "Return a valid sequence of tokens containing the provided TYPE, or nil.

If AFTER is t, generate the tokens after NODE, otherwise before."
  (let ((parent-type (tsc-node-type (tsc-get-parent node))))
    (if-let (override (alist-get parent-type tree-edit-node-insertion-override))
        (funcall override type node)
      (-let* ((reazon-occurs-check nil)
              (grammar (alist-get parent-type tree-edit-grammar))
              ((children . index) (tree-edit--get-parent-tokens node))
              ((left right) (-split-at (+ index (if after 1 0)) children))
              (relevant-types (tree-edit--relevant-types type parent-type)))
        (if-let (result (reazon-run 1 q
                          (reazon-fresh (tokens qr ql)
                            (tree-edit--superpositiono right qr parent-type)
                            (tree-edit--superpositiono left ql parent-type)
                            (tree-edit--max-lengtho q 5)
                            (tree-edit--prefixpostfixo ql q qr tokens)
                            ;; FIXME: this should be limited to only 1 new named node, of the requested type
                            (tree-edit--includes-typeo q relevant-types)
                            (tree-edit-parseo grammar tokens '()))))
            (car result))))))

(defun tree-edit--remove-node-and-surrounding-syntax (tokens idx)
  "Return a pair of indices to remove the node at IDX in TOKENS and all surrounding syntax."
  (let ((end (1+ idx))
        (start (1- idx)))
    (while (stringp (nth end tokens))
      (setq end (1+ end)))
    (while (and (>= start 0) (stringp (nth start tokens)))
      (setq start (1- start)))
    (cons (1+ start) end)))

(defun tree-edit--valid-deletions (node)
  "Return a set of edits if NODE can be deleted, else nil.

If successful, the return type will give a range of siblings to
delete, and what syntax needs to be inserted after, if any."
  (let ((parent-type (tsc-node-type (tsc-get-parent node))))
    (if-let (override (alist-get parent-type tree-edit-node-deletion-override))
        (funcall override node)
      (-let* ((reazon-occurs-check nil)
              (parent-type (tsc-node-type (tsc-get-parent node)))
              (grammar (alist-get (tsc-node-type (tsc-get-parent node)) tree-edit-grammar))
              ((children . index) (tree-edit--get-parent-tokens node))
              ((left-idx . right-idx) (tree-edit--remove-node-and-surrounding-syntax children index))
              (left (-take left-idx children))
              (right (-drop right-idx children))
              (nodes-deleted (- right-idx left-idx)))
        ;; FIXME: Q should be only string types, aka syntax -- we're banking that
        ;;        the first thing reazon stumbles upon is syntax.
        (if-let ((result (reazon-run 1 q
                           (reazon-fresh (tokens qr ql)
                             (tree-edit--superpositiono right qr parent-type)
                             (tree-edit--superpositiono left ql parent-type)
                             ;; Prevent nodes from being 'deleted' by putting the exact same thing back
                             (tree-edit--max-lengtho q (1- nodes-deleted))
                             (tree-edit--prefixpostfixo ql q qr tokens)
                             (tree-edit-parseo grammar tokens '())))))
            (if (-every-p #'stringp (car result))
                `(,left-idx ,(1- right-idx) ,(car result))))))))

;;* Locals: node rendering
(defun tree-edit--adhoc-pcre-to-rx (pcre)
  "Convert PCRE to an elisp regex (in no way robust)

pcre2el package doesn't support character classes, so can't use that.
Upstream patch?"
  (s-replace-all '(("\\p{L}" . "[:alpha:]")
                   ("\\p{Nd}" . "[:digit:]")) pcre))

(defun tree-edit--generate-node (node-type rules &optional tokens)
  "Given a NODE-TYPE and a set of RULES, generate a node string.

If TOKENS is passed in, that will be used as a basis for node
construction, instead of looking up the rules for node-type."
  (interactive)
  (cons node-type
        (--map
         (if (and (not (keywordp it)) (symbolp it)) (tree-edit--generate-node it rules) it)
         ;; TODO: See if we can make it via. the parser?
         (or tokens (alist-get node-type rules)
             (user-error "No node definition for %s" node-type)))))

(defun tree-edit--needs-space-p (left right)
  "Check if the two tokens LEFT and RIGHT need a space between them.

https://tree-sitter.github.io/tree-sitter/creating-parsers#keyword-extraction"
  (let ((regex (tree-edit--adhoc-pcre-to-rx tree-edit--identifier-regex)))
    (and (stringp left)
         (stringp right)
         (< (length (s-matched-positions-all regex (string-join `(,left ,right))))
            (+ (length (s-matched-positions-all regex left))
               (length (s-matched-positions-all regex right)))))))

(defun tree-edit--whitespace-rules-for-type (type)
  "Retrieve whitespace rules for TYPE.

Will search for the most specific rule first and travel through
the TYPE's supertypes until exhausted."
  (car (-remove-item nil (--map (alist-get it tree-edit-whitespace-rules)
                                (alist-get type tree-edit--supertypes `(,type))))))

(defun tree-edit--add-whitespace-rules-to-tokens (type tokens)
  "Wrap TOKENS in the whitespace defined for TYPE, if any."
  (-let (((l . r) (tree-edit--whitespace-rules-for-type type)))
    (append l tokens r)))

(defun tree-edit--render-node (left-tokens new-tokens right-text indentation)
  "Insert NEW-TOKENS into the buffer, properly formatting as needed.

LEFT-TOKENS are used for calculating the formatting of
NEW-TOKENS, while RIGHT-TEXT is used to ensure that no tokens are
improperly spaced.

Pre-existing nodes in the tokens are assumed to be already
formatted correctly and thus are inserted as-is.

New nodes are inserted according `tree-edit-syntax-snippets'.

Text nodes (likely from the `kill-ring') are not assumed to be
formatted correctly and thus decomposed by
`tree-edit--text-to-insertable-node' into chunks where formatting
matters (i.e. expressions are left alone but blocks are split)."
  (-let* ((prev nil)
          (deferred-newline nil))
    (cl-flet ((process-tokens
               (stack do-insert)
               (while stack
                 (-let ((current (pop stack)))
                   ;; TODO: use `pcase'
                   (cond ((not current) '())
                         ((consp current)
                          (setq stack (append (tree-edit--add-whitespace-rules-to-tokens
                                               (car current) (cdr current))
                                              stack)))
                         ((equal current :newline)
                          (setq deferred-newline t))
                         ((equal current :indent)
                          (setq indentation (+ indentation 4)))
                         ((equal current :dedent)
                          (setq indentation (- indentation 4)))
                         ((stringp current)
                          (when deferred-newline
                            (when do-insert
                              (newline)
                              (indent-line-to indentation))
                            (setq deferred-newline nil))
                          (when do-insert
                            (if (tree-edit--needs-space-p prev current)
                                (insert " " current)
                              (insert current)))))
                   (when (or (equal :newline current) (stringp current))
                     (setq prev current))))))
      (process-tokens left-tokens nil)
      (combine-after-change-calls
        (process-tokens new-tokens t)
        (when right-text
          (when deferred-newline
            (newline)
            (indent-line-to indentation)
            (setq deferred-newline nil))
          (when (tree-edit--needs-space-p prev right-text)
            (insert " ")))))))

(defun tree-edit--text-and-type (node)
  "Return a pair of NODE and it's text."
  `(,(tsc-node-type node) ,(tsc-node-text node)))

(defun tree-edit--replace-fragment (fragment node l r)
  "Replace the nodes between L and R with the FRAGMENT in the children of NODE."
  (-let* ((parent (tsc-get-parent node))
          (children (tree-edit--get-all-children parent))
          (left (-map #'tree-edit--text-and-type (-slice children 0 l)))
          (right (-some-> r (nth children) tsc-node-text))
          (render-fragment
           (and fragment
                (tree-edit--generate-node
                 (tsc-node-type (tsc-get-parent node))
                 tree-edit-syntax-snippets
                 fragment))))
    (let ((indentation
           (save-excursion
             (goto-char (tsc-node-start-position (car children)))
             (current-indentation))))
      (save-excursion
        (if (zerop l)
            (goto-char (tsc-node-start-position (nth 0 children)))
          (goto-char (tsc-node-end-position (nth (1- l) children))))
        (delete-region (point)
                       (if-let ((last-node (nth r children)))
                           (tsc-node-start-position last-node)
                         (tsc-node-end-position (nth (1- r) children))))
        (tree-edit--render-node left (if fragment render-fragment) right indentation)))))

(defun tree-edit--insert-fragment (fragment node position)
  "Insert rendered FRAGMENT in the children of NODE in the provided POSITION.

POSITION can be :before, :after, or nil."
  (-let* ((parent (tsc-get-parent node))
          (children (tree-edit--get-all-children parent))
          (node-index (--find-index (equal (tsc-node-position-range node)
                                           (tsc-node-position-range it))
                                    children))
          (split-position (+ (pcase position (:after 1) (:before 0)) node-index))
          (left (-map #'tree-edit--text-and-type (-slice children 0 split-position)))
          (right (-some-> split-position (nth children) tsc-node-text))
          (render-fragment
           (and fragment
                (tree-edit--generate-node
                 (tsc-node-type (tsc-get-parent node))
                 tree-edit-syntax-snippets
                 fragment))))
    (let ((indentation
           (save-excursion
             (goto-char (tsc-node-start-position (car children)))
             (current-indentation))))
      (save-excursion
        (if (zerop split-position)
            (goto-char (tsc-node-start-position (nth 0 children)))
          (goto-char (tsc-node-end-position (nth (1- split-position) children))))
        (if-let ((end (nth split-position children)))
            (delete-region (point)
                           (tsc-node-start-position end)))
        (tree-edit--render-node left render-fragment right indentation)))))

(defun tree-edit--split-node-for-insertion (node)
  "Split NODE into chunks of text as necessary for formatting."
  (let ((rules (tree-edit--whitespace-rules-for-type (tsc-node-type node))))
    (if (or (equal rules '(nil . nil)) (not rules))
        (tree-edit--text-and-type node)
      `(,(tsc-node-type node) .
        ,(-map #'tree-edit--split-node-for-insertion (tree-edit--get-all-children node))))))

(defun tree-edit--text-to-insertable-node (node text)
  "Split NODE for insertion, using TEXT instead of the current buffer.

`tsc-node-text' only operates on the current buffer so we have to
hack around that here."
  (cl-letf (((symbol-function 'tsc-node-text)
             (lambda (node)
               (tsc--without-restriction
                 ;; XXX: Byte and position aren't the same thing, apparently. Maybe this will break?
                 (pcase-let ((`(,beg . ,end) (tsc-node-byte-range node)))
                   (substring-no-properties text (1- beg) (if end (1- end) (length text))))))))
    (tree-edit--split-node-for-insertion node)))

;;* Globals: Structural editing functions
(defun tree-edit-exchange (type-or-text node)
  "Exchange NODE for TYPE-OR-TEXT.

If TYPE-OR-TEXT is a string, the tree-edit will attempt to infer the type of
the text."
  (if (stringp type-or-text)
      (tree-edit--exchange-fragment type-or-text node)
    (tree-edit--exchange-snippet type-or-text node)))

(defun tree-edit--exchange-snippet (type node)
  "Insert a node of the given TYPE next to NODE.

if BEFORE is t, the sibling node will be inserted before the
current, otherwise after."
  (unless (tree-edit--valid-replacement-p type node)
    (user-error "Cannot replace the current node with type %s!" type))
  (-let [(_ . node-index) (tree-edit--get-parent-tokens node)]
    (tree-edit--replace-fragment `(,type) node node-index (1+ node-index))))

(defun tree-edit--exchange-fragment (text node)
  "Insert a node of the given TEXT next to NODE.

if BEFORE is t, the sibling node will be inserted before the
current, otherwise after."
  (cl-block nil
    (dolist (fragment-node (tree-edit--parse-fragment text))
      (-let ((type (tsc-node-type fragment-node))
             ((_ . node-index) (tree-edit--get-parent-tokens node)))
        (when (tree-edit--valid-replacement-p type node)
          (--> fragment-node
               (tree-edit--text-to-insertable-node it text)
               (tree-edit--replace-fragment `(,it) node node-index (1+ node-index)))
          (cl-return))))
    (user-error "Cannot replace the current node with '%s'!" text)))

(defun tree-edit-raise (node)
  "Move NODE up the syntax tree until a valid replacement is found."
  (let ((ancestor-to-replace (tree-edit--find-raise-ancestor (tsc-get-parent node) node)))
    (let ((node-text (tsc-node-text node))
          (ancestor-steps (tree-edit--save-location ancestor-to-replace)))
      (tree-edit-exchange node-text ancestor-to-replace)
      (tree-edit--restore-location ancestor-steps))))

(defun tree-edit-insert-sibling (type-or-text node &optional before)
  "Insert a node of the given TYPE-OR-TEXT next to NODE.

If TYPE-OR-TEXT is a string, the tree-edit will attempt to infer the type of
the text.

if BEFORE is t, the sibling node will be inserted before the
current, otherwise after."
  (if (stringp type-or-text)
      (tree-edit--insert-fragment-sibling type-or-text node before)
    (tree-edit--insert-snippet-sibling type-or-text node before)))

(defun tree-edit--insert-snippet-sibling (type node &optional before)
  "Insert a node of the given TYPE next to NODE.

if BEFORE is t, the sibling node will be inserted before the
current, otherwise after."
  (if-let (tokens (tree-edit--valid-insertions type (not before) node))
      (let* ((used-type (-first #'symbolp tokens))
             (tree-edit-syntax-snippets
              `((,used-type . ,(alist-get type tree-edit-syntax-snippets)) . ,tree-edit-syntax-snippets)))
        (tree-edit--insert-fragment tokens node (if before :before :after)))
    (user-error "Cannot insert node of type %s!" type)))

(defun tree-edit--insert-fragment-sibling (text node &optional before)
  "Insert a node of the given TEXT next to NODE.

if BEFORE is t, the sibling node will be inserted before the
current, otherwise after."
  (cl-block nil
    (dolist (fragment-node (tree-edit--parse-fragment text))
      (if-let ((type (tsc-node-type fragment-node))
               (tokens (tree-edit--valid-insertions type (not before) node)))
          (--> tokens
               (-replace-first (-first #'symbolp tokens) (tree-edit--text-to-insertable-node fragment-node text) it)
               (tree-edit--insert-fragment it node (if before :before :after))
               (cl-return))))
    (user-error "Cannot insert '%s'!" text)))

(defun tree-edit-insert-child (type-or-text node)
  "Insert a node of the given TYPE-OR-TEXT inside of NODE.

If TYPE-OR-TEXT is a string, the tree-edit will attempt to infer the type of
the text."
  (tree-edit-insert-sibling type-or-text (tsc-get-nth-child node 0)))

(defun tree-edit-slurp (node)
  "Transform NODE's next sibling into it's leftmost child, if possible."
  (let ((slurp-candidate (tsc-get-next-named-sibling (tsc-get-parent node))))
    (cond ((not slurp-candidate) (user-error "Nothing to slurp!"))
          ;; No named children, use insert child
          ((equal (tsc-count-named-children node) 0)
           (let ((slurper (tsc--node-steps node)))
             (unless (tree-edit--valid-deletions slurp-candidate)
               (user-error "Cannot delete %s!" (tsc-node-text slurp-candidate)))
             (unless (tree-edit--valid-insertions (tsc-node-type slurp-candidate)
                                                  t
                                                  (tsc-get-nth-child node 0))
               (user-error "Cannot add %s into %s!"
                           (tsc-node-text slurp-candidate)
                           (tsc-node-type node)))
             (let ((slurp-text (tsc-node-text slurp-candidate)))
               (tree-edit-delete slurp-candidate)
               (tree-edit-insert-child slurp-text (tsc--node-from-steps tree-sitter-tree slurper)))))
          ;; Named children, use insert sibling
          (t
           (let* ((slurper
                   (tsc-get-nth-named-child node
                                            (1- (tsc-count-named-children node))))
                  (slurper-steps (tsc--node-steps slurper)))
             (unless (tree-edit--valid-deletions slurp-candidate)
               (user-error "Cannot delete %s!" (tsc-node-text slurp-candidate)))
             (unless (tree-edit--valid-insertions
                      (tsc-node-type slurp-candidate) t
                      slurper)
               (user-error "Cannot add %s into %s!"
                           (tsc-node-text slurp-candidate)
                           (tsc-node-type node)))
             (let ((slurp-text (tsc-node-text slurp-candidate)))
               (tree-edit-delete slurp-candidate)
               (tree-edit-insert-sibling slurp-text (tsc--node-from-steps tree-sitter-tree slurper-steps))))))))

(defun tree-edit-barf (node)
  "Transform NODE's leftmost child into it's next sibling, if possible."
  (unless (> (tsc-count-named-children node) 0)
    (user-error "Cannot barf a node with no named children!"))
  (let* ((barfee (tsc-get-nth-named-child node
                                          (1- (tsc-count-named-children node))))
         (barfer (tsc-get-parent node))
         (barfer-steps (tsc--node-steps barfer)))
    (unless (tree-edit--valid-deletions barfee)
      (user-error "Cannot delete %s!" (tsc-node-text barfee)))
    (unless (tree-edit--valid-insertions (tsc-node-type barfer)
                                         t
                                         (tsc-get-nth-child node 0))
      (user-error "Cannot add %s into %s!"
                  (tsc-node-text barfer)
                  (tsc-node-type node)))
    (let ((barfee-text (tsc-node-text barfee)))
      (tree-edit-delete barfee)
      (tree-edit-insert-sibling barfee-text (tsc--node-from-steps tree-sitter-tree barfer-steps)))))

(defun tree-edit-delete (node)
  "Delete NODE, and any surrounding syntax that accompanies it."
  (-let [(start end fragment) (or (tree-edit--valid-deletions node)
                                  (user-error "Cannot delete the current node"))]
    (tree-edit--replace-fragment fragment node start (1+ end))))

;;* Locals: Relational parser
(reazon-defrel tree-edit-parseo (grammar tokens out)
  "TOKENS are a valid prefix of a node in GRAMMAR and OUT is unused tokens in TOKENS."
  (reazon-disj
   (if tree-edit-parse-comments
       (reazon-fresh (next)
         ;; FIXME: Should use the `extras` field from grammar
         (tree-edit--takeo 'comment tokens next)
         (tree-edit-parseo grammar next out))
     #'reazon-!U)
   (pcase grammar
     (`((type . "STRING")
        (value . ,value))
      (tree-edit--takeo value tokens out))
     (`((type . "PATTERN")
        (value . ,_))
      (tree-edit--takeo :regex tokens out))
     (`((type . "BLANK"))
      (reazon-== tokens out))
     ((and `((type . ,type)
             (value . ,_)
             (content . ,content))
           (guard (s-starts-with-p "PREC" type)))
      ;; Silence the foolish linter.
      (ignore type)
      (tree-edit-parseo content tokens out))
     (`((type . "TOKEN")
        (content . ,content))
      (tree-edit-parseo content tokens out))
     (`((type . "SEQ")
        (members . ,members))
      (tree-edit--seqo members tokens out))
     (`((type . "ALIAS")
        (content . ,_)
        (named . ,_)
        (value . ,alias-name))
      (tree-edit--takeo alias-name tokens out))
     (`((type . "REPEAT")
        (content . ,content))
      (tree-edit--repeato content tokens out))
     (`((type . "REPEAT1")
        (content . ,content))
      (tree-edit--repeat1o content tokens out))
     (`((type . "FIELD")
        (name . ,_)
        (content . ,content))
      (tree-edit-parseo content tokens out))
     (`((type . "SYMBOL")
        (name . ,name))
      (if (member name tree-edit--hidden-node-types)
          (reazon-== tokens out)
        (tree-edit--takeo name tokens out)))
     (`((type . "CHOICE")
        (members . ,members))
      (tree-edit--choiceo members tokens out))
     (_ (error "Bad data: %s" grammar)))))

(reazon-defrel tree-edit--max-lengtho (ls len)
  "LS contains at most LEN elements."
  (cond
   ((> len 0)
    (reazon-disj
     (reazon-nullo ls)
     (reazon-fresh (d)
       (reazon-cdro ls d)
       (tree-edit--max-lengtho d (1- len)))))
   (t (reazon-nullo ls))))

(reazon-defrel tree-edit--seqo (members tokens out)
  "TOKENS parse sequentially for each grammar in MEMBERS, with OUT as leftovers."
  (if members
      (reazon-fresh (next)
        (tree-edit-parseo (car members) tokens next)
        (tree-edit--seqo (cdr members) next out))
    (reazon-== tokens out)))

(reazon-defrel tree-edit--choiceo (members tokens out)
  "TOKENS parse for each grammar in MEMBERS, with OUT as leftovers."
  (if members
      (reazon-disj
       (tree-edit-parseo (car members) tokens out)
       (tree-edit--choiceo (cdr members) tokens out))
    #'reazon-!U))

(reazon-defrel tree-edit--repeato (grammar tokens out)
  "TOKENS parse for GRAMMAR an abritrary amount of times, with OUT as leftovers."
  (reazon-disj
   (reazon-== tokens out)
   (reazon-fresh (next)
     (tree-edit-parseo grammar tokens next)
     (tree-edit--repeato grammar next out))))

(reazon-defrel tree-edit--repeat1o (grammar tokens out)
  "TOKENS parse for GRAMMAR at least once, up to an abritrary amount of times, with OUT as leftovers."
  (reazon-fresh (next)
    (tree-edit-parseo grammar tokens next)
    (tree-edit--repeato grammar next out)))

(reazon-defrel tree-edit--takeo (expected tokens out)
  "TOKENS is a cons, with car as EXPECTED and cdr as OUT."
  (reazon-conso expected out tokens))

(reazon-defrel tree-edit--prefixpostfixo (prefix middle postfix out)
  "OUT is equivalent to (append PREFIX MIDDLE POSTFIX)."
  (reazon-fresh (tmp)
    (reazon-appendo prefix middle tmp)
    (reazon-appendo tmp postfix out)))

(reazon-defrel tree-edit--includes-typeo (tokens relevant-types)
  "One of the types in RELEVANT-TYPES appears in TOKENS."
  (reazon-fresh (a d)
    (reazon-conso a d tokens)
    (reazon-disj
     (reazon-membero a relevant-types)
     (tree-edit--includes-typeo d relevant-types))))

(reazon-defrel tree-edit--superpositiono (tokens out parent-type)
  "OUT is TOKENS where each token is either itself or any relevant type occurring in PARENT-TYPE."
  (cond
   ((not tokens) (reazon-== out '()))
   ((and (not (equal (car tokens) 'comment)) (symbolp (car tokens)))
    (reazon-fresh (a d)
      (reazon-conso a d out)
      (reazon-membero a (tree-edit--relevant-types (car tokens) parent-type))
      (tree-edit--superpositiono (cdr tokens) d parent-type)))
   (t
    (reazon-fresh (a d)
      (reazon-conso a d out)
      (reazon-== a (car tokens))
      (tree-edit--superpositiono (cdr tokens) d parent-type)))))

(provide 'tree-edit)
;;; tree-edit.el ends here
