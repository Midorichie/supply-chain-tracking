;; product-certification.clar
;; A Clarity smart contract for certifying products in the supply chain

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_INVALID_PRODUCT u2)
(define-constant ERR_INVALID_CERTIFIER u3)
(define-constant ERR_ALREADY_CERTIFIED u4)
(define-constant ERR_NOT_CERTIFIED u5)
(define-constant ERR_INVALID_INPUT u400)

;; Data structures
(define-map certifiers
  { certifier: principal }
  {
    name: (string-ascii 64),
    organization: (string-ascii 64),
    specialty: (string-ascii 64),
    active: bool,
    registration-time: uint
  }
)

(define-map certifications
  { product-id: (buff 32), certification-type: (string-ascii 32) }
  {
    certifier: principal,
    timestamp: uint,
    expiration: (optional uint),
    result: (string-ascii 16),
    score: (optional uint),
    notes: (optional (string-ascii 256))
  }
)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Contract reference to supply chain
(define-data-var supply-chain-contract (optional principal) none)

;; Read-only functions

(define-read-only (get-certifier (certifier principal))
  (map-get? certifiers { certifier: certifier })
)

(define-read-only (get-certification (product-id (buff 32)) (certification-type (string-ascii 32)))
  (map-get? certifications { product-id: product-id, certification-type: certification-type })
)

(define-read-only (is-certified? (product-id (buff 32)) (certification-type (string-ascii 32)))
  (is-some (map-get? certifications { product-id: product-id, certification-type: certification-type }))
)

(define-read-only (is-certification-valid? (product-id (buff 32)) (certification-type (string-ascii 32)))
  (match (map-get? certifications { product-id: product-id, certification-type: certification-type })
    certification-data (match (get expiration certification-data)
                          expiry (< block-height expiry)
                          true)
    false)
)

;; Public functions

;; Set supply chain contract reference - validating input
(define-public (set-supply-chain-contract (contract-principal principal))
  (begin
    ;; Check caller is contract owner
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    ;; Ensure contract-principal is not null
    (asserts! (not (is-eq contract-principal 'SP000000000000000000002Q6VF78.null)) (err ERR_INVALID_INPUT))
    ;; Set the supply chain contract
    (var-set supply-chain-contract (some contract-principal))
    (ok contract-principal)
  )
)

;; Register a new certifier - validating input
(define-public (register-certifier 
  (name-input (string-ascii 64)) 
  (organization-input (string-ascii 64)) 
  (specialty-input (string-ascii 64))
)
  (begin
    ;; Check caller is contract owner
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    ;; Validate inputs are not empty
    (asserts! (> (len name-input) u0) (err ERR_INVALID_INPUT))
    (asserts! (> (len organization-input) u0) (err ERR_INVALID_INPUT))
    (asserts! (> (len specialty-input) u0) (err ERR_INVALID_INPUT))
    ;; Set certifier data
    (map-set certifiers
      { certifier: tx-sender }
      { 
        name: name-input,
        organization: organization-input,
        specialty: specialty-input,
        active: true,
        registration-time: block-height
      }
    )
    (ok tx-sender)
  )
)

;; Add a new certifier (by contract owner) - validating input
(define-public (add-certifier 
  (certifier-principal principal) 
  (name-input (string-ascii 64)) 
  (organization-input (string-ascii 64)) 
  (specialty-input (string-ascii 64))
)
  (begin
    ;; Check caller is contract owner
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    ;; Validate inputs are not empty
    (asserts! (> (len name-input) u0) (err ERR_INVALID_INPUT))
    (asserts! (> (len organization-input) u0) (err ERR_INVALID_INPUT))
    (asserts! (> (len specialty-input) u0) (err ERR_INVALID_INPUT))
    ;; Validate certifier principal is not null
    (asserts! (not (is-eq certifier-principal 'SP000000000000000000002Q6VF78.null)) (err ERR_INVALID_INPUT))
    ;; Check if certifier already exists
    (asserts! (is-none (map-get? certifiers { certifier: certifier-principal })) (err ERR_INVALID_CERTIFIER))
    ;; Set certifier data
    (map-set certifiers
      { certifier: certifier-principal }
      { 
        name: name-input,
        organization: organization-input,
        specialty: specialty-input,
        active: true,
        registration-time: block-height
      }
    )
    (ok certifier-principal)
  )
)

;; Deactivate a certifier - validating input
(define-public (deactivate-certifier (certifier-principal principal))
  (begin
    ;; Check caller is contract owner
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    ;; Validate certifier principal is not null
    (asserts! (not (is-eq certifier-principal 'SP000000000000000000002Q6VF78.null)) (err ERR_INVALID_INPUT))
    ;; Check if certifier exists and update active status
    (match (map-get? certifiers { certifier: certifier-principal })
      certifier-data
        (begin
          (map-set certifiers
            { certifier: certifier-principal }
            (merge certifier-data { active: false })
          )
          (ok certifier-principal)
        )
      (err ERR_INVALID_CERTIFIER)
    )
  )
)

;; Certify a product - validating input and sanitizing optional fields
(define-public (certify-product
  (product-id-input (buff 32))
  (certification-type-input (string-ascii 32))
  (result-input (string-ascii 16))
  (score-input (optional uint))
  (expiration-input (optional uint))
  (notes-input (optional (string-ascii 256)))
)
  (let (
    (certifier-data (map-get? certifiers { certifier: tx-sender }))
    (certification-exists (map-get? certifications { 
      product-id: product-id-input, 
      certification-type: certification-type-input 
    }))
  )
    ;; Validate inputs
    (asserts! (> (len product-id-input) u0) (err ERR_INVALID_PRODUCT))
    (asserts! (> (len certification-type-input) u0) (err ERR_INVALID_INPUT))
    (asserts! (> (len result-input) u0) (err ERR_INVALID_INPUT))
    ;; Validate score if provided (assuming score should be 0-100)
    (match score-input s (begin
                            (asserts! (<= s u100) (err ERR_INVALID_INPUT))
                            true)
      true)
    ;; Check the certifier is valid and active
    (asserts! (is-some certifier-data) (err ERR_INVALID_CERTIFIER))
    (asserts! (get active (unwrap! certifier-data (err ERR_INVALID_CERTIFIER))) (err ERR_UNAUTHORIZED))
    ;; Check product is not already certified with this type
    (asserts! (is-none certification-exists) (err ERR_ALREADY_CERTIFIED))
    ;; Sanitize the optional inputs using correct match syntax:
    (let (
      (validated-expiration (match expiration-input exp (some exp) none))
      (validated-score (match score-input s (some s) none))
      (validated-notes (match notes-input n (some n) none))
    )
      ;; Add certification
      (map-set certifications
        { product-id: product-id-input, certification-type: certification-type-input }
        {
          certifier: tx-sender,
          timestamp: block-height,
          expiration: validated-expiration,
          result: result-input,
          score: validated-score,
          notes: validated-notes
        }
      )
    )
    (ok product-id-input)
  )
)

;; Revoke certification - validating input
(define-public (revoke-certification
  (product-id-input (buff 32))
  (certification-type-input (string-ascii 32))
  (reason (string-ascii 256))
)
  (let (
    (certification-data (map-get? certifications { 
      product-id: product-id-input, 
      certification-type: certification-type-input 
    }))
  )
    ;; Validate inputs
    (asserts! (> (len product-id-input) u0) (err ERR_INVALID_PRODUCT))
    (asserts! (> (len certification-type-input) u0) (err ERR_INVALID_INPUT))
    (asserts! (> (len reason) u0) (err ERR_INVALID_INPUT))
    ;; Check certification exists
    (asserts! (is-some certification-data) (err ERR_NOT_CERTIFIED))
    ;; Check sender is either the original certifier or contract owner
    (asserts! (or 
                (is-eq (get certifier (unwrap! certification-data (err ERR_NOT_CERTIFIED))) tx-sender) 
                (is-eq tx-sender (var-get contract-owner))
              ) 
              (err ERR_UNAUTHORIZED))
    ;; Delete the certification
    (map-delete certifications { 
      product-id: product-id-input, 
      certification-type: certification-type-input 
    })
    (ok product-id-input)
  )
)
