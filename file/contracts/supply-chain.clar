;; supply-chain.clar
;; A Clarity smart contract for tracking products through a supply chain

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_INVALID_PRODUCT u2)
(define-constant ERR_INVALID_STAKEHOLDER u3)
(define-constant ERR_PRODUCT_RECALLED u4)
(define-constant ERR_INVALID_BATCH u5)

;; Data structures
(define-map products
  { product-id: (buff 32) }
  {
    name: (string-ascii 64),
    manufacturer: principal,
    current-custodian: principal,
    status: (string-ascii 20),
    batch-id: (optional (buff 32)),
    created-at: uint,
    last-updated: uint,
    recalled: bool,
    recall-reason: (optional (string-ascii 256))
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

(define-map product-batches
  { batch-id: (buff 32) }
  {
    manufacturer: principal,
    product-count: uint,
    creation-date: uint,
    notes: (optional (string-ascii 256)),
    recalled: bool,
    recall-reason: (optional (string-ascii 256))
  }
)

;; Product history tracking
(define-map product-history
  { product-id: (buff 32), event-id: uint }
  {
    event-type: (string-ascii 20),
    actor: principal,
    timestamp: uint,
    details: (optional (string-ascii 256))
  }
)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Event counters
(define-data-var event-id-counter uint u0)
(define-data-var history-id-counter uint u0)

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

(define-read-only (get-batch (batch-id (buff 32)))
  (map-get? product-batches { batch-id: batch-id })
)

(define-read-only (get-last-event-id)
  (var-get event-id-counter)
)

(define-read-only (get-product-history (product-id (buff 32)) (event-id uint))
  (map-get? product-history { product-id: product-id, event-id: event-id })
)

(define-read-only (is-product-recalled? (product-id (buff 32)))
  (match (map-get? products { product-id: product-id })
    product-data (get recalled product-data)
    false)
)

(define-read-only (is-batch-recalled? (batch-id (buff 32)))
  (match (map-get? product-batches { batch-id: batch-id })
    batch-data (get recalled batch-data)
    false)
)

;; Private functions

(define-private (add-history-event 
  (product-id (buff 32)) 
  (event-type (string-ascii 20)) 
  (details (optional (string-ascii 256)))
)
  (let ((new-history-id (+ (var-get history-id-counter) u1)))
    (var-set history-id-counter new-history-id)
    (map-set product-history
      { product-id: product-id, event-id: new-history-id }
      {
        event-type: event-type,
        actor: tx-sender,
        timestamp: block-height,
        details: details
      }
    )
    new-history-id
  )
)

;; Public functions

;; Register a new stakeholder
(define-public (register-stakeholder (name (string-ascii 64)) (role (string-ascii 20)))
  (begin
    ;; Validate inputs
    (asserts! (> (len name) u0) (err ERR_INVALID_STAKEHOLDER))
    (asserts! (> (len role) u0) (err ERR_INVALID_STAKEHOLDER))
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
  (let ((verified-stakeholder stakeholder))
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (match (map-get? stakeholders { stakeholder: verified-stakeholder })
      stakeholder-data
        (begin
          (map-set stakeholders
            { stakeholder: verified-stakeholder }
            (merge stakeholder-data { verified: true })
          )
          (ok verified-stakeholder)
        )
      (err ERR_INVALID_STAKEHOLDER)
    )
  )
)

;; Create a product batch
(define-public (create-batch
  (batch-id (buff 32))
  (product-count uint)
  (notes (optional (string-ascii 256)))
)
  (let (
    (manufacturer-data (unwrap! (map-get? stakeholders { stakeholder: tx-sender }) (err ERR_UNAUTHORIZED)))
    (validated-notes (match notes n (some n) none))
  )
    ;; Check sender is a verified manufacturer
    (asserts! (and 
            (is-eq (get role manufacturer-data) "manufacturer")
            (get verified manufacturer-data)
          ) 
          (err ERR_UNAUTHORIZED))
    ;; Validate batch-id is not empty
    (asserts! (> (len batch-id) u0) (err ERR_INVALID_BATCH))
    ;; Create batch
    (map-set product-batches
      { batch-id: batch-id }
      {
        manufacturer: tx-sender,
        product-count: product-count,
        creation-date: block-height,
        notes: validated-notes,
        recalled: false,
        recall-reason: none
      }
    )
    (ok batch-id)
  )
)

;; Create a new product (with optional batch)
(define-public (create-product 
  (product-id (buff 32)) 
  (name (string-ascii 64))
  (batch-id (optional (buff 32)))
)
  (let ((manufacturer-data (unwrap! (map-get? stakeholders { stakeholder: tx-sender }) (err ERR_UNAUTHORIZED))))
    ;; Check sender is a verified manufacturer
    (asserts! (and 
            (is-eq (get role manufacturer-data) "manufacturer")
            (get verified manufacturer-data)
          ) 
          (err ERR_UNAUTHORIZED))
    ;; Validate product-id and name
    (asserts! (> (len product-id) u0) (err ERR_INVALID_PRODUCT))
    (asserts! (> (len name) u0) (err ERR_INVALID_PRODUCT))
    ;; If batch provided, verify it exists and belongs to this manufacturer
    (if (is-some batch-id)
      (let ((some-batch-id (unwrap! batch-id (err ERR_INVALID_BATCH))))
        (asserts! (> (len some-batch-id) u0) (err ERR_INVALID_BATCH))
        (let ((batch-data (unwrap! (map-get? product-batches { batch-id: some-batch-id }) (err ERR_INVALID_BATCH))))
          (asserts! (is-eq (get manufacturer batch-data) tx-sender) (err ERR_UNAUTHORIZED))
          (asserts! (not (get recalled batch-data)) (err ERR_PRODUCT_RECALLED))
        )
      )
      true
    )
    ;; Create product
    (map-set products
      { product-id: product-id }
      {
        name: name,
        manufacturer: tx-sender,
        current-custodian: tx-sender,
        status: "created",
        batch-id: batch-id,
        created-at: block-height,
        last-updated: block-height,
        recalled: false,
        recall-reason: none
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
      ;; Add to product history
      (add-history-event product-id "created" (some "Product registered"))
      (ok product-id)
    )
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
    (validated-product-id product-id)
    (validated-to to)
    (validated-location (match location l (some l) none))
    (validated-notes (match notes n (some n) none))
    (product-data (map-get? products { product-id: validated-product-id }))
    (receiver-data (map-get? stakeholders { stakeholder: validated-to }))
  )
    ;; Validate product exists
    (asserts! (is-some product-data) (err ERR_INVALID_PRODUCT))
    ;; Check product is not recalled
    (asserts! (not (get recalled (unwrap! product-data (err ERR_INVALID_PRODUCT)))) (err ERR_PRODUCT_RECALLED))
    ;; Check sender is current custodian
    (asserts! (is-eq (get current-custodian (unwrap! product-data (err ERR_INVALID_PRODUCT))) tx-sender) (err ERR_UNAUTHORIZED))
    ;; Check receiver is a registered stakeholder
    (asserts! (is-some receiver-data) (err ERR_INVALID_STAKEHOLDER))
    ;; Check receiver is verified
    (asserts! (get verified (unwrap! receiver-data (err ERR_INVALID_STAKEHOLDER))) (err ERR_UNAUTHORIZED))
    ;; Update product custody
    (map-set products
      { product-id: validated-product-id }
      (merge (unwrap! product-data (err ERR_INVALID_PRODUCT))
        {
          current-custodian: validated-to,
          status: "in-transit",
          last-updated: block-height
        }
      )
    )
    ;; Record custody transfer event
    (let ((new-event-id (+ (var-get event-id-counter) u1)))
      (var-set event-id-counter new-event-id)
      (map-set custody-events
        { product-id: validated-product-id, event-id: new-event-id }
        {
          from: tx-sender,
          to: validated-to,
          timestamp: block-height,
          location: validated-location,
          notes: validated-notes
        }
      )
      ;; Add to product history
      (add-history-event validated-product-id "custody-transfer" (some "Ownership transferred"))
      (ok new-event-id)
    )
  )
)

;; Update product status
(define-public (update-product-status
  (product-id (buff 32))
  (status (string-ascii 20))
)
  (let ((validated-product-id product-id)
        (product-data (map-get? products { product-id: product-id })))
    ;; Validate product exists
    (asserts! (is-some product-data) (err ERR_INVALID_PRODUCT))
    ;; Validate status input
    (asserts! (> (len status) u0) (err ERR_INVALID_PRODUCT))
    ;; Check product is not recalled (unless updating to "recalled")
    (if (not (is-eq status "recalled"))
      (asserts! (not (get recalled (unwrap! product-data (err ERR_INVALID_PRODUCT)))) (err ERR_PRODUCT_RECALLED))
      true
    )
    ;; Check sender is current custodian
    (asserts! (is-eq (get current-custodian (unwrap! product-data (err ERR_INVALID_PRODUCT))) tx-sender) (err ERR_UNAUTHORIZED))
    ;; Update product status
    (map-set products
      { product-id: validated-product-id }
      (merge (unwrap! product-data (err ERR_INVALID_PRODUCT))
        {
          status: status,
          last-updated: block-height
        }
      )
    )
    ;; Add to product history
    (add-history-event validated-product-id "status-update" (some (concat "Status updated to " status)))
    (ok validated-product-id)
  )
)

;; Recall a product
(define-public (recall-product
  (product-id (buff 32))
  (reason (string-ascii 256))
)
  (let ((validated-product-id product-id)
        (product-data (map-get? products { product-id: product-id })))
    ;; Validate product exists
    (asserts! (is-some product-data) (err ERR_INVALID_PRODUCT))
    ;; Validate reason
    (asserts! (> (len reason) u0) (err ERR_INVALID_PRODUCT))
    ;; Check sender is manufacturer or contract owner
    (asserts! (or 
                (is-eq (get manufacturer (unwrap! product-data (err ERR_INVALID_PRODUCT))) tx-sender)
                (is-eq tx-sender (var-get contract-owner))
              ) 
              (err ERR_UNAUTHORIZED))
    ;; Update product recall status
    (map-set products
      { product-id: validated-product-id }
      (merge (unwrap! product-data (err ERR_INVALID_PRODUCT))
        {
          status: "recalled",
          recalled: true,
          recall-reason: (some reason),
          last-updated: block-height
        }
      )
    )
    ;; Add to product history
    (add-history-event validated-product-id "recalled" (some reason))
    (ok validated-product-id)
  )
)

;; Recall an entire batch
(define-public (recall-batch
  (batch-id (buff 32))
  (reason (string-ascii 256))
)
  (let ((validated-batch-id batch-id)
        (batch-data (map-get? product-batches { batch-id: batch-id })))
    ;; Validate batch exists
    (asserts! (is-some batch-data) (err ERR_INVALID_BATCH))
    ;; Validate reason
    (asserts! (> (len reason) u0) (err ERR_INVALID_BATCH))
    ;; Check sender is manufacturer or contract owner
    (asserts! (or 
                (is-eq (get manufacturer (unwrap! batch-data (err ERR_INVALID_BATCH))) tx-sender)
                (is-eq tx-sender (var-get contract-owner))
              ) 
              (err ERR_UNAUTHORIZED))
    ;; Update batch recall status
    (map-set product-batches
      { batch-id: validated-batch-id }
      (merge (unwrap! batch-data (err ERR_INVALID_BATCH))
        {
          recalled: true,
          recall-reason: (some reason)
        }
      )
    )
    (ok validated-batch-id)
  )
)

;; Change contract owner
(define-public (set-contract-owner (new-owner principal))
  (let ((validated-new-owner new-owner))
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (var-set contract-owner validated-new-owner)
    (ok validated-new-owner)
  )
)
