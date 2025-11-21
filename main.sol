// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title PublicArcTipJar
 * @dev A smart contract to facilitate tipping users via Twitter/X handles on the Arc Testnet
 * using USDC, with gas and token deposits handled by the contract owner.
 *
 * NOTE: This implementation uses a simplified Ownable pattern and assumes the
 * USDC token is already deployed on the Arc Testnet.
 */

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract PublicArcTipJar {
    // --- State Variables ---

    // The address of the USDC token (6 decimals on Arc Testnet)
    IERC20 public immutable usdc;

    // Maps a Twitter handle (lowercase) to the linked wallet address
    mapping(string => address) public linkedWallets;

    // Maps a Twitter handle (lowercase) to the pending USDC tip balance (in 6 decimals)
    mapping(string => uint256) public pendingTips;

    // Ownership for fund management (deposit/withdrawal)
    address private _owner;

    // --- Events ---

    event TipSent(string indexed twitterHandle, address indexed recipient, uint258 amount, bool claimedImmediately);
    event WalletLinked(string indexed twitterHandle, address indexed wallet);
    event TipsClaimed(string indexed twitterHandle, address indexed claimant, uint256 amount);

    // --- Modifiers ---

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    // --- Constructor ---

    constructor(address _usdcAddress, address initialOwner) {
        usdc = IERC20(_usdcAddress);
        _owner = initialOwner;
    }

    // --- Owner Functions (for funding the contract) ---

    /**
     * @dev Allows the owner to deposit USDC into the contract to cover tips.
     * Requires the owner to approve the contract address beforehand.
     * @param amount The amount of USDC (6 decimals) to deposit.
     */
    function depositUSDC(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be positive");
        bool success = usdc.transferFrom(msg.sender, address(this), amount);
        require(success, "USDC transfer failed");
    }

    /**
     * @dev Allows the owner to withdraw excess USDC from the contract.
     * @param amount The amount of USDC (6 decimals) to withdraw.
     */
    function withdrawUSDC(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be positive");
        require(usdc.balanceOf(address(this)) >= amount, "Insufficient contract balance");
        bool success = usdc.transfer(msg.sender, amount);
        require(success, "USDC withdrawal failed");
    }
    
    // --- Core Tipping Logic ---

    /**
     * @dev Tips a user identified by their Twitter/X handle.
     * The contract must be pre-funded with USDC by the owner.
     *
     * @param twitterHandle The recipient's Twitter handle (e.g., "vitalik").
     * @param amount The amount of USDC (6 decimals) to tip.
     */
    function tipTwitter(string memory twitterHandle, uint256 amount) external onlyOwner {
        require(amount > 0, "Tip amount must be positive");
        require(usdc.balanceOf(address(this)) >= amount, "Insufficient USDC in tip jar");

        address recipientWallet = linkedWallets[twitterHandle];
        bool claimedImmediately = false;

        if (recipientWallet != address(0)) {
            // Wallet is linked: send the tip directly.
            bool success = usdc.transfer(recipientWallet, amount);
            require(success, "Direct tip transfer failed");
            claimedImmediately = true;
        } else {
            // Wallet is not linked: hold the tip in pendingTips mapping.
            pendingTips[twitterHandle] += amount;
            claimedImmediately = false;
        }

        emit TipSent(twitterHandle, recipientWallet, amount, claimedImmediately);
    }

    // --- Claim & Linking Logic ---

    /**
     * @dev Allows a user to link their current wallet address (msg.sender) to a Twitter handle.
     * Once linked, future tips are sent directly to this address.
     * @param twitterHandle The user's Twitter handle.
     */
    function linkWallet(string memory twitterHandle) external {
        linkedWallets[twitterHandle] = msg.sender;
        emit WalletLinked(twitterHandle, msg.sender);
    }

    /**
     * @dev Allows a user to claim pending tips for a given Twitter handle.
     * Requirements: The handle must be linked to the caller's wallet (msg.sender).
     * @param twitterHandle The user's Twitter handle.
     */
    function claimTips(string memory twitterHandle) external {
        address linkedAddress = linkedWallets[twitterHandle];
        require(linkedAddress == msg.sender, "Wallet not linked to this handle");

        uint256 amountToClaim = pendingTips[twitterHandle];
        require(amountToClaim > 0, "No pending tips to claim");

        // Clear the pending balance first to prevent re-entrancy issues
        pendingTips[twitterHandle] = 0;

        // Transfer the funds
        bool success = usdc.transfer(msg.sender, amountToClaim);
        require(success, "Claim transfer failed");

        emit TipsClaimed(twitterHandle, msg.sender, amountToClaim);
    }

    // --- View Functions ---

    function owner() public view returns (address) {
        return _owner;
    }
}
