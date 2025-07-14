;; Garden Production Contract
;; Coordinates community food growing initiatives

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-PLOT-NOT-FOUND (err u302))
(define-constant ERR-PLOT-OCCUPIED (err u303))

;; Data Variables
(define-data-var next-plot-id uint u1)
(define-data-var next-harvest-id uint u1)
(define-data-var total-garden-plots uint u0)

;; Data Maps
(define-map garden-plots
  { plot-id: uint }
  {
    location: (string-ascii 100),
    size-sqft: uint,
    assigned-to: (optional principal),
    crop-type: (string-ascii 50),
    planting-date: uint,
    expected-harvest: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map harvest-records
  { harvest-id: uint }
  {
    plot-id: uint,
    harvester: principal,
    crop-type: (string-ascii 50),
    quantity: uint,
    harvest-date: uint,
    quality-score: uint
  }
)

(define-map gardener-profiles
  { gardener: principal }
  {
    plots-managed: uint,
    total-harvests: uint,
    experience-level: uint,
    reputation: uint
  }
)

(define-map seed-inventory
  { seed-type: (string-ascii 50) }
  {
    quantity: uint,
    supplier: principal,
    planting-season: (string-ascii 20),
    germination-rate: uint
  }
)

;; Garden token for rewards
(define-fungible-token garden-token)

;; Public Functions

;; Create new garden plot
(define-public (create-garden-plot (location (string-ascii 100)) (size-sqft uint))
  (let
    (
      (plot-id (var-get next-plot-id))
    )
    (asserts! (> size-sqft u0) ERR-INVALID-INPUT)

    (map-set garden-plots
      { plot-id: plot-id }
      {
        location: location,
        size-sqft: size-sqft,
        assigned-to: none,
        crop-type: "",
        planting-date: u0,
        expected-harvest: u0,
        status: "available",
        created-at: block-height
      }
    )

    (var-set next-plot-id (+ plot-id u1))
    (var-set total-garden-plots (+ (var-get total-garden-plots) u1))

    (print { event: "plot-created", plot-id: plot-id, location: location })
    (ok plot-id)
  )
)

;; Assign plot to gardener
(define-public (assign-plot (plot-id uint) (crop-type (string-ascii 50)) (expected-harvest uint))
  (let
    (
      (plot-data (unwrap! (map-get? garden-plots { plot-id: plot-id }) ERR-PLOT-NOT-FOUND))
      (gardener-profile (default-to { plots-managed: u0, total-harvests: u0, experience-level: u1, reputation: u0 }
                                   (map-get? gardener-profiles { gardener: tx-sender })))
    )
    (asserts! (is-eq (get status plot-data) "available") ERR-PLOT-OCCUPIED)
    (asserts! (> expected-harvest block-height) ERR-INVALID-INPUT)

    (map-set garden-plots
      { plot-id: plot-id }
      (merge plot-data {
        assigned-to: (some tx-sender),
        crop-type: crop-type,
        planting-date: block-height,
        expected-harvest: expected-harvest,
        status: "planted"
      })
    )

    (map-set gardener-profiles
      { gardener: tx-sender }
      (merge gardener-profile {
        plots-managed: (+ (get plots-managed gardener-profile) u1)
      })
    )

    (try! (ft-mint? garden-token u30 tx-sender))

    (print { event: "plot-assigned", plot-id: plot-id, gardener: tx-sender, crop: crop-type })
    (ok true)
  )
)

;; Record harvest
(define-public (record-harvest (plot-id uint) (quantity uint) (quality-score uint))
  (let
    (
      (harvest-id (var-get next-harvest-id))
      (plot-data (unwrap! (map-get? garden-plots { plot-id: plot-id }) ERR-PLOT-NOT-FOUND))
      (gardener-profile (default-to { plots-managed: u0, total-harvests: u0, experience-level: u1, reputation: u0 }
                                   (map-get? gardener-profiles { gardener: tx-sender })))
    )
    (asserts! (is-eq (some tx-sender) (get assigned-to plot-data)) ERR-NOT-AUTHORIZED)
    (asserts! (and (> quantity u0) (<= quality-score u100)) ERR-INVALID-INPUT)

    (map-set harvest-records
      { harvest-id: harvest-id }
      {
        plot-id: plot-id,
        harvester: tx-sender,
        crop-type: (get crop-type plot-data),
        quantity: quantity,
        harvest-date: block-height,
        quality-score: quality-score
      }
    )

    (map-set garden-plots
      { plot-id: plot-id }
      (merge plot-data { status: "harvested" })
    )

    (map-set gardener-profiles
      { gardener: tx-sender }
      (merge gardener-profile {
        total-harvests: (+ (get total-harvests gardener-profile) u1),
        reputation: (+ (get reputation gardener-profile) quality-score)
      })
    )

    (var-set next-harvest-id (+ harvest-id u1))
    (try! (ft-mint? garden-token (* quantity quality-score) tx-sender))

    (print { event: "harvest-recorded", harvest-id: harvest-id, plot-id: plot-id, quantity: quantity })
    (ok harvest-id)
  )
)

;; Add seeds to inventory
(define-public (add-seeds (seed-type (string-ascii 50)) (quantity uint) (planting-season (string-ascii 20)) (germination-rate uint))
  (let
    (
      (current-seeds (default-to { quantity: u0, supplier: tx-sender, planting-season: planting-season, germination-rate: germination-rate }
                                 (map-get? seed-inventory { seed-type: seed-type })))
    )
    (asserts! (and (> quantity u0) (<= germination-rate u100)) ERR-INVALID-INPUT)

    (map-set seed-inventory
      { seed-type: seed-type }
      {
        quantity: (+ (get quantity current-seeds) quantity),
        supplier: tx-sender,
        planting-season: planting-season,
        germination-rate: germination-rate
      }
    )

    (try! (ft-mint? garden-token (* quantity u5) tx-sender))

    (print { event: "seeds-added", seed-type: seed-type, quantity: quantity })
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-garden-plot (plot-id uint))
  (map-get? garden-plots { plot-id: plot-id })
)

(define-read-only (get-harvest-record (harvest-id uint))
  (map-get? harvest-records { harvest-id: harvest-id })
)

(define-read-only (get-gardener-profile (gardener principal))
  (map-get? gardener-profiles { gardener: gardener })
)

(define-read-only (get-seed-inventory (seed-type (string-ascii 50)))
  (map-get? seed-inventory { seed-type: seed-type })
)

(define-read-only (get-garden-token-balance (user principal))
  (ft-get-balance garden-token user)
)

(define-read-only (get-total-plots)
  (var-get total-garden-plots)
)
