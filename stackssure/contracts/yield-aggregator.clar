;; Stacks DeFi Yield Aggregator & Insurance Pool
;; Combines yield farming optimization with decentralized insurance

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_POOL_NOT_FOUND (err u103))
(define-constant ERR_CLAIM_NOT_FOUND (err u104))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u105))
(define-constant ERR_INSUFFICIENT_COVERAGE (err u106))
(define-constant ERR_PROTOCOL_NOT_SUPPORTED (err u107))
(define-constant ERR_BATCH_LIMIT_EXCEEDED (err u108))
(define-constant ERR_CLAIM_EXPIRED (err u109))
(define-constant ERR_INVALID_PROTOCOL (err u110))

;; Data Variables
(define-data-var total-value-locked uint u0)
(define-data-var insurance-pool-balance uint u0)
(define-data-var protocol-fee-rate uint u25) ;; 0.25% in basis points
(define-data-var claim-counter uint u0)
(define-data-var batch-counter uint u0)
(define-data-var max-batch-size uint u50)
(define-data-var claim-period uint u144) ;; ~24 hours in blocks

;; Data Maps
(define-map user-deposits principal uint)
(define-map user-insurance-stakes principal uint)
(define-map user-yield-shares principal uint)
(define-map protocol-allocations 
  {protocol: (string-ascii 32)} 
  {allocation-percentage: uint, last-compound: uint, total-deposited: uint, apy: uint})
(define-map insurance-claims 
  uint 
  {
    claimant: principal,
    amount: uint,
    claim-type: (string-ascii 32),
    protocol: (string-ascii 32),
    timestamp: uint,
    status: (string-ascii 16),
    evidence-hash: (buff 32)
  })
(define-map user-claim-history principal (list 10 uint))
(define-map batch-transactions 
  uint 
  {
    protocols: (list 10 (string-ascii 32)),
    amounts: (list 10 uint),
    timestamp: uint,
    status: (string-ascii 16),
    gas-saved: uint
  })
(define-map protocol-risk-scores (string-ascii 32) uint)

;; Read-only functions
(define-read-only (get-total-value-locked)
  (var-get total-value-locked))

(define-read-only (get-insurance-pool-balance)
  (var-get insurance-pool-balance))

(define-read-only (get-user-deposit (user principal))
  (default-to u0 (map-get? user-deposits user)))

(define-read-only (get-user-insurance-stake (user principal))
  (default-to u0 (map-get? user-insurance-stakes user)))

(define-read-only (get-user-yield-shares (user principal))
  (default-to u0 (map-get? user-yield-shares user)))

(define-read-only (get-protocol-allocation (protocol (string-ascii 32)))
  (map-get? protocol-allocations {protocol: protocol}))

(define-read-only (get-insurance-claim (claim-id uint))
  (map-get? insurance-claims claim-id))

(define-read-only (get-user-estimated-yield (user principal))
  (let ((user-shares (get-user-yield-shares user))
        (total-shares (var-get total-value-locked)))
    (if (> total-shares u0)
        (/ (* user-shares (calculate-total-apy)) u10000)
        u0)))

(define-read-only (calculate-total-apy)
  (fold calculate-weighted-apy (list 
    "stackswap" "arkadiko" "alex" "bitflow" "velar" 
    "zest" "lydian" "citycoins" "megapont" "wrapit") u0))

(define-read-only (get-protocol-risk-score (protocol (string-ascii 32)))
  (default-to u500 (map-get? protocol-risk-scores protocol))) ;; Default 50% risk score

(define-read-only (get-optimal-allocation)
  (let ((protocols (list "stackswap" "arkadiko" "alex" "bitflow" "velar")))
    (map get-protocol-metrics protocols)))

;; Private functions
(define-private (calculate-weighted-apy (protocol (string-ascii 32)) (acc uint))
  (match (get-protocol-allocation protocol)
    allocation (+ acc (/ (* (get allocation-percentage allocation) (get apy allocation)) u100))
    acc))

(define-private (get-protocol-metrics (protocol (string-ascii 32)))
  {
    protocol: protocol,
    apy: (default-to u0 (get apy (get-protocol-allocation protocol))),
    risk-score: (get-protocol-risk-score protocol),
    allocation: (default-to u0 (get allocation-percentage (get-protocol-allocation protocol)))
  })

(define-private (validate-protocol (protocol (string-ascii 32)))
  (or (is-eq protocol "stackswap")
      (or (is-eq protocol "arkadiko")
          (or (is-eq protocol "alex")
              (or (is-eq protocol "bitflow")
                  (or (is-eq protocol "velar")
                      (or (is-eq protocol "zest")
                          (or (is-eq protocol "lydian")
                              (or (is-eq protocol "citycoins")
                                  (or (is-eq protocol "megapont")
                                      (is-eq protocol "wrapit")))))))))))

(define-private (calculate-insurance-premium (amount uint) (protocol (string-ascii 32)))
  (let ((risk-score (get-protocol-risk-score protocol)))
    (/ (* amount risk-score) u10000)))

(define-private (update-protocol-allocation (protocol (string-ascii 32)) (new-allocation uint))
  (begin
    (asserts! (validate-protocol protocol) ERR_INVALID_PROTOCOL)
    (match (get-protocol-allocation protocol)
      current-data (map-set protocol-allocations 
        {protocol: protocol}
        (merge current-data {allocation-percentage: new-allocation}))
      (map-set protocol-allocations 
        {protocol: protocol}
        {allocation-percentage: new-allocation, last-compound: block-height, total-deposited: u0, apy: u0}))
    (ok true)))

;; Public functions

;; Yield Farming Functions
(define-public (deposit-for-yield (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((current-deposit (get-user-deposit tx-sender))
          (current-shares (get-user-yield-shares tx-sender))
          (new-shares (+ current-shares amount)))
      (map-set user-deposits tx-sender (+ current-deposit amount))
      (map-set user-yield-shares tx-sender new-shares)
      (var-set total-value-locked (+ (var-get total-value-locked) amount))
      (try! (auto-rebalance-protocols))
      (ok new-shares))))

(define-public (withdraw-yield (amount uint))
  (let ((user-deposit (get-user-deposit tx-sender))
        (user-shares (get-user-yield-shares tx-sender)))
    (asserts! (>= user-shares amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set user-deposits tx-sender (- user-deposit amount))
    (map-set user-yield-shares tx-sender (- user-shares amount))
    (var-set total-value-locked (- (var-get total-value-locked) amount))
    (ok amount)))

(define-public (compound-yields (protocols (list 10 (string-ascii 32))))
  (begin
    (asserts! (<= (len protocols) (var-get max-batch-size)) ERR_BATCH_LIMIT_EXCEEDED)
    (let ((batch-id (+ (var-get batch-counter) u1))
          (gas-estimate (calculate-gas-savings protocols)))
      (var-set batch-counter batch-id)
      (map-set batch-transactions batch-id
        {
          protocols: protocols,
          amounts: (map get-protocol-amount protocols),
          timestamp: block-height,
          status: "processing",
          gas-saved: gas-estimate
        })
      (try! (process-compound-batch protocols))
      (map-set batch-transactions batch-id
        (merge (unwrap-panic (map-get? batch-transactions batch-id)) {status: "completed"}))
      (ok batch-id))))

(define-public (auto-rebalance-protocols)
  (let ((total-balance (var-get total-value-locked)))
    (if (> total-balance u0)
        (begin
          ;; Rebalance based on APY and risk scores
          (try! (update-protocol-allocation "stackswap" u20))
          (try! (update-protocol-allocation "arkadiko" u15))
          (try! (update-protocol-allocation "alex" u25))
          (try! (update-protocol-allocation "bitflow" u20))
          (try! (update-protocol-allocation "velar" u20))
          (ok true))
        (ok false))))

;; Insurance Functions
(define-public (stake-for-insurance (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((current-stake (get-user-insurance-stake tx-sender)))
      (map-set user-insurance-stakes tx-sender (+ current-stake amount))
      (var-set insurance-pool-balance (+ (var-get insurance-pool-balance) amount))
      (ok (+ current-stake amount)))))

(define-public (unstake-insurance (amount uint))
  (let ((user-stake (get-user-insurance-stake tx-sender)))
    (asserts! (>= user-stake amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set user-insurance-stakes tx-sender (- user-stake amount))
    (var-set insurance-pool-balance (- (var-get insurance-pool-balance) amount))
    (ok amount)))

(define-public (file-insurance-claim (amount uint) (claim-type (string-ascii 32)) (protocol (string-ascii 32)) (evidence-hash (buff 32)))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (validate-protocol protocol) ERR_INVALID_PROTOCOL)
    (asserts! (<= amount (var-get insurance-pool-balance)) ERR_INSUFFICIENT_COVERAGE)
    (let ((claim-id (+ (var-get claim-counter) u1))
          (premium (calculate-insurance-premium amount protocol)))
      (var-set claim-counter claim-id)
      (map-set insurance-claims claim-id
        {
          claimant: tx-sender,
          amount: amount,
          claim-type: claim-type,
          protocol: protocol,
          timestamp: block-height,
          status: "pending",
          evidence-hash: evidence-hash
        })
      ;; Update user claim history
      (let ((current-history (default-to (list) (map-get? user-claim-history tx-sender))))
        (map-set user-claim-history tx-sender (unwrap-panic (as-max-len? (append current-history claim-id) u10))))
      (ok claim-id))))

(define-public (process-insurance-claim (claim-id uint) (approved bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (match (get-insurance-claim claim-id)
      claim-data
      (begin
        (asserts! (is-eq (get status claim-data) "pending") ERR_CLAIM_ALREADY_PROCESSED)
        (asserts! (< (- block-height (get timestamp claim-data)) (var-get claim-period)) ERR_CLAIM_EXPIRED)
        (if approved
            (begin
              (try! (as-contract (stx-transfer? (get amount claim-data) tx-sender (get claimant claim-data))))
              (var-set insurance-pool-balance (- (var-get insurance-pool-balance) (get amount claim-data)))
              (map-set insurance-claims claim-id (merge claim-data {status: "approved"}))
              (ok "claim-approved"))
            (begin
              (map-set insurance-claims claim-id (merge claim-data {status: "rejected"}))
              (ok "claim-rejected"))))
      ERR_CLAIM_NOT_FOUND)))

;; Utility Functions
(define-public (update-protocol-apy (protocol (string-ascii 32)) (new-apy uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (validate-protocol protocol) ERR_INVALID_PROTOCOL)
    (match (get-protocol-allocation protocol)
      current-data (begin
        (map-set protocol-allocations {protocol: protocol} 
          (merge current-data {apy: new-apy}))
        (ok true))
      (begin
        (map-set protocol-allocations {protocol: protocol}
          {allocation-percentage: u0, last-compound: block-height, total-deposited: u0, apy: new-apy})
        (ok true)))))

(define-public (update-protocol-risk-score (protocol (string-ascii 32)) (risk-score uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (validate-protocol protocol) ERR_INVALID_PROTOCOL)
    (asserts! (<= risk-score u1000) ERR_INVALID_AMOUNT) ;; Max 100% risk
    (map-set protocol-risk-scores protocol risk-score)
    (ok true)))

(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Emergency pause functionality would be implemented here
    (ok true)))

;; Helper functions for batch processing
(define-private (get-protocol-amount (protocol (string-ascii 32)))
  (match (get-protocol-allocation protocol)
    allocation (get total-deposited allocation)
    u0))

(define-private (calculate-gas-savings (protocols (list 10 (string-ascii 32))))
  ;; Simplified gas calculation - in practice this would be more complex
  (* (len protocols) u1000))

(define-private (process-compound-batch (protocols (list 10 (string-ascii 32))))
  (begin
    (asserts! (> (len protocols) u0) ERR_INVALID_AMOUNT)
    ;; This would interact with external protocols to compound yields
    ;; For this example, we'll simulate the process
    (ok (fold process-single-compound protocols u0))))

(define-private (process-single-compound (protocol (string-ascii 32)) (acc uint))
  (match (get-protocol-allocation protocol)
    allocation (begin
      (map-set protocol-allocations {protocol: protocol}
        (merge allocation {last-compound: block-height}))
      (+ acc u1))
    acc))

;; Initialize default protocol risk scores
(map-set protocol-risk-scores "stackswap" u300)  ;; 30% risk
(map-set protocol-risk-scores "arkadiko" u250)   ;; 25% risk
(map-set protocol-risk-scores "alex" u200)       ;; 20% risk
(map-set protocol-risk-scores "bitflow" u350)    ;; 35% risk
(map-set protocol-risk-scores "velar" u300)      ;; 30% risk
(map-set protocol-risk-scores "zest" u400)       ;; 40% risk
(map-set protocol-risk-scores "lydian" u450)     ;; 45% risk
(map-set protocol-risk-scores "citycoins" u500)  ;; 50% risk
(map-set protocol-risk-scores "megapont" u600)   ;; 60% risk
(map-set protocol-risk-scores "wrapit" u350)     ;; 35% risk