;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2017, 2019 Caleb Ristvedt <caleb.ristvedt@cune.org>
;;; Copyright © 2018, 2020, 2021 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2020 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
;;; Copyright © 2022 Efraim Flashner <efraim@flashner.co.il>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (guix store database)
  #:use-module (sqlite3)
  #:use-module (guix config)
  #:use-module (guix serialization)
  #:use-module (guix store)
  #:use-module (guix derivations)
  #:use-module (guix store deduplication)
  #:use-module (guix base16)
  #:use-module (guix progress)
  #:use-module (guix build syscalls)
  #:use-module ((guix build utils)
                #:select (mkdir-p executable-file?))
  #:use-module (guix build store-copy)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-19)
  #:use-module (srfi srfi-26)
  #:use-module (rnrs io ports)
  #:use-module (ice-9 match)
  #:use-module (ice-9 vlist)
  #:use-module (system foreign)
  #:export (sql-schema
            %default-database-file
            store-database-file
            call-with-database
            with-database

            valid-path-id

            register-valid-path
            register-derivation-outputs
            register-items
            registered-derivation-outputs
            %epoch
            reset-timestamps
            vacuum-database
            valid-path
            all-valid-paths
            valid-path-from-hash-part
            outputs-exist?
            file-closure
            all-transitive-inputs
            valid-path-references))

;;; Code for working with the store database directly.

(define sql-schema
  ;; Name of the file containing the SQL scheme or #f.
  (make-parameter #f))

(define* (store-database-directory #:key prefix state-directory)
  "Return the store database directory, taking PREFIX and STATE-DIRECTORY into
account when provided."
  ;; Priority for options: first what is given, then environment variables,
  ;; then defaults. %state-directory, %store-directory, and
  ;; %store-database-directory already handle the "environment variables /
  ;; defaults" question, so we only need to choose between what is given and
  ;; those.
  (cond (state-directory
         (string-append state-directory "/db"))
        (prefix
         (string-append prefix %localstatedir "/guix/db"))
        (else
         %store-database-directory)))

(define* (store-database-file #:key prefix state-directory)
  "Return the store database file name, taking PREFIX and STATE-DIRECTORY into
account when provided."
  (string-append (store-database-directory #:prefix prefix
                                           #:state-directory state-directory)
                 "/db.sqlite"))

(define (initialize-database db)
  "Initializing DB, an empty database, by creating all the tables and indexes
as specified by SQL-SCHEMA."
  (define schema
    (or (sql-schema)
        (search-path %load-path "guix/store/schema.sql")))

  (sqlite-exec db (call-with-input-file schema get-string-all)))

(define* (call-with-database file proc #:key (wal-mode? #t))
  "Pass PROC a database record corresponding to FILE.  If FILE doesn't exist,
create it and initialize it as a new database.  Unless WAL-MODE? is set to #f,
set journal_mode=WAL."
  (let ((new? (and (not (file-exists? file))
                   (begin
                     (mkdir-p (dirname file))
                     #t)))
        (db   (sqlite-open file)))
    ;; Using WAL breaks for the Hurd <https://bugs.gnu.org/42151>.
    (when wal-mode?
      ;; Turn DB in "write-ahead log" mode, which should avoid SQLITE_LOCKED
      ;; errors when we have several readers: <https://www.sqlite.org/wal.html>.
      (sqlite-exec db "PRAGMA journal_mode=WAL;"))

    ;; Install a busy handler such that, when the database is locked, sqlite
    ;; retries until 30 seconds have passed, at which point it gives up and
    ;; throws SQLITE_BUSY.
    (sqlite-exec db "PRAGMA busy_timeout = 30000;")

    (dynamic-wind noop
                  (lambda ()
                    (when new?
                      (initialize-database db))
                    (proc db))
                  (lambda ()
                    (sqlite-close db)))))

;; XXX: missing in guile-sqlite3@0.1.2
(define SQLITE_BUSY 5)

(define (call-with-SQLITE_BUSY-retrying thunk)
  "Call THUNK, retrying as long as it exits abnormally due to SQLITE_BUSY
errors."
  (catch 'sqlite-error
    thunk
    (lambda (key who code errmsg)
      (if (= code SQLITE_BUSY)
          (call-with-SQLITE_BUSY-retrying thunk)
          (throw key who code errmsg)))))

(define* (call-with-transaction db proc #:key restartable?)
  "Start a transaction with DB and run PROC.  If PROC exits abnormally, abort
the transaction, otherwise commit the transaction after it finishes.
RESTARTABLE? may be set to a non-#f value when it is safe to run PROC multiple
times.  This may reduce contention for the database somewhat."
  ;; We might use begin immediate here so that if we need to retry, we figure
  ;; that out immediately rather than because some SQLITE_BUSY exception gets
  ;; thrown partway through PROC - in which case the part already executed
  ;; (which may contain side-effects!) might have to be executed again for
  ;; every retry.
  (sqlite-exec db (if restartable? "begin;" "begin immediate;"))
  (catch #t
    (lambda ()
      (let-values ((result (proc)))
        (sqlite-exec db "commit;")
        (apply values result)))
    (lambda args
      ;; The roll back may or may not have occurred automatically when the
      ;; error was generated. If it has occurred, this does nothing but signal
      ;; an error. If it hasn't occurred, this needs to be done.
      (false-if-exception (sqlite-exec db "rollback;"))
      (apply throw args))))

(define* (call-with-retrying-transaction db proc #:key restartable?)
  (call-with-SQLITE_BUSY-retrying
   (lambda ()
     (call-with-transaction db proc #:restartable? restartable?))))

(define %default-database-file
  ;; Default location of the store database.
  (string-append %store-database-directory "/db.sqlite"))

(define-syntax with-database
  (syntax-rules ()
    "Open DB from FILE and close it when the dynamic extent of EXP... is left.
If FILE doesn't exist, create it and initialize it as a new database.  Pass
#:wal-mode? to call-with-database."
    ((_ file db #:wal-mode? wal-mode? exp ...)
     (call-with-database file (lambda (db) exp ...) #:wal-mode? wal-mode?))
    ((_ file db exp ...)
     (call-with-database file (lambda (db) exp ...)))))

(define (sqlite-step-and-reset statement)
  (let ((val (sqlite-step statement)))
    (sqlite-reset statement)
    val))

(define (last-insert-row-id db)
  ;; XXX: (sqlite3) currently lacks bindings for 'sqlite3_last_insert_rowid'.
  ;; Work around that.
  (let ((stmt (sqlite-prepare db
                              "SELECT last_insert_rowid();"
                              #:cache? #t)))
    (vector-ref (sqlite-step-and-reset stmt)
                0)))

(define (valid-path-id db path)
  "If PATH exists in the 'ValidPaths' table, return its numerical identifier.
Otherwise, return #f."
  (let ((stmt (sqlite-prepare
               db
               "
SELECT id FROM ValidPaths WHERE path = :path"
               #:cache? #t)))
    (sqlite-bind-arguments stmt #:path path)
    (match (sqlite-step-and-reset stmt)
      (#(id) id)
      (#f #f))))

(define-inlinable (assert-integer proc in-range? key number)
  (unless (integer? number)
    (throw 'wrong-type-arg proc
           "Wrong type argument ~A: ~S" (list key number)
           (list number)))
  (unless (in-range? number)
    (throw 'out-of-range proc
           "Integer ~A out of range: ~S" (list key number)
           (list number))))

(define (register-derivation-outputs db drv)
  "Register all output paths of DRV as being produced by it (note that
this doesn't mean 'already produced by it', but rather just 'associated with
it')."
  (let ((stmt (sqlite-prepare
               db
               "
INSERT OR REPLACE INTO DerivationOutputs (drv, id, path)
SELECT id, :outid, :outpath FROM ValidPaths WHERE path = :drvpath;"
               #:cache? #t)))
    (for-each (match-lambda
                ((outid . ($ <derivation-output> path))
                 (sqlite-bind-arguments stmt
                                        #:drvpath (derivation-file-name
                                                   drv)
                                        #:outid outid
                                        #:outpath path)
                 (sqlite-step-and-reset stmt)))
              (derivation-outputs drv))))

(define (add-references db referrer references)
  "REFERRER is the id of the referring store item, REFERENCES is a list
ids of items referred to."
  (let ((stmt (sqlite-prepare
               db
               "
INSERT OR REPLACE INTO Refs (referrer, reference)
VALUES (:referrer, :reference)"
               #:cache? #t)))
    (for-each (lambda (reference)
                (sqlite-bind-arguments stmt #:referrer referrer
                                       #:reference reference)
                (sqlite-step-and-reset stmt))
              references)))

(define (timestamp)
  "Return a timestamp, either the current time of SOURCE_DATE_EPOCH."
  (match (getenv "SOURCE_DATE_EPOCH")
    (#f
     (current-time time-utc))
    ((= string->number seconds)
     (if seconds
         (make-time time-utc 0 seconds)
         (current-time time-utc)))))

(define* (register-valid-path db #:key path (references '())
                              deriver hash nar-size
                              (time (timestamp)))
  "Registers this stuff in DB.  PATH is the store item to register and
REFERENCES is the list of store items PATH refers to; DERIVER is the '.drv'
that produced PATH, HASH is the base16-encoded Nix sha256 hash of
PATH (prefixed with \"sha256:\"), and NAR-SIZE is the size in bytes PATH after
being converted to nar form.  TIME is the registration time to be recorded in
the database or #f, meaning \"right now\".

Every store item in REFERENCES must already be registered."

  (define registration-time
    (time-second time))

  ;; Make sure NAR-SIZE is valid.
  (assert-integer "register-valid-path" positive? #:nar-size nar-size)
  (assert-integer "register-valid-path" (cut >= <> 0)
                  #:time registration-time)

  (define id
    (let ((existing-id (valid-path-id db path)))
      (if existing-id
          (let ((stmt (sqlite-prepare
                       db
                       "
UPDATE ValidPaths
SET hash = :hash, registrationTime = :time, deriver = :deriver, narSize = :size
WHERE id = :id"
                       #:cache? #t)))
            (sqlite-bind-arguments stmt
                                   #:id existing-id
                                   #:deriver deriver
                                   #:hash hash
                                   #:size nar-size
                                   #:time registration-time)
            (sqlite-step-and-reset stmt)
            existing-id)
          (let ((stmt (sqlite-prepare
                       db
                       "
INSERT INTO ValidPaths (path, hash, registrationTime, deriver, narSize)
VALUES (:path, :hash, :time, :deriver, :size)"
                       #:cache? #t)))
            (sqlite-bind-arguments stmt
                                   #:path path
                                   #:deriver deriver
                                   #:hash hash
                                   #:size nar-size
                                   #:time registration-time)
            (sqlite-step-and-reset stmt)
            (last-insert-row-id db)))))

  (when (derivation-path? path)
    (register-derivation-outputs db
                                 (read-derivation-from-file
                                  path)))

  ;; Call 'path-id' on each of REFERENCES.  This ensures we get a
  ;; "non-NULL constraint" failure if one of REFERENCES is unregistered.
  (add-references db id
                  (map (cut valid-path-id db <>) references)))



;;;
;;; High-level interface.
;;;

(define* (reset-timestamps file #:key preserve-permissions?)
  "Reset the modification time on FILE and on all the files it contains, if
it's a directory.  Canonicalize file permissions unless PRESERVE-PERMISSIONS?
is true."
  ;; Note: We're resetting to one second after the Epoch like 'guix-daemon'
  ;; has always done.
  (let loop ((file file)
             (type (stat:type (lstat file))))
    (case type
      ((directory)
       (unless preserve-permissions?
         (chmod file #o555))
       (utime file 1 1 0 0)
       (let ((parent file))
         (for-each (match-lambda
                     (("." . _) #f)
                     ((".." . _) #f)
                     ((file . properties)
                      (let ((file (string-append parent "/" file)))
                        (loop file
                              (match (assoc-ref properties 'type)
                                ((or 'unknown #f)
                                 (stat:type (lstat file)))
                                (type type))))))
                   (scandir* parent))))
      ((symlink)
       (utime file 1 1 0 0 AT_SYMLINK_NOFOLLOW))
      (else
       (unless preserve-permissions?
         (chmod file (if (executable-file? file) #o555 #o444)))
       (utime file 1 1 0 0)))))

(define %epoch
  ;; When it all began.
  (make-time time-utc 0 1))

(define (registered-derivation-outputs db drv)
  "Get the list of (id, output-path) pairs registered for DRV."
  (let ((stmt (sqlite-prepare
               db
               "
SELECT id, path
FROM DerivationOutputs
WHERE drv in (SELECT id from ValidPaths where path = :drv)"
               #:cache? #t)))
    (sqlite-bind-arguments stmt #:drv drv)
    (let ((result (sqlite-fold (lambda (current prev)
                                 (match current
                                   (#(id path)
                                    (cons (cons id path)
                                          prev))))
                               '() stmt)))
      (sqlite-reset stmt)
      result)))

(define* (register-items db items
                         #:key prefix
                         (registration-time (timestamp))
                         (log-port (current-error-port)))
  "Register all of ITEMS, a list of <store-info> records as returned by
'read-reference-graph', in DB.  ITEMS must be in topological order (with
leaves first.)  REGISTRATION-TIME must be the registration time to be recorded
in the database; #f means \"now\".  Write a progress report to LOG-PORT.  All
of ITEMS must be protected from GC and locked during execution of this,
typically by adding them as temp-roots."
  (define store-dir
    (if prefix
        (string-append prefix %storedir)
        %store-directory))

  (define (register db item)
    (define to-register
      (if prefix
          (string-append %storedir "/" (basename (store-info-item item)))
          ;; note: we assume here that if path is, for example,
          ;; /foo/bar/gnu/store/thing.txt and prefix isn't given, then an
          ;; environment variable has been used to change the store directory
          ;; to /foo/bar/gnu/store, since otherwise real-path would end up
          ;; being /gnu/store/thing.txt, which is probably not the right file
          ;; in this case.
          (store-info-item item)))

    (define real-file-name
      (string-append store-dir "/" (basename (store-info-item item))))


    ;; When TO-REGISTER is already registered, skip it.  This makes a
    ;; significant differences when 'register-closures' is called
    ;; consecutively for overlapping closures such as 'system' and 'bootcfg'.
    (unless (valid-path-id db to-register)
      (let-values (((hash nar-size) (nar-sha256 real-file-name)))
        (call-with-retrying-transaction db
          (lambda ()
            (register-valid-path db #:path to-register
                                 #:references (store-info-references item)
                                 #:deriver (store-info-deriver item)
                                 #:hash (string-append
                                         "sha256:"
                                         (bytevector->base16-string hash))
                                 #:nar-size nar-size
                                 #:time registration-time))))))

  (let* ((prefix   (format #f "registering ~a items" (length items)))
         (progress (progress-reporter/bar (length items)
                                          prefix log-port)))
    (call-with-progress-reporter progress
      (lambda (report)
        (for-each (lambda (item)
                    (register db item)
                    (report))
                  items)))))

(define (vacuum-database)
  (let ((db (sqlite-open (store-database-file))))
    (sqlite-exec db "VACUUM;")
    (sqlite-close db)))

(define (valid-path db store-filename)
  (let ((statement
         (sqlite-prepare
          db
          "
SELECT id, hash, registrationTime, deriver, narSize
FROM ValidPaths
WHERE path = :path"
          #:cache? #t)))

    (sqlite-bind-arguments
     statement
     #:path store-filename)

    (let ((result (sqlite-step statement)))
      (sqlite-reset statement)

      result)))

(define (all-valid-paths db)
  (let ((statement
         (sqlite-prepare
          db
          "
SELECT path FROM ValidPaths"
          #:cache? #t)))

    (let ((result
           (sqlite-map
            (match-lambda
              (#(path) path))
            statement)))
      (sqlite-reset statement)

      result)))

(define (valid-path-from-hash-part db hash)
  (let ((statement
         (sqlite-prepare
          db
          "
SELECT path FROM ValidPaths WHERE path >= :path LIMIT 1"
          #:cache? #t))
        (path-prefix
         (string-append (%store-prefix) "/" hash)))

    (sqlite-bind-arguments
     statement
     #:path path-prefix)

    (let ((result
           (sqlite-step statement)))

      (if (and result (string-prefix? path-prefix result))
          result
          #f))))

(define (outputs-exist? db drv-path outputs)
  "Determine whether all output labels in OUTPUTS exist as built outputs of
DRV-PATH."
  (let ((statement
         (sqlite-prepare
          db
          "
SELECT id
FROM ValidPaths
WHERE path IN (
  SELECT path
  FROM DerivationOutputs
  WHERE DerivationOutputs.id = :id
    AND drv IN (
      SELECT id FROM ValidPaths WHERE path = :drvpath
    )
)"
          #:cache? #t)))
    (sqlite-bind-arguments statement #:drvpath drv-path)

    (every (lambda (out-id)
             (sqlite-bind-arguments statement #:id out-id)
             (sqlite-step-and-reset statement))
           outputs)))

(define* (file-closure db path #:key (list-so-far vlist-null))
  "Return a vlist containing the store paths referenced by PATH, the store
paths referenced by those paths, and so on."
  (let ((get-references
         (sqlite-prepare
          db
          "
SELECT path
FROM ValidPaths
WHERE id IN (
  SELECT reference FROM Refs WHERE referrer IN (
    SELECT id FROM ValidPaths WHERE path = :path
  )
)"
          #:cache? #t)))
    ;; to make it possible to go depth-first we need to get all the
    ;; references of an item first or we'll have re-entrancy issues with
    ;; the get-references statement.
    (define (references-of path)
      ;; There are no problems with resetting an already-reset
      ;; statement.
      (sqlite-bind-arguments get-references #:path path)
      (let ((result
             (sqlite-fold (lambda (row prev)
                            (cons (vector-ref row 0) prev))
                          '()
                          get-references)))
        (sqlite-reset get-references)
        result))

    (let %file-closure ((path path)
                        (references-vlist list-so-far))
      (if (vhash-assoc path references-vlist)
          references-vlist
          (fold %file-closure
                (vhash-cons path #t references-vlist)
                (references-of path))))))

(define (all-input-output-paths drv)
  "Return a list containing the output paths this derivation's inputs need to
provide."
  (apply append (map derivation-input-output-paths
                     (derivation-inputs drv))))

(define (all-transitive-inputs db drv)
  "Produce a list of all inputs and all of their references."
  (let ((input-paths (all-input-output-paths drv)))
    (vhash-fold (lambda (key val prev)
                  (cons key prev))
                '()
                (fold (lambda (input list-so-far)
                        (file-closure db input #:list-so-far list-so-far))
                      vlist-null
                      `(,@(derivation-sources drv)
                        ,@input-paths)))))

(define (valid-path-references db valid-path-id)
  (let ((statement
         (sqlite-prepare
          db
          "
SELECT ValidPaths.path
FROM Refs
INNER JOIN ValidPaths ON Refs.reference = ValidPaths.id
WHERE referrer = :id"
          #:cache? #t)))

    (sqlite-bind-arguments
     statement
     #:id valid-path-id)

    (let ((result (sqlite-fold
                   (lambda (row result)
                     (cons (vector-ref row 0)
                           result))
                   '()
                   statement)))
      (sqlite-reset statement)

      result)))
