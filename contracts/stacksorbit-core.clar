;; StacksOrbit Core Contract - Added Operator Management
;; This contract manages the main functionality of the StacksOrbit L3 rollup

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-STATE (err u1001))
(define-constant ERR-ALREADY-INITIALIZED (err u1002))
(define-constant ERR-NOT-INITIALIZED (err u1003))
(define-constant ERR-SYSTEM-PAUSED (err u1010))

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var system-initialized bool false)
(define-data-var system-paused bool false)
(define-data-var min-bond uint u1000000000) ;; 1000 STX in microSTX
(define-data-var operators-count uint u0)

;; Data Maps
(define-map operators principal bool)
(define-map operator-bonds principal uint)

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

;; Read-only Functions
(define-read-only (get-system-status)
  {
    initialized: (var-get system-initialized),
    paused: (var-get system-paused),
    min-bond: (var-get min-bond),
    operators-count: (var-get operators-count)
  }
)

(define-read-only (get-operator-status (operator principal))
  {
    is-operator: (default-to false (map-get? operators operator)),
    bond-amount: (default-to u0 (map-get? operator-bonds operator))
  }
)

;; Initialize contract with the contract owner
(set-contract-owner tx-sender)
