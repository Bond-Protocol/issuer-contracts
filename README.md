# Bond Protocol Issuer Contracts

Smart contracts and scripts for Bond Protocol market issuers to use to deploy markets and accessory contracts such as callbacks and oracles.

[Documentation](https://docs.bondprotocol.finance/)

This project uses [Foundry](https://getfoundry.sh) as the development and testing environment. The following sections assume Foundry is installed on the local machine.

## Using pre-built (sample) contracts
Bond Protocol has developed some pre-built callbacks and oracles that issuers can deploy directly. 

The following contracts are available:
- Bond Sample Callback - AUDITED
- Bond Chainlink Oracle - AUDITED
- Bond Chainlink L2 Oracle - AUDITED
- Bond UniV3 Oracle - NOT AUDITED

Here are the steps to get started.
1. Clone this repository locally. In your preferred directory, run:
```bash
git clone https://github.com/Bond-Protocol/issuer-contracts
cd issuer-contracts
```

2. Setup .env file based on the sample. Within the issuer-contracts directory, run:
```bash
cp .env.sample .env
```
Then, edit the .env file to include the required data at the top of the file, plus any other external contracts you need based on the scripts you will be running.

3. Run provided shell scripts for desired actions. Some require inputs. Review the shell script files and the scripts/BondScripts.sol file for instructions.

## Building your own contracts from provided base contracts
Bond Protocol has developed some base contracts that issuers can use to build their own callbacks and oracles from. These provide the required interfaces and vetted designs to securely implement the required functionality.

The following base contracts are available:
- Bond Base Callback - AUDITED
- Bond Base Oracle - AUDITED

Here are the steps to get started.
1. Fork this repository to your own GitHub account.
2. Clone your newly created fork locally. In your preferred directory, run:
```bash
git clone https://github.com/<YOUR_GITHUB_USERNAME>/issuer-contracts
```
3. Develop and test your contracts. You can review the provided tests as a starting point. You can build and test foundry projects by running:
```bash
forge build
forge test
```
4. Add deploy / configure scripts specific to your new contracts (see BondScripts.sol and the shell/ directory).
5. Create a .env file based on the sample. Within the issuer-contracts directory, run:
```bash
cp .env.sample .env
```
6. Edit the .env file to include the required data at the top of the file, plus any other external contracts you need based on the scripts you will be running.
7. Run your shell scripts for desired actions.