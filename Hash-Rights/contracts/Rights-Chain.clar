;; IntellectProtect: Intellectual Property Registration and Verification Contract
;; This smart contract provides a decentralized system for registering and protecting intellectual 
;; property through cryptographic hash verification. It allows creators to:
;; - Register unique IP assets with timestamped proof of creation
;; - Verify ownership of registered IP
;; - Transfer ownership rights to other entities
;; - Validate hash authenticity of claimed intellectual property

;; ERROR CONSTANTS
(define-constant ERR-UNAUTHORIZED-ACCESS (err u1000))
(define-constant ERR-INVALID-HASH-LENGTH (err u1001))
(define-constant ERR-EMPTY-HASH-VALUE (err u1002))
(define-constant ERR-DUPLICATE-HASH-ENTRY (err u1003))
(define-constant ERR-IP-RECORD-NOT-FOUND (err u1004))
(define-constant ERR-INVALID-IP-IDENTIFIER (err u1005))
(define-constant ERR-IP-ID-EXCEEDS-RANGE (err u1006))

;; CONTRACT OWNERSHIP
(define-data-var contract-administrator principal tx-sender)

;; DATA STRUCTURES
;; Main registry of intellectual property assets
(define-map ip-registry
  { ip-identifier: uint }
  { 
    creator: principal, 
    registration-timestamp: uint, 
    content-hash: (buff 32) 
  }
)

;; Index to prevent duplicate hash registrations
(define-map registered-hash-index
  { content-hash: (buff 32) }
  { ip-identifier: uint }
)

;; Auto-incrementing counter for issuing unique IP identifiers
(define-data-var ip-asset-counter uint u0)

;; PUBLIC FUNCTIONS

;; Register new intellectual property with a unique hash
(define-public (register-ip-asset (content-hash (buff 32)))
  (let
    (
      (next-asset-id (+ (var-get ip-asset-counter) u1))
    )
    ;; Input validation checks
    (asserts! (is-eq (len content-hash) u32) ERR-INVALID-HASH-LENGTH)
    (asserts! (not (is-eq content-hash 0x0000000000000000000000000000000000000000000000000000000000000000)) ERR-EMPTY-HASH-VALUE)
    (asserts! (is-none (map-get? registered-hash-index { content-hash: content-hash })) ERR-DUPLICATE-HASH-ENTRY)
    
    ;; Create new IP registration
    (map-set ip-registry
      { ip-identifier: next-asset-id }
      { creator: tx-sender, registration-timestamp: block-height, content-hash: content-hash }
    )
    
    ;; Record hash in index to prevent duplicates
    (map-set registered-hash-index
      { content-hash: content-hash }
      { ip-identifier: next-asset-id }
    )
    
    ;; Update counter for next registration
    (var-set ip-asset-counter next-asset-id)
    
    ;; Return the new IP identifier
    (ok next-asset-id)
  )
)

;; Transfer IP ownership to a new owner
(define-public (transfer-ip-ownership (ip-identifier uint) (new-owner principal))
  (let
    (
      (current-asset-count (var-get ip-asset-counter))
    )
    ;; Input validation checks
    (asserts! (<= ip-identifier current-asset-count) ERR-IP-ID-EXCEEDS-RANGE)
    (asserts! (> ip-identifier u0) ERR-INVALID-IP-IDENTIFIER)
    
    (let
      (
        (ip-record (map-get? ip-registry { ip-identifier: ip-identifier }))
      )
      (asserts! (is-some ip-record) ERR-IP-RECORD-NOT-FOUND)
      (let
        (
          (existing-ip-data (unwrap-panic ip-record))
        )
        ;; Verify the sender is the current owner
        (asserts! (is-eq tx-sender (get creator existing-ip-data)) ERR-UNAUTHORIZED-ACCESS)
        
        ;; Update ownership while preserving other data
        (map-set ip-registry
          { ip-identifier: ip-identifier }
          (merge existing-ip-data { creator: new-owner })
        )
        
        (ok true)
      )
    )
  )
)

;; READ-ONLY FUNCTIONS

;; Check current ownership of an IP asset
(define-read-only (get-ip-owner (ip-identifier uint))
  (let
    (
      (ip-record (map-get? ip-registry { ip-identifier: ip-identifier }))
    )
    (if (is-some ip-record)
      (ok (get creator (unwrap-panic ip-record)))
      ERR-IP-RECORD-NOT-FOUND
    )
  )
)

;; Verify if a given hash matches the registered hash for an IP
(define-read-only (verify-ip-hash (ip-identifier uint) (hash-to-check (buff 32)))
  (let
    (
      (ip-record (map-get? ip-registry { ip-identifier: ip-identifier }))
    )
    (if (is-some ip-record)
      (ok (is-eq (get content-hash (unwrap-panic ip-record)) hash-to-check))
      ERR-IP-RECORD-NOT-FOUND
    )
  )
)

;; Check if a hash is already registered in the system
(define-read-only (is-hash-already-registered (content-hash (buff 32)))
  (is-some (map-get? registered-hash-index { content-hash: content-hash }))
)