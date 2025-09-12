;; Donor Impact Analytics & Tax Receipt System
;; Provides comprehensive donation tracking, impact measurement, and tax documentation for donors

(define-constant CONTRACT_OWNER tx-sender)
(define-constant CHARITY_CHAIN_CONTRACT 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.CharityChain)

;; Error constants (500-520 range to avoid conflicts)
(define-constant ERR_NOT_AUTHORIZED (err u500))
(define-constant ERR_DONATION_NOT_FOUND (err u501))
(define-constant ERR_INVALID_TAX_YEAR (err u502))
(define-constant ERR_RECEIPT_ALREADY_GENERATED (err u503))
(define-constant ERR_INVALID_DATE_RANGE (err u504))
(define-constant ERR_ANALYTICS_NOT_FOUND (err u505))
(define-constant ERR_INVALID_CATEGORY (err u506))
(define-constant ERR_INSUFFICIENT_DONATIONS (err u507))

;; Data variables
(define-data-var receipt-counter uint u0)
(define-data-var analytics-counter uint u0)
(define-data-var current-tax-year uint u2024)
(define-data-var blocks-per-year uint u52560) ;; Approximate blocks in a year

;; Annual donation summaries for tax purposes
(define-map donor-annual-summary
  {donor: principal, tax-year: uint}
  {
    total-donations: uint,
    total-projects-supported: uint,
    deductible-amount: uint,
    receipt-generated: bool,
    receipt-id: (optional uint),
    last-updated: uint
  }
)

;; Individual donation records with categorization
(define-map donation-records
  {donor: principal, project-id: uint, donation-id: uint}
  {
    amount: uint,
    donation-date: uint,
    tax-year: uint,
    deductible: bool,
    category: (string-ascii 30), ;; "education", "health", "environment", etc.
    receipt-included: bool,
    project-verified: bool,
    impact-tracked: bool
  }
)

;; Tax receipts with IRS-compliant information
(define-map tax-receipts
  uint ;; receipt-id
  {
    donor: principal,
    tax-year: uint,
    total-deductible: uint,
    receipt-date: uint,
    receipt-hash: (buff 32), ;; Hash of receipt data for verification
    donation-count: uint,
    organization-ein: (string-ascii 20), ;; Employer Identification Number
    receipt-status: (string-ascii 20) ;; "generated", "amended", "voided"
  }
)

;; Donor impact analytics and insights
(define-map donor-impact-analytics
  {donor: principal, analytics-period: uint} ;; period = year or quarter
  {
    period-donations: uint,
    projects-impacted: uint,
    beneficiaries-reached: uint,
    communities-served: uint,
    average-project-rating: uint,
    most-supported-category: (string-ascii 30),
    donation-frequency: uint, ;; donations per month
    impact-score: uint, ;; calculated composite score
    generated-date: uint
  }
)

;; Project impact attribution to donors
(define-map donor-project-impact
  {donor: principal, project-id: uint}
  {
    total-donated: uint,
    percentage-contribution: uint, ;; percentage of total project funding
    beneficiaries-attributed: uint, ;; proportional beneficiaries reached
    impact-value: uint, ;; calculated impact value
    first-donation: uint,
    last-donation: uint,
    donation-count: uint
  }
)

;; Category-based donation tracking
(define-map category-donations
  {donor: principal, category: (string-ascii 30), tax-year: uint}
  {
    total-amount: uint,
    donation-count: uint,
    projects-supported: uint,
    average-donation: uint,
    impact-score: uint
  }
)

;; Record donation for analytics tracking
(define-public (record-donation
  (donor principal)
  (project-id uint)
  (donation-id uint)
  (amount uint)
  (category (string-ascii 30))
  (is-deductible bool)
)
  (let (
    (current-year (var-get current-tax-year))
    (project-verified (is-some (contract-call? .CharityChain get-project project-id)))
  )
    (asserts! (or 
      (is-eq tx-sender CONTRACT_OWNER)
      (is-eq tx-sender donor)
    ) ERR_NOT_AUTHORIZED)
    (asserts! project-verified ERR_DONATION_NOT_FOUND)
    
    ;; Record individual donation
    (map-set donation-records
      {donor: donor, project-id: project-id, donation-id: donation-id}
      {
        amount: amount,
        donation-date: stacks-block-height,
        tax-year: current-year,
        deductible: is-deductible,
        category: category,
        receipt-included: false,
        project-verified: project-verified,
        impact-tracked: false
      }
    )
    
    ;; Update annual summary
    (unwrap-panic (update-annual-summary donor current-year amount is-deductible))
    
    ;; Update category tracking
    (unwrap-panic (update-category-donations donor category current-year amount))
    
    ;; Update project impact attribution
    (unwrap-panic (update-project-impact-attribution donor project-id amount))
    
    (ok true)
  )
)

;; Generate annual tax receipt
(define-public (generate-annual-tax-receipt
  (donor principal)
  (tax-year uint)
  (organization-ein (string-ascii 20))
)
  (let (
    (annual-summary (unwrap! (map-get? donor-annual-summary {donor: donor, tax-year: tax-year}) ERR_ANALYTICS_NOT_FOUND))
    (receipt-id (+ (var-get receipt-counter) u1))
    (receipt-data-hash (keccak256 (concat (concat (unwrap-panic (to-consensus-buff? donor)) 
                                                 (unwrap-panic (to-consensus-buff? tax-year)))
                                          (unwrap-panic (to-consensus-buff? (get total-donations annual-summary))))))
  )
    (asserts! (not (get receipt-generated annual-summary)) ERR_RECEIPT_ALREADY_GENERATED)
    (asserts! (> (get deductible-amount annual-summary) u0) ERR_INSUFFICIENT_DONATIONS)
    (asserts! (>= tax-year u2020) ERR_INVALID_TAX_YEAR)
    (asserts! (<= tax-year (+ (var-get current-tax-year) u1)) ERR_INVALID_TAX_YEAR)
    
    ;; Create tax receipt
    (map-set tax-receipts receipt-id {
      donor: donor,
      tax-year: tax-year,
      total-deductible: (get deductible-amount annual-summary),
      receipt-date: stacks-block-height,
      receipt-hash: receipt-data-hash,
      donation-count: (get total-projects-supported annual-summary),
      organization-ein: organization-ein,
      receipt-status: "generated"
    })
    
    ;; Update annual summary
    (map-set donor-annual-summary {donor: donor, tax-year: tax-year}
      (merge annual-summary {
        receipt-generated: true,
        receipt-id: (some receipt-id),
        last-updated: stacks-block-height
      })
    )
    
    (var-set receipt-counter receipt-id)
    (ok receipt-id)
  )
)

;; Generate comprehensive impact analytics for donor
(define-public (generate-impact-analytics
  (donor principal)
  (analytics-period uint) ;; year
)
  (let (
    (period-summary (default-to 
      {total-donations: u0, total-projects-supported: u0, deductible-amount: u0, 
       receipt-generated: false, receipt-id: none, last-updated: u0}
      (map-get? donor-annual-summary {donor: donor, tax-year: analytics-period})))
    (analytics-id (+ (var-get analytics-counter) u1))
  )
    ;; Calculate comprehensive analytics
    (let (
      (beneficiaries-reached (calculate-total-beneficiaries-reached donor analytics-period))
      (communities-served (calculate-communities-served donor analytics-period))
      (impact-score (calculate-donor-impact-score donor analytics-period))
      (donation-frequency (calculate-donation-frequency donor analytics-period))
      (top-category (get-most-supported-category donor analytics-period))
    )
      (map-set donor-impact-analytics 
        {donor: donor, analytics-period: analytics-period}
        {
          period-donations: (get total-donations period-summary),
          projects-impacted: (get total-projects-supported period-summary),
          beneficiaries-reached: beneficiaries-reached,
          communities-served: communities-served,
          average-project-rating: u0, ;; Simplified - would calculate from project ratings
          most-supported-category: top-category,
          donation-frequency: donation-frequency,
          impact-score: impact-score,
          generated-date: stacks-block-height
        }
      )
      
      (var-set analytics-counter analytics-id)
      (ok analytics-id)
    )
  )
)

;; Update project impact attribution when donation is made
(define-private (update-project-impact-attribution
  (donor principal)
  (project-id uint)
  (amount uint)
)
  (let (
    (current-attribution (default-to
      {total-donated: u0, percentage-contribution: u0, beneficiaries-attributed: u0,
       impact-value: u0, first-donation: stacks-block-height, last-donation: u0, donation-count: u0}
      (map-get? donor-project-impact {donor: donor, project-id: project-id})))
    (new-total (+ (get total-donated current-attribution) amount))
    (new-count (+ (get donation-count current-attribution) u1))
  )
    (map-set donor-project-impact {donor: donor, project-id: project-id}
      (merge current-attribution {
        total-donated: new-total,
        last-donation: stacks-block-height,
        donation-count: new-count,
        impact-value: (calculate-impact-value new-total project-id)
      })
    )
    (ok true)
  )
)

;; Update annual donation summary
(define-private (update-annual-summary
  (donor principal)
  (tax-year uint)
  (amount uint)
  (is-deductible bool)
)
  (let (
    (current-summary (default-to
      {total-donations: u0, total-projects-supported: u0, deductible-amount: u0,
       receipt-generated: false, receipt-id: none, last-updated: u0}
      (map-get? donor-annual-summary {donor: donor, tax-year: tax-year})))
  )
    (map-set donor-annual-summary {donor: donor, tax-year: tax-year}
      (merge current-summary {
        total-donations: (+ (get total-donations current-summary) amount),
        total-projects-supported: (+ (get total-projects-supported current-summary) u1),
        deductible-amount: (if is-deductible 
          (+ (get deductible-amount current-summary) amount)
          (get deductible-amount current-summary)),
        last-updated: stacks-block-height
      })
    )
    (ok true)
  )
)

;; Update category-based donation tracking
(define-private (update-category-donations
  (donor principal)
  (category (string-ascii 30))
  (tax-year uint)
  (amount uint)
)
  (let (
    (current-category (default-to
      {total-amount: u0, donation-count: u0, projects-supported: u0, 
       average-donation: u0, impact-score: u0}
      (map-get? category-donations {donor: donor, category: category, tax-year: tax-year})))
    (new-count (+ (get donation-count current-category) u1))
    (new-total (+ (get total-amount current-category) amount))
  )
    (map-set category-donations {donor: donor, category: category, tax-year: tax-year}
      (merge current-category {
        total-amount: new-total,
        donation-count: new-count,
        projects-supported: (+ (get projects-supported current-category) u1),
        average-donation: (/ new-total new-count)
      })
    )
    (ok true)
  )
)

;; Helper functions for calculations (simplified implementations)
(define-private (calculate-total-beneficiaries-reached (donor principal) (period uint))
  ;; Simplified calculation - would aggregate from project impact data
  u1000
)

(define-private (calculate-communities-served (donor principal) (period uint))
  ;; Simplified calculation - would aggregate unique communities from supported projects
  u25
)

(define-private (calculate-donor-impact-score (donor principal) (period uint))
  ;; Simplified scoring algorithm based on donation diversity, frequency, and project outcomes
  u750
)

(define-private (calculate-donation-frequency (donor principal) (period uint))
  ;; Simplified - would calculate donations per month
  u4
)

(define-private (get-most-supported-category (donor principal) (period uint))
  ;; Simplified - would find category with highest total donations
  "education"
)

(define-private (calculate-impact-value (donation-amount uint) (project-id uint))
  ;; Simplified impact calculation based on project effectiveness metrics
  (/ donation-amount u10)
)

;; Set current tax year (owner only)
(define-public (set-current-tax-year (year uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (>= year u2020) ERR_INVALID_TAX_YEAR)
    (var-set current-tax-year year)
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-annual-summary (donor principal) (tax-year uint))
  (map-get? donor-annual-summary {donor: donor, tax-year: tax-year})
)

(define-read-only (get-tax-receipt (receipt-id uint))
  (map-get? tax-receipts receipt-id)
)

(define-read-only (get-donation-record (donor principal) (project-id uint) (donation-id uint))
  (map-get? donation-records {donor: donor, project-id: project-id, donation-id: donation-id})
)

(define-read-only (get-impact-analytics (donor principal) (period uint))
  (map-get? donor-impact-analytics {donor: donor, analytics-period: period})
)

(define-read-only (get-project-impact-attribution (donor principal) (project-id uint))
  (map-get? donor-project-impact {donor: donor, project-id: project-id})
)

(define-read-only (get-category-donations (donor principal) (category (string-ascii 30)) (tax-year uint))
  (map-get? category-donations {donor: donor, category: category, tax-year: tax-year})
)

(define-read-only (get-current-tax-year)
  (var-get current-tax-year)
)

(define-read-only (verify-receipt-authenticity (receipt-id uint) (provided-hash (buff 32)))
  (match (map-get? tax-receipts receipt-id)
    receipt (is-eq (get receipt-hash receipt) provided-hash)
    false
  )
)
