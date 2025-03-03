;; CharityChain - Donation tracking and impact measurement platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-invalid-rating (err u103))
(define-constant err-invalid-period (err u104))


;; Data Variables
(define-map projects 
    { project-id: uint }
    {
        name: (string-ascii 50),
        description: (string-ascii 256),
        verified: bool,
        total-donations: uint,
        beneficiary: principal
    }
)

(define-map donations
    { donor: principal, project-id: uint }
    {
        amount: uint,
        timestamp: uint
    }
)

;; Project counter
(define-data-var project-count uint u0)

(define-data-var category-count uint u0)
(define-data-var update-count uint u0)
(define-data-var comment-count uint u0)
(define-data-var milestone-count uint u0)

;; Public functions

;; Create new charity project
(define-public (create-project (name (string-ascii 50)) (description (string-ascii 256)) (beneficiary principal))
    (let ((new-id (+ (var-get project-count) u1)))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set projects 
                    { project-id: new-id }
                    {
                        name: name,
                        description: description,
                        verified: false,
                        total-donations: u0,
                        beneficiary: beneficiary
                    }
                )
                (var-set project-count new-id)
                (ok new-id))
            err-owner-only)))

;; Verify project
(define-public (verify-project (project-id uint))
    (if (is-eq tx-sender contract-owner)
        (match (map-get? projects {project-id: project-id})
            project (begin
                (map-set projects 
                    {project-id: project-id}
                    (merge project {verified: true})
                )
                (ok true))
            err-not-found)
        err-owner-only))

;; Make donation
(define-public (donate (project-id uint) (amount uint))
    (match (map-get? projects {project-id: project-id})
        project 
        (begin
            (try! (stx-transfer? amount tx-sender (get beneficiary project)))
            (map-set donations 
                {donor: tx-sender, project-id: project-id}
                {amount: amount, timestamp: stacks-block-height}
            )
            (map-set projects
                {project-id: project-id}
                (merge project {total-donations: (+ (get total-donations project) amount)})
            )
            (ok true))
        err-not-found))

;; Read-only functions

;; Get project details
(define-read-only (get-project (project-id uint))
    (map-get? projects {project-id: project-id}))

;; Get donation details
(define-read-only (get-donation (donor principal) (project-id uint))
    (map-get? donations {donor: donor, project-id: project-id}))

;; Get total number of projects
(define-read-only (get-project-count)
    (var-get project-count))


(define-map project-categories
    { category-id: uint }
    { name: (string-ascii 20) }
)
(define-public (create-category (name (string-ascii 20)))
    (let ((new-cat-id (+ (var-get category-count) u1)))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set project-categories 
                    { category-id: new-cat-id }
                    { name: name }
                )
                (var-set category-count new-cat-id)
                (ok new-cat-id))
            err-owner-only)))



;; Add to Data Variables
(define-map project-updates
    { project-id: uint, update-id: uint }
    {
        title: (string-ascii 50),
        content: (string-ascii 500),
        timestamp: uint
    }
)

(define-public (post-project-update (project-id uint) (title (string-ascii 50)) (content (string-ascii 500)))
    (match (map-get? projects {project-id: project-id})
        project
        (if (is-eq tx-sender (get beneficiary project))
            (let ((update-id (+ (var-get update-count) u1)))
                (map-set project-updates
                    { project-id: project-id, update-id: update-id }
                    { 
                        title: title,
                        content: content,
                        timestamp: stacks-block-height
                    }
                )
                (ok true))
            err-owner-only)
        err-not-found))



(define-map donor-rewards
    { donor: principal }
    {
        total-donated: uint,
        reward-level: uint
    }
)

(define-public (update-donor-rewards (donor principal) (amount uint))
    (let ((current-rewards (default-to 
            { total-donated: u0, reward-level: u0 }
            (map-get? donor-rewards {donor: donor}))))
        (map-set donor-rewards
            {donor: donor}
            {
                total-donated: (+ (get total-donated current-rewards) amount),
                reward-level: (/ (+ (get total-donated current-rewards) amount) u1000)
            }
        )
        (ok true)))


(define-map project-comments
    { project-id: uint, comment-id: uint }
    {
        author: principal,
        content: (string-ascii 200),
        timestamp: uint
    }
)

(define-public (add-comment (project-id uint) (content (string-ascii 200)))
    (let ((comment-id (+ (var-get comment-count) u1)))
        (map-set project-comments
            { project-id: project-id, comment-id: comment-id }
            {
                author: tx-sender,
                content: content,
                timestamp: stacks-block-height
            }
        )
        (var-set comment-count comment-id)
        (ok true)))




(define-map project-ratings
    { project-id: uint, rater: principal }
    { rating: uint }
)

(define-public (rate-project (project-id uint) (rating uint))
    (if (and (>= rating u1) (<= rating u5))
        (begin
            (map-set project-ratings
                { project-id: project-id, rater: tx-sender }
                { rating: rating }
            )
            (ok true))
        (err u103)))




(define-map project-milestones
    { project-id: uint, milestone-id: uint }
    {
        title: (string-ascii 50),
        target-amount: uint,
        completed: bool
    }
)

(define-public (add-milestone (project-id uint) (title (string-ascii 50)) (target-amount uint))
    (let ((milestone-id (+ (var-get milestone-count) u1)))
        (map-set project-milestones
            { project-id: project-id, milestone-id: milestone-id }
            {
                title: title,
                target-amount: target-amount,
                completed: false
            }
        )
        (var-set milestone-count milestone-id)
        (ok true)))



(define-map recurring-donations
    { donor: principal, project-id: uint }
    {
        amount: uint,
        period: uint,
        last-donation: uint,
        active: bool
    }
)

