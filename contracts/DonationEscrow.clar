(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-insufficient-funds (err u202))
(define-constant err-milestone-not-ready (err u203))
(define-constant err-already-approved (err u204))
(define-constant err-unauthorized (err u205))

(define-data-var escrow-count uint u0)

(define-map escrow-accounts
    { escrow-id: uint }
    {
        project-id: uint,
        total-amount: uint,
        released-amount: uint,
        donor-count: uint,
        active: bool
    }
)

(define-map escrow-donations
    { escrow-id: uint, donor: principal }
    {
        amount: uint,
        timestamp: uint
    }
)

(define-map milestone-approvals
    { escrow-id: uint, milestone-id: uint }
    {
        required-amount: uint,
        approved: bool,
        approval-date: (optional uint),
        approver: (optional principal)
    }
)

(define-public (create-escrow-account (project-id uint))
    (let ((escrow-id (+ (var-get escrow-count) u1)))
        (map-set escrow-accounts
            { escrow-id: escrow-id }
            {
                project-id: project-id,
                total-amount: u0,
                released-amount: u0,
                donor-count: u0,
                active: true
            }
        )
        (var-set escrow-count escrow-id)
        (ok escrow-id)))

(define-public (donate-to-escrow (escrow-id uint) (amount uint))
    (match (map-get? escrow-accounts { escrow-id: escrow-id })
        escrow-account
        (if (get active escrow-account)
            (begin
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                (map-set escrow-donations
                    { escrow-id: escrow-id, donor: tx-sender }
                    {
                        amount: amount,
                        timestamp: stacks-block-height
                    }
                )
                (map-set escrow-accounts
                    { escrow-id: escrow-id }
                    (merge escrow-account {
                        total-amount: (+ (get total-amount escrow-account) amount),
                        donor-count: (+ (get donor-count escrow-account) u1)
                    })
                )
                (ok true))
            err-not-found)
        err-not-found))

(define-public (set-milestone-requirement (escrow-id uint) (milestone-id uint) (required-amount uint))
    (if (is-eq tx-sender contract-owner)
        (begin
            (map-set milestone-approvals
                { escrow-id: escrow-id, milestone-id: milestone-id }
                {
                    required-amount: required-amount,
                    approved: false,
                    approval-date: none,
                    approver: none
                }
            )
            (ok true))
        err-owner-only))

(define-public (approve-milestone-release (escrow-id uint) (milestone-id uint))
    (if (is-eq tx-sender contract-owner)
        (match (map-get? milestone-approvals { escrow-id: escrow-id, milestone-id: milestone-id })
            milestone
            (if (not (get approved milestone))
                (begin
                    (map-set milestone-approvals
                        { escrow-id: escrow-id, milestone-id: milestone-id }
                        (merge milestone {
                            approved: true,
                            approval-date: (some stacks-block-height),
                            approver: (some tx-sender)
                        })
                    )
                    (ok true))
                err-already-approved)
            err-not-found)
        err-owner-only))

(define-public (release-escrow-funds (escrow-id uint) (milestone-id uint) (recipient principal))
    (match (map-get? escrow-accounts { escrow-id: escrow-id })
        escrow-account
        (match (map-get? milestone-approvals { escrow-id: escrow-id, milestone-id: milestone-id })
            milestone
            (if (get approved milestone)
                (let ((release-amount (get required-amount milestone)))
                    (if (<= release-amount (- (get total-amount escrow-account) (get released-amount escrow-account)))
                        (begin
                            (try! (as-contract (stx-transfer? release-amount tx-sender recipient)))
                            (map-set escrow-accounts
                                { escrow-id: escrow-id }
                                (merge escrow-account {
                                    released-amount: (+ (get released-amount escrow-account) release-amount)
                                })
                            )
                            (ok release-amount))
                        err-insufficient-funds))
                err-milestone-not-ready)
            err-not-found)
        err-not-found))

(define-public (refund-donor (escrow-id uint) (donor principal))
    (if (is-eq tx-sender contract-owner)
        (match (map-get? escrow-donations { escrow-id: escrow-id, donor: donor })
            donation
            (begin
                (try! (as-contract (stx-transfer? (get amount donation) tx-sender donor)))
                (map-delete escrow-donations { escrow-id: escrow-id, donor: donor })
                (ok true))
            err-not-found)
        err-owner-only))

(define-read-only (get-escrow-account (escrow-id uint))
    (map-get? escrow-accounts { escrow-id: escrow-id }))

(define-read-only (get-escrow-donation (escrow-id uint) (donor principal))
    (map-get? escrow-donations { escrow-id: escrow-id, donor: donor }))

(define-read-only (get-milestone-approval (escrow-id uint) (milestone-id uint))
    (map-get? milestone-approvals { escrow-id: escrow-id, milestone-id: milestone-id }))

(define-read-only (get-available-funds (escrow-id uint))
    (match (map-get? escrow-accounts { escrow-id: escrow-id })
        escrow-account
        (some (- (get total-amount escrow-account) (get released-amount escrow-account)))
        none))

(define-read-only (get-escrow-count)
    (var-get escrow-count))