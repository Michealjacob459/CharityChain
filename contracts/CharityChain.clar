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



;; Define map for tracking impact metrics
(define-map impact-metrics
    { project-id: uint }
    {
        beneficiaries-reached: uint,
        communities-served: uint,
        last-updated: uint
    }
)

(define-public (update-impact-metrics 
    (project-id uint) 
    (beneficiaries uint) 
    (communities uint))
    (match (map-get? projects {project-id: project-id})
        project
        (if (is-eq tx-sender (get beneficiary project))
            (begin
                (map-set impact-metrics
                    {project-id: project-id}
                    {
                        beneficiaries-reached: beneficiaries,
                        communities-served: communities,
                        last-updated: stacks-block-height
                    }
                )
                (ok true))
            err-owner-only)
        err-not-found))

(define-read-only (get-impact-metrics (project-id uint))
    (map-get? impact-metrics {project-id: project-id}))


;; Define variables and maps for tags
(define-data-var tag-count uint u0)

(define-map project-tags
    { project-id: uint, tag-id: uint }
    { tag-name: (string-ascii 20) }
)

(define-public (add-project-tag (project-id uint) (tag-name (string-ascii 20)))
    (match (map-get? projects {project-id: project-id})
        project
        (let ((new-tag-id (+ (var-get tag-count) u1)))
            (begin
                (map-set project-tags
                    {project-id: project-id, tag-id: new-tag-id}
                    {tag-name: tag-name}
                )
                (var-set tag-count new-tag-id)
                (ok true)))
        err-not-found))

(define-read-only (get-project-tags (project-id uint) (tag-id uint))
    (map-get? project-tags {project-id: project-id, tag-id: tag-id}))



;; Define variables and maps for messages
(define-data-var message-count uint u0)

(define-map donor-messages
    { message-id: uint }
    {
        sender: principal,
        recipient: principal,
        project-id: uint,
        content: (string-ascii 500),
        timestamp: uint
    }
)

(define-public (send-message 
    (recipient principal) 
    (project-id uint) 
    (content (string-ascii 500)))
    (let ((message-id (+ (var-get message-count) u1)))
        (begin
            (map-set donor-messages
                {message-id: message-id}
                {
                    sender: tx-sender,
                    recipient: recipient,
                    project-id: project-id,
                    content: content,
                    timestamp: stacks-block-height
                }
            )
            (var-set message-count message-id)
            (ok true))))

(define-read-only (get-message (message-id uint))
    (map-get? donor-messages {message-id: message-id}))


;; Define variables and maps for progress tracking
(define-data-var progress-update-count uint u0)

(define-map project-progress
    { project-id: uint, update-id: uint }
    {
        percentage-complete: uint,
        funds-used: uint,
        update-notes: (string-ascii 500),
        timestamp: uint
    }
)

(define-public (add-progress-update 
    (project-id uint) 
    (percentage uint) 
    (funds-used uint)
    (notes (string-ascii 500)))
    (match (map-get? projects {project-id: project-id})
        project
        (if (is-eq tx-sender (get beneficiary project))
            (let ((update-id (+ (var-get progress-update-count) u1)))
                (begin
                    (map-set project-progress
                        {project-id: project-id, update-id: update-id}
                        {
                            percentage-complete: percentage,
                            funds-used: funds-used,
                            update-notes: notes,
                            timestamp: stacks-block-height
                        }
                    )
                    (var-set progress-update-count update-id)
                    (ok true)))
            err-owner-only)
        err-not-found))


;; Define maps for budget tracking
(define-map project-budgets
    { project-id: uint }
    {
        total-budget: uint,
        allocated-funds: uint,
        remaining-funds: uint,
        last-updated: uint
    }
)

(define-public (set-project-budget 
    (project-id uint) 
    (total-budget uint))
    (match (map-get? projects {project-id: project-id})
        project
        (if (is-eq tx-sender (get beneficiary project))
            (begin
                (map-set project-budgets
                    {project-id: project-id}
                    {
                        total-budget: total-budget,
                        allocated-funds: u0,
                        remaining-funds: total-budget,
                        last-updated: stacks-block-height
                    }
                )
                (ok true))
            err-owner-only)
        err-not-found))

(define-read-only (get-project-budget (project-id uint))
    (map-get? project-budgets {project-id: project-id}))


;; Define variables and maps for timeline events
(define-data-var event-count uint u0)

(define-map timeline-events
    { project-id: uint, event-id: uint }
    {
        event-name: (string-ascii 50),
        description: (string-ascii 200),
        target-date: uint,
        completed: bool,
        completion-date: (optional uint)
    }
)

(define-public (add-timeline-event 
    (project-id uint) 
    (name (string-ascii 50))
    (description (string-ascii 200))
    (target-date uint))
    (match (map-get? projects {project-id: project-id})
        project
        (if (is-eq tx-sender (get beneficiary project))
            (let ((event-id (+ (var-get event-count) u1)))
                (begin
                    (map-set timeline-events
                        {project-id: project-id, event-id: event-id}
                        {
                            event-name: name,
                            description: description,
                            target-date: target-date,
                            completed: false,
                            completion-date: none
                        }
                    )
                    (var-set event-count event-id)
                    (ok true)))
            err-owner-only)
        err-not-found))

(define-public (mark-event-complete 
    (project-id uint) 
    (event-id uint))
    (match (map-get? timeline-events {project-id: project-id, event-id: event-id})
        event
        (begin
            (map-set timeline-events
                {project-id: project-id, event-id: event-id}
                (merge event {
                    completed: true,
                    completion-date: (some stacks-block-height)
                })
            )
            (ok true))
        err-not-found))




(define-map matching-pools
    { pool-id: uint }
    {
        creator: principal,
        project-id: uint,
        match-ratio: uint,
        remaining-funds: uint,
        active: bool
    }
)

(define-data-var pool-count uint u0)

(define-public (create-matching-pool (project-id uint) (match-ratio uint) (total-funds uint))
    (let ((pool-id (+ (var-get pool-count) u1)))
        (try! (stx-transfer? total-funds tx-sender (as-contract tx-sender)))
        (map-set matching-pools
            { pool-id: pool-id }
            {
                creator: tx-sender,
                project-id: project-id,
                match-ratio: match-ratio,
                remaining-funds: total-funds,
                active: true
            }
        )
        (var-set pool-count pool-id)
        (ok pool-id)))

(define-public (process-matching (pool-id uint) (donation-amount uint))
    (match (map-get? matching-pools {pool-id: pool-id})
        pool
        (let ((match-amount (/ (* donation-amount (get match-ratio pool)) u100)))
            (if (and 
                (get active pool)
                (<= match-amount (get remaining-funds pool)))
                (begin
                    (try! (as-contract (stx-transfer? match-amount tx-sender (get beneficiary (unwrap! (map-get? projects {project-id: (get project-id pool)}) err-not-found)))))
                    (map-set matching-pools
                        {pool-id: pool-id}
                        (merge pool {remaining-funds: (- (get remaining-funds pool) match-amount)}))
                    (ok match-amount))
                (ok u0)))
        (ok u0)))



(define-map project-kpis
    { project-id: uint }
    {
        target-beneficiaries: uint,
        target-completion-date: uint,
        target-funding: uint,
        success-threshold: uint
    }
)

(define-map project-reports
    { project-id: uint, report-id: uint }
    {
        beneficiaries-reached: uint,
        funds-utilized: uint,
        completion-percentage: uint,
        report-date: uint
    }
)

(define-data-var report-count uint u0)

(define-public (set-project-kpis 
    (project-id uint) 
    (beneficiaries uint)
    (completion-date uint)
    (funding uint)
    (threshold uint))
    (match (map-get? projects {project-id: project-id})
        project
        (if (is-eq tx-sender (get beneficiary project))
            (begin
                (map-set project-kpis
                    {project-id: project-id}
                    {
                        target-beneficiaries: beneficiaries,
                        target-completion-date: completion-date,
                        target-funding: funding,
                        success-threshold: threshold
                    }
                )
                (ok true))
            err-owner-only)
        err-not-found))

(define-public (submit-progress-report
    (project-id uint)
    (beneficiaries uint)
    (funds uint)
    (completion uint))
    (let ((report-id (+ (var-get report-count) u1)))
        (map-set project-reports
            {project-id: project-id, report-id: report-id}
            {
                beneficiaries-reached: beneficiaries,
                funds-utilized: funds,
                completion-percentage: completion,
                report-date: stacks-block-height
            }
        )
        (var-set report-count report-id)
        (ok true)))