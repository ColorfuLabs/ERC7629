# ERC-7629: Unified Token Protocol

## Table of Contents

- [Abstract](#abstract)
- [Motivation](#motivation)
- [Configuration](#configuration)
  - [Prerequisites](#prerequisites)
  - [Test (Foundry)](#test-foundry)
  - [Format (Foundry)](#format-foundry)

## Abstract

ERC-7629, known as the Unified Token Protocol, introduces a comprehensive protocol unifying the characteristics of ERC-721 and ERC-20 tokens within the Ethereum ecosystem. This standard seamlessly integrates the liquidity features of ERC-20 with the non-fungible nature of ERC-721, enabling frictionless conversion between these asset types. ERC-7629 offers a multifunctional solution, providing developers and users with the flexibility to leverage both liquidity and non-fungibility in a unified token framework.

## Motivation

The motivation behind ERC-7629 stems from the inherent need within the blockchain community for assets that possess both the liquidity of ERC-20 tokens and the non-fungibility of ERC-721 tokens. Current standards present a dichotomy, necessitating users to choose between these features. ERC-7629 addresses this limitation by providing a unified token standard, empowering users to seamlessly transition between ERC-20 and ERC-721 characteristics, catering to diverse blockchain applications.

## Configuration

### Prerequisites

- Foundry

### Test (Foundry)

To test the ERC-7629 implementation with foundry, test cases can be stored in `src/test` directory. The test cases can be run using the following command:

```bash
forge test
```

### Test Coverage (Foundry)

To generate test coverage, run the following command:

```bash
forge coverage
```

Generate a detail report with lcov and genhtml by running the following command:

```bash
forge coverage --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage
```

### Format (Foundry)

Simply run the following command to format the code:

```bash
forge fmt
```

### Gas Snapshot (Foundry)

To generate gas snapshot, run the following command:

```bash
forge snapshot
```

Or check the diff of gas snapshot:

```bash
forge snapshot --diff .gas-snapshot
```