;; Circular Integration Contract
;; Connects recycling with production in a circular economy

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_ORDER_NOT_FOUND (err u401))
(define-constant ERR_INSUFFICIENT_SUPPLY (err u402))
(define-constant ERR_INVALID_STATUS (err u403))

;; Order status
(define-constant STATUS_PENDING u0)
(define-constant STATUS_MATCHED u1)
(define-constant STATUS_IN_TRANSIT u2)
(define-constant STATUS_DELIVERED u3)
(define-constant STATUS_CANCELLED u4)

;; Data structures
(define-map supply-inventory
  { material-type: (string-ascii 50), quality-grade: uint }
  {
    total-available: uint,
    reserved: uint,
    price-per-unit: uint,
    last-updated: uint
  }
)

(define-map demand-orders
  { order-id: uint }
  {
    buyer: principal,
    material-type: (string-ascii 50),
    quality-grade: uint,
    quantity: uint,
    max-price: uint,
    delivery-location: (string-ascii 200),
    status: uint,
    created-at: uint,
    fulfilled-at: uint
  }
)

(define-map supply-matches
  { order-id: uint }
  {
    supplier-batches: (list 10 uint),
    total-quantity: uint,
    total-cost: uint,
    estimated-delivery: uint
  }
)

(define-map circular-metrics
  { period: uint }
  {
    total-recycled: uint,
    total-reused: uint,
    waste-diverted: uint,
    carbon-saved: uint,
    circular-rate: uint
  }
)

(define-data-var next-order-id uint u1)
(define-data-var current-period uint u1)

;; Update supply inventory
(define-public (update-supply
  (material-type (string-ascii 50))
  (quality-grade uint)
  (quantity uint)
  (price-per-unit uint))
  (let ((current-supply (default-to
    { total-available: u0, reserved: u0, price-per-unit: u0, last-updated: u0 }
    (map-get? supply-inventory { material-type: material-type, quality-grade: quality-grade }))))
    (map-set supply-inventory
      { material-type: material-type, quality-grade: quality-grade }
      {
        total-available: (+ (get total-available current-supply) quantity),
        reserved: (get reserved current-supply),
        price-per-unit: price-per-unit,
        last-updated: block-height
      }
    )
    (ok true)
  )
)

;; Create demand order
(define-public (create-demand-order
  (material-type (string-ascii 50))
  (quality-grade uint)
  (quantity uint)
  (max-price uint)
  (delivery-location (string-ascii 200)))
  (let ((order-id (var-get next-order-id)))
    (map-set demand-orders
      { order-id: order-id }
      {
        buyer: tx-sender,
        material-type: material-type,
        quality-grade: quality-grade,
        quantity: quantity,
        max-price: max-price,
        delivery-location: delivery-location,
        status: STATUS_PENDING,
        created-at: block-height,
        fulfilled-at: u0
      }
    )
    (var-set next-order-id (+ order-id u1))
    (ok order-id)
  )
)

;; Match supply with demand
(define-public (match-order
  (order-id uint)
  (supplier-batches (list 10 uint))
  (total-cost uint))
  (let ((order (unwrap! (map-get? demand-orders { order-id: order-id }) ERR_ORDER_NOT_FOUND)))
    (asserts! (is-eq (get status order) STATUS_PENDING) ERR_INVALID_STATUS)
    ;; Verify sufficient supply and reserve it
    (let ((supply-key { material-type: (get material-type order), quality-grade: (get quality-grade order) })
          (current-supply (unwrap! (map-get? supply-inventory supply-key) ERR_INSUFFICIENT_SUPPLY)))
      (asserts! (>= (- (get total-available current-supply) (get reserved current-supply)) (get quantity order)) ERR_INSUFFICIENT_SUPPLY)
      (asserts! (<= total-cost (get max-price order)) ERR_INSUFFICIENT_SUPPLY)

      ;; Reserve supply
      (map-set supply-inventory
        supply-key
        (merge current-supply { reserved: (+ (get reserved current-supply) (get quantity order)) })
      )

      ;; Update order status
      (map-set demand-orders
        { order-id: order-id }
        (merge order { status: STATUS_MATCHED })
      )

      ;; Record match
      (map-set supply-matches
        { order-id: order-id }
        {
          supplier-batches: supplier-batches,
          total-quantity: (get quantity order),
          total-cost: total-cost,
          estimated-delivery: (+ block-height u100)
        }
      )
      (ok true)
    )
  )
)

;; Update order status
(define-public (update-order-status (order-id uint) (new-status uint))
  (let ((order (unwrap! (map-get? demand-orders { order-id: order-id }) ERR_ORDER_NOT_FOUND)))
    (asserts! (<= new-status STATUS_CANCELLED) ERR_INVALID_STATUS)
    (map-set demand-orders
      { order-id: order-id }
      (merge order {
        status: new-status,
        fulfilled-at: (if (is-eq new-status STATUS_DELIVERED) block-height u0)
      })
    )
    (ok true)
  )
)

;; Update circular metrics
(define-public (update-circular-metrics
  (recycled uint)
  (reused uint)
  (waste-diverted uint)
  (carbon-saved uint))
  (let ((period (var-get current-period))
        (current-metrics (default-to
          { total-recycled: u0, total-reused: u0, waste-diverted: u0, carbon-saved: u0, circular-rate: u0 }
          (map-get? circular-metrics { period: period }))))
    (let ((new-recycled (+ (get total-recycled current-metrics) recycled))
          (new-reused (+ (get total-reused current-metrics) reused))
          (new-waste-diverted (+ (get waste-diverted current-metrics) waste-diverted))
          (new-carbon-saved (+ (get carbon-saved current-metrics) carbon-saved)))
      (let ((circular-rate (if (> (+ new-recycled new-reused) u0)
                            (/ (* (+ new-recycled new-reused) u100) (+ new-recycled new-reused new-waste-diverted))
                            u0)))
        (map-set circular-metrics
          { period: period }
          {
            total-recycled: new-recycled,
            total-reused: new-reused,
            waste-diverted: new-waste-diverted,
            carbon-saved: new-carbon-saved,
            circular-rate: circular-rate
          }
        )
        (ok true)
      )
    )
  )
)

;; Read-only functions
(define-read-only (get-supply-inventory (material-type (string-ascii 50)) (quality-grade uint))
  (map-get? supply-inventory { material-type: material-type, quality-grade: quality-grade })
)

(define-read-only (get-demand-order (order-id uint))
  (map-get? demand-orders { order-id: order-id })
)

(define-read-only (get-supply-match (order-id uint))
  (map-get? supply-matches { order-id: order-id })
)

(define-read-only (get-circular-metrics (period uint))
  (map-get? circular-metrics { period: period })
)

(define-read-only (get-available-supply (material-type (string-ascii 50)) (quality-grade uint))
  (match (map-get? supply-inventory { material-type: material-type, quality-grade: quality-grade })
    supply (ok (- (get total-available supply) (get reserved supply)))
    (ok u0)
  )
)
