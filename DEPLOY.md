# Deployment Guide

## Prerequisites

1. Base ETH for gas (~0.001 ETH)
2. Private key with funds
3. BaseScan API key (free at basescan.org)

## Setup

```bash
cd contracts
cp .env.example .env
# Edit .env with your keys
```

## Deploy

```bash
source .env
forge script script/Deploy.s.sol --rpc-url base --broadcast --verify
```

## Post-Deploy

Update `ui/src/lib/addresses.ts` with deployed addresses.

## Contracts

| Contract | Purpose |
|----------|---------|
| MeNabungVault | Main vault, splits deposits across strategies |
| ThetanutsAdapter | Options strategy (mock) |
| AerodromeAdapter | LP strategy (mock) |
| StakingAdapter | Staking strategy (mock) |

Note: Adapters are mock implementations for hackathon demo. Real protocol integrations planned for v2.
