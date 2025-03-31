;; supply-chain.clar
;; A Clarity smart contract for tracking products through a supply chain

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_INVALID_PRODUCT u2)
(define-constant ERR_INVALID_STAKEHOLDER u3)

;; Data structures
(define-map products
  { product-id: (buff 32) }
  {
    name: (string-ascii 64),
    manufacturer: principal,
    current-custodian: principal,
    status: (string-ascii 20),
    created-at: uint,
    last-updated: uint
  }
)

(define-map stakeholders
  { stakeholder: principal }
  {
    name: (string-ascii 64),
    role: (string-ascii 20),
    verified: bool
  }
)

(define-map custody-events
  { product-id: (buff 32), event-id: uint }
  {
    from: principal,
    to: principal,
    timestamp: uint,
    location: (optional (tuple (lat int) (lng int))),
    notes: (optional (string-ascii 256))
  }
)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Event counters
(define-data-var event-id-counter uint u0)

;; Read-only functions

(define-read-only (get-product (product-id (buff 32)))
  (map-get? products { product-id: product-id })
)

(define-read-only (get-stakeholder (stakeholder principal))
  (map-get? stakeholders { stakeholder: stakeholder })
)

(define-read-only (get-custody-event (product-id (buff 32)) (event-id uint))
  (map-get? custody-events { product-id: product-id, event-id: event-id })
)

(define-read-only (get-last-event-id)
  (var-get event-id-counter)
)

;; Public functions

;; Register a new stakeholder
(define-public (register-stakeholder (name (string-ascii 64)) (role (string-ascii 20)))
  (begin
    (map-set stakeholders
      { stakeholder: tx-sender }
      { 
        name: name,
        role: role, 
        verified: false
      }
    )
    (ok tx-sender)
  )
)

;; Verify a stakeholder (only contract owner can do this)
(define-public (verify-stakeholder (stakeholder principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (match (map-get? stakeholders { stakeholder: stakeholder })
      stakeholder-data
        (begin
          (map-set stakeholders
            { stakeholder: stakeholder }
            (merge stakeholder-data { verified: true })
          )
          (ok stakeholder)
        )
      (err ERR_INVALID_STAKEHOLDER)
    )
  )
)

;; Create a new product
(define-public (create-product 
  (product-id (buff 32)) 
  (name (string-ascii 64))
)
  (let ((manufacturer-data (map-get? stakeholders { stakeholder: tx-sender })))
    (asserts! (is-some manufacturer-data) (err ERR_UNAUTHORIZED))
    (asserts! (is-eq (get role (unwrap! manufacturer-data (err ERR_UNAUTHORIZED))) "manufacturer") (err ERR_UNAUTHORIZED))
    
    (map-set products
      { product-id: product-id }
      {
        name: name,
        manufacturer: tx-sender,
        current-custodian: tx-sender,
        status: "created",
        created-at: block-height,
        last-updated: block-height
      }
    )
    
    ;; Record initial custody event
    (let ((new-event-id (+ (var-get event-id-counter) u1)))
      (var-set event-id-counter new-event-id)
      (map-set custody-events
        { product-id: product-id, event-id: new-event-id }
        {
          from: tx-sender,
          to: tx-sender,
          timestamp: block-height,
          location: none,
          notes: (some "Product created")
        }
      )
    )
    
    (ok product-id)
  )
)

;; Transfer product custody
(define-public (transfer-custody
  (product-id (buff 32))
  (to principal)
  (location (optional (tuple (lat int) (lng int))))
  (notes (optional (string-ascii 256)))
)
  (let (
    (product-data (map-get? products { product-id: product-id }))
    (receiver-data (map-get? stakeholders { stakeholder: to }))
  )
    ;; Validate product exists
    (asserts! (is-some product-data) (err ERR_INVALID_PRODUCT))
    ;; Check sender is current custodian
    (asserts! (is-eq (get current-custodian (unwrap! product-data (err ERR_INVALID_PRODUCT))) tx-sender) (err ERR_UNAUTHORIZED))
    ;; Check receiver is a registered stakeholder
    (asserts! (is-some receiver-data) (err ERR_INVALID_STAKEHOLDER))
    
    ;; Update product custody
    (map-set products
      { product-id: product-id }
      (merge (unwrap! product-data (err ERR_INVALID_PRODUCT))
        {
          current-custodian: to,
          status: "in-transit",
          last-updated: block-height
        }
      )
    )
    
    ;; Record custody transfer event
    (let ((new-event-id (+ (var-get event-id-counter) u1)))
      (var-set event-id-counter new-event-id)
      (map-set custody-events
        { product-id: product-id, event-id: new-event-id }
        {
          from: tx-sender,
          to: to,
          timestamp: block-height,
          location: location,
          notes: notes
        }
      )
      
      (ok new-event-id)
    )
  )
)

;; Update product status
(define-public (update-product-status
  (product-id (buff 32))
  (status (string-ascii 20))
)
  (let ((product-data (map-get? products { product-id: product-id })))
    ;; Validate product exists
    (asserts! (is-some product-data) (err ERR_INVALID_PRODUCT))
    ;; Check sender is current custodian
    (asserts! (is-eq (get current-custodian (unwrap! product-data (err ERR_INVALID_PRODUCT))) tx-sender) (err ERR_UNAUTHORIZED))
    
    ;; Update product status
    (map-set products
      { product-id: product-id }
      (merge (unwrap! product-data (err ERR_INVALID_PRODUCT))
        {
          status: status,
          last-updated: block-height
        }
      )
    )
    
    (ok product-id)
  )
)
