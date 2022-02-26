#lang web-server

(require threading
         ;; dotenv
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
(define *listen-port* (make-parameter 8080))
(define *listen-ip* (make-parameter "127.0.0.1"))
(define *known-hosts* (make-parameter #f))
(define ENABLE-WIFI
  ":foreach v in=[/interface wireless find where disabled=yes] do={/interface wireless set \\$v disabled=no}")
(define DISABLE-WIFI
  ":foreach v in=[/interface wireless find where disabled=no] do={/interface wireless set \\$v disabled=yes}")

(define-logger app)

(define-values (enable-responder disable-responder)
  (let ([make-responder (λ (verb)
                          (λ (req)
                            ;; This uses routeros scripts to disable/enable
                            ;; wireless interfaces.
                            (match (ssh-command (match verb ["enable" ENABLE-WIFI] ["disable" DISABLE-WIFI]))
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
  (define incantation (format "ssh -F/dev/null -oUserKnownHostsFile=~a -oPubkeyAcceptedKeyTypes=+ssh-rsa -i~a ~a ~a" (*known-hosts*) (*keyfile*) (*userhost*) cmd))
  (log-app-debug "SSH: ~a" incantation)
  (match-define (list out in pid err proc)
    (process incantation))
  (proc 'wait)
  (define s
    (port->string (merge-input out err)))
  (log-app-debug "OUT: ~a" s)
  (regexp-replace #rx"Warning: Permanently added the RSA host key for[^\n]+\n" s ""))

(define-syntax-rule (let0 ([binding val] more-bindings ...)
                          body body-rest ...)
  (let ([binding val] more-bindings ...)
    body body-rest ...
    binding))

(module+ main
  #;
  (with-handlers ([exn:fail:filesystem? void])
    (dotenv-load!))


  (with-logging-to-port (current-error-port)
    (thunk
     (*known-hosts*
      (let0 ([file (make-temporary-file)])
            (with-output-to-file file (thunk (write-bytes (base64-decode (getenv "WIFI_TOGGLE_SSH_KNOWN_HOSTS")))
                                             (newline)) #:exists 'must-truncate)))

     (match (getenv "WIFI_TOGGLE_LISTEN_IP")
       [#f (void)]
       [s (*listen-ip* s)])

     (match (getenv "WIFI_TOGGLE_LISTEN_PORT")
       [#f (void)]
       [s (*listen-port* (string->number s))])
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
                    #:port (*listen-port*)
                    #:listen-ip (*listen-ip*)
                    #:launch-browser? #f))
    #:logger app-logger
    'debug))
