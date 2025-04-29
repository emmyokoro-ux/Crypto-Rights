;; IntellectProtect: Intellectual Property Registration and Verification Contract
;; This smart contract provides a decentralized system for registering and protecting intellectual 
;; property through cryptographic hash verification. It allows creators to:
;; - Register unique IP assets with timestamped proof of creation
;; - Verify ownership of registered IP
;; - Transfer ownership rights to other entities
;; - Validate hash authenticity of claimed intellectual property
;; - Update IP metadata and manage registration status

;; ERROR CONSTANTS
(define-constant ERR-UNAUTHORIZED-ACCESS (err u1000))
(define-constant ERR-INVALID-HASH-LENGTH (err u1001))
(define-constant ERR-EMPTY-HASH-VALUE (err u1002))
(define-constant ERR-DUPLICATE-HASH-ENTRY (err u1003))
(define-constant ERR-IP-RECORD-NOT-FOUND (err u1004))
(define-constant ERR-INVALID-IP-IDENTIFIER (err u1005))
(define-constant ERR-IP-ID-EXCEEDS-RANGE (err u1006))
(define-constant ERR-NOT-ADMINISTRATOR (err u1007))
(define-constant ERR-REGISTRATION-REVOKED (err u1008))
(define-constant ERR-ARRAY-LENGTH-MISMATCH (err u1009))
(define-constant ERR-BATCH-LIMIT-EXCEEDED (err u1010))
(define-constant ERR-REGISTRATION-FAILED (err u1011))
(define-constant ERR-INVALID-PRINCIPAL (err u1012))
(define-constant ERR-INVALID-FEE (err u1013))
(define-constant ERR-EMPTY-METADATA (err u1014))
(define-constant ERR-MAX-FEE-EXCEEDED (err u1015))

;; CONTRACT OWNERSHIP
(define-data-var contract-administrator principal tx-sender)

;; DATA STRUCTURES
;; Main registry of intellectual property assets
(define-map ip-registry
  { ip-identifier: uint }
  { 
    creator: principal,
    current-owner: principal, 
    registration-timestamp: uint,
    content-hash: (buff 32),
    metadata-uri: (string-utf8 256),
    is-active: bool
  }
)

;; Index to prevent duplicate hash registrations
(define-map registered-hash-index
  { content-hash: (buff 32) }
  { ip-identifier: uint }
)

;; Auto-incrementing counter for issuing unique IP identifiers
(define-data-var ip-asset-counter uint u0)

;; Registration fee in microSTX
(define-data-var registration-fee uint u1000000) ;; 1 STX default

;; Maximum allowed fee to prevent administrator errors
(define-constant MAX-ALLOWED-FEE u1000000000) ;; 1000 STX

;; EVENTS
;; Event for IP registration
(define-public (print-ip-registered (ip-id uint) (owner principal) (hash (buff 32)))
  (ok (print { event: "ip-registered", ip-identifier: ip-id, owner: owner, content-hash: hash }))
)

;; Event for IP ownership transfer
(define-public (print-ip-transferred (ip-id uint) (from principal) (to principal))
  (ok (print { event: "ip-transferred", ip-identifier: ip-id, from: from, to: to }))
)

;; Event for IP metadata update
(define-public (print-ip-updated (ip-id uint) (owner principal))
  (ok (print { event: "ip-updated", ip-identifier: ip-id, owner: owner }))
)

;; Event for IP registration status change
(define-public (print-ip-status-changed (ip-id uint) (status bool))
  (ok (print { event: "ip-status-changed", ip-identifier: ip-id, is-active: status }))
)

;; ADMINISTRATIVE FUNCTIONS

;; Check if caller is the contract administrator
(define-private (is-administrator)
  (is-eq tx-sender (var-get contract-administrator))
)

;; Validate principal is not the zero address
(define-private (is-valid-principal (address principal))
  (not (is-eq address 'SP000000000000000000002Q6VF78)))

;; Transfer contract administration to a new administrator
(define-public (transfer-administration (new-administrator principal))
  (begin
    ;; Check if caller is the current administrator
    (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
    
    ;; Validate the new administrator address
    (asserts! (is-valid-principal new-administrator) ERR-INVALID-PRINCIPAL)
    
    ;; Update the administrator
    (var-set contract-administrator new-administrator)
    (ok true)
  )
)

;; Update registration fee
(define-public (set-registration-fee (new-fee uint))
  (begin
    ;; Check if caller is the current administrator
    (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
    
    ;; Validate the new fee is within acceptable range
    (asserts! (<= new-fee MAX-ALLOWED-FEE) ERR-MAX-FEE-EXCEEDED)
    
    ;; Update the fee
    (var-set registration-fee new-fee)
    (ok true)
  )
)

;; PUBLIC FUNCTIONS

;; Validate metadata is not empty (check length instead of direct comparison)
(define-private (is-valid-metadata (metadata (string-utf8 256)))
  (> (len metadata) u0))

;; Register new intellectual property with a unique hash
(define-public (register-ip-asset (content-hash (buff 32)) (metadata-uri (string-utf8 256)))
  (let
    (
      (next-asset-id (+ (var-get ip-asset-counter) u1))
      (current-fee (var-get registration-fee))
    )
    ;; Input validation checks
    (asserts! (is-eq (len content-hash) u32) ERR-INVALID-HASH-LENGTH)
    (asserts! (not (is-eq content-hash 0x0000000000000000000000000000000000000000000000000000000000000000)) ERR-EMPTY-HASH-VALUE)
    (asserts! (is-none (map-get? registered-hash-index { content-hash: content-hash })) ERR-DUPLICATE-HASH-ENTRY)
    (asserts! (is-valid-metadata metadata-uri) ERR-EMPTY-METADATA)
    
    ;; Process registration fee if greater than zero
    (if (> current-fee u0)
      (unwrap! (stx-transfer? current-fee tx-sender (as-contract tx-sender)) ERR-UNAUTHORIZED-ACCESS)
      true
    )
    
    ;; Create new IP registration
    (map-set ip-registry
      { ip-identifier: next-asset-id }
      { 
        creator: tx-sender, 
        current-owner: tx-sender,
        registration-timestamp: block-height, 
        content-hash: content-hash,
        metadata-uri: metadata-uri,
        is-active: true
      }
    )
    
    ;; Record hash in index to prevent duplicates
    (map-set registered-hash-index
      { content-hash: content-hash }
      { ip-identifier: next-asset-id }
    )
    
    ;; Update counter for next registration
    (var-set ip-asset-counter next-asset-id)
    
    ;; Emit registration event
    (unwrap! (print-ip-registered next-asset-id tx-sender content-hash) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Return the new IP identifier
    (ok next-asset-id)
  )
)

;; Validate IP identifier
(define-private (is-valid-ip-id (ip-id uint))
  (and 
    (> ip-id u0)
    (<= ip-id (var-get ip-asset-counter))
  )
)

;; Transfer IP ownership to a new owner
(define-public (transfer-ip-ownership (ip-identifier uint) (new-owner principal))
  (begin
    ;; Validate IP identifier
    (asserts! (is-valid-ip-id ip-identifier) ERR-INVALID-IP-IDENTIFIER)
    ;; Validate new owner
    (asserts! (is-valid-principal new-owner) ERR-INVALID-PRINCIPAL)
    
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
        (asserts! (is-eq tx-sender (get current-owner existing-ip-data)) ERR-UNAUTHORIZED-ACCESS)
        ;; Verify the registration is active
        (asserts! (get is-active existing-ip-data) ERR-REGISTRATION-REVOKED)
        
        ;; Update ownership while preserving other data
        (map-set ip-registry
          { ip-identifier: ip-identifier }
          (merge existing-ip-data { current-owner: new-owner })
        )
        
        ;; Emit transfer event
        (unwrap! (print-ip-transferred ip-identifier tx-sender new-owner) ERR-UNAUTHORIZED-ACCESS)
        
        (ok true)
      )
    )
  )
)

;; Update IP metadata URI
(define-public (update-ip-metadata (ip-identifier uint) (new-metadata-uri (string-utf8 256)))
  (begin
    ;; Validate IP identifier
    (asserts! (is-valid-ip-id ip-identifier) ERR-INVALID-IP-IDENTIFIER)
    ;; Validate metadata
    (asserts! (is-valid-metadata new-metadata-uri) ERR-EMPTY-METADATA)
    
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
        (asserts! (is-eq tx-sender (get current-owner existing-ip-data)) ERR-UNAUTHORIZED-ACCESS)
        ;; Verify the registration is active
        (asserts! (get is-active existing-ip-data) ERR-REGISTRATION-REVOKED)
        
        ;; Update metadata while preserving other data
        (map-set ip-registry
          { ip-identifier: ip-identifier }
          (merge existing-ip-data { metadata-uri: new-metadata-uri })
        )
        
        ;; Emit update event
        (unwrap! (print-ip-updated ip-identifier tx-sender) ERR-UNAUTHORIZED-ACCESS)
        
        (ok true)
      )
    )
  )
)

;; Change IP registration status (active/inactive)
(define-public (set-ip-status (ip-identifier uint) (active bool))
  (begin
    ;; Validate IP identifier
    (asserts! (is-valid-ip-id ip-identifier) ERR-INVALID-IP-IDENTIFIER)
    
    (let
      (
        (ip-record (map-get? ip-registry { ip-identifier: ip-identifier }))
      )
      (asserts! (is-some ip-record) ERR-IP-RECORD-NOT-FOUND)
      (let
        (
          (existing-ip-data (unwrap-panic ip-record))
        )
        ;; Verify the sender is either the owner or administrator
        (asserts! (or 
                    (is-eq tx-sender (get current-owner existing-ip-data))
                    (is-administrator)
                  ) 
                  ERR-UNAUTHORIZED-ACCESS)
        
        ;; Update status while preserving other data
        (map-set ip-registry
          { ip-identifier: ip-identifier }
          (merge existing-ip-data { is-active: active })
        )
        
        ;; Emit status change event
        (unwrap! (print-ip-status-changed ip-identifier active) ERR-UNAUTHORIZED-ACCESS)
        
        (ok true)
      )
    )
  )
)

;; Batch register multiple IP assets - allows registration of up to 3 IP assets at once
(define-public (batch-register-ip 
                (hash-1 (buff 32)) (metadata-1 (string-utf8 256))
                (hash-2 (optional (buff 32))) (metadata-2 (optional (string-utf8 256)))
                (hash-3 (optional (buff 32))) (metadata-3 (optional (string-utf8 256))))
  (let
    (
      ;; Register first IP asset (required)
      (result-1 (try! (register-ip-asset hash-1 metadata-1)))
      (ids (list result-1))
    )
    ;; Register second IP asset if provided
    (if (and (is-some hash-2) (is-some metadata-2))
      (let
        (
          (result-2 (try! (register-ip-asset (unwrap! hash-2 (err u0)) (unwrap! metadata-2 (err u0)))))
          (ids-with-2 (append ids result-2))
        )
        ;; Register third IP asset if provided
        (if (and (is-some hash-3) (is-some metadata-3))
          (let
            (
              (result-3 (try! (register-ip-asset (unwrap! hash-3 (err u0)) (unwrap! metadata-3 (err u0)))))
              (all-ids (append ids-with-2 result-3))
            )
            (ok all-ids)
          )
          (ok ids-with-2)
        )
      )
      (ok ids)
    )
  )
)

;; READ-ONLY FUNCTIONS

;; Get current registration fee
(define-read-only (get-registration-fee)
  (var-get registration-fee)
)

;; Get contract administrator
(define-read-only (get-administrator)
  (var-get contract-administrator)
)

;; Check current ownership of an IP asset
(define-read-only (get-ip-owner (ip-identifier uint))
  (let
    (
      (ip-record (map-get? ip-registry { ip-identifier: ip-identifier }))
    )
    (if (is-some ip-record)
      (ok (get current-owner (unwrap-panic ip-record)))
      ERR-IP-RECORD-NOT-FOUND
    )
  )
)

;; Get original creator of an IP asset
(define-read-only (get-ip-creator (ip-identifier uint))
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

;; Get complete IP record
(define-read-only (get-ip-record (ip-identifier uint))
  (let
    (
      (ip-record (map-get? ip-registry { ip-identifier: ip-identifier }))
    )
    (if (is-some ip-record)
      (ok (unwrap-panic ip-record))
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

;; Get IP identifier from hash
(define-read-only (get-ip-id-from-hash (content-hash (buff 32)))
  (let
    (
      (hash-record (map-get? registered-hash-index { content-hash: content-hash }))
    )
    (if (is-some hash-record)
      (ok (get ip-identifier (unwrap-panic hash-record)))
      ERR-IP-RECORD-NOT-FOUND
    )
  )
)

;; Check if IP registration is active
(define-read-only (is-ip-active (ip-identifier uint))
  (let
    (
      (ip-record (map-get? ip-registry { ip-identifier: ip-identifier }))
    )
    (if (is-some ip-record)
      (ok (get is-active (unwrap-panic ip-record)))
      ERR-IP-RECORD-NOT-FOUND
    )
  )
)

;; Get total number of registered IP assets
(define-read-only (get-total-ip-count)
  (var-get ip-asset-counter)
)