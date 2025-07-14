;; Emergency Assistance Contract
;; Provides rapid food support during household crises

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-INPUT (err u501))
(define-constant ERR-REQUEST-NOT-FOUND (err u502))
(define-constant ERR-INSUFFICIENT-FUNDS (err u503))
(define-constant ERR-REQUEST-ALREADY-PROCESSED (err u504))

;; Data Variables
(define-data-var next-request-id uint u1)
(define-data-var emergency-fund uint u0)
(define-data-var total-requests uint u0)
(define-data-var total-assistance-provided uint u0)

;; Data Maps
(define-map emergency-requests
  { request-id: uint }
  {
    requester: principal,
    emergency-type: (string-ascii 50),
    description: (string-ascii 500),
    urgency-level: uint,
    household-size: uint,
    assistance-amount: uint,
    status: (string-ascii 20),
    created-at: uint,
    processed-at: uint,
    processed-by: (optional principal)
  }
)

(define-map assistance-history
  { requester: principal, request-date: uint }
  {
    request-id: uint,
    amount-received: uint,
    assistance-type: (string-ascii 50),
    follow-up-needed: bool
  }
)

(define-map volunteer-responders
  { responder: principal }
  {
    name: (string-ascii 100),
    contact-info: (string-ascii 200),
    availability: (string-ascii 50),
    specialties: (string-ascii 200),
    requests-handled: uint,
    response-rating: uint,
    active: bool
  }
)

(define-map emergency-resources
  { resource-type: (string-ascii 50) }
  {
    quantity-available: uint,
    location: (string-ascii 100),
    contact-person: principal,
    last-updated: uint
  }
)

;; Emergency token for crisis response
(define-fungible-token emergency-token)

;; Public Functions

;; Submit emergency assistance request
(define-public (submit-emergency-request
    (emergency-type (string-ascii 50))
    (description (string-ascii 500))
    (urgency-level uint)
    (household-size uint)
    (assistance-amount uint))
  (let
    (
      (request-id (var-get next-request-id))
    )
    (asserts! (and (> urgency-level u0) (<= urgency-level u5) (> household-size u0) (> assistance-amount u0)) ERR-INVALID-INPUT)

    (map-set emergency-requests
      { request-id: request-id }
      {
        requester: tx-sender,
        emergency-type: emergency-type,
        description: description,
        urgency-level: urgency-level,
        household-size: household-size,
        assistance-amount: assistance-amount,
        status: "pending",
        created-at: block-height,
        processed-at: u0,
        processed-by: none
      }
    )

    (var-set next-request-id (+ request-id u1))
    (var-set total-requests (+ (var-get total-requests) u1))

    (print { event: "emergency-request-submitted", request-id: request-id, requester: tx-sender, urgency: urgency-level })
    (ok request-id)
  )
)

;; Process emergency request
(define-public (process-emergency-request (request-id uint) (approved bool))
  (let
    (
      (request-data (unwrap! (map-get? emergency-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (responder-profile (default-to { name: "", contact-info: "", availability: "", specialties: "", requests-handled: u0, response-rating: u0, active: true }
                                    (map-get? volunteer-responders { responder: tx-sender })))
    )
    (asserts! (is-eq (get status request-data) "pending") ERR-REQUEST-ALREADY-PROCESSED)
    (asserts! (>= (var-get emergency-fund) (get assistance-amount request-data)) ERR-INSUFFICIENT-FUNDS)

    (if approved
      (begin
        (map-set emergency-requests
          { request-id: request-id }
          (merge request-data {
            status: "approved",
            processed-at: block-height,
            processed-by: (some tx-sender)
          })
        )

        (map-set assistance-history
          { requester: (get requester request-data), request-date: (get created-at request-data) }
          {
            request-id: request-id,
            amount-received: (get assistance-amount request-data),
            assistance-type: (get emergency-type request-data),
            follow-up-needed: (>= (get urgency-level request-data) u4)
          }
        )

        (var-set emergency-fund (- (var-get emergency-fund) (get assistance-amount request-data)))
        (var-set total-assistance-provided (+ (var-get total-assistance-provided) (get assistance-amount request-data)))

        (try! (ft-mint? emergency-token (get assistance-amount request-data) (get requester request-data)))
        (try! (ft-mint? emergency-token u50 tx-sender))
      )
      (map-set emergency-requests
        { request-id: request-id }
        (merge request-data {
          status: "denied",
          processed-at: block-height,
          processed-by: (some tx-sender)
        })
      )
    )

    (map-set volunteer-responders
      { responder: tx-sender }
      (merge responder-profile {
        requests-handled: (+ (get requests-handled responder-profile) u1)
      })
    )

    (print { event: "request-processed", request-id: request-id, approved: approved, processor: tx-sender })
    (ok approved)
  )
)

;; Add funds to emergency fund
(define-public (contribute-to-emergency-fund (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-INPUT)

    (var-set emergency-fund (+ (var-get emergency-fund) amount))
    (try! (ft-mint? emergency-token (* amount u2) tx-sender))

    (print { event: "emergency-fund-contribution", contributor: tx-sender, amount: amount })
    (ok true)
  )
)

;; Register as volunteer responder
(define-public (register-volunteer-responder
    (name (string-ascii 100))
    (contact-info (string-ascii 200))
    (availability (string-ascii 50))
    (specialties (string-ascii 200)))
  (begin
    (map-set volunteer-responders
      { responder: tx-sender }
      {
        name: name,
        contact-info: contact-info,
        availability: availability,
        specialties: specialties,
        requests-handled: u0,
        response-rating: u0,
        active: true
      }
    )

    (try! (ft-mint? emergency-token u75 tx-sender))

    (print { event: "volunteer-registered", responder: tx-sender, name: name })
    (ok true)
  )
)

;; Update emergency resources
(define-public (update-emergency-resources
    (resource-type (string-ascii 50))
    (quantity-available uint)
    (location (string-ascii 100)))
  (begin
    (asserts! (> quantity-available u0) ERR-INVALID-INPUT)

    (map-set emergency-resources
      { resource-type: resource-type }
      {
        quantity-available: quantity-available,
        location: location,
        contact-person: tx-sender,
        last-updated: block-height
      }
    )

    (try! (ft-mint? emergency-token u25 tx-sender))

    (print { event: "resources-updated", resource-type: resource-type, quantity: quantity-available })
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-emergency-request (request-id uint))
  (map-get? emergency-requests { request-id: request-id })
)

(define-read-only (get-assistance-history (requester principal) (request-date uint))
  (map-get? assistance-history { requester: requester, request-date: request-date })
)

(define-read-only (get-volunteer-responder (responder principal))
  (map-get? volunteer-responders { responder: responder })
)

(define-read-only (get-emergency-resources (resource-type (string-ascii 50)))
  (map-get? emergency-resources { resource-type: resource-type })
)

(define-read-only (get-emergency-fund-balance)
  (var-get emergency-fund)
)

(define-read-only (get-emergency-token-balance (user principal))
  (ft-get-balance emergency-token user)
)

(define-read-only (get-total-requests)
  (var-get total-requests)
)

(define-read-only (get-total-assistance-provided)
  (var-get total-assistance-provided)
)
