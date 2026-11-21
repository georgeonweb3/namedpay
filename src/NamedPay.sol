// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title NamedPay — pay an agent by its .ai name
/// @notice A payment rail for Binance Agent ID holders (BNB Chain). The
/// destination of a payment is a name string, not an address: the contract
/// resolves the name on-chain (tokenId = keccak256(label) -> ownerOf on the
/// SPACE ID Agent ID contract) and routes BNB to the name owner's payout
/// address, directly or via escrow.
/// @dev `resolveName` is a composable view so other contracts can route
/// payments by name. It is NOT a wallet-lookup product: NamedPay offers no
/// lookup UI and never markets name-to-address resolution as a feature. The
/// payout address is only ever shown as the confirmation line of a payment
/// the user initiated.
/// @dev No fee on payments in v1. The deployer (owner) can only pause new
/// registrations/payments/escrows in an emergency; it can never move user
/// funds, and fund release (confirmDelivery / refund / timeoutRefund) is
/// never blocked by a pause.
interface IAgentID {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract NamedPay {
    // --- errors ---
    error NameNotFound(bytes32 labelHash);
    error NotNameOwner(bytes32 labelHash, address caller);
    error EmptyLabel();
    error LabelTooLong();
    error ZeroPayment();
    error ZeroAddress();
    error PaymentFailed(address recipient);
    error EscrowNotFound(uint256 escrowId);
    error AlreadySettled(uint256 escrowId);
    error NotPayer(uint256 escrowId, address caller);
    error NotNameOwnerForEscrow(uint256 escrowId, address caller);
    error DeadlineNotReached(uint256 escrowId, uint256 deadline);
    error ContractPaused();
    error NotOwner(address caller);
    error Reentrant();

    // --- events ---
    event PayeeRegistered(bytes32 indexed labelHash, string label, address indexed owner, address payout);
    event PaidByName(bytes32 indexed labelHash, string label, address indexed payer, address indexed payee, uint256 amount);
    event EscrowCreated(
        uint256 indexed escrowId,
        bytes32 indexed labelHash,
        string label,
        address indexed payer,
        address payee,
        uint256 amount,
        uint256 deadline
    );
    event EscrowReleased(uint256 indexed escrowId, address indexed payee, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, address indexed payer, uint256 amount);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    IAgentID public immutable agentId;
    address public immutable owner;

    /// @notice Escrow auto-refund window. After this, anyone may trigger the refund to the payer.
    uint256 public constant ESCROW_TIMEOUT = 7 days;
    uint256 public constant MAX_LABEL_LENGTH = 64;

    bool public paused;
    /// @notice labelHash => payout override. Zero means "pay the name owner wallet".
    mapping(bytes32 => address) public payoutOf;
    uint256 public nextEscrowId;

    struct Escrow {
        bytes32 labelHash;
        address payer;
        address payee;
        /// @notice Name owner at escrow creation. Release authority follows
        /// this frozen owner, not the live name owner: a payout rotation or
        /// a name sale after creation does not change who may confirm, and
        /// the payee recorded at creation is the one who gets paid. The
        /// owner can ask the payer to refund and re-escrow if they want the
        /// new payout / new owner to take over.
        address owner;
        uint256 amount;
        uint256 deadline;
        bool released;
        bool refunded;
    }

    mapping(uint256 => Escrow) public escrows;

    bool private _locked;

    modifier nonReentrant() {
        if (_locked) revert Reentrant();
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address agentId_) {
        if (agentId_ == address(0)) revert ZeroAddress();
        agentId = IAgentID(agentId_);
        owner = msg.sender;
    }

    // --- label handling ---

    /// @notice Agent ID labels are lowercase (SPACE ID convention). Normalise
    /// A-Z to a-z so "Alice.ai" and "alice.ai" resolve to the same name.
    /// Also strips one trailing ".ai" (case-insensitive) so paying by the
    /// full ".ai" name resolves: "alice.ai" -> "alice". Only one suffix is
    /// stripped ("alice.ai.ai" does not resolve), and a label that is just
    /// ".ai" reverts EmptyLabel. Safe: SPACE ID labels cannot contain dots,
    /// so no real label ends in ".ai".
    function _normalize(string memory label) internal pure returns (string memory) {
        bytes memory b = bytes(label);
        if (b.length == 0) revert EmptyLabel();
        if (b.length > MAX_LABEL_LENGTH) revert LabelTooLong();
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c >= 0x41 && c <= 0x5A) {
                b[i] = bytes1(uint8(c) + 32);
            }
        }
        if (
            b.length >= 3 &&
            b[b.length - 3] == 0x2e && // "."
            b[b.length - 2] == 0x61 && // "a"
            b[b.length - 1] == 0x69 // "i"
        ) {
            bytes memory stripped = new bytes(b.length - 3);
            for (uint256 j = 0; j < stripped.length; j++) {
                stripped[j] = b[j];
            }
            if (stripped.length == 0) revert EmptyLabel();
            return string(stripped);
        }
        return string(b);
    }

    function _labelHash(string memory label) internal pure returns (bytes32) {
        return keccak256(bytes(_normalize(label)));
    }

    /// @notice Owner of a name, by its label hash. Reverts if the name does not exist.
    function _ownerOfHash(bytes32 labelHash) internal view returns (address) {
        address o;
        try agentId.ownerOf(uint256(labelHash)) returns (address owner_) {
            o = owner_;
        } catch {
            revert NameNotFound(labelHash);
        }
        if (o == address(0)) revert NameNotFound(labelHash);
        return o;
    }

    /// @notice Resolve a label to (labelHash, name owner, payout address).
    function _resolve(string memory label) internal view returns (bytes32, address, address) {
        bytes32 lh = _labelHash(label);
        address o = _ownerOfHash(lh);
        address payout = payoutOf[lh];
        return (lh, o, payout == address(0) ? o : payout);
    }

    // --- registration ---

    /// @notice Claim a name as payable, or change its payout address.
    /// Only the name owner may call. Pass address(0) to reset to the owner wallet.
    function registerPayee(string memory label, address payout) external {
        if (paused) revert ContractPaused();
        bytes32 lh = _labelHash(label);
        address o = _ownerOfHash(lh);
        if (o != msg.sender) revert NotNameOwner(lh, msg.sender);
        payoutOf[lh] = payout;
        emit PayeeRegistered(lh, label, o, payout);
    }

    /// @notice Resolve a name to its payout address (registered payout, else the
    /// name owner wallet). Reverts if the name does not exist. Composable view
    /// for other contracts routing payments by name — not a lookup.
    function resolveName(string memory label) public view returns (address) {
        (, , address payee) = _resolve(label);
        return payee;
    }

    // --- direct payments ---

    /// @notice Pay a name in BNB. Forwards exactly msg.value to the payout
    /// address. Reverts if the name does not exist — paying a nonexistent
    /// name fails loudly, by design.
    function payByName(string memory label) external payable nonReentrant {
        if (paused) revert ContractPaused();
        if (msg.value == 0) revert ZeroPayment();
        (bytes32 lh, , address payee) = _resolve(label);
        (bool ok,) = payee.call{value: msg.value}("");
        if (!ok) revert PaymentFailed(payee);
        emit PaidByName(lh, label, msg.sender, payee, msg.value);
    }

    // --- escrow ---

    /// @notice Lock BNB for a named agent. The name owner releases it with
    /// confirmDelivery; the payer may refund before confirmation; after the
    /// timeout anyone may trigger the refund to the payer.
    function escrowByName(string memory label) external payable nonReentrant returns (uint256 escrowId) {
        if (paused) revert ContractPaused();
        if (msg.value == 0) revert ZeroPayment();
        (bytes32 lh, address o, address payee) = _resolve(label);
        escrowId = nextEscrowId++;
        uint256 deadline = block.timestamp + ESCROW_TIMEOUT;
        escrows[escrowId] = Escrow({
            labelHash: lh,
            payer: msg.sender,
            payee: payee,
            owner: o,
            amount: msg.value,
            deadline: deadline,
            released: false,
            refunded: false
        });
        emit EscrowCreated(escrowId, lh, label, msg.sender, payee, msg.value, deadline);
    }

    /// @notice The name owner (at escrow creation) confirms delivery; the
    /// escrowed BNB is released to the payout address recorded at creation.
    /// Never blocked by a pause.
    function confirmDelivery(uint256 escrowId) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        if (e.payer == address(0)) revert EscrowNotFound(escrowId);
        if (e.released || e.refunded) revert AlreadySettled(escrowId);
        if (e.owner != msg.sender) revert NotNameOwnerForEscrow(escrowId, msg.sender);
        e.released = true;
        (bool ok,) = e.payee.call{value: e.amount}("");
        if (!ok) revert PaymentFailed(e.payee);
        emit EscrowReleased(escrowId, e.payee, e.amount);
    }

    /// @notice The payer refunds an unreleased escrow to themselves, any time
    /// before confirmation. Never blocked by a pause.
    function refund(uint256 escrowId) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        if (e.payer == address(0)) revert EscrowNotFound(escrowId);
        if (e.released || e.refunded) revert AlreadySettled(escrowId);
        if (e.payer != msg.sender) revert NotPayer(escrowId, msg.sender);
        e.refunded = true;
        (bool ok,) = e.payer.call{value: e.amount}("");
        if (!ok) revert PaymentFailed(e.payer);
        emit EscrowRefunded(escrowId, e.payer, e.amount);
    }

    /// @notice After the deadline, anyone may trigger the refund of an
    /// unreleased escrow back to the payer. Never blocked by a pause.
    function timeoutRefund(uint256 escrowId) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        if (e.payer == address(0)) revert EscrowNotFound(escrowId);
        if (e.released || e.refunded) revert AlreadySettled(escrowId);
        if (block.timestamp < e.deadline) revert DeadlineNotReached(escrowId, e.deadline);
        e.refunded = true;
        (bool ok,) = e.payer.call{value: e.amount}("");
        if (!ok) revert PaymentFailed(e.payer);
        emit EscrowRefunded(escrowId, e.payer, e.amount);
    }

    // --- emergency pause (registry only; fund release is never paused) ---

    /// @notice Pause new registrations, payments and escrows. Fund release
    /// (confirmDelivery / refund / timeoutRefund) keeps working while paused.
    function pause() external {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice The contract never accepts plain BNB transfers; funds only
    /// enter through payByName / escrowByName, which forward or escrow them.
    receive() external payable {
        revert ZeroPayment();
    }
}
