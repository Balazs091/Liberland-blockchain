import { mainnet, sepolia } from 'viem/chains'

import mainnetAddresses from './ethereum-mainnet.example.json'
import sepoliaAddresses from './sepolia-demo.example.json'

export const liberlandSepolia = {
  chain: sepolia,
  chainId: 11155111,
  explorer: 'https://sepolia.etherscan.io',
  addresses: sepoliaAddresses,
} as const

export const liberlandMainnet = {
  chain: mainnet,
  chainId: 1,
  explorer: 'https://etherscan.io',
  addresses: mainnetAddresses,
} as const

export type LiberlandSepoliaAddresses = typeof sepoliaAddresses
export type LiberlandMainnetAddresses = typeof mainnetAddresses
