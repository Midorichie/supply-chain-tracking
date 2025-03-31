# Blockchain-Powered Supply Chain Tracking

A transparency-focused supply chain solution built on Stacks blockchain using Clarity smart contracts. This project enables tracking of goods from manufacturer to consumer with immutable proof of custody and product history.

## Features

- Register and verify supply chain stakeholders (manufacturers, distributors, retailers)
- Create and track products through the supply chain
- Record custody transfers with location data and notes
- Update product status at each stage
- Full history of custody events stored on blockchain

## Project Structure

```
supply-chain-tracking/
├── contracts/
│   └── supply-chain.clar       # Main smart contract
├── tests/
│   └── supply-chain_test.clar  # Contract test cases
├── Clarinet.toml               # Project configuration
└── README.md                   # Project documentation
```

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Clarity development environment
- [Git](https://git-scm.com/) - Version control

### Installation

1. Clone the repository:
   ```
   git clone https://github.com/midorichie/supply-chain-tracking.git
   cd supply-chain-tracking
   ```

2. Set up the project with Clarinet:
   ```
   clarinet new supply-chain-tracking
   cp contracts/supply-chain.clar supply-chain-tracking/contracts/
   cp tests/supply-chain_test.clar supply-chain-tracking/tests/
   cd supply-chain-tracking
   ```

3. Run tests:
   ```
   clarinet test
   ```

## Smart Contract Functions

### Stakeholder Management
- `register-stakeholder` - Register as a stakeholder in the supply chain
- `verify-stakeholder` - Verify a stakeholder (contract owner only)
- `get-stakeholder` - Get stakeholder information

### Product Management
- `create-product` - Create a new product (manufacturers only)
- `update-product-status` - Update a product's status
- `get-product` - Get product information

### Custody Management
- `transfer-custody` - Transfer custody of a product to another stakeholder
- `get-custody-event` - Get information about a specific custody transfer event
- `get-last-event-id` - Get the latest event ID

## Security Considerations

- Role-based access control ensures only authorized parties can perform specific actions
- Product custody is tracked with immutable event records
- Only the contract owner can verify stakeholders
- Only the current custodian can transfer product custody


