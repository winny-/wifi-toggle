#lang info
(define collection "wifi-toggle")
;; TODO split tests out into own package.
(define deps '("base"
               "threading-lib"
               "base64-lib"
               "umask-lib"
               "web-server-lib"))
(define build-deps '())
(define scribblings '())
(define pkg-desc "Description Here")
(define version "0.1")
(define pkg-authors '("Winston Weinert"))
(define license '(MIT))
(define pkg-info "Toggle wifi via REST api")
