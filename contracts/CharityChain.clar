;; CharityChain - Donation tracking and impact measurement platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))

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
