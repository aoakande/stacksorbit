;; StacksOrbit Core Contract - Added Finalization and Challenge Period
;; This contract manages the main functionality of the StacksOrbit L3 rollup

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-STATE (err u1001))
(define-constant ERR-ALREADY-INITIALIZED (err u1002))
(define-constant ERR-NOT-INITIALIZED (err u1003))
(define-constant ERR-INVALID-BATCH-SIZE (err u1004))
(define-constant ERR-INVALID-ROOT (err u1005))
(define-constant ERR-BATCH-NOT-FOUND (err u1006))
(define-constant ERR-CHALLENGE-PERIOD-ACTIVE (err u1008))
(define-constant ERR-SYSTEM-PAUSED (err u1010))

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var system-initialized bool false)
(define-data-var system-paused bool false)
(define-data-var challenge-period uint u10080) ;; ~7 days in blocks (assuming 10 min blocks)
(define-data-var min-bond uint u1000000000) ;; 1000 STX in microSTX
(define-data-var operators-count uint u0)
(define-data-var last-batch-id uint u0)

;; Data Maps
(define-map operators principal bool)
(define-map operator-bonds principal uint)
(define-map state-roots 
  { batch-id: uint }
  { 
    state-root: (buff 32),
    timestamp: uint,
    submitter: principal,
    tx-count: uint,
    is-finalized: bool
  }
)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-operator)
  (default-to false (map-get? operators tx-sender))
)

(define-private (check-system-active)
  (and (var-get system-initialized) (not (var-get system-paused)))
)

;; Access Control Functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

;; System Administration
(define-public (initialize)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get system-initialized)) ERR-ALREADY-INITIALIZED)
    (var-set system-initialized true)
    (ok true)
  )
)

(define-public (set-system-pause (paused bool))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set system-paused paused)
    (ok true)
  )
)

(define-public (set-challenge-period (new-period uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (check-system-active) ERR-SYSTEM-PAUSED)
    (var-set challenge-period new-period)
    (ok true)
  )
)

(define-public (set-min-bond (new-min-bond uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (check-system-active) ERR-SYSTEM-PAUSED)
    (var-set min-bond new-min-bond)
    (ok true)
  )
)

;; Operator Management
(define-public (register-operator)
  (let
    (
      (required-bond (var-get min-bond))
    )
    (asserts! (check-system-active) ERR-SYSTEM-PAUSED)
    (asserts! (is-none (map-get? operators tx-sender)) ERR-ALREADY-INITIALIZED)

    ;; Transfer bond from operator to contract
    (try! (stx-transfer? required-bond tx-sender (as-contract tx-sender)))

    ;; Register operator
    (map-set operators tx-sender true)
    (map-set operator-bonds tx-sender required-bond)
    (var-set operators-count (+ (var-get operators-count) u1))

    (ok true)
  )
)

(define-public (unregister-operator)
  (let
    (
      (bond-amount (default-to u0 (map-get? operator-bonds tx-sender)))
    )
    (asserts! (check-system-active) ERR-SYSTEM-PAUSED)
    (asserts! (is-operator) ERR-NOT-AUTHORIZED)

    ;; Return bond to operator
    (try! (as-contract (stx-transfer? bond-amount tx-sender tx-sender)))

    ;; Unregister operator
    (map-delete operators tx-sender)
    (map-delete operator-bonds tx-sender)
    (var-set operators-count (- (var-get operators-count) u1))

    (ok true)
  )
)

;; State Root Management
(define-public (submit-state-root (state-root (buff 32)) (tx-count uint))
  (let
    (
      (batch-id (+ (var-get last-batch-id) u1))
      (block-height block-height)
    )
    (asserts! (check-system-active) ERR-SYSTEM-PAUSED)
    (asserts! (is-operator) ERR-NOT-AUTHORIZED)
    (asserts! (> tx-count u0) ERR-INVALID-BATCH-SIZE)

    ;; Store the new state root
    (map-set state-roots
      { batch-id: batch-id }
      {
        state-root: state-root,
        timestamp: block-height,
        submitter: tx-sender,
        tx-count: tx-count,
        is-finalized: false
      }
    )

    ;; Update last batch ID
    (var-set last-batch-id batch-id)

    (ok batch-id)
  )
)

;; State Finalization
(define-public (finalize-state-root (batch-id uint))
  (let
    (
      (state-root-data (unwrap! (map-get? state-roots { batch-id: batch-id }) ERR-BATCH-NOT-FOUND))
      (current-height block-height)
      (submission-height (get timestamp state-root-data))
      (challenge-blocks (var-get challenge-period))
    )
    (asserts! (check-system-active) ERR-SYSTEM-PAUSED)
    (asserts! (not (get is-finalized state-root-data)) ERR-INVALID-STATE)
    (asserts! (>= (- current-height submission-height) challenge-blocks) ERR-CHALLENGE-PERIOD-ACTIVE)

    ;; Mark the state root as finalized
    (map-set state-roots
      { batch-id: batch-id }
      (merge state-root-data { is-finalized: true })
    )

    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-system-status)
  {
    initialized: (var-get system-initialized),
    paused: (var-get system-paused),
    challenge-period: (var-get challenge-period),
    min-bond: (var-get min-bond),
    last-batch-id: (var-get last-batch-id),
    operators-count: (var-get operators-count)
  }
)

(define-read-only (get-operator-status (operator principal))
  {
    is-operator: (default-to false (map-get? operators operator)),
    bond-amount: (default-to u0 (map-get? operator-bonds operator))
  }
)

(define-read-only (get-state-root (batch-id uint))
  (map-get? state-roots { batch-id: batch-id })
)

(define-read-only (is-state-root-finalized (batch-id uint))
  (match (map-get? state-roots { batch-id: batch-id })
    root-data (get is-finalized root-data)
    false
  )
)

;; Initialize contract with the contract owner
(set-contract-owner tx-sender)
