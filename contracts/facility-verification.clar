;; Facility Verification Contract
;; Validates molecular recycling operations and facility credentials

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_FACILITY_NOT_FOUND (err u101))
(define-constant ERR_FACILITY_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_STATUS (err u103))

;; Facility status types
(define-constant STATUS_PENDING u0)
(define-constant STATUS_VERIFIED u1)
(define-constant STATUS_SUSPENDED u2)
(define-constant STATUS_REVOKED u3)

;; Data structures
(define-map facilities
  { facility-id: uint }
  {
    owner: principal,
    name: (string-ascii 100),
    location: (string-ascii 200),
    capacity: uint,
    technology-type: (string-ascii 50),
    certification-level: uint,
    status: uint,
    verified-at: uint,
    expires-at: uint
  }
)

(define-map facility-metrics
  { facility-id: uint }
  {
    total-processed: uint,
    efficiency-rating: uint,
    compliance-score: uint,
    last-audit: uint
  }
)

(define-data-var next-facility-id uint u1)

;; Register a new facility
(define-public (register-facility
  (name (string-ascii 100))
  (location (string-ascii 200))
  (capacity uint)
  (technology-type (string-ascii 50)))
  (let ((facility-id (var-get next-facility-id)))
    (asserts! (is-none (map-get? facilities { facility-id: facility-id })) ERR_FACILITY_ALREADY_EXISTS)
    (map-set facilities
      { facility-id: facility-id }
      {
        owner: tx-sender,
        name: name,
        location: location,
        capacity: capacity,
        technology-type: technology-type,
        certification-level: u0,
        status: STATUS_PENDING,
        verified-at: u0,
        expires-at: u0
      }
    )
    (map-set facility-metrics
      { facility-id: facility-id }
      {
        total-processed: u0,
        efficiency-rating: u0,
        compliance-score: u0,
        last-audit: u0
      }
    )
    (var-set next-facility-id (+ facility-id u1))
    (ok facility-id)
  )
)

;; Verify facility (admin only)
(define-public (verify-facility
  (facility-id uint)
  (certification-level uint)
  (validity-period uint))
  (let ((facility (unwrap! (map-get? facilities { facility-id: facility-id }) ERR_FACILITY_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set facilities
      { facility-id: facility-id }
      (merge facility {
        certification-level: certification-level,
        status: STATUS_VERIFIED,
        verified-at: block-height,
        expires-at: (+ block-height validity-period)
      })
    )
    (ok true)
  )
)

;; Update facility status
(define-public (update-facility-status (facility-id uint) (new-status uint))
  (let ((facility (unwrap! (map-get? facilities { facility-id: facility-id }) ERR_FACILITY_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-status STATUS_REVOKED) ERR_INVALID_STATUS)
    (map-set facilities
      { facility-id: facility-id }
      (merge facility { status: new-status })
    )
    (ok true)
  )
)

;; Update facility metrics
(define-public (update-metrics
  (facility-id uint)
  (processed-amount uint)
  (efficiency uint)
  (compliance uint))
  (let ((facility (unwrap! (map-get? facilities { facility-id: facility-id }) ERR_FACILITY_NOT_FOUND))
        (current-metrics (default-to
          { total-processed: u0, efficiency-rating: u0, compliance-score: u0, last-audit: u0 }
          (map-get? facility-metrics { facility-id: facility-id }))))
    (asserts! (is-eq tx-sender (get owner facility)) ERR_UNAUTHORIZED)
    (map-set facility-metrics
      { facility-id: facility-id }
      {
        total-processed: (+ (get total-processed current-metrics) processed-amount),
        efficiency-rating: efficiency,
        compliance-score: compliance,
        last-audit: block-height
      }
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-facility (facility-id uint))
  (map-get? facilities { facility-id: facility-id })
)

(define-read-only (get-facility-metrics (facility-id uint))
  (map-get? facility-metrics { facility-id: facility-id })
)

(define-read-only (is-facility-verified (facility-id uint))
  (match (map-get? facilities { facility-id: facility-id })
    facility (and
      (is-eq (get status facility) STATUS_VERIFIED)
      (> (get expires-at facility) block-height))
    false
  )
)
