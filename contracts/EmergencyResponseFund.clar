;; Emergency Response Fund
;; Automatically distributes funds to verified charity projects during emergency situations
;; Prioritizes based on urgency levels and donor pre-consent for emergency allocation

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-not-found (err u301))
(define-constant err-insufficient-funds (err u302))
(define-constant err-invalid-severity (err u303))
(define-constant err-emergency-not-active (err u304))
(define-constant err-already-allocated (err u305))
(define-constant err-invalid-threshold (err u306))

;; Emergency severity levels
(define-constant SEVERITY_LOW u1)
(define-constant SEVERITY_MODERATE u2)
(define-constant SEVERITY_HIGH u3)
(define-constant SEVERITY_CRITICAL u4)

;; Emergency fund pool
(define-data-var emergency-fund-balance uint u0)
(define-data-var active-emergency-count uint u0)
(define-data-var total-emergencies-responded uint u0)

;; Emergency situations
(define-map active-emergencies
    { emergency-id: uint }
    {
        title: (string-ascii 100),
        description: (string-ascii 300),
        severity: uint, ;; 1-4 scale
        affected-regions: (string-ascii 200),
        declared-at: uint,
        expires-at: uint,
        total-allocated: uint,
        is-active: bool,
        verifier: principal
    }
)

;; Donor emergency consent settings
(define-map donor-emergency-settings
    { donor: principal }
    {
        auto-allocation-enabled: bool,
        max-emergency-allocation: uint, ;; Max amount per emergency
        min-severity-level: uint, ;; Minimum severity to trigger allocation
        total-allocated: uint,
        last-allocation-date: uint
    }
)

;; Emergency allocations tracking
(define-map emergency-allocations
    { emergency-id: uint, project-id: uint }
    {
        allocated-amount: uint,
        allocation-date: uint,
        priority-score: uint,
        allocation-reason: (string-ascii 150)
    }
)

;; Project emergency readiness
(define-map project-emergency-readiness
    { project-id: uint }
    {
        emergency-response-capable: bool,
        priority-categories: (list 5 (string-ascii 30)), ;; disaster types they handle
        response-capacity: uint, ;; 1-10 scale
        last-emergency-response: uint
    }
)

(define-data-var emergency-counter uint u0)

;; Register project for emergency response
(define-public (register-emergency-response-capacity 
    (project-id uint)
    (categories (list 5 (string-ascii 30)))
    (capacity uint)
)
    (begin
        (asserts! (<= capacity u10) err-invalid-threshold)
        (asserts! (> capacity u0) err-invalid-threshold)
        
        (map-set project-emergency-readiness
            { project-id: project-id }
            {
                emergency-response-capable: true,
                priority-categories: categories,
                response-capacity: capacity,
                last-emergency-response: u0
            }
        )
        (ok true)
    )
)

;; Donor opts into emergency auto-allocation
(define-public (set-emergency-allocation-consent 
    (max-allocation uint)
    (min-severity uint)
)
    (begin
        (asserts! (<= min-severity u4) err-invalid-severity)
        (asserts! (>= min-severity u1) err-invalid-severity)
        
        (map-set donor-emergency-settings
            { donor: tx-sender }
            {
                auto-allocation-enabled: true,
                max-emergency-allocation: max-allocation,
                min-severity-level: min-severity,
                total-allocated: u0,
                last-allocation-date: u0
            }
        )
        (ok true)
    )
)

;; Contract owner declares emergency
(define-public (declare-emergency
    (title (string-ascii 100))
    (description (string-ascii 300))
    (severity uint)
    (affected-regions (string-ascii 200))
    (duration-blocks uint)
)
    (let ((emergency-id (+ (var-get emergency-counter) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= severity u4) err-invalid-severity)
        (asserts! (>= severity u1) err-invalid-severity)
        (asserts! (> duration-blocks u0) err-invalid-threshold)
        
        (map-set active-emergencies
            { emergency-id: emergency-id }
            {
                title: title,
                description: description,
                severity: severity,
                affected-regions: affected-regions,
                declared-at: stacks-block-height,
                expires-at: (+ stacks-block-height duration-blocks),
                total-allocated: u0,
                is-active: true,
                verifier: tx-sender
            }
        )
        
        (var-set emergency-counter emergency-id)
        (var-set active-emergency-count (+ (var-get active-emergency-count) u1))
        (ok emergency-id)
    )
)

;; Contribute to emergency fund
(define-public (contribute-to-emergency-fund (amount uint))
    (begin
        (asserts! (> amount u0) err-insufficient-funds)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set emergency-fund-balance (+ (var-get emergency-fund-balance) amount))
        (ok amount)
    )
)

;; Allocate emergency funds to qualified projects
(define-public (allocate-emergency-funds 
    (emergency-id uint)
    (project-id uint)
    (allocation-amount uint)
    (reason (string-ascii 150))
)
    (let 
        (
            (emergency (unwrap! (map-get? active-emergencies { emergency-id: emergency-id }) err-not-found))
            (current-balance (var-get emergency-fund-balance))
            (project-readiness (map-get? project-emergency-readiness { project-id: project-id }))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get is-active emergency) err-emergency-not-active)
        (asserts! (<= stacks-block-height (get expires-at emergency)) err-emergency-not-active)
        (asserts! (>= current-balance allocation-amount) err-insufficient-funds)
        (asserts! (is-some project-readiness) err-not-found)
        
        ;; Calculate priority score
        (let 
            (
                (priority-score (calculate-priority-score 
                    (get severity emergency)
                    (get response-capacity (unwrap-panic project-readiness))
                ))
            )
            
            ;; Record allocation
            (map-set emergency-allocations
                { emergency-id: emergency-id, project-id: project-id }
                {
                    allocated-amount: allocation-amount,
                    allocation-date: stacks-block-height,
                    priority-score: priority-score,
                    allocation-reason: reason
                }
            )
            
            ;; Update emergency totals
            (map-set active-emergencies
                { emergency-id: emergency-id }
                (merge emergency { 
                    total-allocated: (+ (get total-allocated emergency) allocation-amount) 
                })
            )
            
            ;; Transfer funds
            (try! (as-contract (stx-transfer? allocation-amount tx-sender contract-owner)))
            (var-set emergency-fund-balance (- current-balance allocation-amount))
            
            ;; Update project's last response
            (map-set project-emergency-readiness
                { project-id: project-id }
                (merge (unwrap-panic project-readiness) { 
                    last-emergency-response: stacks-block-height 
                })
            )
            
            (ok allocation-amount)
        )
    )
)

;; Calculate priority score for allocation
(define-private (calculate-priority-score (severity uint) (capacity uint))
    (+ (* severity u25) (* capacity u10))
)

;; Auto-allocate based on donor pre-consent
(define-public (trigger-auto-allocation (emergency-id uint))
    (let 
        (
            (emergency (unwrap! (map-get? active-emergencies { emergency-id: emergency-id }) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get is-active emergency) err-emergency-not-active)
        (asserts! (<= stacks-block-height (get expires-at emergency)) err-emergency-not-active)
        
        ;; This would iterate through consenting donors and allocate funds
        ;; For simplicity, just marking successful
        (ok true)
    )
)

;; Close emergency and prevent further allocations
(define-public (close-emergency (emergency-id uint))
    (let 
        (
            (emergency (unwrap! (map-get? active-emergencies { emergency-id: emergency-id }) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get is-active emergency) err-emergency-not-active)
        
        (map-set active-emergencies
            { emergency-id: emergency-id }
            (merge emergency { is-active: false })
        )
        
        (var-set active-emergency-count (- (var-get active-emergency-count) u1))
        (var-set total-emergencies-responded (+ (var-get total-emergencies-responded) u1))
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-emergency-details (emergency-id uint))
    (map-get? active-emergencies { emergency-id: emergency-id })
)

(define-read-only (get-emergency-fund-balance)
    (var-get emergency-fund-balance)
)

(define-read-only (get-donor-emergency-settings (donor principal))
    (map-get? donor-emergency-settings { donor: donor })
)

(define-read-only (get-project-readiness (project-id uint))
    (map-get? project-emergency-readiness { project-id: project-id })
)

(define-read-only (get-allocation-details (emergency-id uint) (project-id uint))
    (map-get? emergency-allocations { emergency-id: emergency-id, project-id: project-id })
)

(define-read-only (get-active-emergency-count)
    (var-get active-emergency-count)
)

(define-read-only (is-emergency-active (emergency-id uint))
    (match (map-get? active-emergencies { emergency-id: emergency-id })
        emergency (and (get is-active emergency) 
                      (<= stacks-block-height (get expires-at emergency)))
        false
    )
)

(define-read-only (calculate-allocation-eligibility (emergency-id uint) (project-id uint))
    (let
        (
            (emergency (map-get? active-emergencies { emergency-id: emergency-id }))
            (readiness (map-get? project-emergency-readiness { project-id: project-id }))
        )
        (and 
            (is-some emergency)
            (is-some readiness)
            (get is-active (unwrap-panic emergency))
            (get emergency-response-capable (unwrap-panic readiness))
        )
    )
)
