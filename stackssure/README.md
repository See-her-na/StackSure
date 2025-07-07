
# StackSure 

**Smart Yield Farming Meets Decentralized Insurance on Stacks**

StackSure is a fully on-chain DeFi protocol built on the [Stacks blockchain](https://www.stacks.co/) that combines **automated yield optimization** with **decentralized insurance protection**. Designed for yield farmers who want more than returns — they want peace of mind.

---

## 🚀 Features

- **📈 Yield Aggregator**: Automatically allocates deposits across top-performing Stacks protocols like `ALEX`, `Arkadiko`, `Velar`, etc.
- **🛡️ Insurance Pool**: Users can stake into the insurance fund and earn fees, while claimants can get coverage for DeFi losses.
- **⚖️ Risk-Aware Rebalancing**: Allocations factor in both APY and risk scores, offering better-adjusted returns.
- **⚙️ Batch Compounding**: Save gas and compound multiple protocol rewards in a single call.
- **📊 Transparent Protocol Metrics**: Live protocol data including APY, allocation %, risk score, and more.

---

## 🔐 Smart Contract Overview

### Core Modules

| Functionality           | Highlights |
|-------------------------|------------|
| `deposit-for-yield`     | Deposit STX to farm optimized yield |
| `withdraw-yield`        | Withdraw principal + earned yield |
| `stake-for-insurance`   | Stake STX to provide insurance liquidity |
| `file-insurance-claim`  | Submit claim with on-chain evidence |
| `process-insurance-claim` | Owner reviews and processes claims |
| `auto-rebalance-protocols` | Dynamically adjust yield allocations |
| `update-protocol-apy`   | Owner can update protocol APY stats |
| `compound-yields`       | Batch compound yield across protocols |

---

## 🧠 Risk Scoring System

Each supported protocol is assigned a **risk score** (0–1000), which affects:
- Insurance premiums
- Allocation weight in auto-rebalancing

---

## 🗃 Data Storage Architecture

| Map/Var                | Purpose                                           |
| ---------------------- | ------------------------------------------------- |
| `user-deposits`        | Tracks user deposits                              |
| `user-yield-shares`    | Tracks user's share of farm                       |
| `protocol-allocations` | Protocol-level metrics (APY, last compound, etc.) |
| `insurance-claims`     | Registry of submitted claims                      |
| `protocol-risk-scores` | Risk factor per protocol                          |
| `batch-transactions`   | Gas-optimized batch yield actions                 |

---

## 📦 Installation

Clone the repo and deploy using the [Clarinet](https://docs.stacks.co/write-smart-contracts/clarinet/overview/) CLI:

```bash
git clone https://github.com/your-username/stacksure.git
cd stacksure
clarinet check
clarinet test
clarinet deploy
---

## 🏛 Governance & Emergency Controls

* Contract owner (set to `tx-sender` on deploy) can:

  * Update APYs
  * Adjust risk scores
  * Approve/reject claims
  * Trigger emergency pause

---

## 🤝 Contributing

We welcome contributions to improve allocation logic, claim arbitration, or UI integration. Feel free to submit a pull request or open an issue!

> StackSure — Where your yield earns *and* stays safe.
