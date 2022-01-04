#lang web-server

(require threading
         dotenv
         umask
         base64
         racket/logging)

#|
TODO Factor out SSH key and target host/user.

Offers the following routes to enable/disable wifi on a RouterOS host.  Can also get status.

/ GET => {"status": "enabled"} or {"status": "disabled"}
/enable POST => {"status": "enabled"}
/disable POST => {"status": "disabled"}
|#

(require json web-server/servlet web-server/servlet-env)

(define (response/json jsexpr #:code [code 200])
  (response/output (curry write-json jsexpr) #:code code))

(define *userhost* (make-parameter #f))
(define *keyfile* (make-parameter #f))

(define-logger app)

(define-values (enable-responder disable-responder)
  (let ([make-responder (λ (verb)
                          (λ (req)
                            ;; This uses routeros scripts to disable/enable
                            ;; wireless interfaces.
                            (match (ssh-command (format "/system script run ~a-wifi" verb))
                              [""
                               (response/json (hash 'status (string-append verb "d")))]
                              [non-empty-string
                               (error (string->symbol verb) "Error from command: ~a" non-empty-string)])))])
    (values (make-responder "enable")
            (make-responder "disable"))))

(define (status-responder req)
  (~> (ssh-command "/interface wireless print count-only where disabled")
      string-trim
      string->number
      (match _
        [0 "enabled"]
        [#f "unknown"]
        [other "disabled"])
      (hash 'status _)
      response/json))

(define-values (dispatch w-url)
  (dispatch-rules
   [("enable") #:method "post" enable-responder]
   [("disable") #:method "post" disable-responder]
   [("") status-responder]))

(define (four-oh-four-responder req)
  (response/output (curry displayln "Not found :(") #:code 404))


(define (ssh-command cmd)
  (define incantation (format "ssh -i~a ~a ~a" (*keyfile*) (*userhost*) cmd))
  (log-app-debug "SSH: ~a" incantation)
  (match-define (list out in pid err proc)
    (process incantation))
  (proc 'wait)
  (define s
    (port->string (merge-input out err)))
  (log-app-debug "OUT: ~a" s)
  s)

(define-syntax-rule (let0 ([binding val] more-bindings ...)
                          body body-rest ...)
  (let ([binding val] more-bindings ...)
    body body-rest ...
    binding))

(module+ main
  ;; (dotenv-load!)

  (with-logging-to-port (current-error-port)
    (thunk
     (*keyfile*
      (path->string
       (with-umask #o077
         (let0 ([file (make-temporary-file)])
               (with-output-to-file file (thunk (write-bytes (base64-decode (getenv "WIFI_TOGGLE_SSH_PRIVKEY"))))
                 #:exists 'must-truncate)))))
     (*userhost* (getenv "WIFI_TOGGLE_SSH_USERHOST"))

     (serve/servlet dispatch
                    #:file-not-found-responder four-oh-four-responder
                    #:servlet-path "/"
                    #:servlet-regexp #rx""
                    #:port 12341))
    #:logger app-logger
    'debug))
