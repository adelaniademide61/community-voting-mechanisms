;; Voting System Smart Contract
;; Comprehensive decentralized governance and community voting infrastructure

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u500))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u501))
(define-constant ERR-PROPOSAL-EXPIRED (err u502))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u503))
(define-constant ERR-ALREADY-VOTED (err u504))
(define-constant ERR-INVALID-VOTE-OPTION (err u505))
(define-constant ERR-INSUFFICIENT-TOKENS (err u506))
(define-constant ERR-INVALID-PROPOSAL (err u507))
(define-constant ERR-PROPOSAL-ALREADY-FINALIZED (err u508))
(define-constant ERR-VOTING-PERIOD-ACTIVE (err u509))
(define-constant ERR-QUORUM-NOT-MET (err u510))
(define-constant ERR-INVALID-DELEGATION (err u511))
(define-constant ERR-DELEGATION-NOT-FOUND (err u512))

;; Governance Configuration Constants
(define-constant MIN-PROPOSAL-THRESHOLD u1000000) ;; Minimum tokens to create proposal
(define-constant MIN-VOTING-PERIOD u1440) ;; Minimum voting period (1 day in blocks)
(define-constant MAX-VOTING-PERIOD u10080) ;; Maximum voting period (1 week in blocks)
(define-constant DEFAULT-QUORUM u100000000) ;; Default quorum requirement (10% of total supply)
(define-constant MAX-PROPOSAL_DESCRIPTION_LENGTH u500)

;; Data Variables for System Management
(define-data-var next-proposal-id uint u1)
(define-data-var total-proposals uint u0)
(define-data-var active-proposals uint u0)
(define-data-var total-votes-cast uint u0)
(define-data-var system-active bool true)
(define-data-var emergency-mode bool false)
(define-data-var governance-token-contract principal CONTRACT-OWNER)

;; Governance Configuration Variables
(define-data-var default-voting-period uint u2880) ;; 2 days in blocks
(define-data-var proposal-threshold uint MIN-PROPOSAL-THRESHOLD)
(define-data-var quorum-threshold uint DEFAULT-QUORUM)
(define-data-var execution-delay uint u720) ;; 12 hours delay before execution

;; Comprehensive Proposal Management
(define-map proposals
    uint
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        proposal-type: (string-ascii 20),
        voting-options: (list 5 (string-ascii 50)),
        start-height: uint,
        end-height: uint,
        status: (string-ascii 15),
        total-votes: uint,
        required-quorum: uint,
        execution-height: (optional uint),
        metadata: (optional (string-ascii 200))
    }
)

;; Vote Results and Option Tracking
(define-map proposal-votes
    {proposal-id: uint, option: uint}
    {
        vote-count: uint,
        vote-weight: uint,
        voters: (list 100 principal)
    }
)

;; Individual Voter Records
(define-map voter-records
    {proposal-id: uint, voter: principal}
    {
        option: uint,
        voting-power: uint,
        vote-height: uint,
        delegated-power: uint,
        direct-vote: bool
    }
)

;; Delegation System for Proxy Voting
(define-map vote-delegations
    {delegator: principal, proposal-id: uint}
    {
        delegate: principal,
        delegation-height: uint,
        active: bool,
        voting-power: uint
    }
)

;; Global Delegation Tracking
(define-map global-delegations
    principal
    {
        delegate: principal,
        delegation-height: uint,
        active: bool,
        scope: (string-ascii 20)
    }
)

;; Proposal Categories and Templates
(define-map proposal-categories
    (string-ascii 20)
    {
        name: (string-ascii 50),
        description: (string-ascii 200),
        min-threshold: uint,
        voting-period: uint,
        quorum-requirement: uint,
        execution-delay: uint,
        active: bool
    }
)

;; Voting Power Snapshots for Governance
(define-map voting-power-snapshots
    {proposal-id: uint, voter: principal}
    {
        direct-power: uint,
        delegated-power: uint,
        total-power: uint,
        snapshot-height: uint
    }
)

;; Proposal Execution Queue
(define-map execution-queue
    uint
    {
        proposal-id: uint,
        execution-height: uint,
        executed: bool,
        execution-result: (optional (string-ascii 100)),
        executor: (optional principal)
    }
)

;; Participation Tracking and Rewards
(define-map voter-participation
    principal
    {
        total-votes: uint,
        proposals-created: uint,
        successful-proposals: uint,
        participation-score: uint,
        last-active: uint,
        reward-points: uint
    }
)

;; System Statistics and Analytics
(define-map daily-statistics
    uint ;; date (block-height / 144)
    {
        proposals-created: uint,
        votes-cast: uint,
        unique-voters: uint,
        average-participation: uint,
        successful-proposals: uint
    }
)

;; Initialize default proposal categories
(map-set proposal-categories "governance" {
    name: "Governance Proposal",
    description: "Changes to system parameters and governance rules",
    min-threshold: u5000000, ;; 5 tokens
    voting-period: u4320, ;; 3 days
    quorum-requirement: u150000000, ;; 15% of supply
    execution-delay: u1440, ;; 1 day
    active: true
})

(map-set proposal-categories "treasury" {
    name: "Treasury Proposal",
    description: "Treasury fund allocation and spending decisions",
    min-threshold: u10000000, ;; 10 tokens
    voting-period: u7200, ;; 5 days
    quorum-requirement: u200000000, ;; 20% of supply
    execution-delay: u2880, ;; 2 days
    active: true
})

(map-set proposal-categories "technical" {
    name: "Technical Proposal",
    description: "Protocol upgrades and technical improvements",
    min-threshold: u2000000, ;; 2 tokens
    voting-period: u5760, ;; 4 days
    quorum-requirement: u100000000, ;; 10% of supply
    execution-delay: u720, ;; 12 hours
    active: true
})

;; Private Helper Functions

;; Validate proposal content and parameters
(define-private (is-valid-proposal-data 
    (title (string-ascii 100)) 
    (description (string-ascii 500)) 
    (voting-period uint)
    (options (list 5 (string-ascii 50)))
)
    (and
        (> (len title) u0)
        (> (len description) u0)
        (>= voting-period MIN-VOTING-PERIOD)
        (<= voting-period MAX-VOTING-PERIOD)
        (> (len options) u1)
        (<= (len options) u5)
    )
)

;; Check if proposal is in active voting period
(define-private (is-proposal-active (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal
        (and 
            (is-eq (get status proposal) "active")
            (>= block-height (get start-height proposal))
            (< block-height (get end-height proposal))
        )
        false
    )
)

;; Check if voter has already voted on proposal
(define-private (has-voted (proposal-id uint) (voter principal))
    (is-some (map-get? voter-records {proposal-id: proposal-id, voter: voter}))
)

;; Get voter's effective voting power (simulated token balance)
(define-private (get-voting-power (voter principal) (proposal-id uint))
    ;; In a real implementation, this would call the governance token contract
    ;; For this self-contained version, we simulate voting power
    (let 
        (
            (base-power u1000000) ;; Base voting power
            (participation-bonus (get-participation-bonus voter))
        )
        (+ base-power participation-bonus)
    )
)

;; Calculate participation bonus based on voting history
(define-private (get-participation-bonus (voter principal))
    (match (map-get? voter-participation voter)
        participation
        (let ((score (get participation-score participation)))
            (if (>= score u80) 
                u500000 ;; 0.5 token bonus for high participation
                (if (>= score u50)
                    u200000 ;; 0.2 token bonus for medium participation
                    u0)))
        u0
    )
)

;; Update voter participation metrics
(define-private (update-participation (voter principal) (proposal-created bool))
    (let 
        (
            (current-participation (default-to 
                {total-votes: u0, proposals-created: u0, successful-proposals: u0, 
                 participation-score: u50, last-active: u0, reward-points: u0} 
                (map-get? voter-participation voter)))
        )
        (map-set voter-participation voter (merge current-participation {
            total-votes: (if proposal-created 
                            (get total-votes current-participation)
                            (+ (get total-votes current-participation) u1)),
            proposals-created: (if proposal-created 
                                  (+ (get proposals-created current-participation) u1)
                                  (get proposals-created current-participation)),
            last-active: block-height,
            participation-score: (calculate-participation-score 
                                   (get total-votes current-participation)
                                   (get proposals-created current-participation))
        }))
    )
)

;; Calculate participation score based on activity
(define-private (calculate-participation-score (votes uint) (proposal-count uint))
    (let 
        (
            (vote-score (if (> votes u10) u40 (* votes u4)))
            (proposal-score (* proposals u20))
            (total-score (+ vote-score proposal-score))
        )
        (if (> total-score u100) u100 total-score)
    )
)

;; Add voter to option's voter list
(define-private (add-voter-to-option (proposal-id uint) (option uint) (voter principal))
    (let 
        (
            (current-votes (default-to 
                {vote-count: u0, vote-weight: u0, voters: (list)}
                (map-get? proposal-votes {proposal-id: proposal-id, option: option})))
            (current-voters (get voters current-votes))
        )
        (if (< (len current-voters) u100)
            (map-set proposal-votes {proposal-id: proposal-id, option: option}
                (merge current-votes {
                    voters: (unwrap-panic (as-max-len? (append current-voters voter) u100))
                }))
            true
        )
    )
)

;; Public Functions for Governance

;; Create new governance proposal
(define-public (create-proposal
    (title (string-ascii 100))
    (description (string-ascii 500))
    (proposal-type (string-ascii 20))
    (voting-options (list 5 (string-ascii 50)))
    (voting-period uint)
    (metadata (optional (string-ascii 200)))
)
    (let 
        (
            (proposal-id (var-get next-proposal-id))
            (voter-power (get-voting-power tx-sender proposal-id))
            (category-info (map-get? proposal-categories proposal-type))
        )
        ;; Validate proposal creation conditions
        (asserts! (var-get system-active) ERR-UNAUTHORIZED)
        (asserts! (>= voter-power (var-get proposal-threshold)) ERR-INSUFFICIENT-TOKENS)
        (asserts! (is-valid-proposal-data title description voting-period voting-options) ERR-INVALID-PROPOSAL)

        ;; Set voting period and quorum based on category or defaults
        (let 
            (
                (final-period (match category-info 
                                cat (get voting-period cat)
                                voting-period))
                (required-quorum (match category-info
                                   cat (get quorum-requirement cat)
                                   (var-get quorum-threshold)))
                (start-height (+ block-height u144)) ;; Start voting after 1 day
                (end-height (+ start-height final-period))
            )
            
            ;; Create proposal record
            (map-set proposals proposal-id {
                proposer: tx-sender,
                title: title,
                description: description,
                proposal-type: proposal-type,
                voting-options: voting-options,
                start-height: start-height,
                end-height: end-height,
                status: "pending",
                total-votes: u0,
                required-quorum: required-quorum,
                execution-height: none,
                metadata: metadata
            })

            ;; Initialize vote tracking for each option
            (map-set proposal-votes {proposal-id: proposal-id, option: u0} 
                {vote-count: u0, vote-weight: u0, voters: (list)})
            (map-set proposal-votes {proposal-id: proposal-id, option: u1} 
                {vote-count: u0, vote-weight: u0, voters: (list)})

            ;; Update system statistics
            (var-set next-proposal-id (+ proposal-id u1))
            (var-set total-proposals (+ (var-get total-proposals) u1))
            (var-set active-proposals (+ (var-get active-proposals) u1))
            
            ;; Update proposer participation
            (update-participation tx-sender true)
            
            (ok proposal-id)
        )
    )
)

;; Cast vote on active proposal
(define-public (cast-vote (proposal-id uint) (option uint) (voting-power-override (optional uint)))
    (let 
        (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (voter-power (match voting-power-override
                            power power
                            (get-voting-power tx-sender proposal-id)))
        )
        ;; Validate voting conditions
        (asserts! (var-get system-active) ERR-UNAUTHORIZED)
        (asserts! (is-proposal-active proposal-id) ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (not (has-voted proposal-id tx-sender)) ERR-ALREADY-VOTED)
        (asserts! (< option (len (get voting-options proposal))) ERR-INVALID-VOTE-OPTION)
        (asserts! (> voter-power u0) ERR-INSUFFICIENT-TOKENS)

        ;; Record individual vote
        (map-set voter-records {proposal-id: proposal-id, voter: tx-sender} {
            option: option,
            voting-power: voter-power,
            vote-height: block-height,
            delegated-power: u0, ;; TODO: Implement delegation power calculation
            direct-vote: true
        })

        ;; Update proposal vote totals
        (let 
            (
                (current-votes (default-to 
                    {vote-count: u0, vote-weight: u0, voters: (list)}
                    (map-get? proposal-votes {proposal-id: proposal-id, option: option})))
            )
            (map-set proposal-votes {proposal-id: proposal-id, option: option} (merge current-votes {
                vote-count: (+ (get vote-count current-votes) u1),
                vote-weight: (+ (get vote-weight current-votes) voter-power)
            }))
            
            ;; Add voter to option's voter list
            (add-voter-to-option proposal-id option tx-sender)
        )

        ;; Update proposal total votes
        (map-set proposals proposal-id (merge proposal {
            total-votes: (+ (get total-votes proposal) voter-power)
        }))

        ;; Update system and participation statistics
        (var-set total-votes-cast (+ (var-get total-votes-cast) u1))
        (update-participation tx-sender false)

        (ok true)
    )
)

;; Delegate voting power for specific proposal
(define-public (delegate-vote (proposal-id uint) (delegate principal))
    (let 
        (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (voter-power (get-voting-power tx-sender proposal-id))
        )
        ;; Validate delegation conditions
        (asserts! (var-get system-active) ERR-UNAUTHORIZED)
        (asserts! (is-proposal-active proposal-id) ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (not (has-voted proposal-id tx-sender)) ERR-ALREADY-VOTED)
        (asserts! (not (is-eq tx-sender delegate)) ERR-INVALID-DELEGATION)
        (asserts! (> voter-power u0) ERR-INSUFFICIENT-TOKENS)

        ;; Create delegation record
        (map-set vote-delegations {delegator: tx-sender, proposal-id: proposal-id} {
            delegate: delegate,
            delegation-height: block-height,
            active: true,
            voting-power: voter-power
        })

        (ok true)
    )
)

;; Finalize proposal after voting period ends
(define-public (finalize-proposal (proposal-id uint))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
        ;; Validate finalization conditions
        (asserts! (var-get system-active) ERR-UNAUTHORIZED)
        (asserts! (>= block-height (get end-height proposal)) ERR-VOTING-PERIOD-ACTIVE)
        (asserts! (is-eq (get status proposal) "active") ERR-PROPOSAL-ALREADY-FINALIZED)

        ;; Determine if quorum was met and winning option
        (let 
            (
                (total-votes (get total-votes proposal))
                (required-quorum (get required-quorum proposal))
                (quorum-met (>= total-votes required-quorum))
                (winning-option (if quorum-met (get-winning-option proposal-id) u0))
            )
            
            ;; Update proposal status based on results
            (let 
                (
                    (new-status (if quorum-met "passed" "rejected"))
                    (execution-height (if (and quorum-met (> winning-option u0))
                                         (some (+ block-height (var-get execution-delay)))
                                         none))
                )
                (map-set proposals proposal-id (merge proposal {
                    status: new-status,
                    execution-height: execution-height
                }))

                ;; Add to execution queue if passed
                (if (is-some execution-height)
                    (map-set execution-queue proposal-id {
                        proposal-id: proposal-id,
                        execution-height: (unwrap-panic execution-height),
                        executed: false,
                        execution-result: none,
                        executor: none
                    })
                    true
                )

                ;; Update system statistics
                (var-set active-proposals (- (var-get active-proposals) u1))

                (ok {
                    status: new-status,
                    winning-option: winning-option,
                    total-votes: total-votes,
                    quorum-met: quorum-met
                })
            )
        )
    )
)

;; Execute finalized proposal (placeholder for actual execution logic)
(define-public (execute-proposal (proposal-id uint))
    (let 
        (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (queue-item (unwrap! (map-get? execution-queue proposal-id) ERR-PROPOSAL-NOT-FOUND))
        )
        ;; Validate execution conditions
        (asserts! (var-get system-active) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status proposal) "passed") ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (>= block-height (get execution-height queue-item)) ERR-UNAUTHORIZED)
        (asserts! (not (get executed queue-item)) ERR-PROPOSAL-ALREADY-FINALIZED)

        ;; Mark as executed (actual execution logic would go here)
        (map-set execution-queue proposal-id (merge queue-item {
            executed: true,
            execution-result: (some "Executed successfully"),
            executor: (some tx-sender)
        }))

        (ok true)
    )
)

;; Administrative Functions (Contract Owner Only)

;; Update system configuration
(define-public (update-governance-config 
    (new-threshold uint) 
    (new-voting-period uint) 
    (new-quorum uint)
    (new-execution-delay uint)
)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (>= new-threshold MIN-PROPOSAL-THRESHOLD) ERR-INVALID-PROPOSAL)
        (asserts! (and (>= new-voting-period MIN-VOTING-PERIOD) 
                      (<= new-voting-period MAX-VOTING-PERIOD)) ERR-INVALID-PROPOSAL)
        
        (var-set proposal-threshold new-threshold)
        (var-set default-voting-period new-voting-period)
        (var-set quorum-threshold new-quorum)
        (var-set execution-delay new-execution-delay)
        
        (ok true)
    )
)

;; Toggle system active status
(define-public (toggle-system-status)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set system-active (not (var-get system-active)))
        (ok (var-get system-active))
    )
)

;; Activate emergency mode
(define-public (toggle-emergency-mode)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set emergency-mode (not (var-get emergency-mode)))
        (ok (var-get emergency-mode))
    )
)

;; Private function to determine winning option
(define-private (get-winning-option (proposal-id uint))
    (let 
        (
            (option-0-weight (get vote-weight (default-to 
                {vote-count: u0, vote-weight: u0, voters: (list)}
                (map-get? proposal-votes {proposal-id: proposal-id, option: u0}))))
            (option-1-weight (get vote-weight (default-to 
                {vote-count: u0, vote-weight: u0, voters: (list)}
                (map-get? proposal-votes {proposal-id: proposal-id, option: u1}))))
        )
        (if (> option-1-weight option-0-weight) u1 u0)
    )
)

;; Read-only Functions for Data Retrieval

;; Get comprehensive proposal details
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Get vote results for specific option
(define-read-only (get-vote-results (proposal-id uint) (option uint))
    (map-get? proposal-votes {proposal-id: proposal-id, option: option})
)

;; Get voter's voting record for proposal
(define-read-only (get-voter-record (proposal-id uint) (voter principal))
    (map-get? voter-records {proposal-id: proposal-id, voter: voter})
)

;; Get delegation information
(define-read-only (get-vote-delegation (delegator principal) (proposal-id uint))
    (map-get? vote-delegations {delegator: delegator, proposal-id: proposal-id})
)

;; Get proposal category configuration
(define-read-only (get-proposal-category (category (string-ascii 20)))
    (map-get? proposal-categories category)
)

;; Get voter participation metrics
(define-read-only (get-participation-info (voter principal))
    (map-get? voter-participation voter)
)

;; Get system statistics
(define-read-only (get-system-stats)
    {
        total-proposals: (var-get total-proposals),
        active-proposals: (var-get active-proposals),
        total-votes-cast: (var-get total-votes-cast),
        system-active: (var-get system-active),
        emergency-mode: (var-get emergency-mode),
        proposal-threshold: (var-get proposal-threshold),
        default-voting-period: (var-get default-voting-period),
        quorum-threshold: (var-get quorum-threshold),
        execution-delay: (var-get execution-delay)
    }
)

;; Get execution queue item
(define-read-only (get-execution-info (proposal-id uint))
    (map-get? execution-queue proposal-id)
)

;; Get daily statistics
(define-read-only (get-daily-stats (date uint))
    (map-get? daily-statistics date)
)

;; Check if proposal is in voting period
(define-read-only (is-voting-active (proposal-id uint))
    (is-proposal-active proposal-id)
)

;; Get contract owner
(define-read-only (get-contract-owner)
    CONTRACT-OWNER
)

;; Calculate estimated voting power for address
(define-read-only (estimate-voting-power (voter principal))
    (get-voting-power voter u0)
)
