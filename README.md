# 🏦 Foundry DeFi Stablecoin System

<img width="768" alt="Screenshot 2025-06-14 at 3 11 54 PM" src="https://github.com/user-attachments/assets/88c7ba6b-9c2b-42dc-9199-9f246d414c94" />

Welcome to the **Decentralized Stable Coin (DSC) System** — a minimal, exogenously collateralized, algorithmic stablecoin protocol built with [Foundry](https://github.com/foundry-rs/foundry)! This project is inspired by DAI, but with a twist: **no governance, no fees, and only WETH & WBTC as collateral**.

---

## 🚀 What is DSC?

- **Pegged to $1.00**: Maintains a soft peg to the US Dollar using Chainlink price feeds.
- **Exogenous Collateral**: Only accepts external crypto assets (WETH, WBTC) as collateral.
- **Algorithmic Stability**: Overcollateralized and managed by smart contracts, not humans.
- **No Governance**: Purely code-driven, no admin keys or DAOs.

---

## 🧩 System Architecture

```
+-------------------+         +-------------------+
|                   |         |                   |
|  User Wallets     | <-----> |   DSCEngine.sol   |
|                   |         |                   |
+-------------------+         +-------------------+
                                      |
                                      v
                          +---------------------------+
                          | DecentralizedStableCoin   |
                          |         .sol              |
                          +---------------------------+
                                      |
                                      v
                          +---------------------------+
                          |   Chainlink Oracles       |
                          +---------------------------+
```

- **DSCEngine.sol**: The protocol's brain. Handles collateral, minting, redemption, and health checks.
- **DecentralizedStableCoin.sol**: The ERC20 implementation of the stablecoin (DSC).
- **OracleLib.sol**: Ensures price feeds are fresh and reliable.

---

## 🛠️ Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (for scripting, optional)
- An Ethereum node or [Anvil](https://book.getfoundry.sh/anvil/)

### Installation

```bash
git clone <this-repo-url>
cd foundry-defi-stablecoin
forge install
```

---

## ⚙️ Usage

### 1. Compile

```bash
forge build
```

### 2. Test

Run all tests (unit, fuzz, invariants):

```bash
forge test
```

### 3. Deploy

Deploy to a local or testnet chain:

```bash
forge script script/DeployDSC.s.sol --fork-url <YOUR_RPC_URL> --broadcast
```

> **Tip:** The deployment script auto-detects the network and configures price feeds and collateral accordingly.

---

## 🧪 Testing

- **Unit Tests**: `test/unit/DSCEngineTest.t.sol`
- **Fuzz Tests**: `test/fuzz/`
- **Mocks**: For price feeds and ERC20 tokens in `test/mocks/`

---

## 🏗️ Contracts Overview

- **src/DSCEngine.sol**: Core logic for collateral, minting, redemption, and liquidation.
- **src/DecentralizedStableCoin.sol**: ERC20 stablecoin with mint/burn restricted to DSCEngine.
- **src/libraries/OracleLib.sol**: Chainlink oracle safety checks.

---

## 🧰 Scripts

- **DeployDSC.s.sol**: Deploys the DSC system.
- **HelperConfig.s.sol**: Handles network-specific configuration for deployment.

---

## 📦 External Libraries

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [Chainlink Brownie Contracts](https://github.com/smartcontractkit/chainlink)
- [forge-std](https://github.com/foundry-rs/forge-std)

---

## 📝 Configuration

See `foundry.toml` for project configuration, remappings, and profiles.

---

## 🤝 Contributing

Pull requests and issues are welcome! Please open an issue to discuss your ideas or report bugs.

---

## 📜 License

MIT

---

## 🌟 Acknowledgements
- Built with ❤️ by Sakshi Shah

---
