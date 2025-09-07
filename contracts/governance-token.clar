;; Governance Token Smart Contract
;; SIP-010 compliant fungible token for community voting and governance

;; SIP-010 Standard Constants (implemented without trait for self-contained approach)
(define-constant CONTRACT-OWNER tx-sender)

;; Error Constants
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-NOT-TOKEN-OWNER (err u2))
(define-constant ERR-INSUFFICIENT-BALANCE (err u3))
(define-constant ERR-INVALID-AMOUNT (err u4))
(define-constant ERR-TOKEN-ALREADY-EXISTS (err u5))
(define-constant ERR-INVALID-RECIPIENT (err u6))
(define-constant ERR-MINTING-DISABLED (err u7))
(define-constant ERR-BURNING-DISABLED (err u8))
(define-constant ERR-TRANSFER-DISABLED (err u9))
(define-constant ERR-DELEGATION-EXISTS (err u10))
(define-constant ERR-DELEGATION-NOT-FOUND (err u11))
(define-constant ERR-INVALID-DELEGATION (err u12))

;; Token Configuration Constants
(define-constant TOKEN-NAME "Community Governance Token")
(define-constant TOKEN-SYMBOL "CGT")
(define-constant TOKEN-DECIMALS u6)
(define-constant MAX-SUPPLY u1000000000000) ;; 1 million tokens with 6 decimals

;; Data Variables for Token Management
(define-data-var total-supply uint u0)
(define-data-var minting-enabled bool true)
(define-data-var burning-enabled bool true)
(define-data-var transfers-enabled bool true)
(define-data-var delegation-enabled bool true)
(define-data-var governance-active bool false)

;; Token Balance and Allowance Management
(define-map balances principal uint)
(define-map allowances {owner: principal, spender: principal} uint)

;; Delegation System for Voting Power
(define-map delegations 
    principal 
    {
        delegate: principal,
        amount: uint,
        block-height: uint,
        active: bool
    }
)

;; Reverse delegation tracking for efficient lookups
(define-map delegation-totals principal uint)

;; Token Lock Mechanisms for Governance
(define-map locked-balances
    principal
    {
        amount: uint,
        unlock-height: uint,
        lock-type: (string-ascii 20),
        metadata: (optional (string-ascii 100))
    }
)

;; Minting History and Controls
(define-map minting-history 
    uint 
    {
        recipient: principal,
        amount: uint,
        minter: principal,
        timestamp: uint,
        reason: (string-ascii 50)
    }
)

;; Transfer History for Audit Trail
(define-map transfer-history
    uint
    {
        from: principal,
        to: principal,
        amount: uint,
        timestamp: uint,
        transaction-type: (string-ascii 20)
    }
)

;; Administrative Controls
(define-map authorized-minters principal bool)
(define-map authorized-burners principal bool)

;; Data Variables for Event Tracking
(define-data-var next-mint-id uint u1)
(define-data-var next-transfer-id uint u1)
(define-data-var total-minted uint u0)
(define-data-var total-burned uint u0)
(define-data-var total-locked uint u0)
(define-data-var unique-holders uint u0)

;; Initialize contract owner as authorized minter and burner
(map-set authorized-minters CONTRACT-OWNER true)
(map-set authorized-burners CONTRACT-OWNER true)

;; Private Helper Functions

;; Validate amount is greater than zero
(define-private (is-valid-amount (amount uint))
    (> amount u0)
)

;; Check if principal has sufficient balance
(define-private (has-sufficient-balance (account principal) (amount uint))
    (>= (get-balance account) amount)
)

;; Check if principal is authorized minter
(define-private (is-authorized-minter (minter principal))
    (default-to false (map-get? authorized-minters minter))
)

;; Check if principal is authorized burner  
(define-private (is-authorized-burner (burner principal))
    (default-to false (map-get? authorized-burners burner))
)

;; Update holder count when balance changes from/to zero
(define-private (update-holder-count (account principal) (old-balance uint) (new-balance uint))
    (begin
        (if (and (is-eq old-balance u0) (> new-balance u0))
            (var-set unique-holders (+ (var-get unique-holders) u1))
            (if (and (> old-balance u0) (is-eq new-balance u0))
                (begin (var-set unique-holders (- (var-get unique-holders) u1)) u0)
                u0
            )
        )
    )
)

;; Record transfer in history
(define-private (record-transfer (from principal) (to principal) (amount uint) (tx-type (string-ascii 20)))
    (let ((transfer-id (var-get next-transfer-id)))
        (map-set transfer-history transfer-id {
            from: from,
            to: to,
            amount: amount,
            timestamp: block-height,
            transaction-type: tx-type
        })
        (var-set next-transfer-id (+ transfer-id u1))
    )
)

;; Core Token Functions (SIP-010 Implementation)

;; Get token name
(define-read-only (get-name)
    (ok TOKEN-NAME)
)

;; Get token symbol  
(define-read-only (get-symbol)
    (ok TOKEN-SYMBOL)
)

;; Get token decimals
(define-read-only (get-decimals)
    (ok TOKEN-DECIMALS)
)

;; Get total token supply
(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

;; Get balance of specific account
(define-read-only (get-balance (account principal))
    (default-to u0 (map-get? balances account))
)

;; Get token URI (metadata)
(define-read-only (get-token-uri)
    (ok (some "https://governance.community/token-metadata.json"))
)

;; Transfer tokens between accounts
(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
    (begin
        ;; Validate transfer conditions
        (asserts! (var-get transfers-enabled) ERR-TRANSFER-DISABLED)
        (asserts! (is-valid-amount amount) ERR-INVALID-AMOUNT)
        (asserts! (is-eq from tx-sender) ERR-NOT-TOKEN-OWNER)
        (asserts! (not (is-eq from to)) ERR-INVALID-RECIPIENT)
        (asserts! (has-sufficient-balance from amount) ERR-INSUFFICIENT-BALANCE)

        ;; Get current balances
        (let 
            (
                (from-balance (get-balance from))
                (to-balance (get-balance to))
                (new-from-balance (- from-balance amount))
                (new-to-balance (+ to-balance amount))
            )
            
            ;; Update balances
            (map-set balances from new-from-balance)
            (map-set balances to new-to-balance)
            
            ;; Update holder counts
            (update-holder-count from from-balance new-from-balance)
            (update-holder-count to to-balance new-to-balance)
            
            ;; Record transfer
            (record-transfer from to amount "transfer")
            
            ;; Return success with transfer details
            ;; Note: In actual SIP-010, this would emit an event
            (ok true)
        )
    )
)

;; Mint new tokens (restricted function)
(define-public (mint (amount uint) (recipient principal) (reason (string-ascii 50)))
    (begin
        ;; Validate minting conditions
        (asserts! (var-get minting-enabled) ERR-MINTING-DISABLED)
        (asserts! (is-authorized-minter tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-amount amount) ERR-INVALID-AMOUNT)
        (asserts! (<= (+ (var-get total-supply) amount) MAX-SUPPLY) ERR-INVALID-AMOUNT)

        ;; Get current state
        (let 
            (
                (current-balance (get-balance recipient))
                (new-balance (+ current-balance amount))
                (new-total-supply (+ (var-get total-supply) amount))
                (mint-id (var-get next-mint-id))
            )
            
            ;; Update balances and supply
            (map-set balances recipient new-balance)
            (var-set total-supply new-total-supply)
            (var-set total-minted (+ (var-get total-minted) amount))
            
            ;; Update holder count
            (update-holder-count recipient current-balance new-balance)
            
            ;; Record minting history
            (map-set minting-history mint-id {
                recipient: recipient,
                amount: amount,
                minter: tx-sender,
                timestamp: block-height,
                reason: reason
            })
            (var-set next-mint-id (+ mint-id u1))
            
            ;; Record as transfer from contract
            (record-transfer CONTRACT-OWNER recipient amount "mint")
            
            (ok true)
        )
    )
)

;; Burn tokens from account (restricted function)
(define-public (burn (amount uint) (owner principal))
    (begin
        ;; Validate burning conditions
        (asserts! (var-get burning-enabled) ERR-BURNING-DISABLED)
        (asserts! (is-authorized-burner tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-amount amount) ERR-INVALID-AMOUNT)
        (asserts! (has-sufficient-balance owner amount) ERR-INSUFFICIENT-BALANCE)

        ;; Get current state
        (let 
            (
                (current-balance (get-balance owner))
                (new-balance (- current-balance amount))
                (new-total-supply (- (var-get total-supply) amount))
            )
            
            ;; Update balances and supply
            (map-set balances owner new-balance)
            (var-set total-supply new-total-supply)
            (var-set total-burned (+ (var-get total-burned) amount))
            
            ;; Update holder count
            (update-holder-count owner current-balance new-balance)
            
            ;; Record as transfer to contract
            (record-transfer owner CONTRACT-OWNER amount "burn")
            
            (ok true)
        )
    )
)

;; Delegation Functions for Governance

;; Delegate voting power to another account
(define-public (delegate-voting-power (delegate principal) (amount uint))
    (begin
        ;; Validate delegation conditions
        (asserts! (var-get delegation-enabled) ERR-INVALID-DELEGATION)
        (asserts! (is-valid-amount amount) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq tx-sender delegate)) ERR-INVALID-DELEGATION)
        (asserts! (has-sufficient-balance tx-sender amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (is-none (map-get? delegations tx-sender)) ERR-DELEGATION-EXISTS)

        ;; Create delegation record
        (map-set delegations tx-sender {
            delegate: delegate,
            amount: amount,
            block-height: block-height,
            active: true
        })
        
        ;; Update delegate's total delegated power
        (let ((current-total (default-to u0 (map-get? delegation-totals delegate))))
            (map-set delegation-totals delegate (+ current-total amount))
        )
        
        (ok true)
    )
)

;; Revoke existing delegation
(define-public (revoke-delegation)
    (let ((delegation (unwrap! (map-get? delegations tx-sender) ERR-DELEGATION-NOT-FOUND)))
        (asserts! (get active delegation) ERR-DELEGATION-NOT-FOUND)
        
        ;; Deactivate delegation
        (map-set delegations tx-sender (merge delegation {active: false}))
        
        ;; Update delegate's total
        (let 
            (
                (delegate (get delegate delegation))
                (amount (get amount delegation))
                (current-total (default-to u0 (map-get? delegation-totals delegate)))
            )
            (map-set delegation-totals delegate (- current-total amount))
        )
        
        (ok true)
    )
)

;; Token Locking Functions

;; Lock tokens for governance participation
(define-public (lock-tokens (amount uint) (unlock-height uint) (lock-type (string-ascii 20)) (metadata (optional (string-ascii 100))))
    (begin
        ;; Validate lock conditions
        (asserts! (is-valid-amount amount) ERR-INVALID-AMOUNT)
        (asserts! (> unlock-height block-height) ERR-INVALID-AMOUNT)
        (asserts! (has-sufficient-balance tx-sender amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (is-none (map-get? locked-balances tx-sender)) ERR-TOKEN-ALREADY-EXISTS)

        ;; Create lock record
        (map-set locked-balances tx-sender {
            amount: amount,
            unlock-height: unlock-height,
            lock-type: lock-type,
            metadata: metadata
        })
        
        ;; Update total locked
        (var-set total-locked (+ (var-get total-locked) amount))
        
        (ok true)
    )
)

;; Unlock tokens after lock period expires
(define-public (unlock-tokens)
    (let ((lock-info (unwrap! (map-get? locked-balances tx-sender) ERR-TOKEN-ALREADY-EXISTS)))
        (asserts! (>= block-height (get unlock-height lock-info)) ERR-UNAUTHORIZED)
        
        ;; Remove lock record
        (map-delete locked-balances tx-sender)
        
        ;; Update total locked
        (var-set total-locked (- (var-get total-locked) (get amount lock-info)))
        
        (ok (get amount lock-info))
    )
)

;; Administrative Functions (Contract Owner Only)

;; Add authorized minter
(define-public (add-minter (minter principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-minters minter true)
        (ok true)
    )
)

;; Remove authorized minter
(define-public (remove-minter (minter principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-delete authorized-minters minter)
        (ok true)
    )
)

;; Add authorized burner
(define-public (add-burner (burner principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-burners burner true)
        (ok true)
    )
)

;; Remove authorized burner
(define-public (remove-burner (burner principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-delete authorized-burners burner)
        (ok true)
    )
)

;; Toggle minting functionality
(define-public (toggle-minting)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set minting-enabled (not (var-get minting-enabled)))
        (ok (var-get minting-enabled))
    )
)

;; Toggle burning functionality
(define-public (toggle-burning)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set burning-enabled (not (var-get burning-enabled)))
        (ok (var-get burning-enabled))
    )
)

;; Toggle transfer functionality
(define-public (toggle-transfers)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set transfers-enabled (not (var-get transfers-enabled)))
        (ok (var-get transfers-enabled))
    )
)

;; Toggle delegation functionality
(define-public (toggle-delegation)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set delegation-enabled (not (var-get delegation-enabled)))
        (ok (var-get delegation-enabled))
    )
)

;; Activate governance features
(define-public (activate-governance)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set governance-active true)
        (ok true)
    )
)

;; Read-only Functions for Data Retrieval

;; Get delegation information
(define-read-only (get-delegation-info (account principal))
    (map-get? delegations account)
)

;; Get total delegated power for an account
(define-read-only (get-delegated-power (delegate principal))
    (default-to u0 (map-get? delegation-totals delegate))
)

;; Get effective voting power (balance + delegated power)
(define-read-only (get-voting-power (account principal))
    (+ (get-balance account) (get-delegated-power account))
)

;; Get locked balance information
(define-read-only (get-locked-balance (account principal))
    (map-get? locked-balances account)
)

;; Get available balance (balance - locked)
(define-read-only (get-available-balance (account principal))
    (let 
        (
            (total-balance (get-balance account))
            (locked-info (map-get? locked-balances account))
        )
        (match locked-info
            lock (if (< block-height (get unlock-height lock))
                     (- total-balance (get amount lock))
                     total-balance)
            total-balance
        )
    )
)

;; Get minting history record
(define-read-only (get-mint-record (mint-id uint))
    (map-get? minting-history mint-id)
)

;; Get transfer history record
(define-read-only (get-transfer-record (transfer-id uint))
    (map-get? transfer-history transfer-id)
)

;; Get comprehensive token statistics
(define-read-only (get-token-stats)
    {
        total-supply: (var-get total-supply),
        total-minted: (var-get total-minted),
        total-burned: (var-get total-burned),
        total-locked: (var-get total-locked),
        unique-holders: (var-get unique-holders),
        max-supply: MAX-SUPPLY,
        minting-enabled: (var-get minting-enabled),
        burning-enabled: (var-get burning-enabled),
        transfers-enabled: (var-get transfers-enabled),
        delegation-enabled: (var-get delegation-enabled),
        governance-active: (var-get governance-active)
    }
)

;; Check if account is authorized minter
(define-read-only (is-minter (account principal))
    (default-to false (map-get? authorized-minters account))
)

;; Check if account is authorized burner
(define-read-only (is-burner (account principal))
    (default-to false (map-get? authorized-burners account))
)

;; Get contract owner
(define-read-only (get-contract-owner)
    CONTRACT-OWNER
)

;; Get circulating supply (total supply - locked tokens)
(define-read-only (get-circulating-supply)
    (- (var-get total-supply) (var-get total-locked))
)
