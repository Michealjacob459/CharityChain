# CharityChain

A decentralized donation tracking and impact measurement platform built on Stacks blockchain using Clarity smart contracts.

## Overview

CharityChain enables transparent charitable giving by connecting donors directly with verified projects while tracking impact metrics and engagement. The platform provides a trustless environment for charitable donations with built-in verification and tracking mechanisms.

## Features

- **Project Verification**: Rigorous verification process for charity projects
- **Direct Donations**: STX token transfers directly to beneficiaries
- **Impact Tracking**: Transparent donation metrics and engagement analytics
- **Donor Dashboard**: Track individual contributions and project impact

## Smart Contract Functions

### Administrative Functions

```clarity
(create-project (name (string-ascii 50)) (description (string-ascii 256)) (beneficiary principal))
```
Creates a new charity project (contract owner only)

```clarity
(verify-project (project-id uint))
```
Verifies a project's authenticity (contract owner only)

### Public Functions

```clarity
(donate (project-id uint) (amount uint))
```
Make a donation to a specific project

### Read-Only Functions

```clarity
(get-project (project-id uint))
```
Retrieve project details

```clarity
(get-donation (donor principal) (project-id uint))
```
Get donation details for a specific donor and project

```clarity
(get-project-count)
```
Get total number of registered projects

## Data Structures

### Projects
- Project ID
- Name
- Description  
- Verification status
- Total donations received
- Beneficiary address

### Donations
- Donor address
- Project ID
- Amount
- Timestamp

## Getting Started

1. Install [Clarinet](https://github.com/hirosystems/clarinet)
2. Clone the repository
```bash
git clone https://github.com/Michealjacob459/CharityChain.git
```
3. Navigate to project directory
```bash
cd CharityChain
```
4. Test the contract
```bash
clarinet test
```

## Development

### Prerequisites
- Clarinet
- Stacks wallet
- Basic knowledge of Clarity smart contracts

### Local Development
1. Start Clarinet console
```bash
clarinet console
```
2. Deploy contract
3. Interact with contract functions

## Security

- Owner-only administrative functions
- Direct beneficiary payments
- Immutable donation records
- Verified project status

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Open pull request

## License

MIT License

## Contact

Project Link: [https://github.com/Michealjacob459/CharityChain](https://github.com/Michealjacob459/CharityChain)
