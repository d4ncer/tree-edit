;;; tree-edit.el --- Description -*- lexical-binding: t; -*-
;;
;; Copyright (C) Ethan Leba <https://github.com/ethan-leba>
;; Maintainer: Ethan Leba <ethanleba5@gmail.com>
;; Created: June 28, 2021
;; Modified: June 28, 2021
;; Version: 0.0.1
;; Homepage: https://github.com/ethan-leba/tree-edit
;; Package-Requires: ((emacs "27.0") (tree-sitter "0.15.0") (dash "2.19") (evil "1.0.0") (avy "0.5.0") (reazon "0.4.0"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:
;;* Requires
(require 'tree-sitter)
(require 'tree-sitter-langs)
(require 'evil)
(require 'dash)
(require 'reazon)
(require 'avy)
(require 'json)
(require 's)

;; XXX: see mode-local
;;* Internal variables
(defvar-local tree-edit--current-node nil
  "The current node to apply editing commands to.")
(defvar-local tree-edit--node-overlay nil
  "The display overlay to show the current node.")
(defvar-local tree-edit--return-to-tree-state nil
  "Whether tree state should be returned to after exiting insert mode.")

;;* User settings
(defvar tree-edit-query-timeout 0.1
  "How long a query should take before giving up.")

(defvar tree-edit-mode-map (make-sparse-keymap))

(defvar tree-edit-grammar nil "The grammar rules generated by tree-sitter.")

(defvar tree-edit-significant-node-types nil
  "Important nodes in the grammar, used for navigation in `tree-edit-sig-up'.")
(defvar tree-edit-identifier-type 'identifier)
(defvar tree-edit--supertypes nil)
(defvar tree-edit--containing-types nil)
(defvar tree-edit-semantic-snippets nil
  "Snippets for constructing nodes in the grammar.

Must be an alist of node type (as a symbol) to list, where the list can contain
any string or a symbol referencing another node type in the alist.")

(defvar tree-edit-nodes nil
  "Nodes that a user can create via tree-edit.")



;;* Utilities

(defun tree-edit--boring-nodep (node)
  "Check if the NODE is not a named node."
  (and (tsc-node-p node) (stringp (tsc-node-type node))))

(defun tree-edit--supertypes-lru (type parent-type)
  "Return a list of the TYPE and all it's supertypes that occur in PARENT-TYPE.

Return cached result for TYPE and PARENT-TYPE, otherwise compute and return."
  (-intersection
   (alist-get type tree-edit--supertypes)
   (alist-get parent-type tree-edit--containing-types)))

(defun tree-edit--generate-supertype (type)
  "Return an alist of a type to it's supertypes (and itself)."
  (->> (-map #'car tree-edit-grammar)
       (--filter (reazon-run 1 q (te-parseo (alist-get it tree-edit-grammar) `(,type) '())))
       (--mapcat `(,it . ,(tree-edit--generate-supertype it)))
       (cons type)))

(defun tree-edit--generate-supertypes ()
  "Return an alist of a type to it's supertypes (and itself)."
  (-map
   (lambda (grammar)
     (let ((type (car grammar)))
       `(,type . ,(tree-edit--generate-supertype type))))
   tree-edit-grammar))

(defun tree-edit--generate-containing-types ()
  "Return an alist of a type to all the types it contains in it's grammar."
  (--map `(,(car it) . ,(tree-edit--extract-types ,(cdr it))) tree-edit-grammar))

(defun tree-edit--extract-types (grammar)
  "Return a list of all the symbol types in GRAMMAR."
  (pcase grammar
    ((and `((type . ,type)
            (value . ,value)
            (content . ,content))
          (guard (string-prefix-p "PREC" type)))
     (tree-edit--extract-types content))
    (`((type . "SEQ")
       (members . ,members))
     (-mapcat #'tree-edit--extract-types (append members '())))
    (`((type . "ALIAS")
       (content . ,content)
       (named . ,named)
       (value . ,value))
     (tree-edit--extract-types content))
    (`((type . "REPEAT")
       (content . ,content))
     (tree-edit--extract-types content))
    (`((type . "REPEAT1")
       (content . ,content))
     (tree-edit--extract-types content))
    (`((type . "FIELD")
       (name . ,name)
       (content . ,content))
     (tree-edit--extract-types content))
    (`((type . "SYMBOL")
       (name . ,name))
     `(,name))
    (`((type . "CHOICE")
       (members . ,members))
     (-mapcat #'tree-edit--extract-types members))
    (_ '())))

(defun tree-edit--map-nodes (pred fun tree)
  "Call FUN on each node of TREE that satisfies PRED.

If PRED returns nil, continue descending down this node.  If PRED
returns non-nil, apply FUN to this node and do not descend
further."
  (if (funcall pred tree)
      (funcall fun tree)
    (if (listp tree)
        (-map (lambda (x) (tree-edit--map-nodes pred fun x)) tree)
      tree)))

(defun tree-edit--process-node-type (obj)
  "Convert vectors to lists and strings to symbols in OBJ."
  (-tree-map-nodes
   #'-cons-pair-p
   (lambda (it) (pcase it
             (`(type . ,type)
              `(type . ,(intern type)))
             (_ it)))
   obj))

(defun tree-edit--process-grammar (obj)
  "Convert vectors to lists and strings to symbols in OBJ."
  (-tree-map-nodes
   #'-cons-pair-p
   (lambda (it)
     (pcase it
       (`(name . ,name)
        `(name . ,(intern name)))
       (`(,a . ,d) `(,a . ,(tree-edit--process-grammar d)))))
   obj))


;; XXX: bake value into file?
;; XXX: vector -> list a priori
(defmacro tree-edit-load-grammar (directory mode)
  "Load grammar from DIRECTORY for the given MODE."
  `(let ((json-array-type 'list))
     (let ((grammar (tree-edit--process-grammar (json-read-file (format "%s/grammar.json" ,directory)))))
       (setq-mode-local ,mode
                        tree-edit-types
                        (tree-edit--process-node-type (json-read-file (format "%s/node-types.json" ,directory)))
                        tree-edit-grammar
                        (alist-get 'rules grammar)))))

;;* Locals: navigation
(defun tree-edit--get-current-index (node)
  "Return a pair containing the siblings of the NODE and the index of itself."
  (let* ((parent (tsc-get-parent node))
         (pnodes (--map (tsc-get-nth-named-child parent it)
                        (number-sequence 0 (1- (tsc-count-named-children parent))))))
    (--find-index (equal (tsc-node-position-range node) (tsc-node-position-range it)) pnodes)))

(defmacro tree-edit--preserve-location (node movement &rest body)
  "Preserves the location of NODE during the execution of the BODY.

Optionally applies a MOVEMENT to the node after restoration,
moving the sibling index by the provided value."
  (declare (indent 2))
  `(let ((steps (tsc--node-steps (tsc-get-parent ,node)))
         (child-index (tree-edit--get-current-index ,node)))
     ,@body
     (let* ((recovered-parent (tsc--node-from-steps tree-sitter-tree steps))
            (num-children (tsc-count-named-children recovered-parent)))
       (setq tree-edit--current-node
             (if (equal num-children 0) recovered-parent
               (tsc-get-nth-named-child recovered-parent
                                        (min (max (+ child-index ,movement) 0) (1- num-children))))))
     (tree-edit--update-overlay)))

(defun tree-edit--update-overlay ()
  "Update the display of the current selected node, and move the cursor."
  (move-overlay tree-edit--node-overlay
                (tsc-node-start-position tree-edit--current-node)
                (tsc-node-end-position tree-edit--current-node))
  (goto-char (tsc-node-start-position tree-edit--current-node)))

(defun tree-edit--apply-until-interesting (fun node)
  "Apply FUN to NODE until a named node is hit."
  (let ((parent (funcall fun node)))
    (if (tree-edit--boring-nodep parent)
        (tree-edit--apply-until-interesting fun parent)
      parent)))

(defun tree-edit-query (patterns &optional matches tag-assigner)
  "Execute query PATTERNS against the current syntax tree and return captures.

If the optional arg MATCHES is non-nil, matches (from `tsc-query-matches') are
returned instead of captures (from `tsc-query-captures').

If the optional arg TAG-ASSIGNER is non-nil, it is passed to `tsc-make-query' to
assign custom tags to capture names.

This function is primarily useful for debugging purpose. Other packages should
build queries and cursors once, then reuse them."
  (let* ((query (tsc-make-query tree-sitter-language patterns tag-assigner))
         (root-node (tsc-root-node tree-sitter-tree)))
    (seq-map (lambda (capture) (cons (tsc-node-start-position (cdr capture)) (cdr capture)))
             (tsc-query-captures query tree-edit--current-node #'tsc--buffer-substring-no-properties))))

(defun tree-edit--sig-up (node)
  "Move NODE to the next (interesting) named sibling."
  (interactive)
  (setq node (tsc-get-parent node))
  (while (not (member (tsc-node-type node) tree-edit-significant-node-types))
    (setq node (tsc-get-parent node)))
  node)

(defun tree-edit--apply-movement (fun)
  "Apply movement FUN, and then update the node position and display."
  (when-let ((new-pos (tree-edit--apply-until-interesting fun tree-edit--current-node)))
    (setq tree-edit--current-node new-pos)
    (tree-edit--update-overlay)))

;;* Globals: navigation
(defun tree-edit-up ()
  "Move to the next (interesting) named sibling."
  (interactive)
  (tree-edit--apply-movement #'tsc-get-next-named-sibling))

(defun tree-edit-down ()
  "Move to the previous (interesting) named sibling."
  (interactive)
  (tree-edit--apply-movement #'tsc-get-prev-named-sibling))

(defun tree-edit-left ()
  "Move to the up to the next interesting parent."
  (interactive)
  (tree-edit--apply-movement #'tsc-get-parent))

(defun tree-edit-right ()
  "Move to the first child, unless it's an only child."
  (interactive)
  (tree-edit--apply-movement (lambda (node) (tsc-get-nth-named-child node 0))))

(defun tree-edit-sig-up ()
  "Move to the next (interesting) named sibling."
  (interactive)
  (tree-edit--apply-movement #'tree-edit--sig-up))

(defun tree-edit-avy-jump (node-type)
  "Avy jump to a node with the NODE-TYPE."
  (interactive)
  (let* ((position->node (tree-edit-query (format "(%s) @foo" node-type)
                                          ;; Querying needs a @name for unknown reasons
                                          ))
         ;; avy-action declares what should be done with the result of avy-process
         (avy-action (lambda (pos)
                       (setq tree-edit--current-node (alist-get pos position->node))
                       (tree-edit--update-overlay))))
    (avy-process (-map #'car position->node))))

;;* Locals: node transformations
(defun tree-edit--filter-unconstructable-nodes (nodes)
  "Filter NODES to only contain nodes in `tree-edit-nodes'."
  (let ((valid-nodes (--map (plist-get it :type) tree-edit-nodes)))
    (-intersection nodes valid-nodes)))

(defun tree-edit--get-tokens ()
  "Expand TYPE (if abstract) into concrete list of nodes."
  (--map (tsc-node-type (tsc-get-nth-child tree-edit--current-node it))
         (number-sequence 0 (1- (tsc-count-children tree-edit--current-node)))))

(defun tree-edit--get-parent-tokens (node)
  "Return a pair containing the siblings of the NODE and the index of itself."
  (let* ((parent (tsc-get-parent node))
         (pnodes (--map (tsc-get-nth-child parent it)
                        (number-sequence 0 (1- (tsc-count-children parent))))))
    (cons (-map #'tsc-node-type pnodes)
          (--find-index (equal (tsc-node-position-range node) (tsc-node-position-range it)) pnodes))))

;; TODO: Handle less restrictively by ripping out surrounding syntax (ie delete)
(defun tree-edit--valid-replacement-p (type node)
  "Return non-nil if the NODE can be replaced with a node of the provided TYPE."
  (let* ((parent-type (tsc-node-type (tsc-get-parent node)))
         (grammar (alist-get parent-type tree-edit-grammar))
         (current (tree-edit--get-parent-tokens node))
         (_split (-split-at (cdr current) (car current)))
         (left (nth 0 _split))
         ;; Removing the selected element
         (right (cdr (nth 1 _split)))
         (supertype (tree-edit--supertypes-lru type parent-type)))
    (if-let (result (reazon-run 1 q
                      (reazon-fresh (tokens qr ql d)
                        (te-superpositiono right qr parent-type)
                        (te-superpositiono left ql parent-type)
                        (te-max-lengtho q 3)
                        ;; FIXME: this should be limited to only 1 new named node, of the requested type
                        (te-includes-typeo q supertype)
                        (te-prefixpostfix ql q qr tokens)
                        (te-parseo grammar tokens '()))))
        ;; TODO: Put this in the query
        ;; Rejecting multi-node solutions
        (if (equal (length (car result)) 1)
            (--reduce-from (-replace it type acc) (car result) supertype)))))

(defun tree-edit--find-raise-ancestor (ancestor child-type)
  "Find a suitable ANCESTOR to be replaced with a node of CHILD-TYPE."
  (interactive)
  (cond
   ;; XXX: do we need both checks?
   ((not (and ancestor (tsc-get-parent ancestor))) (user-error "Can't raise node!"))
   ((tree-edit--valid-replacement-p child-type ancestor) ancestor)
   (t (tree-edit--find-raise-ancestor (tsc-get-parent ancestor) child-type))))

;; XXX: refactor boilerplate
;; XXX: contract subtypes
(defun tree-edit--valid-insertions (type after)
  "Return a valid sequence of tokens containing the provided TYPE, or nil.

If AFTER is t, generate the tokens after the current node, otherwise before."
  (let* ((parent-type (tsc-node-type (tsc-get-parent tree-edit--current-node)))
         (grammar (alist-get parent-type tree-edit-grammar))
         (current (tree-edit--get-parent-tokens tree-edit--current-node))
         (_split (-split-at (+ (cdr current) (if after 1 0)) (car current)))
         (left (nth 0 _split))
         (right (nth 1 _split))
         (supertype (tree-edit--supertypes-lru type parent-type)))
    (if-let (result (reazon-run 1 q
                      (reazon-fresh (tokens qr ql)
                        (te-superpositiono right qr parent-type)
                        (te-superpositiono left ql parent-type)
                        (te-max-lengtho q 5)
                        (te-prefixpostfix ql q qr tokens)
                        ;; FIXME: this should be limited to only 1 new named node, of the requested type
                        (te-includes-typeo q supertype)
                        (te-parseo grammar tokens '()))))
        (--reduce-from (-replace it type acc) (car result) supertype)
      (user-error "Cannot insert %s" type))))

;; XXX: these indexes are pretty screwy
(defun tree-edit--remove-node-and-surrounding-syntax (tokens idx)
  "Return a pair of indices to remove the node at IDX in TOKENS and all surrounding syntax."
  (let ((end (1+ idx))
        (start (1- idx)))
    (while (stringp (nth end tokens))
      (setq end (1+ end)))
    (while (and (>= start 0) (stringp (nth start tokens)))
      (setq start (1- start)))
    (cons (1+ start) end)))

(defun tree-edit--valid-deletions ()
  "Return a set of edits if `tree-edit--current-node' can be deleted, otherwise nil.

If successful, the return type will give a range of siblings to
delete, and what syntax needs to be inserted after, if any."
  (let* ((parent-type (tsc-node-type (tsc-get-parent tree-edit--current-node)))
         (grammar (alist-get
                   (tsc-node-type (tsc-get-parent tree-edit--current-node))
                   tree-edit-grammar))
         (current (tree-edit--get-parent-tokens tree-edit--current-node))
         (split (tree-edit--remove-node-and-surrounding-syntax
                  (car current) (cdr current)))
         (left-idx (car split))
         (left (-take left-idx (car current)))
         (right-idx (cdr split))
         (right (-drop right-idx (car current))))
    ;; FIXME: Q should be only string types, aka syntax -- we're banking that
    ;;        the first thing reazon stumbles upon is syntax.
    (if-let ((result (reazon-run 1 q
                       (reazon-fresh (tokens qr ql)
                         (te-superpositiono right qr parent-type)
                         (te-superpositiono left ql parent-type)
                         (te-max-lengtho q 5)
                         (te-prefixpostfix ql q qr tokens)
                         (te-parseo grammar tokens '())))))
        (if (-every-p #'stringp (car result))
            `(,left-idx ,(1- right-idx) ,(car result))))))

;;* Locals: node generation and rendering
(defun tree-edit-make-node (node-type rules &optional fragment)
  "Given a NODE-TYPE and a set of RULES, generate a node string.

If FRAGMENT is passed in, that will be used as a basis for node
construction, instead of looking up the rules for node-type."
  (interactive)
  (tree-edit--render-node (tree-edit--generate-node node-type rules fragment)))

(defun tree-edit--adhoc-pcre-to-rx (pcre)
  "Convert PCRE to an elisp regex (in no way robust)

pcre2el package doesn't support character classes, so can't use that.
Upstream patch?"
  (s-replace-all '(("\\p{L}" . "[:alpha:]")
                   ("\\p{Nd}" . "[:digit:]")) pcre))

;; FIXME Hardcoded alert!
(defun tree-edit--is-word (text)
  "Check if the given TEXT is a 'word' in the given grammar.

https://tree-sitter.github.io/tree-sitter/creating-parsers#keyword-extraction"
  (string-match-p (tree-edit--adhoc-pcre-to-rx "[\\p{L}_$][\\p{L}\\p{Nd}_$]*") text))

;; TODO: word spacing
;; TODO: valid grammars function
(defun tree-edit--generate-node (node-type rules &optional fragment)
  "Given a NODE-TYPE and a set of RULES, generate a node string.

If FRAGMENT is passed in, that will be used as a basis for node
construction, instead of looking up the rules for node-type."
  (interactive)
  (--mapcat (if (symbolp it) (tree-edit--generate-node it rules)
              `((,(equal node-type tree-edit-identifier-type) . ,it)))
            ;; See if we can make it via. the parser?
            (or fragment (alist-get node-type rules) (user-error "No node definition for %s" node-type))))

(defun tree-edit--render-node (tokens)
  "Combine TOKENS into a string, properly spacing as needed."
  (string-join
   (-as-> tokens xs
          (--map-indexed
           (pcase-let* ((`(,word-p . ,rendered) it))
             (if (not word-p) rendered
               (let ((beginning-pad (if (and (not (equal it-index 0))
                                             (tree-edit--is-word (cdr (nth (1- it-index) xs))))
                                        " "
                                      ""))
                     (end-pad (if (and (not (equal it-index (1- (length xs))))
                                       (tree-edit--is-word (cdr (nth (1+ it-index) xs))))
                                  " "
                                "")))
                 (string-join (list beginning-pad rendered end-pad))))) xs))))

(defun tree-edit--insert-fragment (fragment node position)
  "Insert rendered FRAGMENT at NODE in the provided POSITION.

POSITION can be :before, :after, or nil."
  ;; XXX: i don't think this accounts for word rules
  (let ((render-fragment (if fragment (tree-edit-make-node (tsc-node-type (tsc-get-parent node)) tree-edit-semantic-snippets fragment) "")))
    (pcase position
      (:after (goto-char (tsc-node-end-position tree-edit--current-node)))
      (:before (goto-char (tsc-node-start-position tree-edit--current-node))))
    (insert render-fragment)))

;;* Globals: Node transformation and generation
(defun tree-edit-change-node ()
  "Change the current node."
  (interactive)
  (tree-edit--preserve-location tree-edit--current-node 0
    (delete-region (tsc-node-start-position tree-edit--current-node)
                   (tsc-node-end-position tree-edit--current-node))
    (setq tree-edit--return-to-tree-state t)
    (evil-change-state 'insert)))

(defun tree-edit-copy-node ()
  "Copy the current node."
  (interactive)
  (kill-ring-save (tsc-node-start-position tree-edit--current-node)
                  (tsc-node-end-position tree-edit--current-node)))



;; XXX: exchange
(defun tree-edit-exchange-node (type)
  "Exchange the current node for the selected TYPE."
  (interactive)
  (unless (tree-edit--valid-replacement-p type tree-edit--current-node)
    (user-error "Cannot replace the current node with type %s!" type))
  (let* ((new-node (tree-edit-make-node type tree-edit-semantic-snippets)))
    (tree-edit--preserve-location tree-edit--current-node 0
      (delete-region (tsc-node-start-position tree-edit--current-node)
                     (tsc-node-end-position tree-edit--current-node))
      (insert new-node))))

(defun tree-edit-raise ()
  "Move the current node up the syntax tree until a valid replacement is found."
  (interactive)
  (let ((ancestor-to-replace (tree-edit--find-raise-ancestor
                              (tsc-get-parent tree-edit--current-node)
                              (tsc-node-type tree-edit--current-node))))
    (tree-edit--preserve-location ancestor-to-replace 0
      (let ((node-text (tsc-node-text tree-edit--current-node)))
        (delete-region (tsc-node-start-position ancestor-to-replace)
                       (tsc-node-end-position ancestor-to-replace))
        (insert node-text)))))

(defun tree-edit-insert-sibling (type)
  "Insert a node of the given TYPE after the current."
  (interactive)
  (let ((fragment (tree-edit--valid-insertions type t)))
    (tree-edit--preserve-location tree-edit--current-node 1
      (tree-edit--insert-fragment fragment tree-edit--current-node :after))))

(defun tree-edit-wrap-node ()
  "TBD."
  ;; Yank, replace, jump to yanked type, paste.
  )

(defun tree-edit-delete-node ()
  "Delete the current node, and any surrounding syntax that accompanies it."
  (interactive)
  (pcase-let ((`(,start ,end ,fragment) (or (tree-edit--valid-deletions) (user-error "Cannot delete the current node"))))
    (tree-edit--preserve-location tree-edit--current-node 0
      (goto-char (tsc-node-start-position (tsc-get-nth-child (tsc-get-parent tree-edit--current-node) start)))
      (delete-region (tsc-node-start-position (tsc-get-nth-child (tsc-get-parent tree-edit--current-node) start))
                     (tsc-node-end-position (tsc-get-nth-child (tsc-get-parent tree-edit--current-node) end)))
      (tree-edit--insert-fragment fragment tree-edit--current-node nil))))


;;* Locals: Relational parser

;; FIXME: deal with 'comment' type
(reazon-defrel te-parseo (grammar tokens out)
  "TOKENS are a valid prefix of a node in GRAMMAR and OUT is unused tokens in TOKENS."
  (pcase grammar
    (`((type . "STRING")
       (value . ,value))
     (te-takeo value tokens out))
    (`((type . "PATTERN")
       (value . ,value))
     (te-takeo :regex tokens out))
    (`((type . "BLANK"))
     (reazon-== tokens out))
    ((and `((type . ,type)
            (value . ,value)
            (content . ,content))
          (guard (string-prefix-p "PREC" type)))
     (te-parseo content tokens out))
    (`((type . "TOKEN")
       (content . ,content))
     (te-parseo content tokens out))
    (`((type . "SEQ")
       (members . ,members))
     (te-seqo members tokens out))
    (`((type . "ALIAS")
       (content . ,content)
       (named . ,named)
       (value . ,value))
     (te-parseo content tokens out))
    (`((type . "REPEAT")
       (content . ,content))
     (te-repeato content tokens out))
    (`((type . "REPEAT1")
       (content . ,content))
     (te-repeat1o content tokens out))
    (`((type . "FIELD")
       (name . ,name)
       (content . ,content))
     (te-parseo content tokens out))
    (`((type . "SYMBOL")
       (name . ,name))
     (te-takeo name tokens out))
    (`((type . "CHOICE")
       (members . ,members))
     (te-choiceo members tokens out))
    (_ (error "Bad data: %s" grammar))))

(reazon-defrel te-max-lengtho (ls len)
  "TOKENS are a valid prefix of a node in GRAMMAR, with OUT as leftovers."
  (cond
   ((zerop len) (reazon-nullo ls))
   (t (reazon-disj
       (reazon-nullo ls)
       (reazon-fresh (d)
         (reazon-cdro ls d)
         (te-max-lengtho d (1- len)))))))

(reazon-defrel te-seqo (members tokens out)
  "TOKENS parse sequentially for each grammar in MEMBERS, with OUT as leftovers."
  (if members
      (reazon-fresh (next)
        (te-parseo (car members) tokens next)
        (te-seqo (cdr members) next out))
    (reazon-== tokens out)))

(reazon-defrel te-choiceo (members tokens out)
  "TOKENS parse for each grammar in MEMBERS, with OUT as leftovers."
  (if members
      (reazon-disj
       (te-parseo (car members) tokens out)
       (te-choiceo (cdr members) tokens out))
    #'reazon-!U))

(reazon-defrel te-repeato (grammar tokens out)
  "TOKENS parse for GRAMMAR an abritrary amount of times, with OUT as leftovers."
  (reazon-disj
   (reazon-== tokens out)
   (reazon-fresh (next)
     (te-parseo grammar tokens next)
     (te-repeato grammar next out))))

(reazon-defrel te-repeat1o (grammar tokens out)
  "TOKENS parse for GRAMMAR at least once, up to an abritrary amount of times, with OUT as leftovers."
  (reazon-fresh (next)
    (te-parseo grammar tokens next)
    (te-repeato grammar next out)))

(reazon-defrel te-takeo (expected tokens out)
  "TOKENS is a cons, with car as EXPECTED and cdr as OUT."
  (reazon-conso expected out tokens))

(reazon-defrel te-prefixpostfix (prefix middle postfix out)
  "OUT is composed of the lists PREFIX, MIDDLE, POSTFIX."
  (reazon-fresh (tmp)
    (reazon-appendo prefix middle tmp)
    (reazon-appendo tmp postfix out)))

(reazon-defrel te-includes-typeo (tokens supertypes)
  "One of the types in SUPERTYPE appears in TOKENS."
  (reazon-fresh (a d)
    (reazon-conso a d tokens)
    (reazon-disj
     (reazon-membero a supertypes)
     (te-includes-typeo d supertypes))))

(reazon-defrel te-superpositiono (tokens out parent-type)
  "OUT is TOKENS where each token is either itself or any supertype occurring in PARENT-TYPE."
  (cond
   ((not tokens) (reazon-== out '()))
   ((symbolp (car tokens))
    (reazon-fresh (a d)
      (reazon-conso a d out)
      (reazon-membero a (tree-edit--supertypes-lru (car tokens) parent-type))
      (te-superpositiono (cdr tokens) d parent-type)))
   (t
    (reazon-fresh (a d)
      (reazon-conso a d out)
      (reazon-== a (car tokens))
      (te-superpositiono (cdr tokens) d parent-type)))))

;;* Evil state definition and keybindings
(defun tree-edit--enter-tree-state ()
  "Activate tree-edit state."
  (when (not tree-edit--node-overlay)
    (setq tree-edit--node-overlay (make-overlay 0 0)))
  (let ((node (tsc-get-descendant-for-position-range
               (tsc-root-node tree-sitter-tree) (point) (point))))
    (setq tree-edit--current-node
          (if (tree-edit--boring-nodep node)
              (tree-edit--apply-until-interesting #'tsc-get-parent node)
            node)))
  (overlay-put tree-edit--node-overlay 'face 'region)
  (tree-edit--update-overlay))

(defun tree-edit--exit-tree-state ()
  "De-activate tree-edit state."
  (overlay-put tree-edit--node-overlay 'face 'nil))

(evil-define-state tree
  "If enabled, foo on you!"
  :tag " <T>"
  :entry-hook (tree-edit--enter-tree-state)
  :exit-hook (tree-edit--exit-tree-state)
  :suppress-keymap t)

(define-minor-mode tree-edit-mode
  "If enabled, foo on you!"
  :keymap (make-sparse-keymap))

;; XXX: TODO minor mode dependency?
(defun define-tree-edit-verb (key func)
  "Define a key command prefixed by KEY, calling FUNC.

FUNC must take two arguments, a symbol of the node type"
  (dolist (node tree-edit-nodes)
    (define-key
     evil-tree-state-map
     (string-join (list key (plist-get node :key)))
     (cons
      ;; emacs-which-key integration
      (or (plist-get node :name) (s-replace "_" " " (symbol-name (plist-get node :type))))
      `(lambda ()
         (interactive)
         (let ((tree-edit-semantic-snippets (append ,(plist-get node :node-override) tree-edit-semantic-snippets)))
           (,func ',(plist-get node :type))))))))

(evil-define-key 'normal tree-edit-mode-map "Q" #'evil-tree-state)

(defun tree-edit--set-state-bindings ()
  (define-tree-edit-verb "i" #'tree-edit-insert-sibling)
  (define-tree-edit-verb "a" #'tree-edit-avy-jump)
  (define-tree-edit-verb "e" #'tree-edit-exchange-node)
  (define-key evil-tree-state-map [escape] 'evil-normal-state)
  (define-key evil-tree-state-map "j" #'tree-edit-up)
  (define-key evil-tree-state-map "k" #'tree-edit-down)
  (define-key evil-tree-state-map "h" #'tree-edit-left)
  (define-key evil-tree-state-map "f" #'tree-edit-right)
  (define-key evil-tree-state-map "c" #'tree-edit-change-node)
  (define-key evil-tree-state-map "d" #'tree-edit-delete-node)
  (define-key evil-tree-state-map "r" #'tree-edit-raise)
  (define-key evil-tree-state-map "y" #'tree-edit-copy-node)
  (define-key evil-tree-state-map "A" #'tree-edit-sig-up))

(require 'tree-edit-java)
(provide 'tree-edit)
;;; tree-edit.el ends here
