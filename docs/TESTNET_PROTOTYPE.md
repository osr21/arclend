# Testnet Prototype Status

## Implemented in this branch

- provider-owned lender liquidity balances;
- borrower collateral balances;
- oracle-priced overcollateralized borrowing across configured assets;
- repayment and liquidation after a price change;
- owner-controlled market risk parameters, oracle address, and pause switch.

## Not implemented

- interest accrual, lender yield, or bad-debt handling;
- a production price oracle with staleness and sequencer checks;
- asset caps, timelock governance, multisig deployment configuration;
- vaults, gasless supply, frontend/API integration, or deployment scripts.

The oracle and ERC-20 contracts in the unit tests are mocks. This implementation
is for local testing and later Arc Testnet experimentation only. It is not
audited and is not ready for any public deployment, especially Mainnet.

## Build and test

Requires Foundry and Solidity 0.8.24:

```sh
forge build
forge test -vv
```

## Mainnet gate

No Mainnet deployment should be considered until the missing features are
implemented, the contract suite passes unit, fuzz, and invariant tests, a
Mainnet fork simulation passes, production feeds and risk parameters are
independently validated, and an independent security review is complete.
